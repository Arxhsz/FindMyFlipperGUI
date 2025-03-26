# FindMyFlipperGUI – README

Overview
FindMyFlipperGUI is an Electron‑based graphical user interface (GUI) that wraps around the original FindMyFlipper project (by MatthewKuKanich) to allow easy monitoring of your Flipper device. This project provides a map display with the Flipper’s location, log viewing, alert functionality, and configurable settings—all without needing to use the command line.

Note:
Your personal .keys file (which must include “Hashed adv key” and “Private key (Hex)”) is only used during the session and is not permanently saved or exported.

Requirements
• Node.js (v14 or later) and npm
• Python (v3.7 or later) with required modules (for the original FindMyFlipper functionality)
• Windows (tested on Windows 10/11)
• A working Bluetooth adapter

Installation and Setup

Clone the Repository:
    git clone https://github.com/arxhsz/FindMyFlipperGUI.git
    cd FindMyFlipperGUI

Install Dependencies:
    npm install

Initial Setup – Creating the Desktop Shortcut:
Run the INSTALL.bat file (located in the project folder). This batch script will:
• Create a desktop shortcut that launches the app using start_app.bat
• Use the icon from the icons\icon.ico file.

Note: If you prefer to launch the app manually, you can always run start_app.bat.

First Run Configuration:
When you first run the app (via the splash screen), you will be prompted to:
1. Upload your .keys file:
   The file must be in a “key: value” format and include at least:
   • Hashed adv key
   • Private key (Hex)
   Remember: Your keys are used only during the session.

2. Specify the path to your Python Web Service file (.py):
   This file provides the backend services.

3. Specify the path to your activation script (activate.bat):
   This script may be used to set up or activate your environment.

The paths you supply are saved in a file named Paths.txt in the project folder. On subsequent runs, the application reads from this file so you won’t be prompted again unless the file is deleted or incomplete.

Usage

Main Window Features:
• Map Display:
  View your Flipper’s last known location on an interactive map.
• Play Alert Button:
  Sends an alert command to your Flipper (with a 5‑second cooldown).
• Add New Key Button:
  Opens a modal to upload a new .keys file and enter your Flipper’s MAC address.
• Open Logs Button:
  Opens a log window that displays real‑time application logs.
• Settings Button:
  Opens a separate Settings window where you can change paths (see below).

Settings Window:
• Open the
