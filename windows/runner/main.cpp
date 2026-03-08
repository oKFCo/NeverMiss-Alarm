#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\NeverMissAlarm_SingleInstance";
constexpr wchar_t kFlutterRunnerWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

std::wstring GetProcessImagePath(DWORD process_id) {
  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (!process) {
    return L"";
  }

  std::vector<wchar_t> buffer(MAX_PATH);
  DWORD size = static_cast<DWORD>(buffer.size());
  while (!QueryFullProcessImageNameW(process, 0, buffer.data(), &size)) {
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
      CloseHandle(process);
      return L"";
    }
    buffer.resize(buffer.size() * 2);
    size = static_cast<DWORD>(buffer.size());
  }

  std::wstring path(buffer.data(), size);
  CloseHandle(process);
  return path;
}

struct WindowLookupContext {
  std::wstring current_exe_path;
  DWORD current_pid = 0;
  HWND found = nullptr;
};

BOOL CALLBACK FindExistingWindowCallback(HWND hwnd, LPARAM lparam) {
  auto* context = reinterpret_cast<WindowLookupContext*>(lparam);
  if (!context) {
    return TRUE;
  }

  wchar_t class_name[256];
  if (!GetClassNameW(hwnd, class_name, ARRAYSIZE(class_name))) {
    return TRUE;
  }
  if (wcscmp(class_name, kFlutterRunnerWindowClass) != 0) {
    return TRUE;
  }

  DWORD window_pid = 0;
  GetWindowThreadProcessId(hwnd, &window_pid);
  if (window_pid == 0 || window_pid == context->current_pid) {
    return TRUE;
  }

  const std::wstring window_exe_path = GetProcessImagePath(window_pid);
  if (window_exe_path.empty()) {
    return TRUE;
  }

  if (_wcsicmp(window_exe_path.c_str(), context->current_exe_path.c_str()) ==
      0) {
    context->found = hwnd;
    return FALSE;
  }

  return TRUE;
}

bool ActivateExistingInstanceWindow() {
  WindowLookupContext context;
  context.current_pid = GetCurrentProcessId();
  context.current_exe_path = GetProcessImagePath(context.current_pid);
  if (context.current_exe_path.empty()) {
    return false;
  }

  EnumWindows(FindExistingWindowCallback, reinterpret_cast<LPARAM>(&context));
  if (!context.found) {
    return false;
  }

  if (IsIconic(context.found)) {
    ShowWindow(context.found, SW_RESTORE);
  } else {
    ShowWindow(context.found, SW_SHOW);
  }
  BringWindowToTop(context.found);
  SetForegroundWindow(context.found);
  SetFocus(context.found);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (single_instance_mutex && GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingInstanceWindow();
    CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"NeverMiss Alarm", origin, size)) {
    if (single_instance_mutex) {
      CloseHandle(single_instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (single_instance_mutex) {
    CloseHandle(single_instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
