; M901 Mapper - remap the extra buttons of a Redragon M901 Perdition (USB 04D9:FC02) in Windows.
;
; The mouse keeps its old on-board mapping (its side buttons send keys such as Ctrl+C, Ctrl+V, "4",
; or mouse Back/Forward). This app intercepts ONLY input coming from the M901 (via AutoHotInterception),
; recognises which button was pressed, and performs the action you chose instead.
; Your real keyboard and the left/right/middle mouse buttons are never touched.
;
; Requires: AutoHotkey v2, the Interception driver, and AutoHotInterception's "AHK v2\Lib" in .\Lib.
; See README.md.

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
#include Lib\AutoHotInterception.ahk

global M901_VID := 0x04D9, M901_PID := 0xFC02
global IniFile := A_ScriptDir "\M901Mapper.ini"
global StartupLink := A_Startup "\M901 Mapper.lnk"

; ---------------------------------------------------------------- theme
global C_BG := "17171B", C_PANEL := "24242A", C_TEXT := "E8E8EC", C_DIM := "9A9AA6", C_ACCENT := "E53935", C_OK := "4CAF50"

; ---------------------------------------------------------------- state
global Mappings := Map()      ; trigger -> action ("keys:^c", "hold:XButton1", "run:...", "text:...", "none", "default")
global Names := Map()         ; trigger -> friendly button name
global Enabled := true        ; master switch (Mapping ON/OFF)
global Detecting := false
global HeldMods := []         ; modifier scancodes from the mouse, held back until the main key arrives
global PassedMods := Map()    ; modifier scancodes already forwarded down
global SwallowUp := Map()     ; scancodes whose release must be swallowed
global ActiveKey := Map()     ; scancode -> action currently held (mapped key)
global ActiveBtn := Map()     ; "XButton1"/"XButton2" -> action currently held
global SwallowBtn := Map()

global ModNames := Map(0x1D, "Ctrl", 0x11D, "Ctrl", 0x2A, "Shift", 0x36, "Shift", 0x38, "Alt", 0x138, "Alt", 0x15B, "Win", 0x15C, "Win")

; Actions offered in the chooser: [category, label, action]
global Presets := [
  ["Basic", "Unchanged (what the mouse sends now)", "default"],
  ["Basic", "Do nothing (disable button)", "none"],
  ["Editing", "Copy (Ctrl+C)", "keys:^c"], ["Editing", "Paste (Ctrl+V)", "keys:^v"], ["Editing", "Cut (Ctrl+X)", "keys:^x"],
  ["Editing", "Undo (Ctrl+Z)", "keys:^z"], ["Editing", "Redo (Ctrl+Y)", "keys:^y"], ["Editing", "Select all (Ctrl+A)", "keys:^a"],
  ["Editing", "Save (Ctrl+S)", "keys:^s"], ["Editing", "Find (Ctrl+F)", "keys:^f"],
  ["Mouse", "Mouse Back", "hold:XButton1"], ["Mouse", "Mouse Forward", "hold:XButton2"], ["Mouse", "Middle click", "hold:MButton"],
  ["Mouse", "Left click", "hold:LButton"], ["Mouse", "Right click", "hold:RButton"], ["Mouse", "Double click", "keys:{Click 2}"],
  ["Browser", "Back", "keys:{Browser_Back}"], ["Browser", "Forward", "keys:{Browser_Forward}"], ["Browser", "Refresh", "keys:{Browser_Refresh}"],
  ["Browser", "New tab (Ctrl+T)", "keys:^t"], ["Browser", "Close tab (Ctrl+W)", "keys:^w"], ["Browser", "Reopen closed tab (Ctrl+Shift+T)", "keys:^+t"],
  ["Browser", "Next tab (Ctrl+Tab)", "keys:^{Tab}"], ["Browser", "Previous tab (Ctrl+Shift+Tab)", "keys:^+{Tab}"],
  ["Media", "Volume Up", "keys:{Volume_Up}"], ["Media", "Volume Down", "keys:{Volume_Down}"], ["Media", "Mute", "keys:{Volume_Mute}"],
  ["Media", "Play / Pause", "keys:{Media_Play_Pause}"], ["Media", "Next track", "keys:{Media_Next}"], ["Media", "Previous track", "keys:{Media_Prev}"],
  ["Keys", "Enter", "hold:Enter"], ["Keys", "Escape", "hold:Escape"], ["Keys", "Space", "hold:Space"], ["Keys", "Tab", "hold:Tab"],
  ["Keys", "Delete", "hold:Delete"], ["Keys", "Backspace", "hold:Backspace"], ["Keys", "Page Up", "hold:PgUp"], ["Keys", "Page Down", "hold:PgDn"],
  ["Keys", "Home", "hold:Home"], ["Keys", "End", "hold:End"], ["Keys", "Shift (hold)", "hold:Shift"], ["Keys", "Ctrl (hold)", "hold:Ctrl"],
  ["Windows", "Show desktop (Win+D)", "keys:#d"], ["Windows", "Task view (Win+Tab)", "keys:#{Tab}"], ["Windows", "Screenshot (Win+Shift+S)", "keys:#+s"],
  ["Windows", "Lock PC (Win+L)", "keys:#l"], ["Windows", "File Explorer (Win+E)", "keys:#e"], ["Windows", "Close window (Alt+F4)", "keys:!{F4}"],
  ["Custom", "Press a key / combination...", "custom-key"],
  ["Custom", "Type text...", "custom-text"],
  ["Custom", "Run a program or open a website...", "custom-run"]
]

