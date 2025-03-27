/***** RENDERER.JS *****/
const { ipcRenderer } = require('electron');
const fs = require('fs'); // Needed to read .keys file if nodeIntegration is enabled

let myMap = null;
let tileLayer = null;
let pollIntervalId = null;
let lastMaxTimestamp = 0;
let noDataCount = 0;

// Tile URLs for different styles
const tileUrls = {
  black: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png",
  white: "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png",
  satellite: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
};

let currentStyle = "black";
let prevBWMode = "black";

// Searching/alert cooldown variables
const SEARCH_DURATION = 30000;
let searchIntervalId = null;
let alertCooldownIntervalId = null;

/*---------------------------------------------------------------------- 
   Utility: disable/enable "Play Alert" button 
----------------------------------------------------------------------*/
function disablePlayAlert() {
  const btn = document.getElementById('playAlertBtn');
  btn.disabled = true;
  btn.style.opacity = 0.5;
}
function enablePlayAlert() {
  const btn = document.getElementById('playAlertBtn');
  btn.disabled = false;
  btn.style.opacity = 1;
}
function showRetryButton() {
  document.getElementById('connectFlipperBtn').style.display = 'inline-block';
}
function hideRetryButton() {
  document.getElementById('connectFlipperBtn').style.display = 'none';
}

/*---------------------------------------------------------------------- 
   Custom notification modal 
----------------------------------------------------------------------*/
function showCustomNotification(title, message, yesCallback, noCallback) {
  document.getElementById('notificationTitle').textContent = title;
  document.getElementById('notificationMessage').textContent = message;
  const modal = document.getElementById('notificationModal');
  modal.style.display = 'flex';

  // Remove old listeners by replacing buttons
  const yesBtnOld = document.getElementById('notificationYesBtn');
  const noBtnOld = document.getElementById('notificationNoBtn');
  yesBtnOld.replaceWith(yesBtnOld.cloneNode(true));
  noBtnOld.replaceWith(noBtnOld.cloneNode(true));

  const yesBtn = document.getElementById('notificationYesBtn');
  const noBtn = document.getElementById('notificationNoBtn');
  yesBtn.addEventListener('click', () => {
    modal.style.display = 'none';
    if (yesCallback) yesCallback();
  });
  noBtn.addEventListener('click', () => {
    modal.style.display = 'none';
    if (noCallback) noCallback();
  });
}

/*---------------------------------------------------------------------- 
   30s search countdown 
----------------------------------------------------------------------*/
function startSearchCountdown() {
  disablePlayAlert();
  hideRetryButton();
  const searchCountdownSpan = document.getElementById('searchCountdown');
  const startTime = Date.now();
  searchCountdownSpan.textContent = "30.0s searching...";

  if (searchIntervalId) clearInterval(searchIntervalId);
  searchIntervalId = setInterval(() => {
    const elapsed = Date.now() - startTime;
    const remaining = Math.max(SEARCH_DURATION - elapsed, 0);
    searchCountdownSpan.textContent = `${(remaining / 1000).toFixed(1)}s searching...`;

    if (remaining <= 0) {
      clearInterval(searchIntervalId);
      searchIntervalId = null;
      searchCountdownSpan.textContent = "";
      showCustomNotification(
        "Flipper Not Found",
        "Could not find your Flipper. Retry connection?",
        () => { doFlipperSearch(); },
        () => { disablePlayAlert(); showRetryButton(); }
      );
    }
  }, 50);
}
function stopSearchCountdown() {
  if (searchIntervalId) {
    clearInterval(searchIntervalId);
    searchIntervalId = null;
  }
  document.getElementById('searchCountdown').textContent = "";
}

/*---------------------------------------------------------------------- 
   5s cooldown for "Play Alert"
----------------------------------------------------------------------*/
function startAlertCooldown() {
  disablePlayAlert();
  const countdownSpan = document.getElementById('playAlertCountdown');
  let remaining = 5.0;
  countdownSpan.textContent = remaining.toFixed(1);

  if (alertCooldownIntervalId) clearInterval(alertCooldownIntervalId);
  alertCooldownIntervalId = setInterval(() => {
    remaining -= 0.1;
    if (remaining <= 0) {
      clearInterval(alertCooldownIntervalId);
      alertCooldownIntervalId = null;
      countdownSpan.textContent = "";
      enablePlayAlert();
    } else {
      countdownSpan.textContent = remaining.toFixed(1);
    }
  }, 100);
}

