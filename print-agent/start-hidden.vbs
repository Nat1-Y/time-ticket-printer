' Starts the Parking Manager print service without a console window.
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = dir
shell.Run "cmd /c node """ & dir & "\server.js"" >> """ & dir & "\service.log"" 2>&1", 0, False
