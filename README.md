# M901 Mapper

Remap the extra buttons of a **Redragon M901 Perdition** (original laser model, USB ID `04D9:FC02`) on Windows 10/11.

## Why this exists

Redragon's current "Perdition" software (2018, `hid.exe` / `ldcfg.exe`) only supports the Perdition 3 (`04D9:FC40`).
The original M901 (`FC02`) rejects its commands at the USB level. Patching the software's device ID made the mouse
freeze, so that route is closed. The original 2013 software ("Perdition driver_131118") is no longer available online.

The mouse still sends whatever was stored in it years ago: keys like `Ctrl+C`, `Ctrl+V`, `4`, or mouse Back/Forward.
**M901 Mapper** catches the input from **this mouse only** and turns each button into the action you choose.
Your real keyboard and the left/right/middle buttons are never touched.

## Step 1 – Install the Interception driver (required, one time)

> Installing a driver requires administrator rights and, in a managed environment, your organization's approval.

1. Download `Interception.zip` from the official releases page <https://github.com/oblitum/Interception/releases>
   and extract it.
2. Open **Command Prompt as Administrator** (in PowerShell, put `&` before the quoted path) and run:
   ```
   "<extracted folder>\Interception\command line installer\install-interception.exe" /install
   ```
3. Restart Windows. (Unplugging and re-plugging the mouse is sometimes enough.)

To remove it later, run the same command with `/uninstall` and restart.

## Step 2 – Choose how to run M901 Mapper

### Option A: Download the EXE (easiest)

1. Download **`M901Mapper.exe`** from the [latest release](https://github.com/Suleiman700/Reddragon-mouse-profiler/releases/latest).
2. Put it in its own folder (for example `C:\Tools\M901Mapper\`) and double-click it.

Nothing else to install: AutoHotInterception and the Interception DLLs are bundled inside the EXE.
On first run it creates a `Lib` folder next to itself; leave it there.

### Option B: Run the AutoHotkey script

Use this if you want to read or change the code.

1. Install **AutoHotkey v2** from <https://www.autohotkey.com/>.
2. Clone or download this repository.
3. Download **AutoHotInterception** from <https://github.com/evilC/AutoHotInterception/releases> and extract it.
   Copy the contents of its **`AHK v2\Lib`** folder, plus `AHK v2\AutoHotInterception.dll`, into a `Lib` folder here.
4. Copy the `library\x64` and `library\x86` folders from `Interception.zip` (Step 1) into `Lib`.
5. Unblock the downloaded DLLs: run `Lib\Unblocker.ps1` as Administrator, or right-click each `.dll` →
   Properties → tick **Unblock**.
6. Double-click `M901Mapper.ahk`.

Expected layout:
```
M901Mapper.ahk
Lib\AutoHotInterception.ahk
Lib\AutoHotInterception.dll
Lib\CLR.ahk
Lib\x64\interception.dll
Lib\x86\interception.dll
```

To build the EXE yourself, get Ahk2Exe from <https://github.com/AutoHotkey/Ahk2Exe/releases> and run
`bash build.sh <path-to-Ahk2Exe.exe>` (Git Bash). The result is `dist\M901Mapper.exe`.

## Use

1. Start M901 Mapper (`M901Mapper.exe` or `M901Mapper.ahk`).
2. Click **Detect button** and press a button on the mouse.
3. Pick what it should do (copy, paste, Back/Forward, media keys, any key or combination, typing text, running a program...).
4. Repeat for other buttons. Settings are saved in `M901Mapper.ini`.
5. Click **Start with Windows** to have it run hidden at login. Closing the window keeps it running in the tray.

Buttons you never set up keep doing what the mouse sends today.

- **Mapping: ON/OFF** (top right, or the tray menu) pauses remapping; the mouse then sends its original keys.
- **Backup** saves all your button settings to an `.ini` file you choose (default: Documents).
- **Restore** loads a backup. Your current settings are kept as `M901Mapper.ini.bak` first.
- **Remove** takes a button off the list; **Unchanged** keeps it listed but restores its original keys.

## Limits

- Works only on this PC, and only while M901 Mapper is running.
- DPI, polling rate and lighting are stored inside the mouse and can't be changed this way.
- Buttons that change DPI inside the mouse don't send anything to Windows, so they can't be remapped.
