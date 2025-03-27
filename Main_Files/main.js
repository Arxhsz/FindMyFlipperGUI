/***************************************************************************
 * main.js – Merged and modified with settings, retry logic, play-alert,
 * and enhanced output handling for FLIPPER_CONNECTED.
 **************************************************************************/
const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');

let splashWindow = null;
let mainWindow = null;
let logsWindow = null;
let settingsWindow = null;
let persistentFlipperProcess = null;
let serverProcess = null;

// Configuration object to hold paths
let PATHS_DATA = {
  webService: "",
  batPath: "",
  macAddress: "",
  keysPath: ""
};

const PATHS_TXT = path.join(__dirname, "Paths.txt");

// For logging
let appLogs = [];
function pushLog(line) {
  appLogs.push(line);
  if (logsWindow) {
    logsWindow.webContents.send('new-log-line', line);
  }
}
const originalLog = console.log;
console.log = (...args) => {
  const line = args.map(a => (typeof a === 'object' ? JSON.stringify(a) : String(a))).join(' ');
  pushLog(line);
  originalLog(...args);
};
const originalError = console.error;
console.error = (...args) => {
  const line = args.map(a => (typeof a === 'object' ? JSON.stringify(a) : String(a))).join(' ');
  pushLog("ERROR: " + line);
  originalError(...args);
};

/***************************************************************************
 * Read/Write the configuration file (Paths.txt)
 **************************************************************************/
function readPathsFile() {
  try {
    if (!fs.existsSync(PATHS_TXT)) return false;
    const lines = fs.readFileSync(PATHS_TXT, 'utf-8').split(/\r?\n/);
    lines.forEach(line => {
      const trimmed = line.trim();
      if (!trimmed) return;
      // Expecting format: Key - "Value"
      const dashIndex = trimmed.indexOf('-');
      if (dashIndex === -1) return;
      const keyPart = trimmed.substring(0, dashIndex).trim();
      const match = trimmed.match(/"([^"]*)"/);
      if (!match) return;
      const val = match[1];
      if (keyPart.startsWith("Web_Service_Path")) {
        PATHS_DATA.webService = val;
      } else if (keyPart.startsWith("Activate.bat_Path")) {
        PATHS_DATA.batPath = val;
      } else if (keyPart.startsWith("Mac_Address")) {
        PATHS_DATA.macAddress = val;
      } else if (keyPart.startsWith(".keys_Path")) {
        PATHS_DATA.keysPath = val;
      }
    });
    return true;
  } catch (err) {
    console.error("Error reading Paths.txt:", err);
    return false;
  }
}

function writePathsFile() {
  const content = [
    `Web_Service_Path - "${PATHS_DATA.webService}"`,
    `Activate.bat_Path - "${PATHS_DATA.batPath}"`,
    `Mac_Address - "${PATHS_DATA.macAddress}"`,
    `.keys_Path - "${PATHS_DATA.keysPath}"`
  ].join('\r\n');
  try {
    fs.writeFileSync(PATHS_TXT, content, 'utf-8');
    console.log("Paths.txt updated:\n" + content);
  } catch (err) {
    console.error("Error writing Paths.txt:", err);
  }
}

/***************************************************************************
 * Window creation
 **************************************************************************/
function createSplashWindow() {
  splashWindow = new BrowserWindow({
    width: 700,
    height: 500,
    frame: false,
    resizable: false,
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

function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    frame: false,
    icon: path.join(__dirname, "icons", "icon.ico"),
    titleBarStyle: 'hiddenInset',
    webPreferences: { nodeIntegration: true, contextIsolation: false }
  });
  mainWindow.loadFile('index.html');
  mainWindow.setMenu(null);
  mainWindow.on('closed', () => {
    if (logsWindow) { logsWindow.close(); logsWindow = null; }
    mainWindow = null;
  });
  mainWindow.webContents.on('did-finish-load', () => {
    // Send stored paths so renderer can decide whether to skip key modal
    mainWindow.webContents.send('paths-data', PATHS_DATA);
  });
}

