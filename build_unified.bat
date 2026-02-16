@echo off
setlocal EnableDelayedExpansion

REM ================================================================
REM  UNIFIED BUILD SYSTEM — ClayMarble Renderer + MarbleNet Protocol
REM  Combines both projects into a single build pipeline.
REM  
REM  ClayMarble: C backend (SDL2 + EGL + OpenGL ES2) + Lua game scripts
REM  MarbleNet:  Lua TCP/WebSocket protocol layer
REM  NetRogue:   The bridge — networked roguelike using both
REM ================================================================

set "MSYS_DIR=C:\msys64\ucrt64"
set "EMSDK_DIR=C:\emsdk"
set "LUA_VERSION=5.4.7"
set "LUA_DIR=vendor\lua-%LUA_VERSION%"
set "PATH=%MSYS_DIR%\bin;C:\msys64\usr\bin;vendor\ThirdParty\bin;%PATH%"
set "OUT_NAME=marble_phase0_2.exe"
set "UI_OUT_NAME=marble_ui.exe"

REM === Detect Lua Library Name ===
set "LUA_LIB=lua"
if exist "%MSYS_DIR%\lib\liblua54.a" set "LUA_LIB=lua54"

REM === Pre-build Cleanup ===
REM Skip killing marble_ui.exe for netrogue targets (allow multiple clients)
if "%1"=="netrogue" goto SKIP_UI_KILL
if "%1"=="netrogue_join" goto SKIP_UI_KILL
if "%1"=="netrogue_full" goto SKIP_UI_KILL
if "%1"=="netrogue_server" goto SKIP_UI_KILL
taskkill /F /IM %UI_OUT_NAME% >nul 2>nul
:SKIP_UI_KILL
taskkill /F /IM %OUT_NAME% >nul 2>nul
taskkill /F /IM test.exe >nul 2>nul
taskkill /F /IM test_cmd.exe >nul 2>nul
taskkill /F /IM test_items.exe >nul 2>nul
taskkill /F /IM test_gen.exe >nul 2>nul

REM === Logic Branching ===
REM --- ClayMarble Targets ---
if "%1"=="ui_test" goto DO_UI_TEST
if "%1"=="sprite_font_editor" goto DO_SPRITE_FONT_EDITOR
if "%1"=="mindmarr" goto DO_MINDMARR
if "%1"=="web" goto DO_WEB_BUILD
if "%1"=="web_serve" goto DO_WEB_SERVE
if "%1"=="test" goto DO_TEST
if "%1"=="gcc" goto DO_GCC
if "%1"=="msvc" goto DO_MSVC
if "%1"=="clean_dlls" goto DO_CLEAN_DLLS

REM --- MarbleNet Targets ---
if "%1"=="net_server" goto DO_NET_SERVER
if "%1"=="net_client" goto DO_NET_CLIENT
if "%1"=="net_test" goto DO_NET_TEST
if "%1"=="net_web" goto DO_NET_WEB

REM --- UNIFIED: NetRogue (ClayMarble renderer + MarbleNet protocol) ---
if "%1"=="netrogue" goto DO_NETROGUE
if "%1"=="netrogue_join" goto DO_NETROGUE_JOIN
if "%1"=="netrogue_server" goto DO_NETROGUE_SERVER
if "%1"=="netrogue_full" goto DO_NETROGUE_FULL

:USAGE
echo ================================================================
echo  UNIFIED BUILD SYSTEM
echo  ClayMarble (Renderer) + MarbleNet (Network Protocol)
echo ================================================================
echo.
echo NETROGUE (The Dream):
echo    netrogue            - Build and launch NetRogue client (renderer)
echo    netrogue_join       - Launch another client (no rebuild, no kill)
echo    netrogue_server     - Launch the TCP game server
echo    netrogue_full       - Launch server + NetRogue client together
echo.
echo ClayMarble (Renderer):
echo    msvc                - Build runtime with Visual Studio cl.exe
echo    gcc                 - Build runtime with GCC/MinGW
echo    test                - Build and run test harness (GCC)
echo    test msvc           - Build and run test harness (MSVC)
echo    ui_test             - Build and run Lua UI Demo (SDL2 + EGL + Lua)
echo    sprite_font_editor  - Build and run Sprite Font Editor Tool
echo    mindmarr            - Build and run MindMarr game
echo    web                 - Build for web with Emscripten
echo    web_serve           - Build for web and start local server
echo    clean_dlls          - Remove all DLLs from project root
echo.
echo MarbleNet (Protocol):
echo    net_server          - Launch TCP network server
echo    net_client          - Launch TCP network client
echo    net_test            - Launch server + 3 clients for testing
echo    net_web             - Build WASM network client (Emscripten)
echo.
exit /b 1

