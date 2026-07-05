@echo off
rem RealWorld — launch the playable game (GUI). Double-click to play.
set "GODOT=%LOCALAPPDATA%\GodotPortable\Godot_v4.7-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot 4.7 not found at "%GODOT%"
  echo Edit this file and set GODOT to your Godot_v4.7-stable_win64.exe
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0godot"