; ---------------------------------------------------------------- devices
global AHI := AutoHotInterception()
global KbdId := AHI.GetKeyboardId(M901_VID, M901_PID)   ; the M901's keyboard interface (side-button keys)
global MouseId := AHI.GetMouseId(M901_VID, M901_PID)    ; the M901's mouse interface

LoadIni()
AHI.SubscribeKeyboard(KbdId, true, OnMouseKey)                          ; block + handle every key the M901 sends
AHI.SubscribeMouseButton(MouseId, 3, true, OnXButton.Bind("XButton1"))  ; side button Back
AHI.SubscribeMouseButton(MouseId, 4, true, OnXButton.Bind("XButton2"))  ; side button Forward
; Left/right/middle buttons and movement are NOT subscribed, so they always work normally.

EnableDarkMenus()
BuildGui()
A_TrayMenu.Insert("1&", "Open M901 Mapper", (*) => MainGui.Show())
A_TrayMenu.Insert("2&", "Mapping ON/OFF", (*) => ToggleEnabled())
A_TrayMenu.Insert("3&")
A_TrayMenu.Default := "Open M901 Mapper"
UpdateTrayTip()
if !(A_Args.Length && A_Args[1] = "/hidden")
  MainGui.Show()

; ================================================================ input handling

OnMouseKey(code, state) {
  global HeldMods, PassedMods, SwallowUp, ActiveKey
  if !Enabled && !Detecting {                    ; paused: pass everything through untouched
    SendSc(code, state)
    return
  }
  if ModNames.Has(code) {
    if state {                                   ; modifier pressed: hold it back until we know the full combo
      if !ArrHas(HeldMods, code) && !PassedMods.Has(code)
        HeldMods.Push(code)
    } else {                                     ; modifier released
      if (i := ArrIndex(HeldMods, code)) {       ; modifier pressed alone -> forward as a tap
        HeldMods.RemoveAt(i)
        if !Detecting
          SendSc(code, 1), SendSc(code, 0)
      } else if PassedMods.Has(code) {
        PassedMods.Delete(code), SendSc(code, 0)
      } else if SwallowUp.Has(code) {
        SwallowUp.Delete(code)
      }
    }
    return
  }

  if state {                                     ; main key pressed
    if ActiveKey.Has(code) || (SwallowUp.Has(code) && !Detecting)   ; auto-repeat of a mapped/swallowed key
      return
    trig := ModPrefix() KeyLabel(code)
    if Detecting {
      SwallowHeld(), SwallowUp[code] := 1
      Detected(trig)
      return
    }
    act := Mappings.Has(trig) ? Mappings[trig] : "default"
    if act = "default" {                         ; unmapped -> pass the original keys through
      for sc in HeldMods
        PassedMods[sc] := 1, SendSc(sc, 1)
      HeldMods := []
      SendSc(code, 1)
    } else {
      SwallowHeld(), SwallowUp[code] := 1
      ActiveKey[code] := act
      RunAction(act, 1)
    }
  } else {                                       ; main key released
    if ActiveKey.Has(code) {
      act := ActiveKey[code], ActiveKey.Delete(code), SwallowUp.Delete(code)
      RunAction(act, 0)
    } else if SwallowUp.Has(code) {
      SwallowUp.Delete(code)
    } else {
      SendSc(code, 0)
    }
  }
}

