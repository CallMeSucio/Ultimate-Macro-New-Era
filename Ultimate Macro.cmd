@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0" 2>nul

rem This CMD is the single entry point. It works with the existing AHK paths.
rem If run from a ZIP preview, Windows typically extracts only this CMD to Temp.
if not exist "%~dp0setup\Launch.ps1" goto NotExtracted
if not exist "%~dp0setup\Repair.ps1" goto NotExtracted

if /i "%~1"=="--strategies" goto Strategies
if /i "%~1"=="--show-files" goto ShowFiles
if /i "%~1"=="--repair" goto Repair
if /i "%~1"=="--verify" goto Verify
if /i "%~1"=="--help" goto Help
if /i "%~1"=="--windows-startup" goto WindowsStartup

:Launch
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\Launch.ps1"
set "launchExit=%errorlevel%"
if not "%launchExit%"=="0" (
  echo.
  echo Ultimate Macro could not start. See the message above.
  pause
)
exit /b %launchExit%

:WindowsStartup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\Launch.ps1" -NoPrompt -WindowsStartupLaunch
exit /b %errorlevel%

:Repair
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\Launch.ps1" -RepairOnly
set "launchExit=%errorlevel%"
if not "%launchExit%"=="0" pause
exit /b %launchExit%

:Verify
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\Launch.ps1" -VerifyOnly
set "launchExit=%errorlevel%"
pause
exit /b %launchExit%

:Strategies
if not exist "%~dp0Resources\Strats" goto NotExtracted
start "" explorer.exe "%~dp0Resources\Strats"
exit /b 0

:ShowFiles
for %%P in ("%~dp0Resources" "%~dp0lib" "%~dp0submacros" "%~dp0_app" "%~dp0setup" "%~dp0discord-gateway" "%~dp0Main.ahk" "%~dp0StrategyLab.exe" "%~dp0icon.ico") do if exist "%%~P" attrib -h "%%~P" >nul 2>&1
echo Internal files and folders are now visible in Explorer.
pause
exit /b 0

:Help
echo.
echo    ULTIMATE MACRO
echo    ----------------------------
echo    Double-click Ultimate Macro.cmd to launch.
echo    --repair       Verify and repair this exact build
echo    --verify       Check integrity without modifying files
echo    --strategies   Open the strategies folder
echo    --show-files   Unhide internal folders for troubleshooting
pause
exit /b 0

:NotExtracted
echo.
echo ========================================================
echo   EXTRACT ULTIMATE MACRO FIRST
echo ========================================================
echo.
echo   1. Right-click the ZIP file in Downloads.
echo   2. Select Extract All...
echo   3. Open the extracted folder.
echo   4. Run Ultimate Macro.cmd again.
echo.
echo Do not drag this launcher out of the ZIP by itself.
echo.
powershell.exe -NoProfile -NonInteractive -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Extract the FULL ZIP first, then run Ultimate Macro.cmd from the new folder.', 'Ultimate Macro - Extract All First', 'OK', 'Warning')" >nul 2>nul
pause
exit /b 2
