

# FindMyFlipperGUI



## Overview

FindMyFlipper GUI is an Electron‑based desktop graphical user interface ([**GUI**](https://www.google.com/search?q=gui&sca_esv=466a80cf504a0fa5&sxsrf=AHTn8zpwKvfmkzbbSBiYK1rDueO8gzns2Q:1743098531283&ei=o5LlZ-D-EMCRwbkPtfSXiAw&ved=0ahUKEwig3I-G7KqMAxXASDABHTX6BcEQ4dUDCBA&uact=5&oq=gui&gs_lp=Egxnd3Mtd2l6LXNlcnAiA2d1aTIKEAAYsAMY1gQYRzIKEAAYsAMY1gQYRzIKEAAYsAMY1gQYRzIKEAAYsAMY1gQYRzIKEAAYsAMY1gQYRzIKEAAYsAMY1gQYRzIKEAAYsAMY1gQYRzIKEAAYsAMY1gQYRzINEAAYgAQYsAMYQxiKBTINEAAYgAQYsAMYQxiKBUi0C1CvC1ivC3ABeAGQAQCYAQCgAQCqAQC4AQPIAQD4AQGYAgGgAgmYAwCIBgGQBgqSBwExoAcAsgcAuAcA&sclient=gws-wiz-serp)) that serves as a wrapper for the original FindMyFlipper project by [MatthewKuKanich](https://github.com/MatthewKuKanich). This project provides an easy way to monitor your Flipper device’s location on a map, Activate the alert function on the flipper, view logs, and adjust configuration settings without using the command line.

Original Project (FindMyFlipper):  
[https://github.com/MatthewKuKanich/FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper)

**_Note:_** This GUI uses your personal **_.keys_** file (which must include at least “Hashed adv key” and “Private key ([Hex](https://www.google.com/search?q=Hexadecimal&sca_esv=466a80cf504a0fa5&sxsrf=AHTn8zoPwVYfd4gbpiMM3wdSUhK9YgSzwA:1743098894028&ei=DpTlZ4fGAbn4wbkP1f232QE&ved=0ahUKEwiHhYyz7aqMAxU5fDABHdX-LRsQ4dUDCBA&uact=5&oq=Hexadecimal&gs_lp=Egxnd3Mtd2l6LXNlcnAiC0hleGFkZWNpbWFsMg0QABiABBixAxhDGIoFMg0QABiABBixAxhDGIoFMgoQABiABBhDGIoFMg0QABiABBixAxhDGIoFMhAQABiABBixAxhDGIMBGIoFMg0QABiABBixAxhDGIoFMggQABiABBixAzILEAAYgAQYsQMYgwEyChAAGIAEGEMYigUyCBAAGIAEGLEDSI4FUABYAHAAeAGQAQCYAWCgAWCqAQExuAEDyAEA-AEC-AEBmAIBoAJmmAMAkgcDMC4xoAfMBbIHAzAuMbgHZg&sclient=gws-wiz-serp)) only during the current session. The keys are not stored or exported.

## Requirements

• Node.js (v14 or later) and npm 
 
• Python (v3.7 or later) with the required modules for FindMyFlipper  

• Windows 10/11 (***tested***)  

• A working Bluetooth adapter on your PC

• [Bleak](https://github.com/hbldh/bleak) 

## Installation and Setup

 1. **Clone the Repository:**
		
	 - Clone the repository using:

			git clone https://github.com/arxhsz/FindMyFlipper-GUI.git

	 - Navigate into the project directory:
	 
			cd FindMyFlipper-GUI
		 	
	 2.  **Install Dependencies:**

		 - Run the following command to install all Node.js dependencies:

				npm install

	

	 3.  **Install Bleak:**
		 

		 - to install bleak run the following command:

				pip install bleak

 - **Initial Setup – Creating the Desktop Shortcut:**

	 - **First time use:**
	  
		 Run the `INSTALL.bat` file. This batch script will:
		 -   Create a desktop shortcut for the app (shortcut points to `start_app.bat`).
    
		-   Use the icon file located in the `icons` folder (icon.ico).
    
		-   Once the shortcut is created, you can launch the app by double‑clicking the desktop shortcut.

 - **Running the App Manually:**
	

	 - If you prefer to run the app without using the desktop shortcut, simply run the `start_app.bat` file. This file launches the Electron application directly.


# Configuration (First Run)
When you run the application for the first time (via the splash screen), you will be prompted to:

 - **Upload your .keys file:**
		The file must be in “key: value” format and include at least:
	 - `Hashed adv key` 
	 	 
	 - `Private key (Hex)`
	 
	 _Important:_ Your .keys file is used only during the session and is not stored or exported.
	 
 - **Specify the path to your Python Web Service file (.py):**
		This is the script that provides backend services.
 - **Specify the path to your activation script (activate.bat):**
This script may be used to set up or activate your environment.

These paths are saved in a file called `Paths.txt` in the project folder for subsequent launches.

## Usage

 - **Main Window Features:**
 
	  -   **Interactive Map:** Displays your Flipper’s last known location.
    
	-   **Play Alert Button:** Sends an alert command to the Flipper (with a 5‑second cooldown).
    
	-   **Add New Key Button:** Opens a modal to upload a new .keys file and enter your Flipper’s MAC address.
    
	-   **Open Logs Button:** Opens a log window that shows real‑time application logs.
    
	-   **Settings Button:** Opens a separate Settings window (see below).

 - **Settings Window:**
 
	 -   Access the Settings window by clicking the “Settings” button.
    
	 -   Here you can change:
    
	    -   The Python Web Service path.
        
	    -   The activation script (activate.bat) path.
        
	 -   After you click “Save,” the new paths are written to `Paths.txt` and the app will automatically relaunch to apply the changes.
    
	 -   If you click “Cancel,” the settings window will close without saving changes.
 

 - **Shortcuts & Batch Files:**
	 -   **INSTALL.bat:**  
    Use this file on first installation to create a desktop shortcut for launching the app.
    
	-   **start_app.bat:**  
    Use this file to manually start the app without using the shortcut.

## Packaging

If you wish to distribute your app as a packaged installer or EXE, you can use **electron‑builder**. (Make sure all instances of the app are closed before packaging.)

***IMPORTANT*** - This app was not made to be packaged yet... so if you run into any errors they will not be solved until the app is made to be packaged.

 - **To package the app, run:**
 
		npm run dist

_Tip:_ Run the packaging command from an Administrator Command Prompt if you encounter errors (such as locked resources or “Access is denied”).

## Troubleshooting Common Issues
 1. **Flipper Marker Not Appearing on the Map:**
	 - Delete your Path.txt file then restart the app by closing it and then opening it through the shortcut.
    
	-   Ensure your .keys file is correctly formatted and includes the required keys.
    
 2.  **Desktop Shortcut Not Created:**
	
	 - Double‑check that you ran `INSTALL.bat` from the correct folder
	 
	 - Ensure that all paths in the batch script are correct and that the icon file exists in the `icons` folder.

3.  **Packaging or Startup Errors:**
	-   Make sure no other instances of the app are running.
    
	-   Run the packaging command with elevated permissions (Run as Administrator).

 4. **Bluetooth connection errors:**
		
	 - Retry the connection at least 2-3 times.
	 
	 - Verify your Bluetooth adapter is plugged and or working.
	 - On your Flipper turn Bluetooth off and on while the app is searching for the connection with at least 25 sec left
	 - Verify if Bluetooth is turned on either on computer and or Flipper

## Additional Notes

-   **.keys File:**  
    The application does not store or export your .keys file permanently. It is used only during the session to authenticate with the backend service.
    
-   **Shortcut Creation:**  
    The first run requires `INSTALL.bat` to create a desktop shortcut for ease of access. Subsequent runs can use the shortcut or `start_app.bat`.

## Contributing
Contributions to improve or add new features are welcome. To contribute:

1.  Fork the repository:  
    [https://github.com/arxhsz/FindMyFlipperGUI](https://github.com/arxhsz/FindMyFlipperGUI)
    
2.  Create a branch for your changes.
    
3.  Submit a pull request with detailed explanations.

## License

This project is licensed under the MIT License.

## Acknowledgments

This GUI is built as a wrapper for the original FindMyFlipper project by MatthewKuKanich.  
Original project: [https://github.com/MatthewKuKanich/FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper)  
Developed by: [Arxhsz](https://github.com/Arxhsz)
