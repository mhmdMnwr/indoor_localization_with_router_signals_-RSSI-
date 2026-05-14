/**
 * RSSI Indoor Positioning — 3D Visualization
 * 
 * 4×2m room with 15 grid squares (5 cols × 3 rows) as reference.
 * Character moves smoothly across the floor with continuous interpolation.
 * Grid is visual reference only — not movement constraint.
 */

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

// ═══════════════════════════════════════════════════════════════
// Room Configuration — 4m × 2m
// ═══════════════════════════════════════════════════════════════
const AREA_W = 4.0;
const AREA_H = 2.0;
const GRID_COLS = 5;
const GRID_ROWS = 3;
const CELL_W = AREA_W / GRID_COLS;  // 0.8m
const CELL_H = AREA_H / GRID_ROWS;  // ~0.667m
const PERSON_HEIGHT = 0.35;
const LERP_SPEED = 6.0;   // Higher = faster, smoother following

// Router corner positions
const ROUTERS = [
    { x: 0, y: 0, label: 'R0' },
    { x: 4, y: 0, label: 'R1' },
    { x: 0, y: 2, label: 'R2' },
    { x: 4, y: 2, label: 'R3' },
];

// Flip Y→Z so y=0 is at bottom of screen (near camera)
function mapZ(y) { return AREA_H - y; }

// Grid cell centers
const GRID_CELLS = [];
for (let row = 0; row < GRID_ROWS; row++) {
    for (let col = 0; col < GRID_COLS; col++) {
        GRID_CELLS.push({
            col, row,
            cx: col * CELL_W + CELL_W / 2,
            cy: row * CELL_H + CELL_H / 2,
        });
    }
}

// ═══════════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════════
const state = {
    targetPos: new THREE.Vector3(AREA_W / 2, 0, AREA_H / 2),
    currentPos: new THREE.Vector3(AREA_W / 2, 0, AREA_H / 2),
    speed: 0,
    isDemo: true,
    showTrail: true,
    ws: null,
};

// ═══════════════════════════════════════════════════════════════
// Three.js Setup
// ═══════════════════════════════════════════════════════════════
const container = document.getElementById('canvas-container');
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.2;
container.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.fog = new THREE.FogExp2(0x0a0e17, 0.04);

const camera = new THREE.PerspectiveCamera(50, window.innerWidth / window.innerHeight, 0.1, 100);
camera.position.set(2, 5.5, 6.5);
camera.lookAt(2, 0, 1);

const controls = new OrbitControls(camera, renderer.domElement);
controls.target.set(AREA_W / 2, 0, AREA_H / 2);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.maxPolarAngle = Math.PI / 2.1;
controls.minDistance = 2;
controls.maxDistance = 14;
controls.update();

// ═══════════════════════════════════════════════════════════════
// Lighting
// ═══════════════════════════════════════════════════════════════
scene.add(new THREE.AmbientLight(0x4466aa, 0.5));

const dirLight = new THREE.DirectionalLight(0xffffff, 1.8);
dirLight.position.set(5, 8, 5);
dirLight.castShadow = true;
dirLight.shadow.mapSize.set(2048, 2048);
dirLight.shadow.camera.left = -6;
dirLight.shadow.camera.right = 6;
dirLight.shadow.camera.top = 4;
dirLight.shadow.camera.bottom = -4;
dirLight.shadow.bias = -0.001;
scene.add(dirLight);

const rimLight = new THREE.DirectionalLight(0x6ee7b7, 0.4);
rimLight.position.set(-3, 3, -3);
scene.add(rimLight);

ROUTERS.forEach(r => {
    const light = new THREE.PointLight(0x60a5fa, 0.3, 4);
    light.position.set(r.x, 0.3, mapZ(r.y));
    scene.add(light);
});