OnXButton(name, state) {
  global ActiveBtn, SwallowBtn
  if state {
    if Detecting {
      SwallowBtn[name] := 1
      Detected(name)
      return
    }
    act := (Enabled && Mappings.Has(name)) ? Mappings[name] : "default"
    if act = "default"
      Send("{" name " down}")
    else
      ActiveBtn[name] := act, RunAction(act, 1)
  } else {
    if ActiveBtn.Has(name) {
      act := ActiveBtn[name], ActiveBtn.Delete(name)
      RunAction(act, 0)
    } else if SwallowBtn.Has(name) {
      SwallowBtn.Delete(name)
    } else {
      Send("{" name " up}")
    }
  }
}

RunAction(act, state) {
  parts := StrSplit(act, ":", , 2)
  kind := parts[1], val := parts.Length > 1 ? parts[2] : ""
  try {
    switch kind {
      case "keys": if state
        Send(val)
      case "hold": Send("{" val (state ? " down}" : " up}"))
      case "text": if state
        SendText(val)
      case "run": if state
        Run(val)
    }
  } catch as e {
    TrayTip("Action failed: " act "`n" e.Message, "M901 Mapper")
  }
}

SendSc(code, state) => Send("{Blind}{sc" Format("{:X}", code) (state ? " down}" : " up}"))

SwallowHeld() {
  global HeldMods, SwallowUp
  for sc in HeldMods
    SwallowUp[sc] := 1
  HeldMods := []
}

ModPrefix() {
  s := ""
  for m in ["Ctrl", "Shift", "Alt", "Win"] {
    for sc in HeldMods
      if ModNames[sc] = m {
        s .= m "+"
        break
      }
  }
  return s
}

KeyLabel(code) {
  n := GetKeyName(Format("sc{:X}", code))
  if n = ""
    return Format("SC{:03X}", code)
  return StrLen(n) = 1 ? StrUpper(n) : n
}

ArrIndex(arr, v) {
  for i, x in arr
    if x = v
      return i
  return 0
}
ArrHas(arr, v) => ArrIndex(arr, v) > 0

; ================================================================ settings storage, backup & restore

LoadIni(file := "") {
  global Mappings, Names, Enabled
  if file = ""
    file := IniFile
  Mappings := Map(), Names := Map()
  if !FileExist(file)
    return
  for line in StrSplit(IniRead(file, "Actions", , ""), "`n") {
    if !(p := InStr(line, "="))
      continue
    trig := SubStr(line, 1, p - 1)
    Mappings[trig] := SubStr(line, p + 1)
    Names[trig] := IniRead(file, "Names", trig, trig)
  }
  Enabled := IniRead(file, "Settings", "Enabled", 1) = 1
}

SaveIni(file := "") {
  if file = ""
    file := IniFile
  tmp := file ".tmp"
  try FileDelete(tmp)
  IniWrite(Enabled ? 1 : 0, tmp, "Settings", "Enabled")
  IniWrite(FormatTime(, "yyyy-MM-dd HH:mm"), tmp, "Settings", "Saved")
  for trig, act in Mappings {
    IniWrite(act, tmp, "Actions", trig)
    IniWrite(Names.Has(trig) ? Names[trig] : trig, tmp, "Names", trig)
  }
  FileMove(tmp, file, 1)
}

