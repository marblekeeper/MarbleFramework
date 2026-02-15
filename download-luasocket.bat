@echo off
REM download_luasocket.bat
REM Downloads LuaSocket source code for WASM compilation

echo ================================================
echo   DOWNLOADING LUASOCKET SOURCES
echo ================================================
echo.

if exist "luasocket" (
    echo LuaSocket sources already exist!
    echo Delete the 'luasocket' folder to re-download.
    pause
    exit /b 0
)

echo Downloading LuaSocket v3.1.0...
curl -L https://github.com/lunarmodules/luasocket/archive/refs/tags/v3.1.0.zip -o luasocket.zip

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Download failed!
    echo.
    echo Alternative: git clone https://github.com/lunarmodules/luasocket.git
    pause
    exit /b 1
)

echo Extracting...
tar -xf luasocket.zip

if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Extraction failed!
    pause
    exit /b 1
)

move luasocket-3.1.0 luasocket >nul
del luasocket.zip

echo.
echo ================================================
echo SUCCESS!
echo ================================================
echo.
echo LuaSocket sources downloaded to: luasocket\
echo.
echo Now you can run: build_enhanced.bat net_web
echo.
pause