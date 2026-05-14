# RSSI Indoor Positioning System

Real-time indoor positioning using WiFi RSSI from 4 routers in a **6.0m × 2.0m room**.

## Architecture

```
Phone (Android)
  │  WiFi RSSI scan [Fast/Continuous]
  ▼
WebSocket (/ws/mobile)
  │
  ▼
┌──────────────────────────────────────┐
│         Python Backend (FastAPI)     │
│                                      │
│  1. Extract Statistical Features     │
│     (mean, std, median differences)  │
│  2. Machine Learning Ensemble        │
│     (RF, KNN, Gradient Boosting)     │
│  3. Temporal Voting Filter           │
└──────────────────────────────────────┘
  │
  ▼
WebSocket (/ws/frontend)
  │
  ▼
3D Visualization (Three.js)
```

## Room Layout

```
  R2 ──────────────────── R3
     │  4×3 grid (12 cells) │
     │  ┌───┬───┬───┬───┐   │
     │  │0,2│1,2│2,2│3,2│   │ 2.0m
     │  ├───┼───┼───┼───┤   │
     │  │0,1│1,1│2,1│3,1│   │
     │  ├───┼───┼───┼───┤   │
     │  │0,0│1,0│2,0│3,0│   │
     │  └───┴───┴───┴───┘   │
  R0 ──────────────────── R1
            6.0m
```

## Quick Start

```bash
# 1. Install dependencies
cd rssi_calculation_backend_server
pip install -r requirements.txt

# 2. Start the server
python server.py

# 3. Open the 3D visualization
#    Open 3d-visualization/index.html in a browser

# 4. Connect the mobile app
#    Run the companion Flutter app on an Android device to feed live data.
```

## File Structure

```
├── fingerprint_data.csv             # Collected RSSI training dataset
├── 3d-visualization/                # Three.js frontend
│   ├── index.html                   # Contains 3D Canvas and RSSI Glass Hud
│   ├── app.js                       # Renders room, grid, furniture & handles WS
│   └── style.css
│
├── rssi_calculation_backend_server/ # Core backend logic
│   ├── config.py                    # Room bounds, IPs, & cell settings 
│   ├── engine.py                    # Robust ML Ensemble Model & Location Voting Filter
│   ├── server.py                    # FastAPI server (WebSocket + REST)
│   ├── train_model.ipynb            # Generates the ML `.pkl` models
│   ├── requirements.txt             # Python dependencies
│   └── *.pkl                        # Compiled Scikit-Learn models
│
└── rssi_mobile_app/                 # Flutter Android app
    └── lib/
        ├── main.dart
        ├── screens/
        │   ├── home_screen.dart           # View continuous RSSI scans
        │   ├── settings_screen.dart       # Enter Router Addresses
        │   └── data_collection_screen.dart# Gather ML fingerprint data
        └── services/
```

## Positioning Engine

The engine uses advanced **Machine Learning Ensemble Voting** to map raw radio frequencies to an exact point on the grid.

### 1. Feature Extraction
Because RSSI is extremely noisy indoors, predicting based purely on instantaneous signals is flawed. The engine caches the last few packets on a rolling window, resolving:
- **Means & Medians** representing core signal strength.
- **Relative Subtractions** representing geometric distance hierarchies regardless of network traffic dropoffs.

### 2. Weighted Voting
All `.pkl` machine learning models (like Random Forest, KNN with Manhattan Distances, Gradient Boosting) stored in the backend cast their votes on which cell the user is in. Votes are inversely weighted based on their cross-validation RMSE performance. 

### 3. Temporal Constraints
To stop erratic jumping while still remaining responsive:
- **`VOTE_WINDOW=3`, `SUPERMAJORITY=0.4`:** Validates sustained probability across time before drifting the visual cursor.
- **`MAX_CELL_JUMP=5`:** Prevents teleportation across the entire room matrix in a single frame unless the confidence override limit triggers.

## Training Custom Models

To train on your own layout:
1. Load `rssi_mobile_app`, navigate to the `Data Collection` route.  
2. Collect samples at every physical cell in the grid.
3. Open `train_model.ipynb` in the backend. Click **"Run All"**.
4. The notebook will automatically wipe/re-generate all `_model.pkl` files based on the `.csv` at the root folder.
