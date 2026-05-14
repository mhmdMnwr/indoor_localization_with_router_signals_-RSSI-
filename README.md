# RSSI Indoor Positioning System

Real-time indoor positioning using WiFi RSSI from 4 routers in a **4m × 2m room**.

## Architecture

```
Phone (Android)
  │  WiFi RSSI scan
  ▼
WebSocket (/ws/mobile)
  │
  ▼
┌──────────────────────────────────────┐
│         Python Backend (FastAPI)     │
│                                      │
│  1. EMA Smoothing (per-router)       │
│  2. Weighted Centroid (RSSI→position)│
│  3. Kalman Filter (smooth output)    │
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
  R2 (0,2) ──────────────────── R3 (4,2)
     │    5×3 grid (15 cells)     │
     │  ┌───┬───┬───┬───┬───┐    │
     │  │0,2│1,2│2,2│3,2│4,2│    │
     │  ├───┼───┼───┼───┼───┤    │
     │  │0,1│1,1│2,1│3,1│4,1│    │
     │  ├───┼───┼───┼───┼───┤    │
     │  │0,0│1,0│2,0│3,0│4,0│    │
     │  └───┴───┴───┴───┴───┘    │
  R0 (0,0) ──────────────────── R1 (4,0)
```

## Quick Start

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Start the server
python server.py

# 3. Open the 3D visualization
#    Open 3d-visualization/index.html in a browser

# 4. Connect the mobile app or run the test client
python test_client.py
```

## File Structure

```
├── config.py             # All tunable parameters
├── engine.py             # Core: EMA + Weighted Centroid + Kalman
├── server.py             # FastAPI server (WebSocket + REST)
├── test_client.py        # Simulated phone for testing
├── train_model.ipynb     # Jupyter notebook for KNN model training
├── requirements.txt      # Python dependencies
│
├── 3d-visualization/     # Three.js frontend
│   ├── index.html
│   ├── app.js
│   └── style.css
│
└── rssi_mobile_app/      # Flutter Android app
    └── lib/
        ├── main.dart
        ├── theme.dart
        ├── screens/
        │   ├── home_screen.dart
        │   ├── settings_screen.dart
        │   └── data_collection_screen.dart
        └── services/
            ├── websocket_service.dart
            └── wifi_scanner_service.dart
```

## API Endpoints

### WebSocket

| Endpoint | Direction | Purpose |
|---|---|---|
| `ws://HOST:6060/ws/mobile` | Phone → Server | Send `{"rssi": [-45, -50, -60, -55]}` |
| `ws://HOST:6060/ws/frontend` | Server → Browser | Receive `{"x": 1.23, "y": 0.67, ...}` |

### REST

| Endpoint | Method | Purpose |
|---|---|---|
| `/health` | GET | Server status |
| `/collect` | POST | Save fingerprint: `{"cell_col": 2, "cell_row": 1, "rssi": [-45, -50, -60, -55]}` |
| `/collect/status` | GET | Sample counts per cell |
| `/collect/reset` | DELETE | Clear all collected data |

## Positioning Engine

### How It Works

The engine uses **3 stages** — no distance calculation, no trilateration:

1. **EMA Smoothing** — Simple exponential moving average per router to reduce RSSI noise
2. **Weighted Centroid** — Converts RSSI to position using power-law weights:
   - `weight = 10^(RSSI/10)` (dBm → milliwatts)
   - Apply sharpness exponent to increase contrast
   - Position = weighted average of router locations
3. **Kalman Filter** — Smooths the trajectory with a constant-velocity model

### Why Not Trilateration?

RSSI cannot give accurate distances indoors (multipath, walls, body absorption). But RSSI **can** tell you which router is closest. Weighted centroid only needs relative proximity — it's inherently more stable than trilateration for demo environments.

## Tuning

Only 3 parameters matter:

```python
# config.py
EMA_ALPHA = 0.3       # 0.2=smoother  0.4=faster
SHARPNESS = 2.0       # 1.0=center-biased  3.0=aggressive corners
PROCESS_NOISE = 0.1   # Lower=smoother  Higher=more responsive
```

| Symptom | Fix |
|---|---|
| Dot clusters at center | Increase `SHARPNESS` (try 2.5 or 3.0) |
| Dot too jittery | Lower `EMA_ALPHA` (try 0.2) |
| Dot lags behind movement | Increase `PROCESS_NOISE` (try 0.2) |
| Dot overshoots | Increase `MEASUREMENT_NOISE` (try 0.5) |

## Fingerprint Data Collection

For better accuracy, collect RSSI fingerprints at each of the 15 grid cells:

### Step 1: Collect Data

1. Open the **Data Collection** screen in the mobile app
2. Tap a grid cell (e.g., `(2,1)`)
3. Stand at that cell's physical location
4. Press **START** — collects for 2 minutes (1 sample/second = ~120 samples)
5. Repeat for all 15 cells

### Step 2: Train Model

```bash
jupyter notebook train_model.ipynb
```

The notebook:
- Loads `fingerprint_data.csv`
- Visualizes RSSI distributions per cell
- Trains a KNN model with cross-validation
- Saves `knn_model.pkl`

### Step 3: Use Model

The server can load `knn_model.pkl` for KNN-based positioning (future upgrade).

## Test Client

```bash
# Circle pattern (default)
python test_client.py

# Listen as frontend
python test_client.py frontend
```

## Mobile App Setup

```bash
cd rssi_mobile_app
flutter pub get
flutter run
```

Configure the 4 router BSSIDs in the app's Settings screen.
# indoor_localization_with_router_signals_-RSSI-
