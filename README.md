# FindMyFlipperGUI

**FindMyFlipperGUI** is a desktop application built using [Electron](https://www.electronjs.org/) that helps you locate and send alerts to your Flipper device. It leverages a Python-based Bluetooth Low Energy (BLE) service (using [Bleak](https://github.com/hbldh/bleak)) to detect your device and display its location on an interactive map (powered by [Leaflet](https://leafletjs.com/)). The app also provides functionality to manage keys, view logs, and adjust settings—all through an intuitive user interface.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation & Setup](#installation--setup)
- [Usage](#usage)
  - [Main Interface](#main-interface)
  - [Settings Window](#settings-window)
- [Troubleshooting](#troubleshooting)
- [Packaging and Distribution](#packaging-and-distribution)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## Features

- **Interactive Map**: Display your Flipper device’s latest location on a map using Leaflet.
- **Persistent BLE Connection**: Connects to your Flipper using a Python service that scans for and interacts with the device via BLE.
- **Play Alert Functionality**: Send an alert command to the Flipper with a built-in cooldown mechanism.
- **Key Management**: Upload your `.keys` file containing credentials and necessary keys.
- **Logging**: View real-time logs of system events, errors, and BLE output.
- **Settings Window**: Update and save configuration paths (Python service, activation script, etc.) via an easy-to-use settings interface.
- **Desktop Shortcut Creation (Optional)**: An installer (or batch file) can create a shortcut on your desktop to launch the application.

---

## Requirements

- **Node.js** (v14 or later) and **npm**
- **Python** (v3.7 or later) with the [Bleak](https://github.com/hbldh/bleak) library installed  
  _(Note: On Windows, ensure that your Python installation includes support for Windows Runtime components.)_
- **Electron** (see `package.json`)
- A modern Windows OS (the app is developed and tested on Windows 10/11)

---

## Installation & Setup

1. **Clone the Repository:**

   ```bash
   git clone https://github.com/yourusername/FindMyFlipper.git
   cd FindMyFlipper
