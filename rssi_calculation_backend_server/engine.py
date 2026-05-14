"""
Positioning Engine — Ensemble Cell Classification + Voting.

Auto-detects whether models use raw or statistical features.
Loads ALL available models in the directory and uses a majority vote across them 
to determine the predicted cell.

Pipeline:
  1. (Optional) Sliding window → compute mean+std per router for stat models
  2. Model predict → collect predictions from ALL loaded models
  3. Map each prediction to a cell and Voting across models
  4. Adjacency constraint
"""

import numpy as np
import time
import pickle
import os
import glob
import logging
from collections import Counter, deque

from config import (
    GRID_COLS, GRID_ROWS,
    CELL_W, CELL_H,
)

logger = logging.getLogger("engine")

MODELS_DIR = os.path.dirname(__file__)

# ── Tuning ──
VOTE_WINDOW = 3          # Keep it snappy
SUPERMAJORITY = 0.40     # Lowered to react faster
MAX_CELL_JUMP = 5        # Allowed to jump faster across the grid


# =========================================================================
# Ensemble Model Loader
# =========================================================================
class EnsemblePositioner:
    def __init__(self, models_dir: str = MODELS_DIR):
        self.models = []
        self.max_window_size = 1
        self.load_all(models_dir)

    def load_all(self, models_dir: str):
        self.models = []
        self.max_window_size = 1
        pattern = os.path.join(models_dir, "*_model.pkl")
        for path in glob.glob(pattern):
            try:
                with open(path, "rb") as f:
                    data = pickle.load(f)
                
                # Check validity
                if "model" not in data:
                    continue
                    
                model_data = {
                    "name": data.get("model_name", os.path.basename(path)),
                    "model": data["model"],
                    "use_stat": data.get("use_stat_features", False),
                    "window": data.get("window_size", 1),
                    "cv_rmse": data.get("cv_rmse", 1.0)
                }
                self.models.append(model_data)
                if model_data["window"] > self.max_window_size:
                    self.max_window_size = model_data["window"]
                
                logger.info("✅ Loaded ensemble model: %s (stat=%s, win=%d)", 
                            model_data["name"], model_data["use_stat"], model_data["window"])
            except Exception as e:
                logger.error("Failed to load model %s: %s", path, e)

    @property
    def available(self) -> bool:
        return len(self.models) > 0

    def predict_xy_all(self, raw_features: np.ndarray, stat_features: np.ndarray | None) -> list[tuple[float, float]]:
        predictions = []
        for m in self.models:
            if m["use_stat"]:
                if stat_features is None:
                    continue # Not enough window data yet for this model
                features = stat_features
            else:
                features = raw_features
            
            try:
                pred = m["model"].predict(features.reshape(1, -1))
                predictions.append((float(pred[0][0]), float(pred[0][1])))
            except Exception as e:
                logger.warning("Model %s prediction failed: %s", m["name"], e)
        return predictions


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
        self.buffers = [deque(maxlen=window_size) for _ in range(n_routers)]

    def add(self, rssi: list[float]):
        for i, val in enumerate(rssi):
            self.buffers[i].append(val)

    @property
    def ready(self) -> bool:
        return all(len(b) >= self.window_size for b in self.buffers)

    def get_features(self) -> np.ndarray:
        """Returns [mean_0, std_0, med_0, ..., diff_0_1, diff_0_2...]."""
        features = []
        medians = []
        for buf in self.buffers:
            arr = np.array(list(buf))
            features.append(float(arr.mean()))
            features.append(float(arr.std()) if len(arr) > 1 else 0.0)
            med = float(np.median(arr))
            features.append(med)
            medians.append(med)
            
        # Relative RSSI differences
        features.append(medians[0] - medians[1])
        features.append(medians[0] - medians[2])
        features.append(medians[0] - medians[3])
        features.append(medians[1] - medians[2])
        features.append(medians[1] - medians[3])
        features.append(medians[2] - medians[3])
        
        return np.array(features)

    def reset(self):
        for buf in self.buffers:
            buf.clear()