:DO_CLEAN_DLLS
echo Cleaning DLLs from project root...
del /Q SDL2.dll 2>nul
del /Q libEGL.dll 2>nul
del /Q libGLESv2.dll 2>nul
del /Q d3dcompiler_47.dll 2>nul
del /Q zlib1.dll 2>nul
del /Q libgcc_s_seh-1.dll 2>nul
del /Q libstdc++-6.dll 2>nul
del /Q libwinpthread-1.dll 2>nul
del /Q lua54.dll 2>nul
del /Q lua.dll 2>nul
echo Done.
exit /b 0

REM ================================================================
REM  NETROGUE — The Unified Target
REM  Builds ClayMarble renderer, launches with NetRogue.lua
REM  which uses MarbleNet's protocol.lua over TCP
REM ================================================================

:DO_NETROGUE
echo ================================================
echo  NETROGUE — Networked ASCII Roguelike
echo  ClayMarble Renderer + MarbleNet Protocol
echo ================================================
echo.

REM Step 1: Verify LuaSocket is available
echo [1/3] Checking dependencies...
lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    echo.
    echo NetRogue requires LuaSocket for TCP networking.
    echo Install via MSYS2 UCRT64 terminal:
    echo   luarocks install luasocket
    exit /b 1
)
echo   [OK] LuaSocket found

REM Verify protocol.lua exists
if not exist "protocol.lua" (
    echo [ERROR] protocol.lua not found!
    echo   MarbleNet protocol files must be in the project root.
    exit /b 1
)
echo   [OK] protocol.lua found

REM Verify NetRogue.lua exists
if not exist "NetRogue\NetRogue.lua" (
    echo [ERROR] NetRogue\NetRogue.lua not found!
    echo   Create the NetRogue folder and place NetRogue.lua inside it.
    exit /b 1
)
echo   [OK] NetRogue.lua found
echo.

REM Step 2: Build the ClayMarble renderer (skip if already built)
if exist %UI_OUT_NAME% (
    echo [2/3] %UI_OUT_NAME% already exists, skipping build.
    echo   Delete it manually to force rebuild.
    goto NETROGUE_LAUNCH
)

echo [2/3] Building ClayMarble renderer...
gcc -std=c99 -O2 tests\test_ui.c src\bridge_engine.c src\input_handler.c -o %UI_OUT_NAME% ^
    -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -I"%MSYS_DIR%\include\SDL2" ^
    -Ivendor\minimp3\minimp3 ^
    -L"%MSYS_DIR%\lib" -Lvendor\ThirdParty\bin ^
    -lmingw32 -lSDL2main -lSDL2 -l%LUA_LIB% -lm ^
    -lEGL -lGLESv2 -lopengl32 -lgdi32 -lwinmm -limm32 -lole32 -loleaut32 -lversion -luuid -lsetupapi

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Build failed!
    exit /b 1
)
echo   [OK] Built %UI_OUT_NAME%

:NETROGUE_LAUNCH
echo.

REM Step 3: Launch with NetRogue script
echo [3/3] Launching NetRogue...
echo.
echo   Make sure the server is running:
echo     build.bat netrogue_server
echo.

if exist %UI_OUT_NAME% (
    .\%UI_OUT_NAME% NetRogue
)
exit /b 0

