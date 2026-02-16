/* src/launcher.c */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char* argv[]) {
    // 1. Define the relative path to your DLLs
    const char* relativeDllPath = "vendor\\ThirdParty\\bin";
    const char* gameExecutable = "_marble_core.exe";

    // 2. Get the current Working Directory
    char currentDir[MAX_PATH];
    GetCurrentDirectoryA(MAX_PATH, currentDir);

    // 3. Construct the absolute path to the DLL folder
    char dllDir[MAX_PATH];
    snprintf(dllDir, MAX_PATH, "%s\\%s", currentDir, relativeDllPath);

    // 4. Get the current PATH environment variable
    DWORD pathLen = GetEnvironmentVariableA("PATH", NULL, 0);
    char* oldPath = (char*)malloc(pathLen + 1);
    GetEnvironmentVariableA("PATH", oldPath, pathLen);

    // 5. Create new PATH: "absoluteDllPath;oldPath"
    //    IMPORTANT: We PREPEND the path so our DLLs are found FIRST.
    size_t newPathLen = pathLen + strlen(dllDir) + 2;
    char* newPath = (char*)malloc(newPathLen);
    
    // CHANGE IS HERE: dllDir comes first!
    snprintf(newPath, newPathLen, "%s;%s", dllDir, oldPath);
    
    SetEnvironmentVariableA("PATH", newPath);

    // 6. Launch the actual game process
    char cmdLine[2048] = {0};
    snprintf(cmdLine, sizeof(cmdLine), "\"%s\\%s\"", currentDir, gameExecutable);
    
    // Append original arguments
    for(int i = 1; i < argc; i++) {
        strcat(cmdLine, " ");
        strcat(cmdLine, argv[i]);
    }

    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    if (!CreateProcessA(
        NULL,           
        cmdLine,        
        NULL,           
        NULL,           
        TRUE,           
        0,              
        NULL,           
        currentDir,     
        &si,
        &pi
    )) {
        char errMsg[256];
        snprintf(errMsg, sizeof(errMsg), "Failed to launch %s", gameExecutable);
        MessageBoxA(NULL, errMsg, "Launcher Error", MB_ICONERROR);
        return 1;
    }

    WaitForSingleObject(pi.hProcess, INFINITE);
    
    DWORD exitCode = 0;
    GetExitCodeProcess(pi.hProcess, &exitCode);

    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    free(oldPath);
    free(newPath);

    return (int)exitCode;
}