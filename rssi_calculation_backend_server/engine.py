"""
Positioning Engine — KNN/RF Cell Classification + Voting.

Auto-detects whether the model uses raw or statistical features.
If statistical: maintains a sliding window and computes mean+std per router.

Pipeline:
  1. (Optional) Sliding window → compute mean+std per router
  2. Model predict → snap to cell
  3. Majority vote over last N predictions
  4. Adjacency constraint
"""

import numpy as np
import time
import pickle
import os
import logging
from collections import Counter, deque

from config import (
    GRID_COLS, GRID_ROWS,
    CELL_W, CELL_H,
)

logger = logging.getLogger("engine")

MODEL_FILE = os.path.join(os.path.dirname(__file__), "knn_model.pkl")

# ── Tuning ──
VOTE_WINDOW = 5
SUPERMAJORITY = 0.50
MAX_CELL_JUMP = 3


# =========================================================================
# Model Loader
# =========================================================================
class ModelPositioner:
    def __init__(self, model_path: str = MODEL_FILE):
        self.model = None
        self.metadata = {}
        self.use_stat_features = False
        self.window_size = 1
        self.load(model_path)

    def load(self, path: str) -> bool:
        if not os.path.exists(path):
            logger.warning("No model found at %s", path)
            return False
        try:
            with open(path, "rb") as f:
                data = pickle.load(f)
            self.model = data["model"]
            self.use_stat_features = data.get("use_stat_features", False)
            self.window_size = data.get("window_size", 1)
            self.metadata = {k: v for k, v in data.items() if k != "model"}
            logger.info(
                "✅ Model loaded: %s, features=%s, window=%d, RMSE=%.4fm, samples=%d",
                data.get("model_name", "unknown"),
                "stat(8)" if self.use_stat_features else "raw(4)",
                self.window_size,
                data.get("cv_rmse", data.get("train_rmse", 0)),
                data.get("n_samples", 0),
            )
            return True
        except Exception as e:
            logger.error("Failed to load model: %s", e)
            self.model = None
            return False

    @property
    def available(self) -> bool:
        return self.model is not None

    def predict_xy(self, features: np.ndarray) -> tuple[float, float]:
        pred = self.model.predict(features.reshape(1, -1))
        return (float(pred[0][0]), float(pred[0][1]))


# =========================================================================
# Cell helpers
# =========================================================================
def xy_to_cell(x: float, y: float) -> tuple[int, int]:
    col = int(np.clip(x / CELL_W, 0, GRID_COLS - 1))
    row = int(np.clip(y / CELL_H, 0, GRID_ROWS - 1))
    return (col, row)


def cell_to_xy(col: int, row: int) -> tuple[float, float]:
    return (col * CELL_W + CELL_W / 2, row * CELL_H + CELL_H / 2)


def cell_distance(a: tuple[int, int], b: tuple[int, int]) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


# =========================================================================
# Sliding Window for Statistical Features
# =========================================================================
class RSSIWindow:
    """Maintains a sliding window per router and computes mean+std."""

    def __init__(self, window_size: int = 5, n_routers: int = 4):
        self.window_size = window_size
        self.n_routers = n_routers
        self.buffers: list[deque] = [deque(maxlen=window_size) for _ in range(n_routers)]

    def add(self, rssi: list[float]):
        for i, val in enumerate(rssi):
            self.buffers[i].append(val)

    @property
    def ready(self) -> bool:
        return all(len(b) >= self.window_size for b in self.buffers)

    def get_features(self) -> np.ndarray:
        """Returns [mean_0, std_0, mean_1, std_1, mean_2, std_2, mean_3, std_3]."""
        features = []
        for buf in self.buffers:
            arr = np.array(list(buf))
            features.append(float(arr.mean()))
            features.append(float(arr.std()) if len(arr) > 1 else 0.0)
        return np.array(features)

    def reset(self):
        for buf in self.buffers:
            buf.clear()