BackupSettings() {
  def := A_MyDocuments "\M901Mapper-backup-" FormatTime(, "yyyy-MM-dd") ".ini"
  f := FileSelect("S16", def, "Save a backup of your M901 Mapper settings", "Settings (*.ini)")
  if f = ""
    return
  if !RegExMatch(f, "i)\.ini$")
    f .= ".ini"
  try {
    SaveIni(f)
    SetStatus("Backup saved: " f, C_OK)
  } catch as e {
    MsgBox("Could not save the backup:`n" e.Message, "M901 Mapper", "Icon!")
  }
}

RestoreSettings() {
  global Mappings, Names
  f := FileSelect(1, A_MyDocuments, "Restore M901 Mapper settings from a backup", "Settings (*.ini)")
  if f = ""
    return
  if IniRead(f, "Actions", , "") = "" {
    MsgBox("That file doesn't contain any M901 Mapper button settings.", "M901 Mapper", "Icon!")
    return
  }
  if MsgBox("Replace your current button settings with the ones from:`n" f "?`n`nYour current settings are kept as M901Mapper.ini.bak.",
      "Restore settings", "YesNo Icon?") != "Yes"
    return
  try FileCopy(IniFile, IniFile ".bak", 1)
  LoadIni(f)
  SaveIni()
  RefreshList()
  UpdateEnabledUi()
  SetStatus("Restored " Mappings.Count " button(s) from backup.", C_OK)
}

; ================================================================ dark theme helpers

EnableDarkMenus() {
  if VerCompare(A_OSVersion, "10.0.17763") < 0
    return
  ux := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
  try DllCall(DllCall("GetProcAddress", "Ptr", ux, "Ptr", 135, "Ptr"), "Int", 2)   ; SetPreferredAppMode(AllowDark)
  try DllCall(DllCall("GetProcAddress", "Ptr", ux, "Ptr", 136, "Ptr"))             ; FlushMenuThemes
}

DarkWindow(g) {
  g.BackColor := C_BG
  if VerCompare(A_OSVersion, "10.0.17763") >= 0 {
    attr := VerCompare(A_OSVersion, "10.0.18985") >= 0 ? 20 : 19
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", attr, "Int*", 1, "Int", 4)
  }
}

DarkCtrl(ctrl, theme := "DarkMode_Explorer") => DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", theme, "Ptr", 0)

DarkButton(g, opts, text, handler) {
  b := g.Add("Button", opts, text)
  DarkCtrl(b)
  b.OnEvent("Click", handler)
  return b
}

; ================================================================ main window