/*---------------------------------------------------------------------- 
   Called when user clicks "Connect to Flipper" or retries 
----------------------------------------------------------------------*/
function doFlipperSearch() {
  startSearchCountdown();
  ipcRenderer.send('retry-flipper');
}

/*---------------------------------------------------------------------- 
   Flipper status from main 
----------------------------------------------------------------------*/
ipcRenderer.on('flipper-connected', () => {
  stopSearchCountdown();
  enablePlayAlert();
  hideRetryButton();
});
ipcRenderer.on('flipper-not-found', () => {
  if (!searchIntervalId) {
    showCustomNotification(
      "Flipper Not Found",
      "Could not find your Flipper. Retry connection?",
      () => { doFlipperSearch(); },
      () => { disablePlayAlert(); showRetryButton(); }
    );
  }
});
ipcRenderer.on('flipper-already-connected', () => {
  stopSearchCountdown();
  enablePlayAlert();
  hideRetryButton();
});

/*---------------------------------------------------------------------- 
   When main sends stored paths data, decide whether to show key modal 
----------------------------------------------------------------------*/
ipcRenderer.on('paths-data', (event, data) => {
  console.log("Received paths-data:", data);
  const haveMac = data.macAddress && data.macAddress.trim() !== "";
  const haveKeys = data.keysPath && data.keysPath.trim() !== "";
  if (haveMac && haveKeys) {
    // Hide the key modal
    document.getElementById('keyModal').style.display = 'none';
    // Initialize the map
    initMap();

    // If there is a stored location, draw the marker
    const savedLoc = localStorage.getItem('lastLocation');
    if (savedLoc) {
      try {
        const coords = JSON.parse(savedLoc);
        if (Array.isArray(coords) && coords.length === 2) {
          L.marker(coords, { icon: createLatestPinIcon() }).addTo(myMap);
          myMap.setView(coords, 13);
        }
      } catch {}
    }
    // Start polling for new data
    startPolling();
    // Start the flipper search
    doFlipperSearch();
  } else {
    document.getElementById('keyModal').style.display = 'flex';
  }
});

/*---------------------------------------------------------------------- 
   DOMContentLoaded – set up event listeners 
----------------------------------------------------------------------*/
document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('mainMinimize').addEventListener('click', () => {
    ipcRenderer.send('app-minimize');
  });
  document.getElementById('mainClose').addEventListener('click', () => {
    ipcRenderer.send('app-close');
  });
  document.getElementById('toggleLogsBtn').addEventListener('click', () => {
    ipcRenderer.send('toggle-logs-window');
  });
  document.getElementById('addKeyBtn').addEventListener('click', () => {
    document.getElementById('keyModal').style.display = 'flex';
  });
  document.getElementById('playAlertBtn').addEventListener('click', () => {
    ipcRenderer.send('play-alert');
    startAlertCooldown();
  });
  document.getElementById('connectFlipperBtn').addEventListener('click', () => {
    doFlipperSearch();
  });

  // "Settings" button – open/close settings window
  document.getElementById('openSettingsBtn').addEventListener('click', () => {
    ipcRenderer.send('open-settings');
  });

  // Toggle black/white style
  const toggleBlackWhiteBtn = document.getElementById('toggleBlackWhiteBtn');
  toggleBlackWhiteBtn.addEventListener('click', () => {
    if (currentStyle === "black") {
      switchMapStyle("white");
      toggleBlackWhiteBtn.style.backgroundImage = "url('icons/white.png')";
    } else {
      switchMapStyle("black");
      toggleBlackWhiteBtn.style.backgroundImage = "url('icons/black.png')";
    }
  });

  // Satellite toggle
  const satBtn = document.getElementById('satBtn');
  satBtn.addEventListener('click', () => {
    if (currentStyle === "satellite") {
      switchMapStyle(prevBWMode);
      toggleBlackWhiteBtn.style.display = 'inline-block';
    } else {
      prevBWMode = currentStyle;
      switchMapStyle("satellite");
      toggleBlackWhiteBtn.style.display = 'none';
    }
  });

  // "Load Keys" button in the key modal
  document.getElementById('loadKeyBtn').addEventListener('click', () => {
    const fileInput = document.getElementById('keyFile');
    const macInput = document.getElementById('flipperMacInput');
    const macValue = macInput.value.trim();
    if (!macValue) {
      alert("Please enter your Flipper's MAC address.");
      return;
    }
    if (!fileInput || fileInput.files.length === 0) {
      alert("Please select a .keys file.");
      return;
    }
    const keysFilePath = fileInput.files[0].path;
    const reader = new FileReader();
    reader.onload = function(e) {
      try {
        const textContent = e.target.result;
        const keyData = parseKeysFile(textContent);
        if (!keyData["Hashed adv key"] || !keyData["Private key (Hex)"]) {
          alert("Key file must contain 'Hashed adv key' and 'Private key (Hex)'.");
          return;
        }
        ipcRenderer.send('set-flipper-mac', macValue);
        ipcRenderer.send('set-keys-path', keysFilePath);
        document.getElementById('keyModal').style.display = 'none';
        localStorage.setItem('hashedAdvKey', keyData["Hashed adv key"]);
        localStorage.setItem('privateKeyHex', keyData["Private key (Hex)"]);
        localStorage.setItem('flipperMac', macValue);
        if (pollIntervalId) clearInterval(pollIntervalId);
        lastMaxTimestamp = 0;
        noDataCount = 0;
        initMap();
        startPolling();
        doFlipperSearch();
      } catch (err) {
        alert("Error parsing key file: " + err);
      }
    };
    reader.readAsText(fileInput.files[0]);
  });

  // Fallback: if localStorage lacks keys, show key modal
  const savedHashedAdvKey = localStorage.getItem('hashedAdvKey');
  const savedPrivateKeyHex = localStorage.getItem('privateKeyHex');
  const savedFlipperMac = localStorage.getItem('flipperMac');
  if (!savedHashedAdvKey || !savedPrivateKeyHex || !savedFlipperMac) {
    document.getElementById('keyModal').style.display = 'flex';
  }

  // Initialize map immediately
  initMap();

  // =======================
  // ADD ZOOM BUTTON LISTENERS
  // =======================
  document.getElementById('zoomInBtn').addEventListener('click', () => {
    if (myMap) myMap.zoomIn();
  });
  document.getElementById('zoomOutBtn').addEventListener('click', () => {
    if (myMap) myMap.zoomOut();
  });
});