// ═══════════════════════════════════════════════════════════════
// Floor — 4×2m with 5×3 grid (15 cells)
// ═══════════════════════════════════════════════════════════════
function createFloor() {
    const group = new THREE.Group();

    // Outer floor
    const floorGeo = new THREE.PlaneGeometry(AREA_W + 2, AREA_H + 2);
    const floorMat = new THREE.MeshStandardMaterial({ color: 0x111827, roughness: 0.9 });
    const floor = new THREE.Mesh(floorGeo, floorMat);
    floor.rotation.x = -Math.PI / 2;
    floor.position.set(AREA_W / 2, -0.01, AREA_H / 2);  // center stays same
    floor.receiveShadow = true;
    group.add(floor);

    // Grid cells — alternating checkerboard pattern
    const cellColors = [0x1a2332, 0x1e293b];
    GRID_CELLS.forEach(cell => {
        const geo = new THREE.PlaneGeometry(CELL_W - 0.015, CELL_H - 0.015);
        const mat = new THREE.MeshStandardMaterial({
            color: cellColors[(cell.col + cell.row) % 2],
            roughness: 0.85,
        });
        const mesh = new THREE.Mesh(geo, mat);
        mesh.rotation.x = -Math.PI / 2;
        mesh.position.set(cell.cx, 0.001, mapZ(cell.cy));
        mesh.receiveShadow = true;
        group.add(mesh);
    });

    // Grid lines
    const gridMat = new THREE.LineBasicMaterial({ color: 0x475569, transparent: true, opacity: 0.4 });
    for (let i = 0; i <= GRID_COLS; i++) {
        const x = i * CELL_W;
        group.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints([
            new THREE.Vector3(x, 0.003, mapZ(0)), new THREE.Vector3(x, 0.003, mapZ(AREA_H))
        ]), gridMat));
    }
    for (let i = 0; i <= GRID_ROWS; i++) {
        const y = i * CELL_H;
        group.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints([
            new THREE.Vector3(0, 0.003, mapZ(y)), new THREE.Vector3(AREA_W, 0.003, mapZ(y))
        ]), gridMat));
    }

    // Border glow
    const borderPts = [
        new THREE.Vector3(0, 0.004, mapZ(0)),
        new THREE.Vector3(AREA_W, 0.004, mapZ(0)),
        new THREE.Vector3(AREA_W, 0.004, mapZ(AREA_H)),
        new THREE.Vector3(0, 0.004, mapZ(AREA_H)),
        new THREE.Vector3(0, 0.004, mapZ(0)),
    ];
    group.add(new THREE.Line(
        new THREE.BufferGeometry().setFromPoints(borderPts),
        new THREE.LineBasicMaterial({ color: 0x6ee7b7, transparent: true, opacity: 0.4 })
    ));

    // Cell labels
    GRID_CELLS.forEach(cell => {
        const canvas = document.createElement('canvas');
        canvas.width = 96;
        canvas.height = 48;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = 'rgba(100, 116, 139, 0.4)';
        ctx.font = 'bold 22px Inter, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(`${cell.col},${cell.row}`, 48, 32);

        const texture = new THREE.CanvasTexture(canvas);
        const spriteMat = new THREE.SpriteMaterial({ map: texture, transparent: true, opacity: 0.5 });
        const sprite = new THREE.Sprite(spriteMat);
        sprite.position.set(cell.cx, 0.01, mapZ(cell.cy));
        sprite.scale.set(0.35, 0.18, 1);
        group.add(sprite);
    });

    return group;
}
scene.add(createFloor());

// ═══════════════════════════════════════════════════════════════
// Soft highlight that follows the character (no grid snap)
// ═══════════════════════════════════════════════════════════════
const glowRingGeo = new THREE.RingGeometry(0.15, 0.22, 48);
const glowRingMat = new THREE.MeshBasicMaterial({
    color: 0x6ee7b7, transparent: true, opacity: 0.12, side: THREE.DoubleSide,
});
const glowRing = new THREE.Mesh(glowRingGeo, glowRingMat);
glowRing.rotation.x = -Math.PI / 2;
glowRing.position.set(AREA_W / 2, 0.006, AREA_H / 2);
scene.add(glowRing);