BuildGui() {
  global MainGui, LV, Status, BtnDetect, BtnCancel, BtnEnabled, BtnStartup
  MainGui := Gui("-MaximizeBox", "M901 Mapper")
  DarkWindow(MainGui)
  MainGui.MarginX := 20, MainGui.MarginY := 16
  MainGui.OnEvent("Close", (*) => MainGui.Hide())
  MainGui.OnEvent("Escape", (*) => (Detecting ? CancelDetect() : MainGui.Hide()))

  ; header
  MainGui.SetFont("s20 bold c" C_ACCENT, "Segoe UI")
  MainGui.Add("Text", "xm ym w440", "M901 MAPPER")
  MainGui.SetFont("s10 norm c" C_DIM, "Segoe UI")
  MainGui.Add("Text", "xm y+0 w440", "Redragon M901 Perdition  ·  side buttons remapped in Windows")
  MainGui.SetFont("s10 bold c" C_TEXT, "Segoe UI")
  BtnEnabled := DarkButton(MainGui, "x520 ym+6 w220 h36", "", (*) => ToggleEnabled())

  ; detect bar
  MainGui.SetFont("s11 bold c" C_TEXT, "Segoe UI")
  BtnDetect := DarkButton(MainGui, "xm y+30 w200 h42 Default", "◉  Detect button", (*) => StartDetect())
  MainGui.SetFont("s10 norm c" C_TEXT, "Segoe UI")
  BtnCancel := DarkButton(MainGui, "x+10 yp w90 h42 Disabled", "Cancel", (*) => CancelDetect())
  MainGui.SetFont("s10 c" C_DIM, "Segoe UI")
  Status := MainGui.Add("Text", "x+16 yp+12 w410", "Click 'Detect button', then press a button on your mouse.")

  ; button list
  MainGui.SetFont("s10 norm c" C_TEXT, "Segoe UI")
  LV := MainGui.Add("ListView", "xm y+24 w720 r13 -Multi -E0x200 Background" C_PANEL " LV0x10000", ["Button", "Mouse sends", "Action"])
  DarkCtrl(LV)
  LV.OnEvent("DoubleClick", (*) => EditSelected())
  LV.OnEvent("ItemSelect", (*) => UpdateSelectionUi())

  ; actions row
  MainGui.SetFont("s10 norm c" C_TEXT, "Segoe UI")
  global BtnEdit := DarkButton(MainGui, "xm y+12 w140 h34", "✎  Change action", (*) => EditSelected())
  global BtnRename := DarkButton(MainGui, "x+8 yp w110 h34", "Rename", (*) => RenameSelected())
  global BtnReset := DarkButton(MainGui, "x+8 yp w110 h34", "Unchanged", (*) => ResetSelected())
  global BtnDelete := DarkButton(MainGui, "x+8 yp w100 h34", "Remove", (*) => DeleteSelected())
  DarkButton(MainGui, "x+40 yp w90 h34", "↓  Backup", (*) => BackupSettings())
  DarkButton(MainGui, "x+8 yp w90 h34", "↑  Restore", (*) => RestoreSettings())

  ; footer
  MainGui.SetFont("s9 c" C_DIM, "Segoe UI")
  BtnStartup := DarkButton(MainGui, "xm y+18 w190 h30", "", (*) => ToggleStartup())
  MainGui.Add("Text", "x+16 yp+7 w510", "Closing this window keeps mapping active in the tray. Right-click the tray icon › Exit to quit.")

  RefreshList()
  UpdateEnabledUi()
  UpdateStartupUi()
  UpdateSelectionUi()
}

SetStatus(text, color := "") {
  Status.Opt("c" (color = "" ? C_DIM : color))
  Status.Text := text
}

RefreshList(select := "") {
  LV.Delete()
  LV.Opt("-Redraw")
  for trig, act in Mappings {
    row := LV.Add(, Names.Has(trig) ? Names[trig] : trig, trig, ActionLabel(act))
    if trig = select
      LV.Modify(row, "Select Focus Vis")
  }
  LV.ModifyCol(1, 190), LV.ModifyCol(2, 170), LV.ModifyCol(3, 330)
  LV.Opt("+Redraw")
  UpdateSelectionUi()
}

UpdateSelectionUi() {
  has := LV.GetNext() > 0
  for b in [BtnEdit, BtnRename, BtnReset, BtnDelete]
    b.Enabled := has
}

UpdateEnabledUi() {
  BtnEnabled.Text := Enabled ? "●  Mapping: ON" : "○  Mapping: OFF (paused)"
  UpdateTrayTip()
}

UpdateStartupUi() => BtnStartup.Text := FileExist(StartupLink) ? "✔  Starts with Windows" : "Start with Windows: off"

UpdateTrayTip() {
  A_IconTip := "M901 Mapper - " (Enabled ? "ON" : "paused")
}

ToggleEnabled() {
  global Enabled := !Enabled
  SaveIni()
  UpdateEnabledUi()
  SetStatus(Enabled ? "Mapping is ON." : "Mapping paused - the mouse sends its original keys.", Enabled ? C_OK : C_ACCENT)
}

ToggleStartup() {
  if FileExist(StartupLink) {
    try FileDelete(StartupLink)
  } else {
    FileCreateShortcut(A_AhkPath, StartupLink, A_ScriptDir, '"' A_ScriptFullPath '" /hidden', "M901 Mapper")
  }
  UpdateStartupUi()
}