# =========================================================================
# Complete Engine
# =========================================================================
class PositioningEngine:
    def __init__(self):
        self.positioner = ModelPositioner()
        self._vote_history: list[tuple[int, int]] = []
        self._current_cell: tuple[int, int] = (2, 1)
        self._rssi_window = RSSIWindow(
            window_size=self.positioner.window_size if self.positioner.available else 5
        )
        self.mode = "model" if self.positioner.available else "none"

        # Aliases for backward compatibility (server.py references engine.knn)
        self.knn = self.positioner

        logger.info("Engine mode: %s", self.mode.upper())
        if self.positioner.available:
            logger.info(
                "Feature mode: %s",
                "STATISTICAL (mean+std, window=%d)" % self.positioner.window_size
                if self.positioner.use_stat_features
                else "RAW (4 RSSI values)"
            )

    def process(self, raw_rssi: list[float], timestamp: float | None = None) -> dict:
        now = timestamp or time.time()

        if not self.positioner.available:
            cx, cy = cell_to_xy(*self._current_cell)
            return self._make_result(self._current_cell, cx, cy, now, raw_rssi)

        # ── Step 1: Build features ──
        if self.positioner.use_stat_features:
            self._rssi_window.add(raw_rssi)
            if not self._rssi_window.ready:
                # Not enough data yet — stay at current cell
                cx, cy = cell_to_xy(*self._current_cell)
                return self._make_result(self._current_cell, cx, cy, now, raw_rssi)
            features = self._rssi_window.get_features()
        else:
            features = np.array(raw_rssi)

        # ── Step 2: Predict → cell ──
        pred_x, pred_y = self.positioner.predict_xy(features)
        predicted_cell = xy_to_cell(pred_x, pred_y)

        # ── Step 3: Vote ──
        self._vote_history.append(predicted_cell)
        if len(self._vote_history) > VOTE_WINDOW:
            self._vote_history = self._vote_history[-VOTE_WINDOW:]

        counts = Counter(self._vote_history)
        top_cell, top_count = counts.most_common(1)[0]
        vote_ratio = top_count / len(self._vote_history)

        # ── Step 4: Adjacency check ──
        if top_cell != self._current_cell:
            dist = cell_distance(self._current_cell, top_cell)
            if vote_ratio >= SUPERMAJORITY and dist <= MAX_CELL_JUMP:
                self._current_cell = top_cell

        cx, cy = cell_to_xy(*self._current_cell)
        return self._make_result(
            self._current_cell, cx, cy, now, raw_rssi,
            predicted_cell=predicted_cell, vote_ratio=vote_ratio,
        )

    def _make_result(
        self,
        cell: tuple[int, int],
        cx: float, cy: float,
        timestamp: float,
        raw_rssi: list[float],
        predicted_cell: tuple[int, int] | None = None,
        vote_ratio: float = 0,
    ) -> dict:
        return {
            "cell_col": cell[0],
            "cell_row": cell[1],
            "x": round(cx, 4),
            "y": round(cy, 4),
            "z": 0.0,
            "timestamp": timestamp,
            "mode": self.mode,
            "debug": {
                "raw_rssi": raw_rssi,
                "raw_cell": list(predicted_cell) if predicted_cell else list(cell),
                "voted_cell": list(cell),
                "vote_ratio": round(vote_ratio, 2),
            },
        }

    def reload_model(self) -> bool:
        loaded = self.positioner.load(MODEL_FILE)
        self.mode = "model" if self.positioner.available else "none"
        self._vote_history.clear()
        self._rssi_window = RSSIWindow(
            window_size=self.positioner.window_size if self.positioner.available else 5
        )
        self.knn = self.positioner
        logger.info("Engine mode after reload: %s", self.mode.upper())
        return loaded

    def reset(self):
        self._vote_history.clear()
        self._current_cell = (2, 1)
        self._rssi_window.reset()
