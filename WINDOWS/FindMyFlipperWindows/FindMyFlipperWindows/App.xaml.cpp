#include "pch.h"
#include "App.xaml.h"
#include "MainWindow.xaml.h"

using namespace winrt;
using namespace Microsoft::UI::Xaml;

namespace {
void StartupTrace(std::wstring const &message) noexcept {
  try {
    wchar_t *localAppData{};
    size_t ignored{};
    _wdupenv_s(&localAppData, &ignored, L"LOCALAPPDATA");
    auto root = localAppData ? std::filesystem::path(localAppData)
                             : std::filesystem::temp_directory_path();
    free(localAppData);
    root /= L"FindMyFlipper";
    std::filesystem::create_directories(root);
    std::wofstream stream(root / L"app.log", std::ios::app);
    stream << message << L'\n';
    OutputDebugStringW((L"[FindMyFlipper] " + message + L"\n").c_str());
  } catch (...) {
  }
}
} // namespace

namespace winrt::FindMyFlipperWindows::implementation {
App::App() {
  StartupTrace(L"App: InitializeComponent starting");
  InitializeComponent();
  StartupTrace(L"App: InitializeComponent complete");
  UnhandledException([](IInspectable const &,
                        UnhandledExceptionEventArgs const &args) {
    StartupTrace(L"Unhandled WinUI exception: " +
                 std::wstring(args.Message()));
    // WinUI otherwise terminates the entire process for recoverable routed
    // event/rendering exceptions. Individual feature handlers surface their
    // own error state, so keep the window alive and preserve diagnostics.
    args.Handled(true);
  });
}

void App::OnLaunched(LaunchActivatedEventArgs const &) {
  StartupTrace(L"App: OnLaunched starting");
  try {
    auto window = make<MainWindow>();
    get_self<MainWindow>(window)->InitializeAfterXaml();
    m_window = window;
    m_window.Activate();
    StartupTrace(L"App: window activated");
  } catch (hresult_error const &error) {
    auto message = L"FindMyFlipper could not start.\n\n" +
                   std::wstring(error.message()) + L"\n\nHRESULT: 0x";
    wchar_t code[16]{};
    swprintf_s(code, L"%08X", static_cast<unsigned>(error.code().value));
    message += code;
    OutputDebugStringW(message.c_str());
    StartupTrace(message);
    MessageBoxW(nullptr, message.c_str(), L"FindMyFlipper startup error",
                MB_OK | MB_ICONERROR);
  } catch (std::exception const &error) {
    auto message = L"FindMyFlipper could not start.\n\n" +
                   std::wstring(winrt::to_hstring(error.what()));
    OutputDebugStringW(message.c_str());
    StartupTrace(message);
    MessageBoxW(nullptr, message.c_str(), L"FindMyFlipper startup error",
                MB_OK | MB_ICONERROR);
  }
}
} // namespace winrt::FindMyFlipperWindows::implementation
