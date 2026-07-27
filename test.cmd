@echo off
rem RealWorld — run the headless test suites (sim unit tests + playthrough smoke).
set "GODOT=%LOCALAPPDATA%\GodotPortable\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
  echo Godot 4.7 console build not found at "%GODOT%"
  pause
  exit /b 1
)
echo === Unit tests ===
"%GODOT%" --headless --path "%~dp0godot" -s res://tests/run_tests.gd
echo.
echo === Kernel tests (spec 0003) ===
"%GODOT%" --headless --path "%~dp0godot" -s res://tests/run_kernel_tests.gd
echo.
echo === Content catalogue tests (deep craft/resource/building tree) ===
"%GODOT%" --headless --path "%~dp0godot" -s res://tests/run_catalog_tests.gd
echo.
echo === Progression pipeline tests (research -^> unlock) ===
"%GODOT%" --headless --path "%~dp0godot" -s res://tests/run_progression_tests.gd
echo.
echo === UI view-layer tests (spec 0005) ===
"%GODOT%" --headless --path "%~dp0godot" -s res://tests/run_ui_tests.gd
echo.
echo === Determinism suite (spec 0006 - twin-instance world hash) ===
"%GODOT%" --headless --path "%~dp0godot" -s res://tests/run_determinism_tests.gd
echo.
echo === Net transport spike (spec 0006 - 1 server + 2 clients over WebSocket) ===
"%GODOT%" --headless --path "%~dp0godot" -s res://tests/run_net_spike.gd
echo.
echo === Playthrough smoke ===
"%GODOT%" --headless --path "%~dp0godot" -s res://tests/run_smoke.gd
echo.
pause
