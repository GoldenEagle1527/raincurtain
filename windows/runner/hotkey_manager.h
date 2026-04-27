#ifndef RUNNER_HOTKEY_MANAGER_H_
#define RUNNER_HOTKEY_MANAGER_H_

#include <windows.h>
#include <functional>

class HotkeyManager {
 public:
  HotkeyManager(HWND hwnd);
  ~HotkeyManager();

  bool RegisterHotkey(UINT modifiers, UINT vk);
  void UnregisterHotkey();
  void HandleHotkeyMessage();

  void SetHotkeyCallback(std::function<void()> callback);
  bool IsRegistered() const { return isRegistered_; }

 private:
  HWND hwnd_;
  bool isRegistered_;
  UINT currentModifiers_;
  UINT currentVk_;
  std::function<void()> hotkeyCallback_;

  static constexpr int HOTKEY_ID = 1;
};

#endif  // RUNNER_HOTKEY_MANAGER_H_