ActionLabel(act) {
  for p in Presets
    if p[3] = act
      return (p[1] = "Basic" ? "" : p[1] " › ") p[2]
  parts := StrSplit(act, ":", , 2)
  switch parts[1] {
    case "keys": return "Keys: " parts[2]
    case "hold": return "Key: " parts[2]
    case "text": return "Type: " parts[2]
    case "run":  return "Run: " parts[2]
  }
  return act
}

; ---------------------------------------------------------------- detection

StartDetect() {
  global Detecting := true
  BtnDetect.Enabled := false, BtnCancel.Enabled := true
  SetStatus("Press the mouse button now...", C_ACCENT)
  SetTimer(CancelDetect, -15000)
}

CancelDetect() {
  global Detecting := false
  SetTimer(CancelDetect, 0)
  BtnDetect.Enabled := true, BtnCancel.Enabled := false
  SetStatus("Click 'Detect button', then press a button on your mouse.")
}

Detected(trig) {
  global Mappings, Names
  CancelDetect()
  isNew := !Mappings.Has(trig)
  if isNew {
    Mappings[trig] := "default"
    Names[trig] := "Button " Mappings.Count
    SaveIni()
  }
  RefreshList(trig)
  SetStatus((isNew ? "New button detected: " : "Detected: ") trig, C_OK)
  MainGui.Show()
  ChooseAction(trig)
}

; ---------------------------------------------------------------- list actions

SelectedTrigger() {
  if !(row := LV.GetNext())
    return ""
  return LV.GetText(row, 2)
}

EditSelected() {
  if (t := SelectedTrigger()) != ""
    ChooseAction(t)
}

RenameSelected() {
  global Names
  if (t := SelectedTrigger()) = ""
    return
  v := DarkInput("Rename button", "Name for this button (e.g. 'Side 5'):", Names.Has(t) ? Names[t] : t)
  if v != "" {
    Names[t] := v, SaveIni(), RefreshList(t)
  }
}

ResetSelected() {
  global Mappings
  if (t := SelectedTrigger()) = ""
    return
  Mappings[t] := "default", SaveIni(), RefreshList(t)
  SetStatus("Back to unchanged: " t)
}

DeleteSelected() {
  global Mappings, Names
  if (t := SelectedTrigger()) = ""
    return
  Mappings.Delete(t)
  if Names.Has(t)
    Names.Delete(t)
  SaveIni(), RefreshList()
  SetStatus("Removed " t " (it sends its original keys again).")
}

; ---------------------------------------------------------------- action chooser

ChooseAction(trig) {
  name := Names.Has(trig) ? Names[trig] : trig
  cur := Mappings.Has(trig) ? Mappings[trig] : "default"

  dlg := Gui("+Owner" MainGui.Hwnd " -MinimizeBox", "Choose action")
  DarkWindow(dlg)
  dlg.MarginX := 18, dlg.MarginY := 14
  dlg.SetFont("s13 bold c" C_TEXT, "Segoe UI")
  dlg.Add("Text", "xm w520", name)
  dlg.SetFont("s9 norm c" C_DIM, "Segoe UI")
  dlg.Add("Text", "xm y+0 w520", "Mouse sends: " trig "     ·     Current: " ActionLabel(cur))

  cats := []
  for p in Presets
    if !ArrHas(cats, p[1])
      cats.Push(p[1])
  dlg.SetFont("s10 c" C_TEXT, "Segoe UI")
  lbCat := dlg.Add("ListBox", "xm y+14 w150 r15 -E0x200 Background" C_PANEL, cats)
  lbAct := dlg.Add("ListBox", "x+10 yp w360 r15 -E0x200 Background" C_PANEL)
  DarkCtrl(lbCat), DarkCtrl(lbAct)
  shown := []                                   ; actions currently listed in lbAct

  FillActions(*) {
    lbAct.Delete()
    shown := []
    for p in Presets
      if p[1] = cats[lbCat.Value]
        lbAct.Add([p[2]]), shown.Push(p[3])
    for i, a in shown
      if a = cur
        lbAct.Choose(i)
  }
  lbCat.OnEvent("Change", FillActions)
  lbAct.OnEvent("DoubleClick", Apply)

  ; preselect the current action's category
  sel := 1
  for p in Presets
    if p[3] = cur
      sel := ArrIndex(cats, p[1])
  if cur ~= "^(keys|hold|text|run):" && !HasPreset(cur)
    sel := ArrIndex(cats, "Custom")
  lbCat.Choose(sel), FillActions()

  dlg.SetFont("s10 bold c" C_TEXT, "Segoe UI")
  DarkButton(dlg, "xm y+14 w120 h34 Default", "OK", Apply)
  dlg.SetFont("s10 norm c" C_TEXT, "Segoe UI")
  DarkButton(dlg, "x+8 yp w120 h34", "Cancel", (*) => dlg.Destroy())
  dlg.OnEvent("Escape", (*) => dlg.Destroy())
  dlg.Show()

  Apply(*) {
    global Mappings
    if !lbAct.Value
      return
    act := shown[lbAct.Value]
    dlg.Destroy()
    switch act {
      case "custom-key":  act := AskKey()
      case "custom-text":
        v := DarkInput("Type text", "Text to type when the button is pressed:")
        act := v != "" ? "text:" v : ""
      case "custom-run":
        v := DarkInput("Run", "Program path or website (e.g. notepad.exe or https://google.com):")
        act := v != "" ? "run:" v : ""
    }
    if act = ""
      return
    Mappings[trig] := act
    SaveIni(), RefreshList(trig)
    SetStatus("Saved: " name " → " ActionLabel(act), C_OK)
  }
}