/*---------------------------------------------------------------------- 
   parseKeysFile 
----------------------------------------------------------------------*/
function parseKeysFile(text) {
  const lines = text.split(/\r?\n/);
  const data = {};
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    const idx = trimmed.indexOf(':');
    if (idx === -1) continue;
    const key = trimmed.substring(0, idx).trim();
    const value = trimmed.substring(idx + 1).trim();
    data[key] = value;
  }
  return data;
}

/*---------------------------------------------------------------------- 
   Logging helper 
----------------------------------------------------------------------*/
function logLine(line) {
  ipcRenderer.send('log-line', line);
  console.log(line);
}

/*---------------------------------------------------------------------- 
   Map initialization and style 
----------------------------------------------------------------------*/
function initMap() {
  if (myMap) {
    myMap.remove();
    myMap = null;
  }

  myMap = L.map('map', {
    zoomControl: false,
    attributionControl: false,
    // Prevent zooming out beyond level 2 and zooming in beyond level 15:
    minZoom: 3,
    maxZoom: 19
  }).setView([0, 0], 2);

  currentStyle = "black";
  switchMapStyle("black");
  console.log("Map initialized.");
}

function switchMapStyle(styleName) {
  currentStyle = styleName;
  if (tileLayer) {
    myMap.removeLayer(tileLayer);
  }
  const url = tileUrls[styleName] || tileUrls.black;
  tileLayer = L.tileLayer(url, {
    attribution: '',
    maxZoom: 25
  });
  tileLayer.addTo(myMap);
  redrawMarker();
  console.log("Switched map style to:", styleName);
}

function redrawMarker() {
  if (window.lastDecryptedData) {
    processDecryptedData(window.lastDecryptedData, true);
  }
}

/*---------------------------------------------------------------------- 
   Polling for decrypted data 
----------------------------------------------------------------------*/
function startPolling() {
  pollIntervalId = setInterval(fetchDecryptedData, 5000);
  fetchDecryptedData();
  console.log("Polling started.");
}

