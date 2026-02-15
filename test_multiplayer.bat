@echo off
REM test_multiplayer.bat
REM Quick multiplayer test - launches server + 3 clients

echo ================================================
echo   MARBLE ROGUELIKE - MULTIPLAYER TEST
echo ================================================
echo.
echo Launching:
echo   1 Server + 3 Clients
echo.

set "MSYS_DIR=C:\msys64\ucrt64"
set "PATH=%MSYS_DIR%\bin;C:\msys64\usr\bin;%PATH%"

REM Start server
start "Marble Server" cmd /k "lua server_tcp.lua"
timeout /t 2 /nobreak >nul

REM Start 3 clients
start "Client 1" cmd /k "lua client_unified.lua"
timeout /t 1 /nobreak >nul

start "Client 2" cmd /k "lua client_unified.lua"
timeout /t 1 /nobreak >nul

start "Client 3" cmd /k "lua client_unified.lua"

echo.
echo All windows launched!
echo Try moving in each client window and watch the others update.
echo.
pause