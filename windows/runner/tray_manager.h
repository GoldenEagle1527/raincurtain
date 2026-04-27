#ifndef RUNNER_TRAY_MANAGER_H_
#define RUNNER_TRAY_MANAGER_H_

#include <windows.h>
#include <shellapi.h>
#include <functional>

class TrayManager {
 public:
  TrayManager(HWND hwnd, HINSTANCE hInstance);
  ~TrayManager();

  bool CreateTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void HandleTrayMessage(WPARAM wParam, LPARAM lParam);

  void SetShowWindowCallback(std::function<void()> callback);
  void SetExitAppCallback(std::function<void()> callback);

  static constexpr UINT WM_TRAYICON = WM_USER + 1;

 private:
  HWND hwnd_;
  HINSTANCE hInstance_;
  NOTIFYICONDATA nid_;

  std::function<void()> showWindowCallback_;
  std::function<void()> exitAppCallback_;

  static constexpr UINT ID_TRAY_SHOW = 1001;
  static constexpr UINT ID_TRAY_EXIT = 1002;
};

#endif  // RUNNER_TRAY_MANAGER_H_
