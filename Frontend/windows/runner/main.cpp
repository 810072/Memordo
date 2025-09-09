#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// --- 백엔드 서버 관리 시작 ---
// 백엔드 프로세스 정보를 저장할 전역 변수
PROCESS_INFORMATION g_backendProcessInfo = { 0 };

// 백엔드 서버를 시작하는 함수
void StartBackendProcess() {
    // 1. 현재 실행 파일의 경로를 가져옵니다.
    wchar_t path[MAX_PATH];
    GetModuleFileName(NULL, path, MAX_PATH);

    // 2. 경로에서 파일 이름(예: memordo.exe)을 제거하여 부모 디렉토리로 이동합니다.
    *wcsrchr(path, L'\\') = 0;

    // 3. 백엔드 서버 실행 파일의 전체 경로를 구성합니다.
    // 최종 경로는 C:\path\to\your_app\resources\memordo_ai_backend.exe 가 됩니다.
    wchar_t backend_path[MAX_PATH];
    swprintf(backend_path, MAX_PATH, L"%s\\resources\\memordo_ai_backend.exe", path);

    // 4. CreateProcess를 사용하여 백엔드 서버를 실행합니다.
    STARTUPINFO si = { sizeof(si) };
    if (CreateProcess(backend_path, NULL, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &g_backendProcessInfo)) {
        // 성공적으로 시작됨
    }
}

// 백엔드 서버를 종료하는 함수
void StopBackendProcess() {
    if (g_backendProcessInfo.hProcess != NULL) {
        TerminateProcess(g_backendProcessInfo.hProcess, 0);
        CloseHandle(g_backendProcessInfo.hProcess);
        CloseHandle(g_backendProcessInfo.hThread);
    }
}
// --- 백엔드 서버 관리 끝 ---

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ PWSTR cmd_line, _In_ int show_command) {
  
  // --- 백엔드 서버 관리 시작 ---
  // Flutter 앱이 시작되기 전에 백엔드 서버를 먼저 실행합니다.
  StartBackendProcess();
  // --- 백엔드 서버 관리 끝 ---

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

  // --- 백엔드 서버 관리 시작 ---
  // Flutter 앱이 종료될 때 백엔드 서버도 함께 종료합니다.
  StopBackendProcess();
  // --- 백엔드 서버 관리 끝 ---

  return EXIT_SUCCESS;
}