function createLogsWindow() {
  logsWindow = new BrowserWindow({
    width: 600,
    height: 400,
    title: "Logs",
    frame: false,
    // ADD YOUR ICON PATH HERE:
    icon: path.join(__dirname, 'icons', 'icon.ico'), 
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  logsWindow.loadFile('logs.html');
  logsWindow.setMenu(null);

  logsWindow.on('closed', () => {
    logsWindow = null;
  });

  // When logs window finishes loading, send it the existing logs
  logsWindow.webContents.on('did-finish-load', () => {
    logsWindow.webContents.send('load-initial-logs', appLogs);
  });
}

function createSettingsWindow() {
  settingsWindow = new BrowserWindow({
    width: 500,
    height: 400,
    // Remove the standard OS title bar:
    frame: false,
    resizable: false,
    icon: path.join(__dirname, "icons", "icon.ico"),
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  settingsWindow.loadFile('settings.html');
  settingsWindow.setMenu(null);

  settingsWindow.on('closed', () => {
    settingsWindow = null;
  });

  settingsWindow.webContents.on('did-finish-load', () => {
    // Send current PATHS_DATA so the fields show the existing values
    settingsWindow.webContents.send('current-paths', PATHS_DATA);
  });
}

function toggleLogsWindow() {
  if (logsWindow) { logsWindow.close(); logsWindow = null; }
  else { createLogsWindow(); }
}

/***************************************************************************
 * Start the Python server & Persistent Flipper
 **************************************************************************/
function startPythonServer() {
  if (!PATHS_DATA.webService) {
    console.log("No Python service path set, not starting server yet.");
    return;
  }
  console.log("Starting python server:", PATHS_DATA.webService);
  serverProcess = spawn('python', [PATHS_DATA.webService]);
  serverProcess.stdout.on('data', d => console.log("Server:", d.toString().trim()));
  serverProcess.stderr.on('data', d => console.error("Server error:", d.toString().trim()));
  serverProcess.on('close', code => console.log("Server process exited with code", code));
}

/**
 * Start or restart persistent_flipper.py with the given MAC.
 * Output is converted to uppercase so that "FLIPPER_CONNECTED" is reliably detected.
 */
function startPersistentFlipper() {
  if (!PATHS_DATA.macAddress) {
    console.log("No Flipper MAC is set yet. Cannot start persistent process.");
    return;
  }
  console.log("Starting persistent_flipper.py with MAC:", PATHS_DATA.macAddress);
  if (persistentFlipperProcess) {
    try { persistentFlipperProcess.kill(); } catch (err) { console.error(err); }
    persistentFlipperProcess = null;
  }
  persistentFlipperProcess = spawn('python', [
    path.join(__dirname, 'persistent_flipper.py'),
    PATHS_DATA.macAddress
  ]);
  persistentFlipperProcess.stdout.on('data', data => {
    const output = data.toString().trim();
    console.log("Flipper:", output);
    if (mainWindow) {
      const upperOutput = output.toUpperCase();
      if (upperOutput.includes("FLIPPER_NOT_FOUND")) {
        mainWindow.webContents.send('flipper-not-found');
      } else if (upperOutput.includes("FLIPPER_CONNECTED")) {
        mainWindow.webContents.send('flipper-connected');
      } else if (upperOutput.includes("SUCCESS! ALERT PLAYED.")) {
        mainWindow.webContents.send('play-alert-output', "Success! Alert played.");
      }
    }
  });
  persistentFlipperProcess.stderr.on('data', data => {
    console.error("Flipper Error:", data.toString().trim());
    if (mainWindow) {
      mainWindow.webContents.send('play-alert-error', data.toString().trim());
    }
  });
  persistentFlipperProcess.on('close', code => {
    console.log("Persistent flipper process exited with code", code);
  });
}

/***************************************************************************
 * IPC Handlers
 **************************************************************************/
// File dialogs
ipcMain.on('open-web-service-dialog', async (event) => {
  const result = await dialog.showOpenDialog({
    properties: ['openFile'],
    filters: [{ name: 'Python Files', extensions: ['py'] }]
  });
  if (!result.canceled && result.filePaths.length > 0) {
    event.sender.send('web-service-path-selected', result.filePaths[0]);
  }
});

ipcMain.on('open-activate-bat-dialog', async (event) => {
  const result = await dialog.showOpenDialog({
    properties: ['openFile'],
    filters: [{ name: 'Batch Files', extensions: ['bat'] }]
  });
  if (!result.canceled && result.filePaths.length > 0) {
    event.sender.send('activate-bat-path-selected', result.filePaths[0]);
  }
});

// From splash: set .py and .bat paths
ipcMain.on('set-web-service-path', (event, pyPath) => {
  PATHS_DATA.webService = pyPath;
  console.log("Python Service Path set to:", pyPath);
});
ipcMain.on('set-activate-bat-path', (event, batPath) => {
  PATHS_DATA.batPath = batPath;
  console.log("Activate BAT Path set to:", batPath);
});

// After user hits "Continue" in splash
ipcMain.on('splash-continue', () => {
  writePathsFile();
  if (splashWindow) {
    splashWindow.close();
    splashWindow = null;
  }
  createMainWindow();
  if (PATHS_DATA.webService) {
    startPythonServer();
  }
});

// From main window: set MAC and .keys path
ipcMain.on('set-flipper-mac', (event, mac) => {
  PATHS_DATA.macAddress = mac.trim();
  console.log("Flipper MAC set to:", PATHS_DATA.macAddress);
  writePathsFile();
  startPersistentFlipper();
});
ipcMain.on('set-keys-path', (event, keysFilePath) => {
  PATHS_DATA.keysPath = keysFilePath;
  console.log(".keys path set to:", keysFilePath);
  writePathsFile();
});

// "Play Alert" command: send "alert" to persistent_flipper.py via stdin
ipcMain.on('play-alert', () => {
  if (!persistentFlipperProcess) {
    console.log("No persistent flipper process running, cannot send alert.");
    return;
  }
  console.log("Sending 'alert' to persistent_flipper.py via stdin...");
  persistentFlipperProcess.stdin.write("alert\n");
});

// Retry flipper search: restart persistent_flipper.py
ipcMain.on('retry-flipper', () => {
  console.log("User requested a flipper retry search.");
  startPersistentFlipper();
});

// Toggle logs window
ipcMain.on('toggle-logs-window', () => {
  toggleLogsWindow();
});

// ----- Settings Window IPC Handlers -----
ipcMain.on('open-settings', () => {
  if (!settingsWindow) {
    createSettingsWindow();
  }
});
ipcMain.on('save-settings', (event, newData) => {
  PATHS_DATA.webService = newData.webService;
  PATHS_DATA.batPath = newData.batPath;
  writePathsFile();
  // Relaunch the app to apply new settings
  app.relaunch();
  app.exit(0);
});
ipcMain.on('close-settings', () => {
  if (settingsWindow) {
    settingsWindow.close();
    settingsWindow = null;
  }
});

// Minim & Close
ipcMain.on('app-minimize', () => {
  if (mainWindow) mainWindow.minimize();
});
ipcMain.on('app-close', () => {
  app.quit();
});

/***************************************************************************
 * App Lifecycle
 **************************************************************************/
app.on('ready', () => {
  const found = readPathsFile();
  const hasPy = PATHS_DATA.webService && PATHS_DATA.webService.trim() !== "";
  const hasBat = PATHS_DATA.batPath && PATHS_DATA.batPath.trim() !== "";
  if (found && hasPy && hasBat) {
    console.log("Paths.txt found, skipping splash. Data is:", PATHS_DATA);
    createMainWindow();
    if (PATHS_DATA.webService) { startPythonServer(); }
    if (PATHS_DATA.macAddress) { startPersistentFlipper(); }
  } else {
    console.log("Paths.txt not found or incomplete, showing splash.");
    createSplashWindow();
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') { app.quit(); }
});

app.on('activate', () => {
  if (!mainWindow && !splashWindow) {
    const found = readPathsFile();
    if (found) {
      createMainWindow();
      if (PATHS_DATA.webService) startPythonServer();
      if (PATHS_DATA.macAddress) startPersistentFlipper();
    } else {
      createSplashWindow();
    }
  }
});