// ═══════════════════════════════════════════════════════════════
// Router Markers
// ═══════════════════════════════════════════════════════════════
function createRouterMarker(rx, ry, color) {
    const group = new THREE.Group();
    group.position.set(rx, 0, ry);

    const base = new THREE.Mesh(
        new THREE.CylinderGeometry(0.06, 0.08, 0.04, 16),
        new THREE.MeshStandardMaterial({ color, roughness: 0.3, metalness: 0.7 })
    );
    base.position.y = 0.02;
    base.castShadow = true;
    group.add(base);

    const ant = new THREE.Mesh(
        new THREE.CylinderGeometry(0.01, 0.01, 0.15, 8),
        new THREE.MeshStandardMaterial({ color: 0x94a3b8, roughness: 0.4, metalness: 0.6 })
    );
    ant.position.y = 0.115;
    group.add(ant);

    const ring = new THREE.Mesh(
        new THREE.RingGeometry(0.1, 0.14, 32),
        new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.2, side: THREE.DoubleSide })
    );
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.005;
    group.add(ring);

    const pulse = new THREE.Mesh(
        new THREE.RingGeometry(0.12, 0.13, 32),
        new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.3, side: THREE.DoubleSide })
    );
    pulse.rotation.x = -Math.PI / 2;
    pulse.position.y = 0.004;
    pulse.userData.pulse = true;
    group.add(pulse);

    return group;
}

const routerColors = [0x60a5fa, 0xa78bfa, 0xfb923c, 0xf472b6];
ROUTERS.forEach((r, i) => scene.add(createRouterMarker(r.x, mapZ(r.y), routerColors[i])));

// ═══════════════════════════════════════════════════════════════
// Person Figure
// ═══════════════════════════════════════════════════════════════
function createPerson() {
    const group = new THREE.Group();

    const bodyMat = new THREE.MeshStandardMaterial({
        color: 0x6ee7b7, roughness: 0.25, metalness: 0.3,
        emissive: 0x6ee7b7, emissiveIntensity: 0.15,
    });

    const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.06, 0.16, 8, 16), bodyMat);
    body.position.y = PERSON_HEIGHT * 0.55;
    body.castShadow = true;
    group.add(body);

    const head = new THREE.Mesh(
        new THREE.SphereGeometry(0.05, 16, 12),
        new THREE.MeshStandardMaterial({ color: 0xfcd34d, roughness: 0.3, metalness: 0.2 })
    );
    head.position.y = PERSON_HEIGHT * 0.55 + 0.13;
    head.castShadow = true;
    group.add(head);

    const glow = new THREE.Mesh(
        new THREE.CircleGeometry(0.12, 32),
        new THREE.MeshBasicMaterial({ color: 0x6ee7b7, transparent: true, opacity: 0.25 })
    );
    glow.rotation.x = -Math.PI / 2;
    glow.position.y = 0.003;
    group.add(glow);

    group.position.set(AREA_W / 2, 0, AREA_H / 2);
    return group;
}

const person = createPerson();
scene.add(person);

// ═══════════════════════════════════════════════════════════════
// Trail System
// ═══════════════════════════════════════════════════════════════
const trailMaxPoints = 300;
const trailPositions = new Float32Array(trailMaxPoints * 3);
const trailGeometry = new THREE.BufferGeometry();
trailGeometry.setAttribute('position', new THREE.BufferAttribute(trailPositions, 3));
trailGeometry.setDrawRange(0, 0);

const trailLine = new THREE.Line(trailGeometry, new THREE.LineBasicMaterial({
    color: 0x6ee7b7, transparent: true, opacity: 0.4,
}));
trailLine.frustumCulled = false;
scene.add(trailLine);

let trailIndex = 0;
let lastTrailPos = new THREE.Vector3(AREA_W / 2, 0, AREA_H / 2);

function addTrailPoint(x, z) {
    const dx = x - lastTrailPos.x, dz = z - lastTrailPos.z;
    if (dx * dx + dz * dz < 0.001) return;
    const idx = trailIndex % trailMaxPoints;
    trailPositions[idx * 3] = x;
    trailPositions[idx * 3 + 1] = 0.005;
    trailPositions[idx * 3 + 2] = z;
    trailIndex++;
    trailGeometry.setDrawRange(0, Math.min(trailIndex, trailMaxPoints));
    trailGeometry.attributes.position.needsUpdate = true;
    lastTrailPos.set(x, 0, z);
}

// ═══════════════════════════════════════════════════════════════
// Demo — smooth Lissajous path across the 4×2 space
// ═══════════════════════════════════════════════════════════════
function getDemoPosition(t) {
    const cx = AREA_W / 2, cy = AREA_H / 2;
    const x = cx + (AREA_W * 0.42) * Math.sin(t * 0.4) * Math.cos(t * 0.15);
    const y = cy + (AREA_H * 0.38) * Math.cos(t * 0.3) * Math.sin(t * 0.2);
    return {
        x: THREE.MathUtils.clamp(x, 0.15, AREA_W - 0.15),
        y: mapZ(THREE.MathUtils.clamp(y, 0.15, AREA_H - 0.15)),
    };
}

