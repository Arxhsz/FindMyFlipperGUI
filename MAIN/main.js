/***************************************************************************
 * main.js – Single config.json for all paths + debugMode + mac/keys
 **************************************************************************/
const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const fs   = require('fs');
const path = require('path');
const { spawn } = require('child_process');

// 1) CONFIG LOADING & SAVING
const USER_CONFIG = path.join(app.getPath('userData'), 'config.json');
let cfg = {
  webServicePath:  "",
  activateBatPath: "",
  macAddress:      "",
  keysPath:        "",
  debugMode:       false
};

function loadConfig() {
  try {
    if (fs.existsSync(USER_CONFIG)) {
      Object.assign(cfg,
        JSON.parse(fs.readFileSync(USER_CONFIG, 'utf-8'))
      );
      return;
    }
  } catch (e) {
    console.error("Failed to read config.json, overwriting:", e);
  }
  saveConfig();  // write defaults
}

function saveConfig() {
  try {
    fs.writeFileSync(USER_CONFIG,
      JSON.stringify(cfg, null, 2),
      'utf-8'
    );
  } catch (e) {
    console.error("Failed to write config.json:", e);
  }
}

// 2) WINDOW REFS
let splashWindow   = null;
let mainWindow     = null;
let logsWindow     = null;
let settingsWindow = null;

// 3) APP LIFECYCLE
app.on('ready', () => {
  loadConfig();

  // Auto-open DevTools if debugMode is on
  if (cfg.debugMode) {
    app.once('browser-window-created', (_e, win) => {
      win.webContents.openDevTools({ mode: 'detach' });
    });
  }

  // Decide splash vs main
  if (cfg.webServicePath && cfg.activateBatPath) {
    createMainWindow();
    startPythonServer();
    if (cfg.macAddress) startPersistentFlipper();
  } else {
    createSplashWindow();
  }
});

app.on('window-all-closed', () => {
  app.quit();
});

app.on('activate', () => {
  if (!mainWindow && !splashWindow) {
    if (cfg.webServicePath && cfg.activateBatPath) {
      createMainWindow();
      startPythonServer();
      if (cfg.macAddress) startPersistentFlipper();
    } else {
      createSplashWindow();
    }
  }
});

// 4) SPLASH → MAIN
function createSplashWindow() {
  splashWindow = new BrowserWindow({
    width: 700, height: 500, frame: false, resizable: false,
    icon: path.join(__dirname, "icons", "icon.ico"),
    webPreferences: { nodeIntegration: true, contextIsolation: false }
  });
  splashWindow.loadFile('splash.html');
  splashWindow.setMenu(null);
  splashWindow.on('closed', () => {
    splashWindow = null;
    if (!mainWindow) app.quit();
  });
}

ipcMain.on('set-web-service-path', (_e, p) => {
  cfg.webServicePath = p;
  saveConfig();
});
ipcMain.on('set-activate-bat-path', (_e, p) => {
  cfg.activateBatPath = p;
  saveConfig();
});
ipcMain.on('splash-continue', () => {
  if (splashWindow) splashWindow.close();
  createMainWindow();
  startPythonServer();
});

// 5) MAIN WINDOW + SETTINGS
function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 1200, height: 800, frame: false,
    icon: path.join(__dirname, "icons", "icon.ico"),
    titleBarStyle: 'hiddenInset',
    webPreferences: { nodeIntegration: true, contextIsolation: false }
  });
  mainWindow.loadFile('index.html');
  mainWindow.setMenu(null);
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
  mainWindow.webContents.on('did-finish-load', () => {
    mainWindow.webContents.send('paths-data', cfg);
  });
}

ipcMain.on('open-settings', () => {
  if (settingsWindow) return;
  settingsWindow = new BrowserWindow({
    width: 500, height: 600, frame: false, resizable: false,
    icon: path.join(__dirname, "icons", "icon.ico"),
    webPreferences: { nodeIntegration: true, contextIsolation: false }
  });
  settingsWindow.loadFile('settings.html');
  settingsWindow.setMenu(null);
  settingsWindow.on('closed', () => { settingsWindow = null; });
  settingsWindow.webContents.on('did-finish-load', () => {
    settingsWindow.webContents.send('current-config', cfg);
  });
});

ipcMain.on('save-settings', (_e, newData) => {
  Object.assign(cfg, newData);
  saveConfig();
  if (settingsWindow) settingsWindow.close();
  app.relaunch();
  app.exit(0);
});
ipcMain.on('close-settings', () => {
  if (settingsWindow) settingsWindow.close();
});

