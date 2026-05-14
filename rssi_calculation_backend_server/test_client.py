"""
Test Client — Simulates a mobile phone sending RSSI data.

This script connects to the server via WebSocket and sends
synthetic RSSI data that simulates a person walking in a path
inside the 4×2 meter area. Useful for testing without the actual phone.

Usage:
    python test_client.py

Options (edit the constants below):
    WALK_PATTERN:  "circle", "diagonal", "random", "static"
    NOISE_STD:     Standard deviation of RSSI noise (dBm)
    INTERVAL:      Seconds between readings
"""

import asyncio
import json
import math
import random
import time

import websockets

from config import SERVER_PORT, ROUTER_POSITIONS, RSSI_REF_PER_ROUTER, PATH_LOSS_EXPONENT_PER_ROUTER, RSSI_REF, PATH_LOSS_EXPONENT

# =============================================================================
# TEST CONFIGURATION
# =============================================================================
SERVER_URL = f"ws://localhost:{SERVER_PORT}/ws/mobile"

# Walk pattern: "circle", "diagonal", "random", "static"
WALK_PATTERN = "circle"

# RSSI noise standard deviation (dBm). Real-world is typically 3-8 dBm.
NOISE_STD = 5.0

# Time between readings (seconds)
INTERVAL = 1.0

# Duration of test (seconds). Set to 0 for infinite.
DURATION = 60

# Static position (only used with "static" pattern)
STATIC_X, STATIC_Y = 2.0, 1.0


# =============================================================================
# SIMULATE RSSI
# =============================================================================
def distance_to_rssi(distance: float, router_id: str = "", noise_std: float = NOISE_STD) -> float:
    """
    Convert a true distance to a simulated RSSI reading with noise.
    Uses per-router calibration values for realistic simulation.
    """
    if distance < 0.05:
        distance = 0.05

    rssi_ref = RSSI_REF_PER_ROUTER.get(router_id, RSSI_REF)
    n = PATH_LOSS_EXPONENT_PER_ROUTER.get(router_id, PATH_LOSS_EXPONENT)
    rssi_true = rssi_ref - 10 * n * math.log10(distance)

    noise = random.gauss(0, noise_std)

    # 5% chance of a large outlier (simulates real-world RSSI spikes)
    if random.random() < 0.05:
        noise += random.choice([-1, 1]) * random.uniform(10, 20)

    return rssi_true + noise


def generate_position(t: float, pattern: str) -> tuple[float, float]:
    """Generate a test position based on time and pattern."""

    if pattern == "circle":
        # Ellipse centered at (2, 1), scaled for 4×2 area, period 20s
        cx, cy = 2.0, 1.0
        rx, ry = 1.4, 0.7  # Ellipse radii matching area proportions
        angle = 2 * math.pi * t / 20.0
        return (cx + rx * math.cos(angle), cy + ry * math.sin(angle))

    elif pattern == "diagonal":
        # Walk diagonally across 4×2 area, back and forth
        period = 10.0
        progress = (t % (2 * period)) / period
        if progress > 1.0:
            progress = 2.0 - progress
        x = 0.3 + progress * 3.4  # 0.3 → 3.7
        y = 0.2 + progress * 1.6  # 0.2 → 1.8
        return (x, y)

    elif pattern == "random":
        # Random walk scaled for 4×2 area
        x = 2.0 + 1.2 * math.sin(0.3 * t) + 0.6 * math.sin(0.7 * t)
        y = 1.0 + 0.5 * math.cos(0.4 * t) + 0.3 * math.cos(0.9 * t)
        return (max(0.2, min(3.8, x)), max(0.2, min(1.8, y)))

    elif pattern == "static":
        return (STATIC_X, STATIC_Y)

    else:
        return (2.0, 1.0)


def simulate_rssi(true_x: float, true_y: float) -> list[float]:
    """
    Given a true position, compute simulated RSSI from each router.
    """
    rssi_values = []
    for name, (rx, ry) in ROUTER_POSITIONS.items():
        dist = math.sqrt((true_x - rx) ** 2 + (true_y - ry) ** 2)
        rssi = distance_to_rssi(dist, router_id=name)
        rssi_values.append(round(rssi, 1))
    return rssi_values


# =============================================================================
# WEBSOCKET CLIENT
# =============================================================================
async def run_test():
    print(f"Connecting to {SERVER_URL}...")
    print(f"Pattern: {WALK_PATTERN}")
    print(f"Noise std: {NOISE_STD} dBm")
    print(f"Interval: {INTERVAL}s")
    print(f"Duration: {DURATION}s (0 = infinite)")
    print("-" * 60)

    async with websockets.connect(SERVER_URL) as ws:
        print("✅ Connected to server!")
        start_time = time.time()
        count = 0

        try:
            while True:
                elapsed = time.time() - start_time
                if DURATION > 0 and elapsed > DURATION:
                    print(f"\n⏱️  Test complete ({DURATION}s elapsed)")
                    break

                # Generate true position
                true_x, true_y = generate_position(elapsed, WALK_PATTERN)

                # Simulate RSSI readings
                rssi_values = simulate_rssi(true_x, true_y)

                # Send to server
                payload = json.dumps({"rssi": rssi_values})
                await ws.send(payload)

                # Receive response
                response = await ws.recv()
                result = json.loads(response)

                if "error" in result:
                    print(f"❌ Server error: {result['error']}")
                else:
                    pos = result.get("position", {})
                    est_x = pos.get("x", 0)
                    est_y = pos.get("y", 0)
                    error = math.sqrt(
                        (est_x - true_x) ** 2 + (est_y - true_y) ** 2
                    )

                    count += 1
                    print(
                        f"#{count:04d} │ "
                        f"True ({true_x:.2f}, {true_y:.2f}) │ "
                        f"Est  ({est_x:.2f}, {est_y:.2f}) │ "
                        f"Error: {error:.3f}m │ "
                        f"RSSI {rssi_values}"
                    )

                await asyncio.sleep(INTERVAL)

        except KeyboardInterrupt:
            print("\n🛑 Test stopped by user")


# =============================================================================
# FRONTEND LISTENER (optional: also listen to frontend output)
# =============================================================================
async def listen_frontend():
    """Connect as a frontend client and print received positions."""
    url = f"ws://localhost:{SERVER_PORT}/ws/frontend"
    print(f"Listening on {url} as frontend client...")

    async with websockets.connect(url) as ws:
        print("✅ Connected as frontend listener!")
        try:
            while True:
                msg = await ws.recv()
                data = json.loads(msg)
                print(
                    f"Frontend received: "
                    f"({data['x']:.4f}, {data['y']:.4f}) "
                    f"speed={data.get('speed', 0):.3f} m/s"
                )
        except KeyboardInterrupt:
            print("Frontend listener stopped")


# =============================================================================
# MAIN
# =============================================================================
if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == "frontend":
        asyncio.run(listen_frontend())
    else:
        asyncio.run(run_test())
