#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

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

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);

  // Arabic window/taskbar title: "مرجعي" (MARJIY). Written here as raw UTF-8
  // bytes so the source stays pure ASCII and builds correctly no matter how the
  // file is encoded (the Flutter Windows runner does not force the MSVC /utf-8
  // option). The bytes are converted to UTF-16 at runtime for the Win32 title.
  const char* title_utf8 = "\xD9\x85\xD8\xB1\xD8\xAC\xD8\xB9\xD9\x8A";
  // MultiByteToWideChar returns the required length *including* the null
  // terminator. Allocate a buffer of exactly that size, then trim the trailing
  // null from the string's logical length. Fall back to an ASCII title if the
  // conversion fails.
  std::wstring window_title = L"MARJIY";
  int wide_len =
      ::MultiByteToWideChar(CP_UTF8, 0, title_utf8, -1, nullptr, 0);
  if (wide_len > 0) {
    std::wstring converted(static_cast<size_t>(wide_len), L'\0');
    int written = ::MultiByteToWideChar(CP_UTF8, 0, title_utf8, -1,
                                        &converted[0], wide_len);
    if (written > 0) {
      converted.resize(static_cast<size_t>(written) - 1);
      window_title = std::move(converted);
    }
  }

  if (!window.Create(window_title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