:DO_NETROGUE_JOIN
echo ================================================
echo  NETROGUE — Join (no rebuild)
echo ================================================
echo.
if not exist %UI_OUT_NAME% (
    echo [ERROR] %UI_OUT_NAME% not found! Run "build.bat netrogue" first to build.
    exit /b 1
)
echo Launching additional NetRogue client...
start "NetRogue Client" .\%UI_OUT_NAME% NetRogue
exit /b 0

:DO_NETROGUE_SERVER
echo ================================================
echo  NETROGUE SERVER (MarbleNet TCP)
echo ================================================
echo.

where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found in PATH
    exit /b 1
)

lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    echo.
    echo Install via MSYS2 UCRT64 terminal:
    echo   luarocks install luasocket
    exit /b 1
)

echo [OK] Starting NetRogue TCP server...
echo     Clients connect via: build.bat netrogue
echo.
lua server_tcp.lua
exit /b 0

:DO_NETROGUE_FULL
echo ================================================
echo  NETROGUE — Full Stack Launch
echo  Server + Renderer Client
echo ================================================
echo.

REM Verify dependencies first
where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found in PATH
    exit /b 1
)
lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    exit /b 1
)

REM Build renderer
echo [1/3] Building renderer...
gcc -std=c99 -O2 tests\test_ui.c src\bridge_engine.c src\input_handler.c -o %UI_OUT_NAME% ^
    -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -I"%MSYS_DIR%\include\SDL2" ^
    -Ivendor\minimp3\minimp3 ^
    -L"%MSYS_DIR%\lib" -Lvendor\ThirdParty\bin ^
    -lmingw32 -lSDL2main -lSDL2 -l%LUA_LIB% -lm ^
    -lEGL -lGLESv2 -lopengl32 -lgdi32 -lwinmm -limm32 -lole32 -loleaut32 -lversion -luuid -lsetupapi

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Build failed!
    exit /b 1
)

echo [2/3] Launching server...
start "NetRogue Server" cmd /k "lua server_tcp.lua"
timeout /t 2 /nobreak >nul

echo [3/3] Launching NetRogue client...
if exist %UI_OUT_NAME% (
    start "NetRogue Client" .\%UI_OUT_NAME% NetRogue
)

echo.
echo ================================================
echo  NetRogue is running!
echo  Server: Terminal 1 (TCP on 127.0.0.1:12345)
echo  Client: SDL2 window
echo  
echo  Launch additional clients with:
echo    build.bat netrogue
echo ================================================
exit /b 0

REM ================================================================
REM  MARBLENET TARGETS (unchanged from your existing build)
REM ================================================================

:DO_NET_SERVER
echo ================================================
echo   MARBLE NETWORK — TCP SERVER
echo ================================================
echo.

where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found in PATH
    exit /b 1
)

lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    echo.
    echo Install via MSYS2 UCRT64 terminal:
    echo   luarocks install luasocket
    exit /b 1
)

echo [OK] Starting TCP server...
lua server_tcp.lua
exit /b 0

:DO_NET_CLIENT
echo ================================================
echo   MARBLE NETWORK — TCP CLIENT
echo ================================================
echo.

where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found
    exit /b 1
)

lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    exit /b 1
)

echo [OK] Connecting to server...
lua client_unified.lua
exit /b 0

:DO_NET_TEST
echo ================================================
echo   MARBLE NETWORK — MULTIPLAYER TEST
echo ================================================
echo.

where lua >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Lua not found
    exit /b 1
)

lua -e "require('socket')" >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] LuaSocket not found!
    exit /b 1
)

echo Launching server + 3 clients...
echo.

start "Network Server" cmd /k "lua server_tcp.lua"
timeout /t 2 /nobreak >nul

start "Client 1" cmd /k "lua client_unified.lua"
timeout /t 1 /nobreak >nul

start "Client 2" cmd /k "lua client_unified.lua"
timeout /t 1 /nobreak >nul

start "Client 3" cmd /k "lua client_unified.lua"

echo All windows launched!
exit /b 0

:DO_NET_WEB
echo ================================================
echo BUILDING NETWORK CLIENT FOR WASM
echo ================================================
echo.

