const { app, BrowserWindow, Tray, Menu, shell, ipcMain } = require('electron');
const path = require('path');
const { spawn } = require('child_process');

let mainWindow;
let tray;
let aresBackend = null;

const PORT = 8787;
const PACKAGE_ROOT = path.resolve(__dirname, '..');
const BACKEND_CMD = process.env.ARES_BACKEND_CMD || 'node';
const BACKEND_ARGS = process.env.ARES_BACKEND_ARGS ? process.env.ARES_BACKEND_ARGS.split(' ') : [];
const DEV_PORT = String(process.env.ARES_PORT || '8787');
const DEV_URL = `http://127.0.0.1:${DEV_PORT}`;

function isBackendUp() {
  return new Promise((resolve) => {
    try {
      const http = require('http');
      const req = http.get(`${DEV_URL}/`, (res) => {
        resolve(true);
      });
      req.on('error', () => resolve(false));
      req.setTimeout(500, () => { req.destroy(); resolve(false); });
    } catch {
      resolve(false);
    }
  });
}

async function startBackend() {
  const up = await isBackendUp();
  if (up) return aresBackend;

  const webuiDir = path.resolve(PACKAGE_ROOT, '..', 'webui');
  const backendScript = path.resolve(webuiDir, 'server.py');
  const args = process.env.ARES_BACKEND_ARGS_PY ? process.env.ARES_BACKEND_ARGS_PY.split(' ') : [];
  const pythonBin = process.env.ARES_PYTHON || findPython();

  const child = spawn(pythonBin, [backendScript, ...args], {
    cwd: webuiDir,
    detached: true,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, PYTHONUNBUFFERED: '1' },
    windowsHide: true,
  });

  child.on('error', (err) => {
    console.error('[ares-backend] spawn error', err);
  });

  child.stdout.on('data', (d) => console.log('[ares-backend]', d.toString()));
  child.stderr.on('data', (d) => console.error('[ares-backend]', d.toString()));
  child.unref();
  aresBackend = child;

  await new Promise((r) => setTimeout(r, 750));
  return child;
}

function findPython() {
  const candidates = ['python', 'python3', 'py', path.join('C:\\Python311\\python.exe'), path.join('C:\\Python310\\python.exe')];
  for (const bin of candidates) {
    try {
      const { spawnSync } = require('child_process');
      const res = spawnSync(bin, ['-c', 'print(1)']);
      if (res.status === 0) return bin;
    } catch {}
  }
  return 'python';
}

function createWindow() {
  mainWindow = new BrowserWindow({
    title: 'ARES',
    width: 1280,
    height: 900,
    minWidth: 860,
    minHeight: 640,
    icon: path.join(PACKAGE_ROOT, 'assets', 'icon.ico'),
    show: false,
    webPreferences: {
      preload: path.join(PACKAGE_ROOT, 'src', 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  mainWindow.webContents.on('did-fail-load', (e, code, desc) => {
    console.error('[web] did-fail-load', code, desc);
  });
  mainWindow.webContents.on('page-title-updated', () => {});
  mainWindow.webContents.openDevTools({ mode: 'right' });

  mainWindow.once('ready-to-show', () => mainWindow.show());
  mainWindow.on('close', (e) => {
    if (!app.isQuitting) { e.preventDefault(); mainWindow.hide(); }
  });

  mainWindow.loadURL(DEV_URL).catch((err) => console.error('[web] loadURL error', err));
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http')) { shell.openExternal(url); }
    return { action: 'deny' };
  });
}

function createTray() {
  try {
    tray = new Tray(path.join(PACKAGE_ROOT, 'assets', 'icon.ico'));
  } catch {
    try { tray = new Tray(path.join(PACKAGE_ROOT, 'assets', 'icon.png')); } catch { return; }
  }
  tray.setToolTip('ARES');
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Show ARES', click: () => { mainWindow.show(); mainWindow.focus(); } },
    { label: 'Hide', click: () => mainWindow.hide() },
    { type: 'separator' },
    { label: 'Quit', click: () => { app.isQuitting = true; app.quit(); } }
  ]));
  tray.on('click', () => { mainWindow.isVisible() ? mainWindow.hide() : mainWindow.show(); mainWindow.focus(); });
}

app.setLoginItemSettings({ openAtLogin: true, openAsHidden: true });

process.on('unhandledRejection', (err) => {
  if (err && err.message && /Failed to load image/.test(err.message)) return;
  console.error('[unhandledRejection]', err);
});
app.on('ready', () => {});
process.on('SIGINT', () => app.quit());
process.on('SIGTERM', () => app.quit());

app.whenReady().then(async () => {
  await startBackend();
  createWindow();
  createTray();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', () => {
  app.isQuitting = true;
  aresBackend?.kill('SIGTERM');
});
