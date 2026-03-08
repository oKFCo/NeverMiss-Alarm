#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring ReadMachineGuid() {
  HKEY key;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Cryptography", 0,
                    KEY_READ | KEY_WOW64_64KEY, &key) != ERROR_SUCCESS) {
    return L"";
  }

  DWORD type = 0;
  DWORD size = 0;
  const auto query_status =
      RegQueryValueExW(key, L"MachineGuid", nullptr, &type, nullptr, &size);
  if (query_status != ERROR_SUCCESS || type != REG_SZ || size == 0) {
    RegCloseKey(key);
    return L"";
  }

  std::wstring value(size / sizeof(wchar_t), L'\0');
  if (RegQueryValueExW(key, L"MachineGuid", nullptr, nullptr,
                       reinterpret_cast<LPBYTE>(value.data()),
                       &size) != ERROR_SUCCESS) {
    RegCloseKey(key);
    return L"";
  }
  RegCloseKey(key);

  while (!value.empty() && value.back() == L'\0') {
    value.pop_back();
  }
  return value;
}

std::string WideToUtf8(const std::wstring& input) {
  if (input.empty()) {
    return "";
  }
  const int size_needed = WideCharToMultiByte(
      CP_UTF8, 0, input.c_str(), static_cast<int>(input.size()), nullptr, 0,
      nullptr, nullptr);
  if (size_needed <= 0) {
    return "";
  }
  std::string result(size_needed, '\0');
  WideCharToMultiByte(CP_UTF8, 0, input.c_str(),
                      static_cast<int>(input.size()), result.data(),
                      size_needed, nullptr, nullptr);
  return result;
}

}  // namespace

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
  identity_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "verint_alarm/android_alarm",
          &flutter::StandardMethodCodec::GetInstance());
  identity_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "getDeviceIdentifier") {
          result->NotImplemented();
          return;
        }
        const auto machine_guid = ReadMachineGuid();
        if (machine_guid.empty()) {
          result->Error("device_id_unavailable", "MachineGuid unavailable");
          return;
        }
        result->Success(flutter::EncodableValue(
            "windows:" + WideToUtf8(machine_guid)));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  identity_channel_ = nullptr;
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