set "EMCC_PATH="
if exist "%EMSDK_DIR%\upstream\emscripten\emcc.bat" (
    set "EMCC_PATH=%EMSDK_DIR%\upstream\emscripten"
)

if "%EMCC_PATH%"=="" (
    echo [ERROR] Emscripten not found!
    echo Install from: https://emscripten.org/docs/getting_started/downloads.html
    exit /b 1
)

set "PATH=%EMCC_PATH%;%EMSDK_DIR%;%PATH%"

echo [1/4] Checking Lua %LUA_VERSION% sources...
if not exist "%LUA_DIR%\src\lua.h" (
    echo [ERROR] Lua sources not found at %LUA_DIR%\src\
    exit /b 1
)
echo [OK] Lua sources found
echo.

echo [2/4] Compiling Lua for WebAssembly...
pushd %LUA_DIR%\src
call emcc -c -O2 -DLUA_USE_POSIX ^
    lapi.c lcode.c lctype.c ldebug.c ldo.c ldump.c lfunc.c lgc.c llex.c lmem.c ^
    lobject.c lopcodes.c lparser.c lstate.c lstring.c ltable.c ltm.c lundump.c ^
    lvm.c lzio.c lauxlib.c lbaselib.c lcorolib.c ldblib.c liolib.c lmathlib.c ^
    loadlib.c loslib.c lstrlib.c ltablib.c lutf8lib.c linit.c

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Lua compilation failed!
    popd
    exit /b 1
)
call emar rcs liblua_wasm.a *.o
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to create Lua archive!
    popd
    exit /b 1
)
popd
echo [OK] Lua compiled for WebAssembly
echo.

echo [3/4] Setting up network demo files...
if not exist "web_network" mkdir web_network
copy protocol.lua web_network\ >nul
copy network_config.lua web_network\ >nul
copy client_wasm_main.lua web_network\ >nul
echo [OK] Network files prepared
echo.

echo [4/4] Building WASM network client...
if not exist "network_client.c" (
    echo [ERROR] network_client.c not found!
    exit /b 1
)

call emcc network_client.c -o web_network\index.html ^
    -I%LUA_DIR%\src ^
    %LUA_DIR%\src\liblua_wasm.a ^
    -s ALLOW_MEMORY_GROWTH=1 ^
    -s INITIAL_MEMORY=33554432 ^
    -s EXPORTED_RUNTIME_METHODS="['ccall','cwrap']" ^
    -s EXPORTED_FUNCTIONS="['_main','_malloc','_free']" ^
    -s FORCE_FILESYSTEM=1 ^
    --preload-file web_network/protocol.lua@/ ^
    --preload-file web_network/network_config.lua@/ ^
    --preload-file web_network/client_wasm_main.lua@/ ^
    -O2 ^
    -std=c99

del *.o >nul 2>nul
del libluasocket_wasm.a >nul 2>nul

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] WASM build failed!
    exit /b 1
)

echo.
echo ================================================
echo BUILD SUCCESS!
echo ================================================
echo Files in web_network/
echo To test: see net_web instructions
echo ================================================
exit /b 0

REM ================================================================
REM  CLAYMARBLE TARGETS (unchanged)
REM ================================================================

:DO_UI_TEST
echo [1/2] Building UI Test Runtime (SDL2 + Lua + EGL + Audio)...
gcc -std=c99 -O2 tests\test_ui.c src\bridge_engine.c src\input_handler.c -o %UI_OUT_NAME% ^
    -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -I"%MSYS_DIR%\include\SDL2" ^
    -Ivendor\minimp3\minimp3 ^
    -L"%MSYS_DIR%\lib" -Lvendor\ThirdParty\bin ^
    -lmingw32 -lSDL2main -lSDL2 -l%LUA_LIB% -lm ^
    -lEGL -lGLESv2 -lopengl32 -lgdi32 -lwinmm -limm32 -lole32 -loleaut32 -lversion -luuid -lsetupapi

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] UI BUILD FAILED
    exit /b 1
)

echo.
echo [2/2] Running UI Demo...
if exist %UI_OUT_NAME% (
    .\%UI_OUT_NAME%
)
exit /b 0

