# Backend Server — RSSI Calculation & Engine

This folder contains the core machine learning and processing logic for the RSSI Indoor Positioning System. It handles everything from collecting calibration data to training the models and serving real-time position estimates via WebSockets.

Here is a detailed breakdown of how the four main pillars of the backend operate.

---

## 1. Data Collection (`server.py` REST API)

Before the system can locate a user, it needs to understand the radio environment. This is known as "Fingerprinting."

* **The Flow:** A developer stands in a specific cell (e.g., column 1, row 2) holding the Android app in Data Collection mode. The app constantly scans WiFi RSSI and sends HTTP `POST /collect` requests to the backend.
* **Storage:** `server.py` receives the JSON payload payload containing `cell_col`, `cell_row`, and the 4 `rssi` values. It appends this directly to `../fingerprint_data.csv` located in the root project directory.
* **API Endpoints for Collection:**
  * `POST /collect` — Appends a new timestamped row to the CSV.
  * `GET /collect/status` — Returns a summary of how many samples have been gathered per grid cell.
  * `DELETE /collect/reset` — Wipes the CSV to start a fresh calibration.

---

## 2. Machine Learning Models (`train_model.ipynb`)

Once data collection is complete, the Jupyter Notebook converts the raw CSV data into highly accurate spatial prediction models.

* **Feature Extraction:** Raw RSSI is too noisy to use directly. The notebook processes the data into two sets:
  * **Raw:** Just the 4 RSSI numbers.
  * **Statistical (18 Dimensions):** Simulates what a realistic "moving" window feels like. It extracts the **mean**, **standard deviation**, and **median** for each of the 4 routers over a sliding window. It also calculates the **relative differences** between all pairs of router medians (capturing geographic ratios rather than absolute dBm).
* **Training the Models:** The script trains multiple Scikit-Learn models under different hyperparameters:
  * **Random Forest Regressor** (Deep trees, multiple estimators)
  * **Gradient Boosting Regressor**
  * **K-Nearest Neighbors** (Using $k=3$ and $k=7$ tight clusters, specifically leveraging `manhattan` distance which maps signal geometry better).
* **Exporting:** It scores them using Cross-Validation RMSE (Root Mean Squared Error), and dumps the trained binaries as `.pkl` files (e.g., `rf_stats_model.pkl`, `knn_7_stats_model.pkl`) right in this directory.

---

## 3. The Positioning Engine (`engine.py`)

The Engine is where the magic happens during live tracking. It heavily relies on an `EnsemblePositioner` and a Temporal Constraint Filter.

* **Ensemble Voting:** When initialized, the engine dynamically grabs *all* `.pkl` files it finds in the directory.
* **Incoming Feed:** It keeps a running queue (`deque`) of the last few RSSI arrays sent from the phone.
* **Live Feature Extraction:** Just like the notebook, the engine instantly computes the 18-dimensional statistical features on the fly.
* **Casting Votes:** It asks every single loaded model (RF, GB, KNN) to predict the user's X/Y coordinates. Every model is given a "voting weight" inversely proportional to its training RMSE (better models cast stronger votes).
* **Temporal Constraint Filter:**
  * **`VOTE_WINDOW` & `SUPERMAJORITY`:** It doesn't instantly snap the user to the predicted cell. Instead, it requires a rolling subset of recent frames to agree with a minimum confidence (`0.40`).
  * **Clipping Jumps:** It enforces a `MAX_CELL_JUMP` constraint. If a bad Wi-Fi scan claims the user teleported to the other side of the room in 0.1 seconds, the engine rejects it as multipath noise and slides them over gracefully instead. (Though it features an instant-breakout if confidence hits absolute overwhelming levels `> 0.70`).

---

## 4. The Real-Time Server (`server.py` WebSockets)

The FastAPI application acts as the traffic controller, bridging the smartphone, the engine, and the 3D graphics in the browser.

* **`/ws/mobile` (Input):** The Android app connects to this WebSocket and unloads raw RSSI arrays (e.g., `[-45, -50, -42, -48]`) multiple times a second.
* **The Bridge:** Every time a message arrives, `server.py` passes it down to `engine.update(rssi)`. The engine processes the ensemble vote and returns a clean, filtered `(x, y)` position and exact `(col, row)`.
* **`/ws/frontend` (Output):** The server packages the engine's X/Y coordinates, grid IDs, and the raw stats (for debugging bars) into a JSON packet, broadcasting it out to the Three.js 3D frontend. The frontend reads this X/Y and glides the avatar across the screen.