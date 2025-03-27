const { ipcRenderer } = require('electron');
const logArea = document.getElementById('logArea');

// Helper to format current time as HH:MM:SS
function getCurrentTimestamp() {
  const now = new Date();
  return now.toLocaleTimeString();
}

// Append a log line with timestamp
function appendLogLine(line) {
  const timestamp = getCurrentTimestamp();
  const logEntry = document.createElement('div');
  logEntry.textContent = `[${timestamp}] ${line}`;
  logArea.appendChild(logEntry);
  logArea.scrollTop = logArea.scrollHeight;
}

// On initial load, main sends the entire logs array
ipcRenderer.on('load-initial-logs', (event, allLogs) => {
  logArea.innerHTML = "";
  allLogs.forEach(line => {
    appendLogLine(line);
  });
});

// For new lines after logs window is open
ipcRenderer.on('new-log-line', (event, line) => {
  appendLogLine(line);
});
