Option Explicit

Dim shell, fso, rootDir, appScript, command

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

rootDir = fso.GetParentFolderName(WScript.ScriptFullName)
appScript = fso.BuildPath(fso.BuildPath(rootDir, "app"), "Sync-ASCTSharedMods-UI.ps1")
command = "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Quote(appScript)

shell.Run command, 0, False

Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
