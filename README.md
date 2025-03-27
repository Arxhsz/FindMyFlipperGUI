FindMyFlipperGUI – README
-------------------------

Overview
--------

FindMyFlipperGUI is an Electron‑based graphical user interface (GUI) that wraps around the original FindMyFlipper project (by MatthewKuKanich) to allow easy monitoring of your Flipper device. This project provides a map display with the Flipper’s location, log viewing, alert functionality, and configurable settings—all without needing to use the command line.

**Original FindMyFlipper project:**[https://github.com/MatthewKuKanich/FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper)

**Note:**Your personal _.keys_ file (which must include “Hashed adv key” and “Private key (Hex)”) is only used during the session and is not permanently saved or exported.

Requirements
------------

• Node.js (v14 or later) and npm• Python (v3.7 or later) with required modules (for the original FindMyFlipper functionality)• Windows (tested on Windows 10/11)• A working Bluetooth adapter

Installation and Setup
----------------------

1.  **Clone the Repository:**
    
    *   bashCopygit clone https://github.com/arxhsz/FindMyFlipperGUI.git
        
    *   bashCopycd FindMyFlipperGUI
        
2.  **Install Dependencies:**
    
    *   nginxCopynpm install
        
3.  **Initial Setup – Creating the Desktop Shortcut:**
    
    *   Run the INSTALL.bat file (located in the project folder). This batch script will:
        
        *   Create a desktop shortcut that launches the app using start\_app.bat
            
        *   Use the icon from the icons\\icon.ico file.
            
    *   **Note:** If you prefer to launch the app manually, you can always run start\_app.bat.
        
4.  **First Run Configuration:**
    
    *   When you first run the app (via the splash screen), you will be prompted to:
        
        *   **Upload your .keys file:**The file must be in a “key: value” format and include at least:
            
            *   Hashed adv key
                
            *   Private key (Hex)_Remember:_ Your keys are used only during the session.
                
        *   **Specify the path to your Python Web Service file (.py):**This file provides the backend services.
            
        *   **Specify the path to your activation script (activate.bat):**This script may be used to set up or activate your environment.
            
    *   The paths you supply are saved in a file named Paths.txt in the project folder. On subsequent runs, the application reads from this file so you won’t be prompted again unless the file is deleted or incomplete.
        

Usage
-----

*   **Main Window Features:**
    
    *   **Map Display:**View your Flipper’s last known location on an interactive map.
        
    *   **Play Alert Button:**Sends an alert command to your Flipper (with a 5‑second cooldown).
        
    *   **Add New Key Button:**Opens a modal to upload a new .keys file and enter your Flipper’s MAC address.
        
    *   **Open Logs Button:**Opens a log window that displays real‑time application logs.
        
    *   **Settings Button:**Opens a separate Settings window where you can change paths (see below).
        
*   **Settings Window:**
    
    *   Open the Settings window by clicking the “Settings” button.
        
    *   In this window you can update:
        
        *   The Python Web Service path.
            
        *   The activation script (activate.bat) path.
            
    *   When you click “Save,” the new paths are written to Paths.txt and the application automatically relaunches to apply the changes.
        
    *   If you click “Cancel,” the Settings window closes without saving any changes.
        
*   **Shortcuts & Batch Files:**
    
    *   **INSTALL.bat:**Run this file on the first installation to create a desktop shortcut for launching the app.
        
    *   **start\_app.bat:**Use this file to manually start the app without the shortcut.
        

Packaging and Running Without Packaging
---------------------------------------

If you don’t wish to package the app into a single EXE (so you can keep all the individual files), you can simply run it using the provided batch files. The desktop shortcut created via INSTALL.bat will launch the app, or you can run start\_app.bat directly. This way, you retain easy access while keeping the source files intact.

Troubleshooting
---------------

1.  **Flipper Marker Not Showing on the Map:**
    
    *   Ensure your Bluetooth adapter is enabled.
        
    *   Verify that your .keys file is correctly formatted and includes the required keys.
        
    *   Double‑check that you entered the correct MAC address for your Flipper.
        
    *   Note: On first run, if you delete Paths.txt and reconfigure, the marker should appear.
        
2.  **Shortcut Issues:**
    
    *   If the desktop shortcut isn’t created, make sure you run INSTALL.bat from the correct folder and that the icons\\icon.ico file exists.
        
3.  **Packaging Errors:**
    
    *   If you choose to package the app (using npm run dist), close all running instances first.
        
    *   Run the packaging command from an elevated (Administrator) command prompt if necessary.
        

Contributing
------------

Contributions are welcome! If you have suggestions or improvements:

1.  Fork the repository:https://github.com/arxhsz/FindMyFlipperGUI
    
2.  Create a branch for your changes.
    
3.  Submit a pull request with detailed explanations of your changes.
    

License
-------

This project is licensed under the MIT License.

Acknowledgments
---------------

*   This GUI is built as a wrapper for the original FindMyFlipper project by MatthewKuKanich.Original project: [https://github.com/MatthewKuKanich/FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper)
    
*   Developed by: arxhsz
