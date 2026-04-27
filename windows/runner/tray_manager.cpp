#include "tray_manager.h"
#include "resource.h"
#include <string>

TrayManager::TrayManager(HWND hwnd, HINSTANCE hInstance)
    : hwnd_(hwnd), hInstance_(hInstance) {
  ZeroMemory(&nid_, sizeof(NOTIFYICONDATA));
}

TrayManager::~TrayManager() {
  RemoveTrayIcon();
}

bool TrayManager::CreateTrayIcon() {
  nid_.cbSize = sizeof(NOTIFYICONDATA);
  nid_.hWnd = hwnd_;
  nid_.uID = 1;
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid_.uCallbackMessage = WM_TRAYICON;
  nid_.hIcon = LoadIcon(hInstance_, MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(nid_.szTip, L"\u96e8\u5e55");  // Unicode for "雨幕"

  return Shell_NotifyIcon(NIM_ADD, &nid_);
}

void TrayManager::RemoveTrayIcon() {
  Shell_NotifyIcon(NIM_DELETE, &nid_);
}

void TrayManager::ShowTrayMenu() {
  POINT pt;
  GetCursorPos(&pt);

  HMENU hMenu = CreatePopupMenu();
  AppendMenu(hMenu, MF_STRING, ID_TRAY_SHOW, L"\u663e\u793a\u7a97\u53e3");  // "显示窗口"
  AppendMenu(hMenu, MF_SEPARATOR, 0, NULL);
  AppendMenu(hMenu, MF_STRING, ID_TRAY_EXIT, L"\u9000\u51fa");  // "退出"

  SetForegroundWindow(hwnd_);

  UINT cmd = TrackPopupMenu(hMenu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                            pt.x, pt.y, 0, hwnd_, NULL);

  if (cmd == ID_TRAY_SHOW && showWindowCallback_) {
    showWindowCallback_();
  } else if (cmd == ID_TRAY_EXIT && exitAppCallback_) {
    exitAppCallback_();
  }

  DestroyMenu(hMenu);
}

void TrayManager::HandleTrayMessage(WPARAM wParam, LPARAM lParam) {
  if (wParam != 1) return;

  switch (lParam) {
    case WM_LBUTTONDBLCLK:
      if (showWindowCallback_) {
        showWindowCallback_();
      }
      break;

    case WM_RBUTTONUP:
      ShowTrayMenu();
      break;
  }
}

void TrayManager::SetShowWindowCallback(std::function<void()> callback) {
  showWindowCallback_ = callback;
}

void TrayManager::SetExitAppCallback(std::function<void()> callback) {
  exitAppCallback_ = callback;
}
