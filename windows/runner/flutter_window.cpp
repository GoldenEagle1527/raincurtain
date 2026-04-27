#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "tray_manager.h"
#include "hotkey_manager.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Initialize tray manager
  auto tray_manager = std::make_unique<TrayManager>(
      GetHandle(), GetModuleHandle(nullptr));
  
  tray_manager->SetShowWindowCallback([this]() {
    this->ShowAndActivate();
  });
  
  tray_manager->SetExitAppCallback([this]() {
    DestroyWindow(GetHandle());
    PostQuitMessage(0);
  });
  
  tray_manager->CreateTrayIcon();
  SetTrayManager(std::move(tray_manager));

  // Initialize hotkey manager
  auto hotkey_manager = std::make_unique<HotkeyManager>(GetHandle());
  
  hotkey_manager->SetHotkeyCallback([this]() {
    this->ShowAndActivate();
  });
  
  SetHotkeyManager(std::move(hotkey_manager));

  // Setup method channel
  SetupMethodChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (GetTrayManager()) {
    GetTrayManager()->RemoveTrayIcon();
  }

  if (GetHotkeyManager()) {
    GetHotkeyManager()->UnregisterHotkey();
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetupMethodChannel() {
  const static std::string channel_name = "raincurtain/window_control";
  
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), channel_name,
      &flutter::StandardMethodCodec::GetInstance());
  
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        this->HandleMethodCall(call, std::move(result));
      });
}

void FlutterWindow::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  
  const std::string& method = method_call.method_name();
  
  if (method == "registerHotkey") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Arguments must be a map");
      return;
    }
    
    auto modifiers_it = arguments->find(flutter::EncodableValue("modifiers"));
    auto keyCode_it = arguments->find(flutter::EncodableValue("keyCode"));
    
    if (modifiers_it == arguments->end() || keyCode_it == arguments->end()) {
      result->Error("INVALID_ARGUMENT", "Missing modifiers or keyCode");
      return;
    }
    
    int modifiers = std::get<int>(modifiers_it->second);
    int keyCode = std::get<int>(keyCode_it->second);
    
    if (GetHotkeyManager()) {
      bool success = GetHotkeyManager()->RegisterHotkey(modifiers, keyCode);
      if (success) {
        result->Success(flutter::EncodableValue(true));
      } else {
        result->Error("REGISTER_FAILED", "Failed to register hotkey");
      }
    } else {
      result->Error("NOT_INITIALIZED", "Hotkey manager not initialized");
    }
  }
  else if (method == "unregisterHotkey") {
    if (GetHotkeyManager()) {
      GetHotkeyManager()->UnregisterHotkey();
      result->Success(flutter::EncodableValue(true));
    } else {
      result->Error("NOT_INITIALIZED", "Hotkey manager not initialized");
    }
  }
  else if (method == "showWindow") {
    ShowAndActivate();
    result->Success(flutter::EncodableValue(true));
  }
  else if (method == "hideWindow") {
    Hide();
    result->Success(flutter::EncodableValue(true));
  }
  else if (method == "exitApp") {
    DestroyWindow(GetHandle());
    PostQuitMessage(0);
    result->Success(flutter::EncodableValue(true));
  }
  else {
    result->NotImplemented();
  }
}
