/***** RENDERER.JS *****/
const { ipcRenderer } = require('electron');
const fs = require('fs');

let myMap = null;
let tileLayer = null;
let pollIntervalId = null;
let lastMaxTimestamp = 0;
let noDataCount = 0;
let lastUpdateTime = Date.now();
let latestBatteryLevel = 0;
let flipperMarker = null;

// immediately load & parse an existing keysPath from config.json
ipcRenderer.on('paths-data', (_evt, cfg) => {
  // if we got a keysPath from main, AND we haven't already populated localStorage:
  if (cfg.keysPath && !localStorage.getItem('hashedAdvKey')) {
    try {
      const text = fs.readFileSync(cfg.keysPath, 'utf-8');
      const parsed = parseKeysFile(text);
      if (parsed['Hashed adv key'] && parsed['Private key (Hex)']) {
        localStorage.setItem('hashedAdvKey',  parsed['Hashed adv key']);
        localStorage.setItem('privateKeyHex', parsed['Private key (Hex)']);
        localStorage.setItem('flipperMac',    cfg.macAddress || '');
        // hide the modal
        document.getElementById('keyModal').style.display = 'none';
        // now kick off the map & polling
        initMap();
        startPolling();
        doFlipperSearch();
      } else {
        console.error("Keys file missing required fields");
      }
    } catch (err) {
      console.error("Failed to auto‐load keysPath:", err);
    }
  }
});

const tileUrls = {
  black:     "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png",
  white:     "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png",
  satellite: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
};
let currentStyle = "black";
let prevBWMode   = "black";

const SEARCH_DURATION = 30000;
let searchIntervalId = null;
let alertCooldownIntervalId = null;

// === Keys-file / MAC modal hookup ===
ipcRenderer.on('keys-path-selected', (_e, filePath) => {
  if (!filePath) return;
  ipcRenderer.send('set-keys-path', filePath);
  document.getElementById('keyModal').style.display = 'none';
});
ipcRenderer.on('paths-data', (_e, cfg) => {
  if (cfg.keysPath) {
    document.getElementById('keyModal').style.display = 'none';
  }
});
// === end keys hookup ===

// ────────────────────────
// UTILITY FUNCTIONS
// ────────────────────────
function disablePlayAlert() {
  const b = document.getElementById('playAlertBtn');
  b.disabled = true; b.style.opacity = 0.5;
}
function enablePlayAlert() {
  const b = document.getElementById('playAlertBtn');
  b.disabled = false; b.style.opacity = 1;
}
function showRetryButton() { document.getElementById('connectFlipperBtn').style.display = 'inline-block'; }
function hideRetryButton() { document.getElementById('connectFlipperBtn').style.display = 'none'; }

function showCustomNotification(title, message, yesCb, noCb) {
  document.getElementById('notificationTitle').textContent = title;
  document.getElementById('notificationMessage').textContent = message;
  const modal = document.getElementById('notificationModal');
  modal.style.display = 'flex';
  const yesOld = document.getElementById('notificationYesBtn');
  const noOld  = document.getElementById('notificationNoBtn');
  yesOld.replaceWith(yesOld.cloneNode(true));
  noOld.replaceWith(noOld.cloneNode(true));
  document.getElementById('notificationYesBtn').onclick = () => { modal.style.display='none'; yesCb(); };
  document.getElementById('notificationNoBtn').onclick  = () => { modal.style.display='none'; noCb(); };
}

function startSearchCountdown() {
  disablePlayAlert(); hideRetryButton();
  const span = document.getElementById('searchCountdown');
  const start = Date.now();
  span.textContent = "30.0s searching...";
  if (searchIntervalId) clearInterval(searchIntervalId);
  searchIntervalId = setInterval(() => {
    const rem = Math.max(SEARCH_DURATION - (Date.now() - start), 0);
    span.textContent = `${(rem/1000).toFixed(1)}s searching...`;
    if (rem === 0) {
      clearInterval(searchIntervalId);
      span.textContent = "";
      showCustomNotification(
        "Flipper Not Found",
        "Could not find your Flipper. Retry?",
        () => doFlipperSearch(),
        () => { disablePlayAlert(); showRetryButton(); }
      );
    }
  }, 50);
}
function stopSearchCountdown() {
  if (searchIntervalId) { clearInterval(searchIntervalId); searchIntervalId = null; }
  document.getElementById('searchCountdown').textContent = "";
}

function startAlertCooldown() {
  disablePlayAlert();
  const span = document.getElementById('playAlertCountdown');
  let rem = 5.0;
  span.textContent = rem.toFixed(1);
  if (alertCooldownIntervalId) clearInterval(alertCooldownIntervalId);
  alertCooldownIntervalId = setInterval(() => {
    rem -= 0.1;
    if (rem <= 0) {
      clearInterval(alertCooldownIntervalId);
      span.textContent = "";
      enablePlayAlert();
    } else {
      span.textContent = rem.toFixed(1);
    }
  }, 100);
}