// Which cell is a point in? (for HUD display only)
function posToCell(x, y) {
    return {
        col: Math.max(0, Math.min(GRID_COLS - 1, Math.floor(x / CELL_W))),
        row: Math.max(0, Math.min(GRID_ROWS - 1, Math.floor(y / CELL_H))),
    };
}

// ═══════════════════════════════════════════════════════════════
// Toast
// ═══════════════════════════════════════════════════════════════
function showToast(msg, type = 'info') {
    let c = document.getElementById('toast-container');
    if (!c) {
        c = document.createElement('div');
        c.id = 'toast-container';
        c.style.cssText = 'position:fixed;top:80px;left:50%;transform:translateX(-50%);z-index:1000;display:flex;flex-direction:column;gap:8px;pointer-events:none;';
        document.body.appendChild(c);
    }
    const colors = { info: '#60a5fa', success: '#22c55e', error: '#ef4444', warning: '#f59e0b' };
    const toast = document.createElement('div');
    toast.style.cssText = `padding:12px 24px;background:rgba(17,24,39,0.92);border:1px solid ${colors[type] || colors.info};border-radius:12px;color:#f1f5f9;font-family:'Inter',sans-serif;font-size:13px;font-weight:500;backdrop-filter:blur(12px);box-shadow:0 4px 24px rgba(0,0,0,0.4);pointer-events:auto;opacity:0;transform:translateY(-10px);transition:all 0.3s ease;`;
    toast.textContent = msg;
    c.appendChild(toast);
    requestAnimationFrame(() => { toast.style.opacity = '1'; toast.style.transform = 'translateY(0)'; });
    setTimeout(() => { toast.style.opacity = '0'; setTimeout(() => toast.remove(), 300); }, 4000);
}

// ═══════════════════════════════════════════════════════════════
// WebSocket
// ═══════════════════════════════════════════════════════════════
function connectWebSocket(url) {
    if (state.ws) { state.ws.close(); state.ws = null; }
    showToast('Connecting...', 'info');
    updateWsBadge('connecting');

    try {
        const ws = new WebSocket(url);
        state.ws = ws;

        ws.onopen = () => {
            showToast('Connected!', 'success');
            updateWsBadge('connected');
            state.isDemo = false;
            document.getElementById('btn-demo').classList.remove('active');
            document.querySelector('#badge-mode .badge-dot').className = 'badge-dot connected';
            document.getElementById('mode-text').textContent = 'Live Mode';
        };

        ws.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                if (data.cell_col !== undefined && data.cell_row !== undefined) {
                    // Cell-based positioning: compute cell center, then LERP smoothly
                    const cellCx = data.cell_col * CELL_W + CELL_W / 2;
                    const cellCy = data.cell_row * CELL_H + CELL_H / 2;
                    state.targetPos.set(cellCx, 0, mapZ(cellCy));
                    state.speed = 0;
                    const cell = { col: data.cell_col, row: data.cell_row };
                    updateCoordsHUD(cellCx, cellCy, 0, 0, cell);
                }
            } catch (e) { console.warn('[WS] Parse error:', e); }
        };

        ws.onclose = (e) => {
            showToast('Disconnected', 'warning');
            updateWsBadge('disconnected');
            state.ws = null;
        };

        ws.onerror = () => {
            showToast('Connection failed!', 'error');
            updateWsBadge('disconnected');
        };
    } catch (e) {
        showToast('Error: ' + e.message, 'error');
        updateWsBadge('disconnected');
    }
}

function updateWsBadge(status) {
    const dot = document.querySelector('#badge-ws .badge-dot');
    const text = document.getElementById('ws-text');
    dot.className = 'badge-dot ' + (status === 'connected' ? 'connected' : status === 'connecting' ? 'demo' : 'disconnected');
    text.textContent = status === 'connected' ? 'Connected' : status === 'connecting' ? 'Connecting...' : 'Disconnected';
}

