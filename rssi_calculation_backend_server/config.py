"""
Configuration — Tuned for stable KNN positioning.
"""

# =============================================================================
# ROUTER POSITIONS (4m × 2m rectangle)
# =============================================================================
ROUTER_POSITIONS = [
    (0.0, 0.0),   # router_0 — Bottom-left
    (4.0, 0.0),   # router_1 — Bottom-right
    (0.0, 2.0),   # router_2 — Top-left
    (4.0, 2.0),   # router_3 — Top-right
]

# =============================================================================
# RSSI SMOOTHING
# Heavy EMA to stabilize RSSI before feeding to KNN.
# With KNN, even 1-2 dBm change can jump cells, so we smooth aggressively.
# =============================================================================
EMA_ALPHA = 0.15    # Was 0.3. Lower = much smoother RSSI (less jitter)

# =============================================================================
# WEIGHTED CENTROID (fallback only — used when no KNN model)
# =============================================================================
SHARPNESS = 2.0

# =============================================================================
# KALMAN FILTER
# Tuned for "standing still should not move the dot":
#   - Low process noise = assume person moves slowly
#   - High measurement noise = don't trust each KNN prediction too much
# =============================================================================
PROCESS_NOISE = 0.02     # Was 0.1. Much lower = dot barely moves on noise
MEASUREMENT_NOISE = 1.0  # Was 0.3. Much higher = smooths out KNN jumps

# =============================================================================
# GRID — for fingerprinting data collection (5×3 = 15 cells)
# =============================================================================
GRID_COLS = 5
GRID_ROWS = 3
CELL_W = 4.0 / GRID_COLS  # 0.8m
CELL_H = 2.0 / GRID_ROWS  # ~0.667m

# =============================================================================
# AREA BOUNDS
# =============================================================================
AREA_X_MIN = -0.2
AREA_X_MAX = 4.2
AREA_Y_MIN = -0.2
AREA_Y_MAX = 2.2

# =============================================================================
# SERVER
# =============================================================================
SERVER_HOST = "0.0.0.0"
SERVER_PORT = 6060
FIXED_Z = 0.0
