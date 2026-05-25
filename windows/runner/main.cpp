#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>

#include <fstream>
#include <string>

#include "flutter_window.h"
#include "utils.h"

constexpr const wchar_t kMutexName[] = L"RainCurtainSingleInstanceMutex";
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// 窗口状态持久化结构
#pragma pack(push, 1)
struct WindowState {
  int x;
  int y;
  int width;
  int height;
  bool valid;
};
#pragma pack(pop)

// 获取窗口状态文件路径
std::wstring GetWindowStateFilePath() {
  wchar_t* appdata = nullptr;
  HRESULT hr = SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, NULL, &appdata);
  if (FAILED(hr) || !appdata) {
    if (appdata) CoTaskMemFree(appdata);
    return L"";
  }
  std::wstring path(appdata);
  CoTaskMemFree(appdata);
  path += L"\\GoldenEaglePersonal\\雨幕\\RainCurtain\\window-state.dat";
  return path;
}

// 保存窗口状态
void SaveWindowState(HWND hwnd) {
  if (!hwnd || IsIconic(hwnd)) return;

  std::wstring filePath = GetWindowStateFilePath();
  if (filePath.empty()) return;

  RECT rect;
  GetWindowRect(hwnd, &rect);

  WindowState state;
  state.x = rect.left;
  state.y = rect.top;
  state.width = rect.right - rect.left;
  state.height = rect.bottom - rect.top;
  state.valid = true;

  // 确保目录存在
  std::wstring dir = filePath.substr(0, filePath.find_last_of(L'\\'));
  CreateDirectoryW(dir.c_str(), NULL);

  std::ofstream file(filePath, std::ios::binary);
  if (file.is_open()) {
    file.write(reinterpret_cast<const char*>(&state), sizeof(state));
    file.close();
  }
}

// 读取窗口状态
WindowState LoadWindowState() {
  WindowState state = {0, 0, 1280, 720, false};

  std::wstring filePath = GetWindowStateFilePath();
  if (filePath.empty()) return state;

  std::ifstream file(filePath, std::ios::binary);
  if (file.is_open()) {
    WindowState loaded;
    file.read(reinterpret_cast<char*>(&loaded), sizeof(loaded));
    if (file.good() && loaded.valid) {
      // 验证位置是否仍在某个显示器上
      POINT pt = {loaded.x + loaded.width / 2, loaded.y + loaded.height / 2};
      HMONITOR monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTONULL);
      if (monitor != NULL) {
        state = loaded;
      }
    }
    file.close();
  }

  return state;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Check for existing instance
  HANDLE hMutex = CreateMutex(NULL, TRUE, kMutexName);
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is running, find and activate it
    HWND hwnd = FindWindow(kWindowClassName, NULL);
    if (hwnd) {
      // Show the window if it's hidden
      ShowWindow(hwnd, SW_SHOW);
      SetForegroundWindow(hwnd);
      BringWindowToTop(hwnd);
    }
    if (hMutex) {
      CloseHandle(hMutex);
    }
    return 0;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // 读取保存的窗口状态，决定初始位置
  WindowState saved = LoadWindowState();
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  bool shouldCenter = true;
  bool useRawPixels = false;

  if (saved.valid) {
    origin = Win32Window::Point(static_cast<unsigned int>(std::max(0, saved.x)),
                                static_cast<unsigned int>(std::max(0, saved.y)));
    size = Win32Window::Size(static_cast<unsigned int>(saved.width),
                             static_cast<unsigned int>(saved.height));
    shouldCenter = false;
    useRawPixels = true;
  }

  if (!window.Create(L"\u96e8\u5e55", origin, size, shouldCenter, useRawPixels)) {
    if (hMutex) {
      CloseHandle(hMutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Clean up mutex
  if (hMutex) {
    CloseHandle(hMutex);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