:DO_SPRITE_FONT_EDITOR
echo ================================================
echo SPRITE FONT EDITOR
echo ================================================
echo [1/2] Building...
gcc -std=c99 -O2 tests\test_ui.c src\bridge_engine.c src\input_handler.c -o %UI_OUT_NAME% ^
    -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -I"%MSYS_DIR%\include\SDL2" ^
    -Ivendor\minimp3\minimp3 ^
    -L"%MSYS_DIR%\lib" -Lvendor\ThirdParty\bin ^
    -lmingw32 -lSDL2main -lSDL2 -l%LUA_LIB% -lm ^
    -lEGL -lGLESv2 -lopengl32 -lgdi32 -lwinmm -limm32 -lole32 -loleaut32 -lversion -luuid -lsetupapi

if %ERRORLEVEL% NEQ 0 exit /b 1

echo [2/2] Launching...
if exist %UI_OUT_NAME% (
    .\%UI_OUT_NAME% sprite_font_editor
)
exit /b 0

:DO_MINDMARR
echo ================================================
echo MINDMARR
echo ================================================
echo [1/2] Building...
gcc -std=c99 -O2 tests\test_ui.c src\bridge_engine.c src\input_handler.c -o %UI_OUT_NAME% ^
    -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -I"%MSYS_DIR%\include\SDL2" ^
    -Ivendor\minimp3\minimp3 ^
    -L"%MSYS_DIR%\lib" -Lvendor\ThirdParty\bin ^
    -lmingw32 -lSDL2main -lSDL2 -l%LUA_LIB% -lm ^
    -lEGL -lGLESv2 -lopengl32 -lgdi32 -lwinmm -limm32 -lole32 -loleaut32 -lversion -luuid -lsetupapi

if %ERRORLEVEL% NEQ 0 exit /b 1

echo [2/2] Launching MindMarr...
if exist %UI_OUT_NAME% (
    .\%UI_OUT_NAME% MindMarr
)
exit /b 0

:DO_WEB_BUILD
echo ================================================
echo BUILDING FOR WEB WITH EMSCRIPTEN
echo ================================================
echo.

set "EMCC_PATH="
if exist "%EMSDK_DIR%\upstream\emscripten\emcc.bat" (
    set "EMCC_PATH=%EMSDK_DIR%\upstream\emscripten"
)

if "%EMCC_PATH%"=="" (
    echo [ERROR] Emscripten not found!
    exit /b 1
)

set "PATH=%EMCC_PATH%;%EMSDK_DIR%;%PATH%"

echo [1/3] Checking Lua %LUA_VERSION% for WebAssembly...

if not exist "%LUA_DIR%\src\lua.h" (
    echo [ERROR] Lua sources not found at %LUA_DIR%\src\
    exit /b 1
)

echo Lua sources found.
echo.

echo [2/3] Compiling Lua for WebAssembly...

pushd %LUA_DIR%\src
call emcc -c -O2 -DLUA_USE_POSIX ^
    lapi.c lcode.c lctype.c ldebug.c ldo.c ldump.c lfunc.c lgc.c llex.c lmem.c ^
    lobject.c lopcodes.c lparser.c lstate.c lstring.c ltable.c ltm.c lundump.c ^
    lvm.c lzio.c lauxlib.c lbaselib.c lcorolib.c ldblib.c liolib.c lmathlib.c ^
    loadlib.c loslib.c lstrlib.c ltablib.c lutf8lib.c linit.c

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Lua compilation failed!
    popd
    exit /b 1
)
call emar rcs liblua_wasm.a *.o
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to create Lua archive!
    popd
    exit /b 1
)
popd
echo Lua compiled for WebAssembly.
echo.

echo [3/3] Building WebAssembly application...
if not exist "web" mkdir web

