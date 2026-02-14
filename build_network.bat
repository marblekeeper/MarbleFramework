@echo off
setlocal EnableDelayedExpansion

REM === Configuration ===
set "MSYS_DIR=C:\msys64\ucrt64"
set "EMSDK_DIR=C:\emsdk"
set "LUA_VERSION=5.4.7"
set "LUA_DIR=vendor\lua-%LUA_VERSION%"
set "PATH=%MSYS_DIR%\bin;C:\msys64\usr\bin;vendor\ThirdParty\bin;%PATH%"

REM === Detect Lua Executable and Library ===
set "LUA_EXE=lua"
set "LUA_LIB=lua"
if exist "%MSYS_DIR%\bin\lua54.exe" set "LUA_EXE=%MSYS_DIR%\bin\lua54.exe"
if exist "%MSYS_DIR%\lib\liblua54.a" set "LUA_LIB=lua54"

REM === Logic Branching for Network Demo ===
if "%1"=="net_server" goto DO_NET_SERVER
if "%1"=="net_client" goto DO_NET_CLIENT
if "%1"=="net_test" goto DO_NET_TEST

:USAGE
echo Usage: build.bat [net_server^|net_client^|net_test]
echo.
echo Network Demo Commands:
echo    net_server  - Launch TCP server (LuaSocket)
echo    net_client  - Launch TCP client (LuaSocket)
echo    net_test    - Run server + client in sequence
echo.
exit /b 1

REM ================================================
REM NETWORK SERVER
REM ================================================
:DO_NET_SERVER
echo ================================================
echo   MARBLE NETWORK - SERVER
echo ================================================
echo.

REM === Pre-flight Checks ===
echo [1/4] Checking Lua installation...
where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found in PATH
    echo.
    echo Install via MSYS2 UCRT64:
    echo   pacman -S mingw-w64-ucrt-x86_64-lua
    exit /b 1
)
echo [OK] Lua found

echo [2/4] Checking LuaRocks installation...
where luarocks >nul 2>nul
if %errorlevel% neq 0 (
    echo [WARNING] LuaRocks not found in PATH
    echo.
    echo Install via MSYS2 UCRT64:
    echo   pacman -S mingw-w64-ucrt-x86_64-lua-luarocks
    echo.
    echo Note: LuaRocks must be run from MSYS2 UCRT64 terminal
)

echo [3/4] Checking LuaSocket library...
lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    echo.
    echo Install via MSYS2 UCRT64 terminal:
    echo   1. Open "MSYS2 UCRT64" from Start Menu
    echo   2. Run: luarocks install luasocket
    echo.
    echo LuaRocks location: %MSYS_DIR%\bin\luarocks
    exit /b 1
)
echo [OK] LuaSocket found

echo [4/4] Starting server on 127.0.0.1:12345...
echo.
%LUA_EXE% network\server.lua

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Server crashed with code %ERRORLEVEL%
    exit /b 1
)
exit /b 0

REM ================================================
REM NETWORK CLIENT
REM ================================================
:DO_NET_CLIENT
echo ================================================
echo   MARBLE NETWORK - CLIENT
echo ================================================
echo.

REM === Pre-flight Checks ===
echo [1/3] Checking Lua installation...
where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found
    exit /b 1
)
echo [OK] Lua found

echo [2/3] Checking LuaSocket library...
lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    echo.
    echo Install via MSYS2 UCRT64 terminal:
    echo   luarocks install luasocket
    exit /b 1
)
echo [OK] LuaSocket found

echo [3/3] Connecting to server...
echo.
%LUA_EXE% network\client.lua

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Client exited with code %ERRORLEVEL%
    exit /b 1
)
exit /b 0

REM ================================================
REM NETWORK TEST (Server + Client)
REM ================================================
:DO_NET_TEST
echo ================================================
echo   MARBLE NETWORK - FULL TEST
echo ================================================
echo.
echo This will verify your network setup.
echo.

REM === Pre-flight Checks ===
echo [1/2] Checking dependencies...
where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found in PATH
    echo.
    echo Install via MSYS2 UCRT64:
    echo   pacman -S mingw-w64-ucrt-x86_64-lua
    exit /b 1
)

lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    echo.
    echo Install steps:
    echo   1. Open "MSYS2 UCRT64" from Start Menu
    echo   2. Run: pacman -S mingw-w64-ucrt-x86_64-lua-luarocks
    echo   3. Run: luarocks install luasocket
    echo.
    echo Your MSYS2 path: %MSYS_DIR%
    exit /b 1
)

echo [OK] All dependencies found
echo.

echo [2/2] Test Instructions:
echo.
echo   Terminal 1: build.bat net_server
echo   Terminal 2: build.bat net_client
echo   Terminal 3: build.bat net_client  (optional - test multi-client)
echo.
echo Or use the simple launchers:
echo   Terminal 1: run_server.bat
echo   Terminal 2: run_client.bat
echo.
echo Starting server in 3 seconds...
timeout /t 3 /nobreak >nul

call :DO_NET_SERVER
exit /b 0