function doFlipperSearch() {
  startSearchCountdown();
  ipcRenderer.send('retry-flipper');
}

// ────────────────────────
// SVG ICON BUILDER
// ────────────────────────
function createFlipperSvgIcon(pct, isOnline) {
  const bubbleImg = currentStyle === "black" ? "icons/markerb.png" : "icons/markerw.png";
  const barMax   = 40;
  const barW     = Math.floor((pct / 100) * barMax);
  const hue      = Math.round((pct * 120) / 100);
  const barColor = `hsl(${hue},100%,50%)`;
  const dotColor = isOnline ? "#4caf50" : "#666";

  const W      = 100, H = 100, dotH = 12, flSize = 45;
  const circleHeight = 80;
  const baseFlY      = dotH + Math.round((circleHeight - flSize) / 2);
  const flYOffset    = -15;
  const flX          = (W - flSize) / 2;
  const flY          = baseFlY + flYOffset;
  const barX = (W - barMax) / 2, barY = dotH - 3;

  const html = `
    <div style="width:0;height:0;position:relative;">
      <div style="position:absolute; left:0; top:0; transform: translate(-50%, -90%);">
        <img src="${bubbleImg}" style="display:block;width:${W}px;height:${H}px;object-fit:contain;" />
        <img src="icons/flipper.png" style="position:absolute;left:${flX}px;top:${flY}px;width:${flSize}px;height:${flSize}px;object-fit:contain;" />
        <div style="position:absolute;top:${barY}px;left:${barX}px;width:${barMax}px;height:6px;background:#333;border:1px solid #000;border-radius:3px;overflow:hidden;">
          <div style="width:${barW}px;height:100%;background:${barColor};"></div>
        </div>
        <div style="position:absolute;bottom:38px;right:24px;width:8px;height:8px;background:${dotColor};border:1px solid #fff;border-radius:50%;"></div>
      </div>
    </div>
  `.trim();

  return L.divIcon({ html, className: '', iconSize:[0,0], iconAnchor:[0,0], popupAnchor:[0,0] });
}

// ────────────────────────
// DRAW / UPDATE MARKER
// ────────────────────────
function drawFlipperMarker(lat, lon) {
  const coords = [lat, lon];
  const online = (Date.now() - lastUpdateTime) < 10*60*1000;
  const pct    = latestBatteryLevel || 0;
  const icon   = createFlipperSvgIcon(pct, online);

  if (flipperMarker) myMap.removeLayer(flipperMarker);
  flipperMarker = L.marker(coords, { icon, pane:'markerPane' }).addTo(myMap);
  const el = flipperMarker.getElement();
  if (el) el.style.zIndex = 100000;
}

// ────────────────────────
// IPC RESPONSES
// ────────────────────────
ipcRenderer.on('flipper-connected',   ()=>{ stopSearchCountdown(); enablePlayAlert(); hideRetryButton(); });
ipcRenderer.on('flipper-not-found',   ()=>{ if(!searchIntervalId) doFlipperSearch(); });
ipcRenderer.on('flipper-already-connected', ()=>{ stopSearchCountdown(); enablePlayAlert(); hideRetryButton(); });
ipcRenderer.on('battery-update', (_e,level)=>{
  latestBatteryLevel = level;
  if (flipperMarker) {
    const { lat, lng } = flipperMarker.getLatLng();
    drawFlipperMarker(lat, lng);
  }
});

// ────────────────────────
// PATHS-DATA
// ────────────────────────
ipcRenderer.on('paths-data', (event, data) => {
  const haveMac  = data.macAddress && data.macAddress.trim() !== "";
  const haveKeys = data.keysPath   && data.keysPath.trim()   !== "";
  if (haveMac && haveKeys) {
    document.getElementById('keyModal').style.display = 'none';
    initMap();
    const loc = localStorage.getItem('lastLocation');
    if (loc) {
      try {
        const [la, lo] = JSON.parse(loc);
        drawFlipperMarker(la, lo);
        myMap.setView([la, lo], 13);
      } catch(e) { console.error(e); }
    }
    startPolling();
    doFlipperSearch();
  } else {
    document.getElementById('keyModal').style.display = 'flex';
  }
});

// ────────────────────────
// DOMContentLoaded
// ────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('mainMinimize').onclick = () => ipcRenderer.send('app-minimize');
  document.getElementById('mainClose').onclick    = () => ipcRenderer.send('app-close');
  document.getElementById('toggleLogsBtn').onclick= () => ipcRenderer.send('toggle-logs-window');
  document.getElementById('addKeyBtn').onclick    = () => document.getElementById('keyModal').style.display='flex';
  document.getElementById('playAlertBtn').onclick = () => { ipcRenderer.send('play-alert'); startAlertCooldown(); };
  document.getElementById('connectFlipperBtn').onclick = () => doFlipperSearch();
  document.getElementById('openSettingsBtn').onclick   = () => ipcRenderer.send('open-settings');

  const bwBtn = document.getElementById('toggleBlackWhiteBtn');
  bwBtn.onclick = () => {
    if (currentStyle === "black") {
      switchMapStyle("white");
      bwBtn.style.backgroundImage = "url('icons/white.png')";
    } else {
      switchMapStyle("black");
      bwBtn.style.backgroundImage = "url('icons/black.png')";
    }
  };
  const satBtn = document.getElementById('satBtn');
  satBtn.onclick = () => {
    if (currentStyle === "satellite") {
      switchMapStyle(prevBWMode);
      bwBtn.style.display = 'inline-block';
    } else {
      prevBWMode = currentStyle;
      switchMapStyle("satellite");
      bwBtn.style.display = 'none';
    }
  };