// 6) OPEN DIALOGS
ipcMain.on('open-web-service-dialog', async event => {
  const result = await dialog.showOpenDialog({
    properties: ['openFile'],
    filters: [{ name: 'Python Files', extensions: ['py'] }]
  });
  if (!result.canceled && result.filePaths.length) {
    event.sender.send('web-service-path-selected', result.filePaths[0]);
  }
});
ipcMain.on('open-activate-bat-dialog', async event => {
  const result = await dialog.showOpenDialog({
    properties: ['openFile'],
    filters: [{ name: 'Batch Files', extensions: ['bat'] }]
  });
  if (!result.canceled && result.filePaths.length) {
    event.sender.send('activate-bat-path-selected', result.filePaths[0]);
  }
});
function createLogsWindow() {
  logsWindow = new BrowserWindow({
    width: 600,
    height: 400,
    title: "FindMyFlipper – Logs",
    maximizable: false,        // ← disable maximize
    resizable: true,           // you can still resize by drag
    icon: path.join(__dirname, "icons", "icon.ico"),
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  })
  logsWindow.loadFile('logs.html')
  logsWindow.setMenu(null)
  logsWindow.on('closed', () => {
    logsWindow = null
  })
}

ipcMain.on('toggle-logs-window', () => {
  if (logsWindow) {
    logsWindow.close()
  } else {
    createLogsWindow()
  }
})

ipcMain.on('log-line', (_e, line) => {
  if (logsWindow) {
    logsWindow.webContents.send('log-line', line)
  }
})
ipcMain.on('open-keys-dialog', async event => {
  const result = await dialog.showOpenDialog({
    properties: ['openFile'],
    filters: [{ name: 'Keys Files', extensions: ['keys','json'] }]
  });
  if (!result.canceled && result.filePaths.length) {
    event.sender.send('keys-path-selected', result.filePaths[0]);
  }
});

// ─── CONSOLE+ERROR REDIRECT ─────────────────────────
const _origLog   = console.log.bind(console);
const _origError = console.error.bind(console);

// any console.log/x will also send to logsWindow (if open)
console.log   = (...args) => {
  if (logsWindow) logsWindow.webContents.send('log-line', args.join(' '));
  _origLog(...args);
};
console.error = (...args) => {
  if (logsWindow) logsWindow.webContents.send('log-line', args.join(' '));
  _origError(...args);
};
// allow the renderer to push into the logs window, too
ipcMain.on('log-line', (_e, line) => {
  if (logsWindow) logsWindow.webContents.send('log-line', line);
});


// 7) SPAWN PYTHON SERVER
let serverProcess = null;
function startPythonServer() {
  if (!cfg.webServicePath) return;
  serverProcess = spawn('python', [ cfg.webServicePath ]);
  serverProcess.stdout.on('data', d => console.log("[Server]", d.toString().trim()));
  serverProcess.stderr.on('data', d => console.error("[Server ERR]", d.toString().trim()));
}

// 8) SPAWN PERSISTENT HELPER (BLE SERVICE)
let persistentFlipperProcess = null;
function startPersistentFlipper() {
  if (!cfg.macAddress) return;
  const exeName = process.platform === 'win32' ? 'ble_service.exe' : 'ble_service';
  const exePath = path.join(
    app.isPackaged ? process.resourcesPath : __dirname,
    'bin', exeName
  );
  if (persistentFlipperProcess) {
    persistentFlipperProcess.kill();
    persistentFlipperProcess = null;
  }
  persistentFlipperProcess = spawn(exePath, [ cfg.macAddress ]);
  persistentFlipperProcess.stdout.on('data', data => {
    const out = data.toString().trim();
    if (out.startsWith("BATTERY_LEVEL:")) {
      mainWindow.webContents.send('battery-update', Number(out.split(':')[1]));
      return;
    }
    try {
      const msg = JSON.parse(out);
      if (msg.event === 'battery_update') {
        mainWindow.webContents.send('battery-update', msg.level);
      } else if (msg.event === 'error') {
        mainWindow.webContents.send('flipper-error', msg.error);
      }
    } catch {}
    const U = out.toUpperCase();
    if (U.includes("FLIPPER_NOT_FOUND")) mainWindow.webContents.send('flipper-not-found');
    if (U.includes("FLIPPER_CONNECTED")) mainWindow.webContents.send('flipper-connected');
  });
  persistentFlipperProcess.stderr.on('data', d => {
    console.error("[Flipper ERR]", d.toString().trim());
  });
}

// IPC for mac/keys
ipcMain.on('set-flipper-mac', (_e, m) => {
  cfg.macAddress = m;
  saveConfig();
  startPersistentFlipper();
});
ipcMain.on('set-keys-path', (_e, k) => {
  cfg.keysPath = k;
  saveConfig();
  if (mainWindow) mainWindow.webContents.send('paths-data', cfg);
});

// Play-alert & retry
ipcMain.on('play-alert', () => {
  if (persistentFlipperProcess) persistentFlipperProcess.stdin.write("alert\n");
});
ipcMain.on('retry-flipper', () => { startPersistentFlipper(); });

// Minimize & close
ipcMain.on('app-minimize', () => { if (mainWindow) mainWindow.minimize(); });
ipcMain.on('app-close', () => {
  if (persistentFlipperProcess) persistentFlipperProcess.stdin.write("quit\n");
  setTimeout(() => app.quit(), 500);
});
