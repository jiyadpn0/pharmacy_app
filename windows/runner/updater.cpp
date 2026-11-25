#include <windows.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <string>
#include <vector>
#include <chrono>
#include <thread>

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "shell32.lib")

// PharmaPro ERP Dedicated Updater Utility
// Usage: updater.exe --source "<extracted_dir>" --target "<app_dir>" --exe "<target_exe>"
int APIENTRY wWinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow) {
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv || argc < 7) {
        return 1;
    }

    std::wstring sourceDir;
    std::wstring targetDir;
    std::wstring targetExe;

    for (int i = 1; i < argc - 1; ++i) {
        if (wcscmp(argv[i], L"--source") == 0) {
            sourceDir = argv[i + 1];
        } else if (wcscmp(argv[i], L"--target") == 0) {
            targetDir = argv[i + 1];
        } else if (wcscmp(argv[i], L"--exe") == 0) {
            targetExe = argv[i + 1];
        }
    }
    LocalFree(argv);

    if (sourceDir.empty() || targetDir.empty() || targetExe.empty()) {
        return 2;
    }

    // 1. Wait up to 10 seconds for main process to exit cleanly
    std::this_thread::sleep_for(std::chrono::milliseconds(1500));

    // Force kill any remaining pharmacy_app.exe instance if still lingering
    system("taskkill /F /IM pharmacy_app.exe >nul 2>&1");
    std::this_thread::sleep_for(std::chrono::milliseconds(1000));

    // 2. Perform Robocopy synchronization
    std::wstring robocopyCmd = L"robocopy \"" + sourceDir + L"\" \"" + targetDir + L"\" /E /IS /IT /NP /NJH /NJS /R:3 /W:1 >nul 2>&1";
    int roboResult = _wsystem(robocopyCmd.c_str());

    // 3. Fallback to elevated PowerShell if robocopy encountered access issues
    if (roboResult > 7) {
        std::wstring psCmd = L"-NoProfile -ExecutionPolicy Bypass -Command \"Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -Command Copy-Item -Path ''" + sourceDir + L"\\*'' -Destination ''" + targetDir + L"'' -Recurse -Force'\"";
        ShellExecuteW(NULL, L"open", L"powershell.exe", psCmd.c_str(), NULL, SW_HIDE);
        std::this_thread::sleep_for(std::chrono::milliseconds(2000));
    }

    // 4. Launch the updated application executable
    ShellExecuteW(NULL, L"open", targetExe.c_str(), NULL, targetDir.c_str(), SW_SHOWNORMAL);

    return 0;
}
