#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

#include <string>
#include <vector>

#include "brand_config.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t* kSingleInstanceMutexName =
    L"Local\\" BRAND_APP_USER_MODEL_ID L".single_instance";

HWND FindExistingMainWindowWithRetry() {
  for (int attempt = 0; attempt < 20; ++attempt) {
    HWND hwnd = ::FindWindowW(BRAND_WINDOW_CLASS_NAME, nullptr);
    if (hwnd != nullptr) {
      return hwnd;
    }
    ::Sleep(100);
  }
  return nullptr;
}

bool RestoreExistingInstance(const std::string& launch_uri) {
  HWND hwnd = FindExistingMainWindowWithRetry();
  if (hwnd == nullptr) {
    return false;
  }

  ::ShowWindow(hwnd, SW_SHOW);
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  }
  ::SetForegroundWindow(hwnd);

  if (!launch_uri.empty()) {
    COPYDATASTRUCT copy_data = {};
    copy_data.dwData = 1;
    copy_data.cbData = static_cast<DWORD>(launch_uri.size() + 1);
    copy_data.lpData = const_cast<char*>(launch_uri.c_str());
    ::SendMessage(hwnd, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&copy_data));
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Windows taskbar and pinned shortcuts use AppUserModelID for grouping and
  // icon identity. Setting it explicitly prevents shell cache fallbacks from
  // showing a generic placeholder on some upgraded machines.
  const HRESULT app_user_model_result =
      ::SetCurrentProcessExplicitAppUserModelID(BRAND_APP_USER_MODEL_ID);
  (void)app_user_model_result;

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Check if launched via URL scheme (e.g., svid://activate?key=...)
  std::string launch_uri;
  for (const auto& arg : command_line_arguments) {
    if (arg.rfind(BRAND_URL_SCHEME, 0) == 0) {
      launch_uri = arg;
      break;
    }
  }

  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (RestoreExistingInstance(launch_uri)) {
      ::CloseHandle(single_instance_mutex);
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }

    const DWORD wait_result = ::WaitForSingleObject(single_instance_mutex, 1500);
    if (wait_result != WAIT_OBJECT_0 && wait_result != WAIT_ABANDONED) {
      if (RestoreExistingInstance(launch_uri)) {
        ::CloseHandle(single_instance_mutex);
        ::CoUninitialize();
        return EXIT_SUCCESS;
      }
      ::CloseHandle(single_instance_mutex);
      ::CoUninitialize();
      return launch_uri.empty() ? EXIT_SUCCESS : EXIT_FAILURE;
    }
  }

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(BRAND_NAME_WIDE, origin, size)) {
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Queue launch URI for forwarding to Flutter after first frame
  if (!launch_uri.empty()) {
    window.SetLaunchUri(launch_uri);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  // Hard-terminate the process to bypass plugin/WinRT DLL teardown.
  //
  // REPRODUCED (2026-06-02): closing the window crashes on EVERY exit with a
  // fail-fast (0xC0000602) in coremessaging.dll at fault offset 0x72e16 -- the
  // Windows WinRT notification stack tears down a COM/coremessaging object
  // after CoUninitialize during process teardown. This fires regardless of
  // whether a toast was shown. The fix that previously suppressed it
  // (commit 3ba87427) was removed as collateral in the close-to-tray revert
  // (88a42813), re-exposing the crash.
  //
  // This is INDEPENDENT of close behavior: the message loop has already
  // drained here, so the window is closed and Dart-side cleanup
  // (windowManager listener -> saveWindowState -> file flush) has completed.
  // We only change HOW the already-exiting process finalizes. ExitProcess
  // still fires DLL_PROCESS_DETACH (and so still hits the crash);
  // TerminateProcess skips all detach notifications and ends the process at
  // the kernel level with a clean exit code.
  ::TerminateProcess(::GetCurrentProcess(), 0);
  return EXIT_SUCCESS;  // not reached
}