// ─── “Load Keys” button handler ──────────────────────────
const loadKeyBtn = document.getElementById('loadKeyBtn');
loadKeyBtn.onclick = () => {
  const mac = document.getElementById('flipperMacInput').value.trim();
  if (!mac) {
    alert("Enter MAC address first.");
    return;
  }

  ipcRenderer.send('open-keys-dialog');
};

// 2) When they choose a file, grab the MAC input, then send *both* MAC & keysPath
ipcRenderer.on('keys-path-selected', (_e, filePath) => {
  const mac = document.getElementById('flipperMacInput').value.trim();
  if (!mac) {
    alert("Enter MAC address first.");
    return;
  }

  // 3) Send both to main; main will save into config.json and then re‐emit paths-data
  ipcRenderer.send('set-flipper-mac', mac);
  ipcRenderer.send('set-keys-path', filePath);
});

  // on initial load, if config already has keysPath & mac, skip modal
  ipcRenderer.on('paths-data', (_evt, cfg) => {
    if (cfg.macAddress && cfg.keysPath) {
      document.getElementById('keyModal').style.display = 'none';
      initMap();
      startPolling();
      doFlipperSearch();
    }
  });

  setInterval(() => {
    const s = Math.floor((Date.now() - lastUpdateTime) / 1000);
    const m = Math.floor(s/60), sec = s%60;
    const txt = m>0 ? `${m}m ${sec}s ago` : `${sec}s ago`;
    document.getElementById('updateTimer').textContent = `Last update: ${txt}`;
  }, 1000);

  setInterval(() => {
    if (flipperMarker) {
      const { lat, lng } = flipperMarker.getLatLng();
      drawFlipperMarker(lat, lng);
    }
  }, 1000);

  document.getElementById('zoomInBtn').onclick  = () => myMap.zoomIn();
  document.getElementById('zoomOutBtn').onclick = () => myMap.zoomOut();

  initMap();
  startPolling();
  doFlipperSearch();
});

// ────────────────────────
// parseKeysFile
// ────────────────────────
function parseKeysFile(text) {
  const out = {};
  text.split(/\r?\n/).forEach(l => {
    const t = l.trim(), i = t.indexOf(':');
    if (i<0||!t) return;
    out[t.slice(0,i).trim()] = t.slice(i+1).trim();
  });
  return out;
}

// ────────────────────────
// map init, style, polling, fetch
// ────────────────────────
function initMap() {
  if (myMap) { myMap.remove(); myMap = null; }
  myMap = L.map('map', { zoomControl:false, attributionControl:false, minZoom:3, maxZoom:19 })
            .setView([0,0], 2);
  switchMapStyle("black");
  const saved = localStorage.getItem('lastLocation');
  if (saved) {
    try {
      const [la, lo] = JSON.parse(saved);
      drawFlipperMarker(la, lo);
      myMap.setView([la, lo], 13);
    } catch{}
  }
}
function switchMapStyle(style) {
  currentStyle = style;
  if (tileLayer) myMap.removeLayer(tileLayer);
  tileLayer = L.tileLayer(tileUrls[style], { attribution:'', maxZoom:25 }).addTo(myMap);
}
function startPolling() {
  pollIntervalId = setInterval(fetchDecryptedData, 5000);
  fetchDecryptedData();
}
async function fetchDecryptedData() {
  const adv = localStorage.getItem('hashedAdvKey');
  const pk  = localStorage.getItem('privateKeyHex');
  if (!adv||!pk) { console.log("No keys"); return; }
  try {
    const resp = await fetch(`http://127.0.0.1:8000/DecryptedReports/?hours=24&prefix=`, { method:'POST' });
    const data = await resp.json();
    const newMax = data.reports.reduce((m,r)=> r.timestamp>m?r.timestamp:m, 0);
    if (newMax>lastMaxTimestamp) {
      lastMaxTimestamp = newMax;
      lastUpdateTime   = Date.now();
      const lt = data.reports[data.reports.length-1];
      drawFlipperMarker(lt.lat, lt.lon);
      localStorage.setItem('lastLocation', JSON.stringify([lt.lat, lt.lon]));
    } else {
      noDataCount++;
      if (noDataCount>=5) {
        console.log("No new location");
        noDataCount=0;
      }
    }
  } catch (err) {
    console.log(`Fetch error: ${err}`);
  }
}