async function fetchDecryptedData() {
  const hashedAdvKey = localStorage.getItem('hashedAdvKey');
  const privateKeyHex = localStorage.getItem('privateKeyHex');
  if (!hashedAdvKey || !privateKeyHex) {
    logLine("No keys found. Please upload your .keys file.");
    return;
  }
  const defaultHours = 24;
  try {
    const response = await fetch(
      `http://127.0.0.1:8000/DecryptedReports/?hours=${defaultHours}&prefix=`,
      { method: 'POST' }
    );
    const data = await response.json();
    window.lastDecryptedData = data;
    const newMaxTimestamp = getMaxTimestamp(data);
    if (newMaxTimestamp > lastMaxTimestamp) {
      lastMaxTimestamp = newMaxTimestamp;
      noDataCount = 0;
      logLine("New location from Flipper");
      logReports(data);
      processDecryptedData(data, true);

      // Save the latest location for immediate display on restart
      const reports = data.reports || [];
      if (reports.length > 0) {
        const latest = reports[reports.length - 1];
        if (typeof latest.lat === 'number' && typeof latest.lon === 'number') {
          localStorage.setItem('lastLocation', JSON.stringify([latest.lat, latest.lon]));
        }
      }
    } else {
      noDataCount++;
      if (noDataCount >= 5) {
        logLine("No new location found");
        noDataCount = 0;
      }
    }
  } catch (error) {
    logLine(`Error fetching data: ${error.message}`);
  }
}

function getMaxTimestamp(decryptedData) {
  if (!decryptedData || !decryptedData.reports || !decryptedData.reports.length) {
    return 0;
  }
  let maxT = 0;
  for (const rpt of decryptedData.reports) {
    if (rpt.timestamp && rpt.timestamp > maxT) {
      maxT = rpt.timestamp;
    }
  }
  return maxT;
}

function logReports(data) {
  const reports = data.reports || [];
  for (const rpt of reports) {
    if ('goog' in rpt) delete rpt.goog;
    logLine(JSON.stringify(rpt));
  }
  if (data.found_keys) {
    logLine(`found: ${JSON.stringify(data.found_keys)}`);
  } else if (data.found) {
    logLine(`found: ${JSON.stringify(data.found)}`);
  }
  if (data.missing_keys) {
    logLine(`missing: ${JSON.stringify(data.missing_keys)}`);
  } else if (data.missing) {
    logLine(`missing: ${JSON.stringify(data.missing)}`);
  }
}

function processDecryptedData(decryptedData, forceRedraw = false) {
  if (!forceRedraw) return;
  if (!decryptedData || !decryptedData.reports) return;
  const reports = decryptedData.reports;
  if (!Array.isArray(reports) || reports.length === 0) return;

  // Clear old markers (but keep tileLayer)
  myMap.eachLayer((layer) => {
    if (layer !== tileLayer) {
      myMap.removeLayer(layer);
    }
  });

  reports.sort((a, b) => (a.timestamp || 0) - (b.timestamp || 0));
  const coords = [];
  for (const rpt of reports) {
    if (typeof rpt.lat === 'number' && typeof rpt.lon === 'number') {
      coords.push([rpt.lat, rpt.lon]);
    }
  }
  if (coords.length === 0) return;

  const latest = coords[coords.length - 1];
  L.marker(latest, { icon: createLatestPinIcon() }).addTo(myMap);
  myMap.setView(latest, 13);
}

function createLatestPinIcon() {
  let baseMarker;
  if (currentStyle === "black") {
    baseMarker = "icons/markerb.png";
  } else if (currentStyle === "white") {
    baseMarker = "icons/markerw.png";
  } else {
    baseMarker = (prevBWMode === "white") ? "icons/markerw.png" : "icons/markerb.png";
  }

    // New flipper icon image
  const flipperIcon = "icons/icon.ico";

  const markerSize = 100;
  const flipperSize = 45;
  const offset = (markerSize - flipperSize) / 2 - 10;
  const html = `
    <div style="position: relative; width: ${markerSize}px; height: ${markerSize}px;">
      <img 
        src="${baseMarker}" 
        style="width: ${markerSize}px; height: ${markerSize}px; object-fit: contain;" 
      />
      <img 
        src="icons/flipper.png" 
        style="
          position: absolute; 
          top: ${offset}px; 
          left: ${(markerSize - flipperSize) / 2}px; 
          width: ${flipperSize}px; 
          height: ${flipperSize}px; 
          object-fit: contain;" 
      />
    </div>
  `;
  return L.divIcon({
    html,
    className: '',
    iconSize: [markerSize, markerSize],
    iconAnchor: [markerSize / 2, markerSize * 0.85],
    popupAnchor: [0, -markerSize / 2]
  });
}