# =========================================================================
# Complete Engine
# =========================================================================
class PositioningEngine:
    def __init__(self):
        self.positioner = EnsemblePositioner()
        self._vote_history = []
        self._current_cell = (2, 1)
        self._rssi_window = RSSIWindow(
            window_size=self.positioner.max_window_size if self.positioner.available else 5
        )
        self.mode = "ensemble" if self.positioner.available else "none"

        # Aliases for backward compatibility
        self.knn = self.positioner

        logger.info("Engine mode: %s (%d models)", self.mode.upper(), len(self.positioner.models))

    def process(self, raw_rssi: list[float], timestamp: float | None = None) -> dict:
        now = timestamp or time.time()

        if not self.positioner.available:
            cx, cy = cell_to_xy(*self._current_cell)
            return self._make_result(self._current_cell, cx, cy, now, raw_rssi)

        raw_features = np.array(raw_rssi)
        
        # Build stat features
        self._rssi_window.add(raw_rssi)
        stat_features = None
        if self._rssi_window.ready:
            stat_features = self._rssi_window.get_features()

        # Step 1: Predict from all models (that have ready features)
        xy_preds = self.positioner.predict_xy_all(raw_features, stat_features)
        
        if not xy_preds:
            # No models ready yet (e.g., waiting on stat window)
            cx, cy = cell_to_xy(*self._current_cell)
            return self._make_result(self._current_cell, cx, cy, now, raw_rssi)

        # Step 2: Weighted Vote across ALL models in this frame
        cell_weights = Counter()
        for idx, m in enumerate(self.positioner.models):
            if not xy_preds or idx >= len(xy_preds): continue
                
            cell = xy_to_cell(xy_preds[idx][0], xy_preds[idx][1])
            # Weight is inversely proportional to model error
            rmse = m.get("cv_rmse", 1.0)
            weight = 1.0 / (rmse + 0.1) 
            cell_weights[cell] += weight
            
        ensemble_cell, max_weight = cell_weights.most_common(1)[0]
        total_weight = sum(cell_weights.values())
        ensemble_confidence = max_weight / total_weight if total_weight > 0 else 0

        # Step 3: Optional temporal smoothing (VOTE_WINDOW frames)
        self._vote_history.append(ensemble_cell)
        if len(self._vote_history) > VOTE_WINDOW:
            self._vote_history = self._vote_history[-VOTE_WINDOW:]

        temporal_counts = Counter(self._vote_history)
        top_cell, top_count = temporal_counts.most_common(1)[0]
        temporal_ratio = top_count / len(self._vote_history)

        # Step 4: Adjacency check using temporal vote
        # (Could also just use the ensemble cell directly, but smoothing helps against jumps)
        if top_cell != self._current_cell:
            dist = cell_distance(self._current_cell, top_cell)
            if temporal_ratio >= SUPERMAJORITY and dist <= MAX_CELL_JUMP:
                self._current_cell = top_cell
            elif temporal_ratio >= 0.70:
                # Absolute certainty override: jump instantly regardless of distance max cell jump
                self._current_cell = top_cell

        cx, cy = cell_to_xy(*self._current_cell)
        
        return self._make_result(
            self._current_cell, cx, cy, now, raw_rssi,
            ensemble_cell=ensemble_cell, 
            vote_ratio=ensemble_confidence,
            temporal_ratio=temporal_ratio
        )

    def _make_result(
        self,
        cell: tuple[int, int],
        cx: float, cy: float,
        timestamp: float,
        raw_rssi: list[float],
        ensemble_cell: tuple[int, int] | None = None,
        vote_ratio: float = 0,
        temporal_ratio: float = 0,
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
                "raw_cell": list(ensemble_cell) if ensemble_cell else list(cell),
                "voted_cell": list(cell),
                "ensemble_confidence": round(vote_ratio, 2),
                "temporal_ratio": round(temporal_ratio, 2),
            },
        }

    def reload_model(self) -> bool:
        self.positioner.load_all(MODELS_DIR)
        self.mode = "ensemble" if self.positioner.available else "none"
        self._vote_history.clear()
        self._rssi_window = RSSIWindow(
            window_size=self.positioner.max_window_size if self.positioner.available else 5
        )
        self.knn = self.positioner
        logger.info("Engine mode after reload: %s", self.mode.upper())
        return self.positioner.available

    def reset(self):
        self._vote_history.clear()
        self._current_cell = (2, 1)
        self._rssi_window.reset()