function updateCoordsHUD(x, y, z, speed, cell) {
    document.getElementById('coord-x').textContent = x.toFixed(2);
    document.getElementById('coord-y').textContent = y.toFixed(2);
    document.getElementById('coord-z').textContent = z.toFixed(2);
    document.getElementById('coord-speed').textContent = speed.toFixed(2);
    const cellEl = document.getElementById('coord-cell');
    if (cellEl && cell) cellEl.textContent = `(${cell.col},${cell.row})`;
}

// ═══════════════════════════════════════════════════════════════
// UI Bindings
// ═══════════════════════════════════════════════════════════════
document.getElementById('btn-connect').addEventListener('click', () => {
    const url = document.getElementById('ws-url').value.trim();
    if (url) connectWebSocket(url);
});

document.getElementById('btn-demo').addEventListener('click', () => {
    if (state.ws) { state.ws.close(); state.ws = null; }
    state.isDemo = true;
    document.getElementById('btn-demo').classList.add('active');
    updateWsBadge('disconnected');
    document.querySelector('#badge-mode .badge-dot').className = 'badge-dot demo';
    document.getElementById('mode-text').textContent = 'Demo Mode';
});

document.getElementById('btn-trail').addEventListener('click', () => {
    state.showTrail = !state.showTrail;
    document.getElementById('btn-trail').classList.toggle('active', state.showTrail);
    trailLine.visible = state.showTrail;
});

document.getElementById('btn-reset-view').addEventListener('click', () => {
    camera.position.set(2, 5.5, 6.5);
    controls.target.set(AREA_W / 2, 0, AREA_H / 2);
    controls.update();
});

// ═══════════════════════════════════════════════════════════════
// Resize
// ═══════════════════════════════════════════════════════════════
window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

// ═══════════════════════════════════════════════════════════════
// Animation Loop — smooth continuous movement
// ═══════════════════════════════════════════════════════════════
const clock = new THREE.Clock();
let prevPos = new THREE.Vector3(AREA_W / 2, 0, AREA_H / 2);

function animate() {
    requestAnimationFrame(animate);
    const dt = clock.getDelta();
    const elapsed = clock.getElapsedTime();

    // Demo mode — smooth continuous path
    if (state.isDemo) {
        const demoPos = getDemoPosition(elapsed);
        state.targetPos.set(demoPos.x, 0, demoPos.y);
        const spd = state.currentPos.distanceTo(state.targetPos) / Math.max(dt, 0.001);
        state.speed = spd;
        const cell = posToCell(demoPos.x, demoPos.y);
        updateCoordsHUD(state.currentPos.x, state.currentPos.z, 0, Math.min(spd, 2), cell);
    }

    // Smooth LERP — continuous, fluid movement
    const lerpFactor = 1.0 - Math.exp(-LERP_SPEED * dt);
    state.currentPos.lerp(state.targetPos, lerpFactor);

    // Update person — continuous position
    person.position.x = state.currentPos.x;
    person.position.z = state.currentPos.z;
    person.position.y = Math.sin(elapsed * 3) * 0.006;

    // Glow ring follows person smoothly
    glowRing.position.x = state.currentPos.x;
    glowRing.position.z = state.currentPos.z;
    glowRingMat.opacity = 0.08 + 0.05 * Math.sin(elapsed * 2);
    const glowScale = 1.0 + 0.1 * Math.sin(elapsed * 1.5);
    glowRing.scale.set(glowScale, glowScale, 1);

    // Face direction of movement
    const moveDir = new THREE.Vector3().subVectors(state.currentPos, prevPos);
    if (moveDir.lengthSq() > 0.000005) {
        const angle = Math.atan2(moveDir.x, moveDir.z);
        person.rotation.y = THREE.MathUtils.lerp(person.rotation.y, angle, lerpFactor * 0.4);
    }
    prevPos.copy(state.currentPos);

    // Trail
    if (state.showTrail) addTrailPoint(state.currentPos.x, state.currentPos.z);

    // Router pulse animation
    scene.traverse(obj => {
        if (obj.userData.pulse) {
            const s = 1 + 0.3 * Math.sin(elapsed * 2 + obj.parent.position.x * 3);
            obj.scale.set(s, s, 1);
            obj.material.opacity = 0.15 + 0.15 * Math.cos(elapsed * 2);
        }
    });

    controls.update();
    renderer.render(scene, camera);
}

animate();