call emcc tests\test_ui.c src\bridge_engine.c src\input_handler.c -o web\index.html ^
    -Iinclude -Ivendor\ThirdParty\include -I%LUA_DIR%\src ^
    -Ivendor\minimp3\minimp3 ^
    %LUA_DIR%\src\liblua_wasm.a ^
    -s USE_SDL=2 ^
    -s FULL_ES2=1 ^
    -s ALLOW_MEMORY_GROWTH=1 ^
    -s INITIAL_MEMORY=67108864 ^
    -s EXPORTED_RUNTIME_METHODS="['ccall','cwrap']" ^
    -s EXPORTED_FUNCTIONS="['_main','_malloc','_free']" ^
    --preload-file scripts@/scripts ^
    --preload-file "MindMarr@/MindMarr" ^
    --preload-file assets@/assets ^
    -O2 ^
    -std=gnu99 ^
    --shell-file shell_minimal.html

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Web build failed!
    exit /b 1
)

echo.
echo ================================================
echo BUILD SUCCESS!
echo ================================================
echo Files in web/
echo To run: python -m http.server 8000
echo Then: http://localhost:8000/web/
echo ================================================
exit /b 0

:DO_WEB_SERVE
call :DO_WEB_BUILD
if %ERRORLEVEL% NEQ 0 exit /b 1
echo.
echo [Starting server...]
echo Open: http://localhost:8000/web/
python -m http.server 8000
exit /b 0

:DO_TEST
if "%2"=="msvc" (
    cl /std:c11 /W4 /O2 tests\test.c /Fe:test.exe /Iinclude /Ivendor\ThirdParty\include /I"%MSYS_DIR%\include" /link /LIBPATH:"%MSYS_DIR%\lib" %LUA_LIB%.lib
    cl /std:c11 /W4 /O2 tests\test_cmd.c /Fe:test_cmd.exe /Iinclude /Ivendor\ThirdParty\include /I"%MSYS_DIR%\include" /link /LIBPATH:"%MSYS_DIR%\lib" %LUA_LIB%.lib
    cl /std:c11 /W4 /O2 tests\test_items.c /Fe:test_items.exe /Iinclude /Ivendor\ThirdParty\include /I"%MSYS_DIR%\include" /link /LIBPATH:"%MSYS_DIR%\lib" %LUA_LIB%.lib
    cl /std:c11 /W4 /O2 tests\test_gen.c /Fe:test_gen.exe /Iinclude /Ivendor\ThirdParty\include /I"%MSYS_DIR%\include" /link /LIBPATH:"%MSYS_DIR%\lib" %LUA_LIB%.lib
) else (
    gcc -std=c99 -w -O2 tests\test.c -o test.exe -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -L"%MSYS_DIR%\lib" -static -l%LUA_LIB% -lm
    gcc -std=c99 -w -O2 tests\test_cmd.c -o test_cmd.exe -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -L"%MSYS_DIR%\lib" -static -l%LUA_LIB% -lm
    gcc -std=c99 -w -O2 tests\test_items.c -o test_items.exe -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -L"%MSYS_DIR%\lib" -static -l%LUA_LIB% -lm
    gcc -std=c99 -w -O2 tests\test_gen.c -o test_gen.exe -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -L"%MSYS_DIR%\lib" -static -l%LUA_LIB% -lm
)
if %ERRORLEVEL% NEQ 0 exit /b 1
if exist test.exe .\test.exe
if exist test_cmd.exe .\test_cmd.exe
if exist test_items.exe .\test_items.exe
if exist test_gen.exe .\test_gen.exe
exit /b 0

:DO_GCC
gcc -std=c99 -w -O2 src\main.c -o %OUT_NAME% -Iinclude -Ivendor\ThirdParty\include -I"%MSYS_DIR%\include" -L"%MSYS_DIR%\lib" -static -l%LUA_LIB% -lm
goto FINISH

:DO_MSVC
cl /std:c11 /W4 /O2 src\main.c /Fe:%OUT_NAME% /Iinclude /Ivendor\ThirdParty\include /I"%MSYS_DIR%\include" /link /LIBPATH:"%MSYS_DIR%\lib" %LUA_LIB%.lib
goto FINISH

:FINISH
if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build Success: %OUT_NAME%
) else (
    echo.
    echo [ERROR] BUILD FAILED
)
exit /b %ERRORLEVEL%
