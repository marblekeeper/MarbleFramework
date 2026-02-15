@echo off
setlocal EnableDelayedExpansion

REM === Marble Roguelike - Desktop Offline Mode ===
REM Launches local TCP server and client

set "MSYS_DIR=C:\msys64\ucrt64"
set "PATH=%MSYS_DIR%\bin;C:\msys64\usr\bin;%PATH%"

echo ================================================
echo   MARBLE ROGUELIKE - DESKTOP OFFLINE MODE
echo ================================================
echo.
echo This will launch:
echo   1. Local TCP server (port 12345)
echo   2. Desktop client (connects via TCP)
echo.

REM Check Lua
where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found
    pause
    exit /b 1
)

REM Check LuaSocket
lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found
    pause
    exit /b 1
)

echo [1/2] Starting TCP server...
start "Marble Server" cmd /c "lua server_tcp.lua & pause"
timeout /t 2 /nobreak >nul

echo [2/2] Starting client...
lua client_unified.lua

pause