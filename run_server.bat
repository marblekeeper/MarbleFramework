@echo off
setlocal EnableDelayedExpansion

REM === Configuration ===
set "MSYS_DIR=C:\msys64\ucrt64"
set "LUA_VERSION=5.4.7"
set "PATH=%MSYS_DIR%\bin;C:\msys64\usr\bin;%PATH%"

REM === Detect Lua Executable ===
set "LUA_EXE=lua"
if exist "%MSYS_DIR%\bin\lua.exe" set "LUA_EXE=%MSYS_DIR%\bin\lua.exe"
if exist "%MSYS_DIR%\bin\lua54.exe" set "LUA_EXE=%MSYS_DIR%\bin\lua54.exe"

echo ================================================
echo   MARBLE ROGUELIKE - SERVER LAUNCHER
echo ================================================
echo.

REM === Check if Lua is installed ===
where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found in PATH
    echo.
    echo Install via MSYS2 UCRT64:
    echo   pacman -S mingw-w64-ucrt-x86_64-lua
    echo.
    pause
    exit /b 1
)

REM === Check if LuaSocket is available ===
echo [1/3] Checking LuaSocket installation...
lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    echo.
    echo Install via MSYS2 UCRT64 terminal:
    echo   Open "MSYS2 UCRT64" from Start Menu
    echo   Run: luarocks install luasocket
    echo.
    echo LuaRocks location: %MSYS_DIR%\bin\luarocks
    pause
    exit /b 1
)

echo [OK] LuaSocket detected
echo.

REM === Display Network Info ===
echo [2/3] Network Configuration:
echo   Server Address: 127.0.0.1
echo   Port: 12345
echo   Protocol: TCP
echo.

REM === Launch Server ===
echo [3/3] Starting TCP server...
echo.
%LUA_EXE% server_tcp.lua

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Server crashed with code %ERRORLEVEL%
    pause
    exit /b 1
)

pause