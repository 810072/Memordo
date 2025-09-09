#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// --- Backend Server Management Start ---
// Global variable to store backend process information
PROCESS_INFORMATION g_backendProcessInfo = { 0 };

// Function to start the backend server process
void StartBackendProcess() {
    // 1. Get the path of the current executable.
    wchar_t path[MAX_PATH];
    GetModuleFileName(NULL, path, MAX_PATH);

    // 2. Remove the file name (e.g., memordo.exe) to get the parent directory.
    *wcsrchr(path, L'\\') = 0;

    // 3. Construct the full path to the backend server executable.
    // The final path will be C:\path\to\your_app\resources\memordo_ai_backend.exe
    wchar_t backend_path[MAX_PATH];
    swprintf(backend_path, MAX_PATH, L"%s\\resources\\memordo_ai_backend.exe", path);

    // 4. Use CreateProcess to run the backend server.
    STARTUPINFO si = { sizeof(si) };
    if (CreateProcess(backend_path, NULL, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &g_backendProcessInfo)) {
        // Successfully started
    }
}

// Function to stop the backend server process
void StopBackendProcess() {
    if (g_backendProcessInfo.hProcess != NULL) {
        TerminateProcess(g_backendProcessInfo.hProcess, 0);
        CloseHandle(g_backendProcessInfo.hProcess);
        CloseHandle(g_backendProcessInfo.hThread);
    }
}
// --- Backend Server Management End ---

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ PWSTR cmd_line, _In_ int show_command) {
  
  // --- Backend Server Management Start ---
  // Start the backend server before the Flutter app starts.
  StartBackendProcess();
  // --- Backend Server Management End ---

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and shared
  // components.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Memordo", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  // --- Backend Server Management Start ---
  // Stop the backend server when the Flutter app exits.
  StopBackendProcess();
  // --- Backend Server Management End ---

  return EXIT_SUCCESS;
}