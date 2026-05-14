"""
RSSI Indoor Positioning Server v4.
Uses weighted centroid engine + fingerprint data collection.
"""

import json
import time
import csv
import os
import logging
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

from config import SERVER_HOST, SERVER_PORT, FIXED_Z, ROUTER_POSITIONS, GRID_COLS, GRID_ROWS
from engine import PositioningEngine

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s │ %(levelname)-7s │ %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("rssi-server")

# Global state
engine = PositioningEngine()
frontend_clients: set[WebSocket] = set()
update_count = 0
last_result = None

# Fingerprint data file
FINGERPRINT_FILE = "fingerprint_data.csv"


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("=" * 50)
    logger.info("  RSSI Positioning Server v4")
    logger.info(f"  ws://{SERVER_HOST}:{SERVER_PORT}")
    logger.info(f"  Mobile:   /ws/mobile")
    logger.info(f"  Frontend: /ws/frontend")
    logger.info(f"  Collect:  POST /collect")
    logger.info(f"  Grid:     {GRID_COLS}×{GRID_ROWS} = {GRID_COLS*GRID_ROWS} cells")
    logger.info("=" * 50)
    for i, (x, y) in enumerate(ROUTER_POSITIONS):
        logger.info(f"  router_{i}: ({x}, {y})")
    yield


app = FastAPI(title="RSSI Positioning", version="4.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)


# ─── Health ───
@app.get("/health")
async def health():
    return {
        "status": "ok",
        "mode": engine.mode,
        "clients": len(frontend_clients),
        "updates": update_count,
        "grid": f"{GRID_COLS}x{GRID_ROWS}",
        "fingerprints_collected": _count_fingerprints(),
        "model_info": engine.knn.metadata if engine.knn.available else None,
    }


@app.post("/reload-model")
async def reload_model():
    """Hot-reload the KNN model without restarting the server."""
    success = engine.reload_model()
    return {
        "status": "ok" if success else "no_model",
        "mode": engine.mode,
        "model_info": engine.knn.metadata if engine.knn.available else None,
    }


def _count_fingerprints():
    if not os.path.exists(FINGERPRINT_FILE):
        return 0
    with open(FINGERPRINT_FILE) as f:
        return sum(1 for _ in f) - 1  # minus header


# ─── Fingerprint Data Collection ───
class FingerprintSample(BaseModel):
    cell_col: int
    cell_row: int
    rssi: list[float]  # 4 values


@app.post("/collect")
async def collect_fingerprint(sample: FingerprintSample):
    """
    Collect a single fingerprint sample for a grid cell.

    The mobile app calls this repeatedly while you stand at a cell.
    Each call saves one row: timestamp, col, row, rssi0, rssi1, rssi2, rssi3

    Body: {"cell_col": 2, "cell_row": 1, "rssi": [-45, -50, -60, -55]}
    """
    if len(sample.rssi) != 4:
        return {"error": "Need exactly 4 RSSI values"}
    if not (0 <= sample.cell_col < GRID_COLS and 0 <= sample.cell_row < GRID_ROWS):
        return {"error": f"Cell ({sample.cell_col},{sample.cell_row}) out of range"}

    file_exists = os.path.exists(FINGERPRINT_FILE)
    with open(FINGERPRINT_FILE, "a", newline="") as f:
        writer = csv.writer(f)
        if not file_exists:
            writer.writerow(["timestamp", "cell_col", "cell_row", "rssi_0", "rssi_1", "rssi_2", "rssi_3"])
        writer.writerow([
            datetime.now().isoformat(),
            sample.cell_col,
            sample.cell_row,
            *[round(r, 1) for r in sample.rssi],
        ])

    logger.info(f"📊 Collected: cell({sample.cell_col},{sample.cell_row}) RSSI={[round(r,1) for r in sample.rssi]}")
    return {
        "status": "ok",
        "cell": f"({sample.cell_col},{sample.cell_row})",
        "total_samples": _count_fingerprints(),
    }


@app.get("/collect/status")
async def collection_status():
    """Show how many samples per cell have been collected."""
    if not os.path.exists(FINGERPRINT_FILE):
        return {"total": 0, "cells": {}}

    counts = {}
    with open(FINGERPRINT_FILE) as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = f"({row['cell_col']},{row['cell_row']})"
            counts[key] = counts.get(key, 0) + 1

    return {"total": sum(counts.values()), "cells": counts}


@app.delete("/collect/reset")
async def reset_collection():
    """Delete all collected fingerprint data."""
    if os.path.exists(FINGERPRINT_FILE):
        os.remove(FINGERPRINT_FILE)
        logger.info("🗑️ Fingerprint data reset")
    return {"status": "reset"}


# ─── Mobile WebSocket (live positioning) ───
@app.websocket("/ws/mobile")
async def mobile_endpoint(websocket: WebSocket):
    global update_count, last_result, frontend_clients

    await websocket.accept()
    logger.info("📱 Mobile connected")
    engine.reset()
    update_count = 0

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_text(json.dumps({"error": "bad json"}))
                continue

            rssi = payload.get("rssi")
            if not isinstance(rssi, list) or len(rssi) != 4:
                await websocket.send_text(json.dumps({"error": "need rssi array of 4"}))
                continue
            try:
                rssi = [float(v) for v in rssi]
            except (ValueError, TypeError):
                await websocket.send_text(json.dumps({"error": "rssi must be numbers"}))
                continue

            update_count += 1
            result = engine.process(rssi)
            last_result = result

            logger.info(
                f"#{update_count:04d} │ "
                f"RSSI {[round(r,1) for r in rssi]} │ "
                f"→ cell({result['cell_col']},{result['cell_row']})"
            )

            # Push to frontend
            payload_out = json.dumps(result)
            dead = set()
            for client in frontend_clients:
                try:
                    await client.send_text(payload_out)
                except Exception:
                    dead.add(client)
            frontend_clients -= dead

            # Ack to mobile
            await websocket.send_text(json.dumps({
                "status": "ok",
                "cell": {"col": result["cell_col"], "row": result["cell_row"]},
            }))

    except WebSocketDisconnect:
        logger.info("📱 Mobile disconnected")
    except Exception as e:
        logger.error(f"Error: {e}", exc_info=True)


# ─── Frontend WebSocket ───
@app.websocket("/ws/frontend")
async def frontend_endpoint(websocket: WebSocket):
    await websocket.accept()
    frontend_clients.add(websocket)
    logger.info(f"🖥️  Frontend connected ({len(frontend_clients)})")

    if last_result:
        try:
            await websocket.send_text(json.dumps(last_result))
        except Exception:
            pass

    try:
        while True:
            msg = await websocket.receive_text()
            if msg == "ping":
                await websocket.send_text('{"pong":true}')
            elif msg == "reset":
                engine.reset()
                await websocket.send_text('{"status":"reset"}')
    except WebSocketDisconnect:
        frontend_clients.discard(websocket)
        logger.info(f"🖥️  Frontend disconnected ({len(frontend_clients)})")


if __name__ == "__main__":
    uvicorn.run(
        "server:app", host=SERVER_HOST, port=SERVER_PORT,
        reload=False, log_level="info",
    )
