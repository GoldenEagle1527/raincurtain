#include "hotkey_manager.h"

HotkeyManager::HotkeyManager(HWND hwnd)
    : hwnd_(hwnd),
      isRegistered_(false),
      currentModifiers_(0),
      currentVk_(0) {}

HotkeyManager::~HotkeyManager() {
  UnregisterHotkey();
}

bool HotkeyManager::RegisterHotkey(UINT modifiers, UINT vk) {
  if (isRegistered_) {
    UnregisterHotkey();
  }

  if (RegisterHotKey(hwnd_, HOTKEY_ID, modifiers, vk)) {
    isRegistered_ = true;
    currentModifiers_ = modifiers;
    currentVk_ = vk;
    return true;
  }

  return false;
}

void HotkeyManager::UnregisterHotkey() {
  if (isRegistered_) {
    UnregisterHotKey(hwnd_, HOTKEY_ID);
    isRegistered_ = false;
    currentModifiers_ = 0;
    currentVk_ = 0;
  }
}

void HotkeyManager::HandleHotkeyMessage() {
  if (hotkeyCallback_) {
    hotkeyCallback_();
  }
}

void HotkeyManager::SetHotkeyCallback(std::function<void()> callback) {
  hotkeyCallback_ = callback;
}
