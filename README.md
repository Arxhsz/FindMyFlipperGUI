
![](https://raw.githubusercontent.com/Arxhsz/FindMyFlipperGUI/refs/heads/main/IMG/logo.png)

https://github.com/user-attachments/assets/167dfd30-9c8a-419e-b7b9-515afcd3cb4b

# FindMyFlipperGUI

FindMyFlipperGUI is a cross-platform desktop application built with Electron and Leaflet that makes it easy to locate and interact with your Flipper Zero device over Bluetooth Low Energy (BLE). It wraps the core functionality of the original [FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper) project in a polished graphical interface—no command line required.

----------

## Key Features

-   **Credential Management**  
    Import your exported `.keys` file (must include `Hashed adv key` and `Private key (Hex)`) and enter your device’s BLE MAC address.
    
-   **Live Map & Status**  
    Embedded Leaflet map with a custom “speech-bubble” marker showing:
    
    -   **Battery bar** (0–100% with red→green gradient)
        
    -   **Online/offline dot** (green if seen in the last 10 minutes, grey otherwise)
        
-   **Remote Alert**  
    One-click **Play Alert** button rings your Flipper so you can find it.
    
-   **Live Logs Window**  
    Frameless window streaming both Python decryption-service output and BLE helper diagnostics.
    
-   **Unified Configuration**  
    All settings saved in a single `config.json` in your OS user-data folder. In-app Settings panel lets you adjust paths and toggle DevTools on launch.
    
-   **Error Handling & Retry**
    
    -   BLE scan retry button
        
    -   Fetch-failure banners instead of silent failures
        
    -   Play-alert cooldown (5 s) and custom search countdown modal (30 s)
        

----------

# !!!IMPORTANT!!!

This App is just a GUI wrapper for [FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper) that means you have to have FindMyFlipper already setup and working. Once it is working you will notice in the AirTagGeneration folder you see web_service.py you have to replace that file with the web_service.py given in this project this allows the app to comunicate with the orignal FindMyFlipper project. This app does not export or save any information it only saves the file paths and reads the informtion from the file its self the source code is open if you want to take a look dont forget to star!
## Requirements

-   **Node.js** v14+ and **npm**
    
-   **Python** v3.7+
    
-   **Bleak** Python library (`pip install bleak`)
    
-   **Windows 10/11** (tested) or macOS/Linux
    
-   A working Bluetooth adapter
    

----------

## Installation & Setup

To install and package **FindMyFlipperGUI**, follow these steps:

1.  **Clone the repository & install dependencies**
    
    ```
    git clone https://github.com/Arxhsz/FindMyFlipperGUI.git
    cd FindMyFlipperGUI
    npm install
    pip install bleak
    ```
    
2.  **Package the application**
    
    ```
    npm run dist
    ```
    
3.  **Run the installer**
    
    Navigate to the `release/` folder and launch the platform-specific installer (e.g., `.exe` on Windows, `.dmg` on macOS). After installation, start the app from your system’s application menu or desktop shortcut.
    

## First‑Run Configuration

On first launch, you’ll see a splash screen prompting you to:

-   **Upload your** `**.keys**` **file** (format: `key: value`) containing at least:
    
    -   `Hashed adv key`
        
    -   `Private key (Hex)`  
        _This file is used only in the current session; it is not saved._
        
-   **Specify paths for:**
    
    -   Python backend script (`web_service.py`)
        
    -   Activation script (`activate.bat`)
        

These values are saved to `config.json` for subsequent launches.

----------

## Usage

Once configured, the main window provides:

-   **Add Keys (+)**: Re-import credentials and MAC address
    
-   **🔔 Play Alert**: Ring your Flipper (5 s cooldown)
    
-   **🔍 Retry Flipper**: Restart BLE scan
    
-   **⚙️ Settings**: Update paths or DevTools toggle
    
-   **📜 Logs**: View real‑time logs
    

The map shows your Flipper’s last-known GPS coordinates with the battery bar and status dot updating live.

----------

## Packaging

To build platform installers with **electron-builder**:

```
npm run dist
```

Output will appear in the `release/` folder. On Windows, an NSIS installer; on macOS, a DMG.

> **Note:** Packaging support is experimental. If you encounter permission or resource-lock errors, try running as administrator or ensure no app instances are open.

----------

## Troubleshooting

1.  **Marker not appearing**
    
    -   Delete `config.json` from your user-data folder and restart.
        
    -   Verify your `.keys` file has the required entries.
        
2.  **Packaging errors**
    
    -   Close all running instances.
        
    -   Run packaging command in an elevated terminal.
        
3.  **Bluetooth issues**
    
    -   Retry scan; toggle Bluetooth off/on on both PC and Flipper.
        

## Contributing

Contributions welcome! Please:

1.  Fork the repo
    
2.  Create a feature branch
    
3.  Submit a pull request
    

----------

## License

MIT © Arxhsz

----------

## Acknowledgments

Built as a GUI wrapper for [FindMyFlipper](https://github.com/MatthewKuKanich/FindMyFlipper) by Matthew KuKanich.  
Thanks to the BLEAK and Electron communities for their libraries.
