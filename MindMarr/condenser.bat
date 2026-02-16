@echo off
set "output=combined_scripts.txt"

:: Create/Clear the output file
type nul > "%output%"

for %%f in (*.lua) do (
    echo ==== FILE START %%f ==== >> "%output%"
    type "%%f" >> "%output%"
    echo. >> "%output%"
    echo ==== FILE END ==== >> "%output%"
    echo. >> "%output%"
)

echo Done! Created %output%
pause