HasPreset(act) {
  for p in Presets
    if p[3] = act
      return true
  return false
}

; ---------------------------------------------------------------- small dark dialogs

DarkInput(title, prompt, default := "") {
  result := ""
  dlg := Gui("+Owner" MainGui.Hwnd " -MinimizeBox", title)
  DarkWindow(dlg)
  dlg.MarginX := 18, dlg.MarginY := 14
  dlg.SetFont("s10 c" C_TEXT, "Segoe UI")
  dlg.Add("Text", "xm w420", prompt)
  ed := dlg.Add("Edit", "xm y+8 w420 -E0x200 Background" C_PANEL, default)
  DarkCtrl(ed)
  dlg.SetFont("s10 bold c" C_TEXT, "Segoe UI")
  DarkButton(dlg, "xm y+14 w110 h32 Default", "OK", (*) => (result := Trim(ed.Value), dlg.Destroy()))
  dlg.SetFont("s10 norm c" C_TEXT, "Segoe UI")
  DarkButton(dlg, "x+8 yp w110 h32", "Cancel", (*) => dlg.Destroy())
  dlg.OnEvent("Escape", (*) => dlg.Destroy())
  dlg.Show()
  hwnd := dlg.Hwnd
  WinWaitClose("ahk_id " hwnd)
  return result
}

AskKey() {
  result := ""
  dlg := Gui("+Owner" MainGui.Hwnd " -MinimizeBox", "Press a key / combination")
  DarkWindow(dlg)
  dlg.MarginX := 18, dlg.MarginY := 14
  dlg.SetFont("s10 c" C_TEXT, "Segoe UI")
  dlg.Add("Text", "xm w340", "Click the box, then press the key or combination on your KEYBOARD:")
  hk := dlg.Add("Hotkey", "xm y+8 w340")
  dlg.SetFont("s10 bold c" C_TEXT, "Segoe UI")
  DarkButton(dlg, "xm y+14 w110 h32 Default", "OK", (*) => (result := hk.Value, dlg.Destroy()))
  dlg.SetFont("s10 norm c" C_TEXT, "Segoe UI")
  DarkButton(dlg, "x+8 yp w110 h32", "Cancel", (*) => dlg.Destroy())
  dlg.Show()
  hwnd := dlg.Hwnd
  WinWaitClose("ahk_id " hwnd)
  if result = ""
    return ""
  ; No modifiers -> "hold" so the key can be held down (games). With modifiers -> send the combination.
  return RegExMatch(result, "^[\^\+!#]") ? "keys:" result : "hold:" result
}
