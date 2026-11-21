# M901 Mapper

Remap the extra buttons of a **Redragon M901 Perdition** (original laser model, USB ID `04D9:FC02`) on Windows 10/11.

## Why this exists

Redragon's current "Perdition" software (2018, `hid.exe` / `ldcfg.exe`) only supports the Perdition 3 (`04D9:FC40`).
The original M901 (`FC02`) rejects its commands at the USB level. Patching the software's device ID made the mouse
freeze, so that route is closed. The original 2013 software ("Perdition driver_131118") is no longer available online.

The mouse still sends whatever was stored in it years ago: keys like `Ctrl+C`, `Ctrl+V`, `4`, or mouse Back/Forward.
**M901 Mapper** catches the input from **this mouse only** and turns each button into the action you choose.
Your real keyboard and the left/right/middle buttons are never touched.

## Setup (one time)

> Installing a driver requires administrator rights and, in a managed environment, your organization's approval.

1. **AutoHotkey v2**: already installed (`C:\Program Files\AutoHotkey\v2`).
2. **Interception driver**: download `Interception.zip` from the official releases page
   <https://github.com/oblitum/Interception/releases>, extract it, then in an **Administrator** command prompt run:
   ```
   "<extracted folder>\command line installer\install-interception.exe" /install
   ```
   Restart Windows afterwards.
3. **AutoHotInterception (AHK v2 version)**: download the latest release from
   <https://github.com/evilC/AutoHotInterception/releases> and extract it. Copy its **`AHK v2\Lib`** folder into this
   folder, so you have `Lib\AutoHotInterception.ahk` next to `M901Mapper.ahk`.
4. Copy Interception's `library\x64` and `library\x86` folders (from the zip in step 2) into `Lib`, so you have
   `Lib\x64\interception.dll` and `Lib\x86\interception.dll`.
5. Unblock the downloaded DLLs: run `Lib\Unblocker.ps1` as Administrator, or right-click each `.dll` →
   Properties → tick **Unblock**.

Expected layout:
```
M901Mapper.ahk
Lib\AutoHotInterception.ahk
Lib\AutoHotInterception.dll
Lib\CLR.ahk
Lib\x64\interception.dll
Lib\x86\interception.dll
```

## Use

1. Double-click `M901Mapper.ahk`.
2. Click **Detect button...** and press a button on the mouse.
3. Pick what it should do (copy, paste, Back/Forward, media keys, any key or combination, typing text, running a program...).
4. Repeat for other buttons. Settings are saved in `M901Mapper.ini`.
5. Tick **Start with Windows** to have it run hidden at login. Closing the window keeps it running in the tray.

Buttons you never set up keep doing what the mouse sends today.

- **Mapping: ON/OFF** (top right, or the tray menu) pauses remapping; the mouse then sends its original keys.
- **Backup** saves all your button settings to an `.ini` file you choose (default: Documents).
- **Restore** loads a backup. Your current settings are kept as `M901Mapper.ini.bak` first.
- **Remove** takes a button off the list; **Unchanged** keeps it listed but restores its original keys.

## Limits

- Works only on this PC, and only while M901 Mapper is running.
- DPI, polling rate and lighting are stored inside the mouse and can't be changed this way.
- Buttons that change DPI inside the mouse don't send anything to Windows, so they can't be remapped.
