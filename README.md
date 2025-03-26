Below is a sample README.md in GitHub Markdown format that explains the project in detail. You can copy and paste this file into your repository.

markdown
Copy
# FindMyFlipper

**FindMyFlipper** is a desktop application built using [Electron](https://www.electronjs.org/) that helps you locate and send alerts to your Flipper device. It leverages a Python-based Bluetooth Low Energy (BLE) service (using [Bleak](https://github.com/hbldh/bleak)) to detect your device and display its location on an interactive map (powered by [Leaflet](https://leafletjs.com/)). The app also provides functionality to manage keys, view logs, and adjust settings—all through an intuitive user interface.

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
Install Dependencies:

bash
Copy
npm install
Configure the Application:

On first run, the app will prompt you to:

Upload your .keys file (which should contain at least “Hashed adv key” and “Private key (Hex)”).

Specify the path to your Python Web Service (the .py file) and your activation script (activate.bat).

These settings are saved in a file called Paths.txt so that subsequent runs load your configuration automatically.

Run in Development Mode:

bash
Copy
npm start
(Optional) Package the Application:

To build an installer or executable (using electron-builder), run:

bash
Copy
npm run dist
Note: If you encounter packaging errors, make sure no instances of the app are running and try running the command in an elevated (admin) prompt.

Usage
Main Interface
Map Display:
The main window shows a Leaflet map that displays the latest known location of your Flipper device.

Play Alert:
Clicking the Play Alert button sends an alert command to your Flipper. The button will display a countdown (5 seconds) during its cooldown period to prevent multiple rapid triggers.

Key Upload:
Use the Add New Key button to open the key modal, where you can upload your .keys file and enter your Flipper's MAC address.

Logs:
Click the Open Logs button to open a window that shows real-time logs from the app (helpful for troubleshooting).

Settings:
Click the Settings button to open the settings window. Here you can update the paths for:

Python Web Service (.py file)

Activation Script (activate.bat)

After saving, the app will restart and apply the new settings.

Settings Window
Updating Paths:
In the settings window, you can modify the paths for the Python service and the activation script. These changes are saved to Paths.txt.

Save & Restart:
Click Save to write the new settings and restart the application automatically. Click Cancel to close the settings window without saving changes.

Troubleshooting
Persistent Flipper / BLE Issues
Ensure Bluetooth is enabled on your computer.

If you see errors like ModuleNotFoundError: No module named 'winrt.windows.foundation.collections', verify that your Python installation has the necessary Windows Runtime components. (Sometimes upgrading Python or installing additional packages might help.)

Check that your .keys file contains the required keys.

Packaging / Shortcut Issues
If packaging fails due to locked files or resource busy errors, ensure the app is not already running.

For shortcut creation errors, verify that the paths provided are correct and that you have sufficient permissions.

Packaging and Distribution
If you prefer launching the app with a shortcut instead of using the command line:

Packaging into an EXE:
You can use electron-builder (via npm run dist) to package your app as a standalone executable.

Creating a Desktop Shortcut:
Our installer or batch file can automatically create a shortcut (using a PowerShell command) to launch start_app.bat from the Desktop.

This method allows you to keep all the files in one folder and still launch the app via a shortcut without converting everything into a single EXE.

Contributing
Contributions are welcome! Please follow these steps:

Fork the repository.

Create a new branch for your feature or bug fix.

Commit your changes with clear messages.

Open a pull request explaining your changes.

For any major changes, please open an issue first to discuss what you would like to change.

License
This project is licensed under the MIT License.

Acknowledgments
Built with Electron.

Interactive maps by Leaflet.

Bluetooth communication via Bleak.

Special thanks to the community for their invaluable contributions and support.
