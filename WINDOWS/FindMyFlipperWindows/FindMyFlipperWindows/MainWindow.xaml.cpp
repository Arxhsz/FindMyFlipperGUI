#include "pch.h"
#include "MainWindow.xaml.h"
#if __has_include("MainWindow.g.cpp")
#include "MainWindow.g.cpp"
#endif
#include "Services/CredentialService.h"

using namespace winrt;
using namespace Microsoft::UI;
using namespace Microsoft::UI::Xaml;
using namespace Microsoft::UI::Xaml::Controls;
using namespace Microsoft::UI::Xaml::Controls::Primitives;
using namespace Microsoft::UI::Xaml::Media;
using namespace Windows::Data::Json;
using namespace Windows::Storage;
using namespace Windows::Storage::Pickers;
using namespace FindMyFlipper::Models;
using FindMyFlipper::Services::CredentialService;

namespace {
struct ResumeOnDispatcher {
  Microsoft::UI::Dispatching::DispatcherQueue queue{nullptr};

  bool await_ready() const noexcept {
    return queue && queue.HasThreadAccess();
  }

  bool await_suspend(std::coroutine_handle<> continuation) const {
    if (!queue)
      throw hresult_error(E_HANDLE, L"The UI dispatcher is unavailable.");
    if (!queue.TryEnqueue([continuation]() noexcept { continuation.resume(); }))
      throw hresult_error(E_ABORT, L"The UI dispatcher is shutting down.");
    return true;
  }

  void await_resume() const noexcept {}
};

winrt::Windows::UI::Color HexColor(std::wstring value) {
  if (!value.empty() && value.front() == L'#')
    value.erase(value.begin());
  auto number = std::stoul(value, nullptr, 16);
  return ColorHelper::FromArgb(255, static_cast<uint8_t>((number >> 16) & 0xff),
                               static_cast<uint8_t>((number >> 8) & 0xff),
                               static_cast<uint8_t>(number & 0xff));
}

void SetBrush(ResourceDictionary const &resources, wchar_t const *key,
              std::wstring const &color) {
  if (auto brush = resources.Lookup(box_value(key)).try_as<SolidColorBrush>())
    brush.Color(HexColor(color));
}

std::wstring Trim(std::wstring value) {
  auto isSpace = [](wchar_t c) { return iswspace(c) != 0; };
  value.erase(value.begin(),
              std::find_if_not(value.begin(), value.end(), isSpace));
  value.erase(std::find_if_not(value.rbegin(), value.rend(), isSpace).base(),
              value.end());
  return value;
}

std::filesystem::path ExecutableDirectory() {
  std::wstring path(32768, L'\0');
  path.resize(GetModuleFileNameW(nullptr, path.data(),
                                 static_cast<DWORD>(path.size())));
  return std::filesystem::path(path).parent_path();
}

void Trace(std::wstring const &message) noexcept {
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
    OutputDebugStringW(L"[FindMyFlipper] Diagnostic logging failed.\n");
  }
}

bool SystemUsesDarkTheme() noexcept {
  DWORD useLight = 1;
  DWORD size = sizeof(useLight);
  auto result = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &useLight, &size);
  return result == ERROR_SUCCESS && useLight == 0;
}

ThemeColors ResolvedColors(ThemeOption theme) {
  if (theme == ThemeOption::System)
    return ColorsFor(SystemUsesDarkTheme() ? ThemeOption::Dark
                                           : ThemeOption::Light);
  return ColorsFor(theme);
}

bool DemoModeEnabled() noexcept {
  wchar_t value[8]{};
  return GetEnvironmentVariableW(L"FINDMYFLIPPER_DEMO", value,
                                 static_cast<DWORD>(std::size(value))) > 0 &&
         value[0] == L'1';
}
} // namespace

namespace winrt::FindMyFlipperWindows::implementation {
MainWindow::MainWindow() {
  m_demoMode = DemoModeEnabled();
}

void MainWindow::InitializeAfterXaml() {
  InitializePolishUI();
  InitializeFlipperDetailsUI();
  if (m_demoMode)
    SeedDemoData();
  auto loadedWeak = get_weak();
  WindowRoot().Loaded([loadedWeak](IInspectable const &, RoutedEventArgs const &) {
    if (auto self = loadedWeak.get()) {
      self->m_windowLoaded = true;
      if (self->AppShell().Visibility() == Visibility::Visible)
        self->InitializeMaps();
    }
  });
  m_dispatcher = this->DispatcherQueue();
  m_servicePollTimer = m_dispatcher.CreateTimer();
  m_servicePollTimer.Interval(std::chrono::seconds(4));
  m_servicePollTimer.IsRepeating(true);
  auto serviceWeak = get_weak();
  m_servicePollTimer.Tick([serviceWeak](auto const &, auto const &) {
    if (auto self = serviceWeak.get())
      self->RefreshServiceStatus();
  });
  m_servicePollTimer.Start();

  Trace(L"MainWindow: configuring native window");
  auto windowNative = this->try_as<::IWindowNative>();
  HWND window{};
  check_hresult(windowNative->get_WindowHandle(&window));
  auto module = GetModuleHandleW(nullptr);
  auto largeIcon = reinterpret_cast<HICON>(LoadImageW(
      module, MAKEINTRESOURCEW(101), IMAGE_ICON, 32, 32, LR_DEFAULTCOLOR));
  auto smallIcon = reinterpret_cast<HICON>(LoadImageW(
      module, MAKEINTRESOURCEW(101), IMAGE_ICON, 16, 16, LR_DEFAULTCOLOR));
  if (largeIcon)
    SendMessageW(window, WM_SETICON, ICON_BIG,
                 reinterpret_cast<LPARAM>(largeIcon));
  if (smallIcon)
    SendMessageW(window, WM_SETICON, ICON_SMALL,
                 reinterpret_cast<LPARAM>(smallIcon));
  RECT rect{};
  GetWindowRect(window, &rect);
  SetWindowPos(window, nullptr, rect.left, rect.top, 1280, 820,
               SWP_NOZORDER | SWP_NOACTIVATE);

  Trace(L"MainWindow: configuring Bluetooth callbacks");
  auto weak = get_weak();
  m_bluetooth.SetDevicesChanged(
      [weak](auto const &devices) {
        if (auto self = weak.get())
          self->OnBluetoothDevices(devices);
      });
  m_bluetooth.SetStatusChanged(
      [weak](auto const &message, bool connected, int battery) {
        if (auto self = weak.get())
          self->OnBluetoothStatus(message, connected, battery);
      });
  Trace(L"MainWindow: initializing tray icon");
  m_tray.Initialize(
      AssetPath(L"Assets\\FindMyFlipper.ico"), [this](unsigned command) {
        m_dispatcher.TryEnqueue([this, command] {
          switch (command) {
          case FindMyFlipper::Services::TrayIconService::OpenDashboard:
            OpenShell(L"dashboard");
            Activate();
            break;
          case FindMyFlipper::Services::TrayIconService::PlayAlert:
            m_bluetooth.PlayAlert();
            break;
          case FindMyFlipper::Services::TrayIconService::RefreshReports:
            RefreshReports();
            break;
          case FindMyFlipper::Services::TrayIconService::OpenSettings:
            OpenShell(L"settings");
            Activate();
            break;
          case FindMyFlipper::Services::TrayIconService::Quit:
            Close();
            break;
          }
        });
      });

  Trace(L"MainWindow: initializing view state");
  ThemePicker().SelectedIndex(0);
  ReportFilter().SelectedIndex(1);
  UpdateProfileUI();
  if (m_store.OnboardingComplete())
    OpenShell();
  else
    ShowOnboardingStep(1);
  Trace(L"MainWindow: starting services");
  InitializeServices();
  Trace(L"MainWindow: post-XAML initialization complete");
}

void MainWindow::SeedDemoData() {
  FlipperProfile profile;
  profile.id = L"demo-flipper";
  profile.displayName = L"Demo Flipper";
  profile.keyIdentityId = L"demo-identity";
  profile.generatedFindMyMac = L"7a4f2c91be10";
  profile.bluetoothDeviceId = L"Demo Bluetooth LE device";
  profile.bluetoothName = L"Demo Flipper";
  profile.bluetoothMac = L"80:E1:26:12:34:56";
  profile.firmwareVersion = L"1.1.2 (demo)";
  profile.batteryLevel = 82;
  profile.rssi = -48;
  profile.connected = true;
  profile.autoReconnect = false;
  m_store.UpdateProfile(profile);

  KeyIdentity key;
  key.id = L"demo-identity";
  key.sourceFileName = L"demo.keys";
  key.generatedFindMyMac = profile.generatedFindMyMac;
  m_store.UpdateKey(key);
  m_store.SetOnboardingComplete(true);

  auto now = static_cast<int64_t>(std::time(nullptr));
  constexpr double lat = 37.33490;
  constexpr double lon = -122.00900;
  for (int i = 0; i < 18; ++i) {
    LocationReport report;
    report.id = L"demo-report-" + std::to_wstring(i + 1);
    report.timestamp = now - i * 37 * 60;
    report.latitude = lat + std::sin(i * 0.7) * 0.0045;
    report.longitude = lon + std::cos(i * 0.7) * 0.0055;
    report.confidence = 12 + (i % 5) * 7;
    m_reports.push_back(report);
  }
}

void MainWindow::InitializeFlipperDetailsUI() {
  auto content = FlipperPage().Content().as<StackPanel>();
  auto header = content.Children().GetAt(0).as<Grid>()
                    .Children().GetAt(1).as<StackPanel>();
  m_bluetoothMacValue = TextBlock();
  m_bluetoothMacValue.Text(L"Bluetooth MAC: Not selected");
  m_bluetoothMacValue.FontFamily(
      Microsoft::UI::Xaml::Media::FontFamily(L"Consolas"));
  header.Children().InsertAt(3, m_bluetoothMacValue);
  Border card;
  card.Style(Application::Current()
                 .Resources()
                 .Lookup(box_value(L"CardStyle"))
                 .as<Style>());
  StackPanel details;
  details.Spacing(10);
  TextBlock heading;
  heading.Text(L"Device and Key Status");
  heading.FontSize(19);
  m_firmwareValue = TextBlock();
  m_firmwareValue.Text(L"Firmware: Not exposed over Bluetooth");
  m_alertSupportValue = TextBlock();
  m_alertSupportValue.Text(
      L"Alert support: Connect over Bluetooth to check");
  m_flipperUsbDetail = TextBlock();
  m_flipperUsbDetail.Text(
      L"microSD: Connect by USB and close qFlipper, then refresh.");
  m_flipperUsbDetail.TextWrapping(TextWrapping::Wrap);
  m_activeKeyMatch = TextBlock();
  m_activeKeyMatch.Text(L"Active identity: Not verified");
  m_activeKeyMatch.TextWrapping(TextWrapping::Wrap);
  m_refreshFlipperButton = Button();
  m_refreshFlipperButton.Content(
      box_value(L"Refresh Firmware and microSD Keys"));
  m_refreshFlipperButton.HorizontalAlignment(HorizontalAlignment::Left);
  m_refreshFlipperButton.Style(Application::Current()
                                   .Resources()
                                   .Lookup(box_value(L"CriticalButtonStyle"))
                                   .as<Style>());
  auto weak = get_weak();
  m_refreshFlipperButton.Click(
      [weak](IInspectable const &, RoutedEventArgs const &) {
        if (auto self = weak.get())
          self->ConfirmRefreshFlipperDetails();
      });
  details.Children().Append(heading);
  details.Children().Append(m_firmwareValue);
  details.Children().Append(m_alertSupportValue);
  details.Children().Append(m_flipperUsbDetail);
  details.Children().Append(m_activeKeyMatch);
  details.Children().Append(m_refreshFlipperButton);
  card.Child(details);
  content.Children().InsertAt(2, card);
}

void MainWindow::InitializePolishUI() {
  auto importContent = ImportStep().Children().GetAt(0).as<StackPanel>();
  auto keyActions = importContent.Children().GetAt(4).as<StackPanel>();
  m_importFlipperKeysButton = Button();
  m_importFlipperKeysButton.Content(box_value(L"Import from USB Flipper"));
  auto weak = get_weak();
  m_importFlipperKeysButton.Click([weak](auto const &, auto const &) {
    if (auto self = weak.get())
      self->ImportKeysFromFlipper();
  });
  keyActions.Children().InsertAt(1, m_importFlipperKeysButton);

  m_mapActionsButton = Button();
  m_mapActionsButton.Content(box_value(L"\x2026"));
  m_mapActionsButton.Width(44);
  m_mapActionsButton.Height(42);
  m_mapActionsButton.FontSize(20);
  m_mapActionsButton.Foreground(Application::Current().Resources()
                                    .Lookup(box_value(L"PrimaryTextBrush"))
                                    .as<Brush>());
  m_mapActionsButton.Background(Application::Current().Resources()
                                    .Lookup(box_value(L"SurfaceBrush"))
                                    .as<Brush>());
  m_mapActionsButton.BorderBrush(Application::Current().Resources()
                                   .Lookup(box_value(L"CardBorderBrush"))
                                   .as<Brush>());
  m_mapActionsButton.BorderThickness(ThicknessHelper::FromUniformLength(1));
  m_mapActionsButton.CornerRadius(CornerRadiusHelper::FromUniformRadius(12));
  Automation::AutomationProperties::SetName(m_mapActionsButton,
                                             L"More map actions");
  m_mapActionsButton.Click([weak](IInspectable const &sender, RoutedEventArgs const &args) {
    if (auto self = weak.get())
      self->MapActions_Click(sender, args);
  });
  MapTopBar().Children().Append(m_mapActionsButton);

  // Recreate the Flipper action row in native code. WinUI's generated XBF
  // event table could route the first inline XAML button to the adjacent scan
  // handler after the dynamic details card was inserted, which sent Play Alert
  // back to onboarding. Native handlers give each stable visual its own action.
  auto flipperContent = FlipperPage().Content().as<StackPanel>();
  auto flipperActionCard = flipperContent.Children().GetAt(2).as<Border>();
  auto flipperActionGrid = flipperActionCard.Child().as<Grid>();
  flipperActionGrid.Children().Clear();
  auto makeActionContent = [](wchar_t const *glyph, wchar_t const *label) {
    StackPanel content;
    content.Orientation(Orientation::Horizontal);
    content.Spacing(9);
    FontIcon icon;
    icon.Glyph(glyph);
    TextBlock text;
    text.Text(label);
    content.Children().Append(icon);
    content.Children().Append(text);
    return content;
  };
  Button flipperAlert;
  flipperAlert.Content(makeActionContent(L"\xE7ED", L"Play Alert"));
  flipperAlert.Style(Application::Current().Resources()
                         .Lookup(box_value(L"PrimaryButtonStyle"))
                         .as<Style>());
  flipperAlert.HorizontalAlignment(HorizontalAlignment::Stretch);
  flipperAlert.Click([weak](auto const &, auto const &) {
    if (auto self = weak.get()) {
      if (self->m_store.OnboardingComplete()) {
        self->OnboardingRoot().Visibility(Visibility::Collapsed);
        self->AppShell().Visibility(Visibility::Visible);
        self->ShowPage(self->m_currentPage);
      }
      self->m_bluetooth.PlayAlert();
      if (self->m_mapReady)
        self->MapWebView().ExecuteScriptAsync(L"pulseMarker()");
    }
  });
  Button flipperScan;
  flipperScan.Content(makeActionContent(L"\xE950", L"Scan Again"));
  flipperScan.HorizontalAlignment(HorizontalAlignment::Stretch);
  Grid::SetColumn(flipperScan, 1);
  flipperScan.Click([weak](auto const &, auto const &) {
    if (auto self = weak.get())
      self->ShowOnboardingStep(4);
  });
  Button flipperDisconnect;
  flipperDisconnect.Content(makeActionContent(L"\xE711", L"Disconnect"));
  flipperDisconnect.HorizontalAlignment(HorizontalAlignment::Stretch);
  Grid::SetColumn(flipperDisconnect, 2);
  flipperDisconnect.Click([weak](auto const &, auto const &) {
    if (auto self = weak.get())
      self->m_bluetooth.Disconnect();
  });
  flipperActionGrid.Children().Append(flipperAlert);
  flipperActionGrid.Children().Append(flipperScan);
  flipperActionGrid.Children().Append(flipperDisconnect);

  auto settingsContent = SettingsPage().Content().as<StackPanel>();
  auto appearance = settingsContent.Children().GetAt(4).as<Border>()
                        .Child().as<StackPanel>();
  Border divider;
  divider.Height(1);
  divider.Background(Application::Current().Resources()
                         .Lookup(box_value(L"CardBorderBrush"))
                         .as<Brush>());
  Grid markerRow;
  TextBlock label;
  label.Text(L"Flipper marker");
  label.VerticalAlignment(VerticalAlignment::Center);
  m_markerPicker = ComboBox();
  m_markerPicker.HorizontalAlignment(HorizontalAlignment::Right);
  m_markerPicker.MinWidth(170);
  for (auto const *name : {L"Flipper Zero", L"Black", L"Transparent"}) {
    ComboBoxItem item;
    item.Content(box_value(name));
    m_markerPicker.Items().Append(item);
  }
  m_markerPicker.SelectionChanged(
      [weak](IInspectable const &sender, SelectionChangedEventArgs const &args) {
        if (auto self = weak.get())
          self->MarkerPicker_SelectionChanged(sender, args);
      });
  markerRow.Children().Append(label);
  markerRow.Children().Append(m_markerPicker);
  appearance.Children().Append(divider);
  appearance.Children().Append(markerRow);
}

MainWindow::~MainWindow() {
  m_closing = true;
  if (m_servicePollTimer)
    m_servicePollTimer.Stop();
  m_bluetooth.StopScan();
  m_bluetooth.SetDevicesChanged({});
  m_bluetooth.SetStatusChanged({});
}

fire_and_forget MainWindow::InitializeServices() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  if (m_demoMode) {
    m_backendReady = true;
    m_anisetteReady = true;
    m_appleConnected = true;
    AppleInfo().Message(L"Demo mode uses local sample data only.");
    AppleInfo().Severity(InfoBarSeverity::Informational);
    NoReportsBackendStatus().Text(L"Local backend   Demo mode");
    SettingsBackendStatus().Text(L"Local backend: Demo mode");
    SettingsAppleStatus().Text(L"Find My reports: Demo data");
    UpdateProfileUI();
    co_return;
  }
  try {
    co_await resume_background();
    auto health = m_backend.EnsureServices();
    std::wstring authStatus;
    if (health.backendReady) {
      try {
        authStatus = m_backend.Post(L"/auth/status", L"{}");
      } catch (std::exception const &error) {
        Trace(L"Apple status request failed: " +
              std::wstring(winrt::to_hstring(error.what())));
      } catch (hresult_error const &error) {
        Trace(L"Apple status request failed: " +
              std::wstring(error.message()));
      }
    }
    co_await uiThread;
    if (m_closing)
      co_return;
    m_backendReady = health.backendReady;
    m_anisetteReady = health.anisetteReady;
    AppleInfo().Message(health.message);
    AppleInfo().Severity(health.backendReady ? InfoBarSeverity::Informational
                                             : InfoBarSeverity::Error);
    NoReportsBackendStatus().Text(health.backendReady
                                      ? L"Local backend   Running"
                                      : L"Local backend   Offline");
    SettingsBackendStatus().Text(health.backendReady ? L"Local backend: Running"
                                                     : L"Local backend: Offline");
    if (health.backendReady && !authStatus.empty()) {
      try {
        auto status = JsonObject::Parse(authStatus);
        m_appleConnected = status.GetNamedBoolean(L"connected", false);
        SettingsAppleStatus().Text(m_appleConnected
                                       ? L"Find My reports: Connected"
                                       : L"Find My reports: Sign-in required");
        if (!m_appleConnected && m_store.OnboardingComplete()) {
          GlobalWarning().Message(L"Apple access expired or is missing. Sign in "
                                  L"again to refresh Find My reports.");
          GlobalWarning().IsOpen(true);
        } else if (m_appleConnected && m_store.OnboardingComplete() &&
                   !m_store.Key().id.empty()) {
          RefreshReports();
        }
      } catch (winrt::hresult_error const &error) {
        SettingsAppleStatus().Text(L"Find My reports: " +
                                   std::wstring(error.message()));
      }
    }
    auto profile = m_store.Profile();
    if (profile.autoReconnect && !profile.bluetoothDeviceId.empty())
      m_bluetooth.Reconnect(profile.bluetoothDeviceId);
  } catch (hresult_error const &error) {
    auto message = std::wstring(error.message());
    Trace(L"Service initialization WinRT failure: " + message);
    auto weak = lifetime->get_weak();
    m_dispatcher.TryEnqueue([weak, message] {
      if (auto self = weak.get(); self && !self->m_closing) {
        self->m_backendReady = false;
        self->AppleInfo().Severity(InfoBarSeverity::Error);
        self->AppleInfo().Message(L"Local services could not start: " + message);
      }
    });
  } catch (std::exception const &error) {
    Trace(L"Service initialization C++ failure: " +
          std::wstring(winrt::to_hstring(error.what())));
    auto weak = lifetime->get_weak();
    m_dispatcher.TryEnqueue([weak] {
      if (auto self = weak.get(); self && !self->m_closing) {
        self->m_backendReady = false;
        self->AppleInfo().Severity(InfoBarSeverity::Error);
        self->AppleInfo().Message(L"Local services could not start.");
      }
    });
  } catch (...) {
    Trace(L"Service initialization unknown failure.");
    auto weak = lifetime->get_weak();
    m_dispatcher.TryEnqueue([weak] {
      if (auto self = weak.get(); self && !self->m_closing) {
        self->m_backendReady = false;
        self->AppleInfo().Severity(InfoBarSeverity::Error);
        self->AppleInfo().Message(L"Local services could not start.");
      }
    });
  }
}

void MainWindow::ShowOnboardingStep(int step) {
  m_step = std::clamp(step, 1, 5);
  if (m_step != 4)
    m_bluetooth.StopScan();
  OnboardingRoot().Visibility(Visibility::Visible);
  AppShell().Visibility(Visibility::Collapsed);
  WelcomeStep().Visibility(m_step == 1 ? Visibility::Visible
                                       : Visibility::Collapsed);
  ImportStep().Visibility(m_step == 2 ? Visibility::Visible
                                      : Visibility::Collapsed);
  AppleStep().Visibility(m_step == 3 ? Visibility::Visible
                                     : Visibility::Collapsed);
  BluetoothStep().Visibility(m_step == 4 ? Visibility::Visible
                                         : Visibility::Collapsed);
  TestStep().Visibility(m_step == 5 ? Visibility::Visible
                                    : Visibility::Collapsed);
  StepLabel().Text(L"Step " + std::to_wstring(m_step) + L" of 5");
  BackButton().Visibility(m_step > 1 ? Visibility::Visible
                                     : Visibility::Collapsed);
  ContinueButton().Content(
      box_value(hstring(m_step == 5 ? L"Finish Setup" : L"Continue")));
  ContinueButton().IsEnabled(
      m_step == 1 || (m_step == 2 && m_keysValid) ||
      (m_step == 3 && m_appleConnected) ||
      (m_step == 4 && !m_store.Profile().bluetoothDeviceId.empty()) ||
      m_step == 5);
  if (m_step == 4) {
    BluetoothScanButton().Content(
        box_value(m_scanStarted ? L"Scan Again" : L"Start Bluetooth Scan"));
    if (!m_scanStarted)
      BluetoothStatus().Text(
          L"Ready. Start a scan after opening FindMyFlipper on the device.");
  }
  if (m_step == 5)
    RunDiagnostics();
}

void MainWindow::Continue_Click(IInspectable const &, RoutedEventArgs const &) {
  if (m_step == 5) {
    m_store.SetOnboardingComplete(true);
    OpenShell();
    return;
  }
  ShowOnboardingStep(m_step + 1);
}

void MainWindow::Back_Click(IInspectable const &, RoutedEventArgs const &) {
  ShowOnboardingStep(m_step - 1);
}
void MainWindow::ChooseKeys_Click(IInspectable const &,
                                  RoutedEventArgs const &) {
  ImportKeys();
}

void MainWindow::ImportFlipperKeys_Click(IInspectable const &,
                                         RoutedEventArgs const &) {
  ImportKeysFromFlipper();
}

fire_and_forget MainWindow::ImportKeysFromFlipper() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  m_importFlipperKeysButton.IsEnabled(false);
  KeysInfo().Severity(InfoBarSeverity::Informational);
  KeysInfo().Message(L"Reading .keys from /ext/apps_data/findmy over USB...");
  KeysInfo().IsOpen(true);
  std::wstring response;
  try {
    co_await resume_background();
    auto filesResponse = JsonObject::Parse(
        m_backend.Get(L"/desktop/flipper/keys"));
    if (!filesResponse.GetNamedBoolean(L"ok", false))
      throw std::runtime_error(winrt::to_string(
          filesResponse.GetNamedString(L"error", L"USB read failed.")));
    auto files = filesResponse.GetNamedArray(L"files", JsonArray{});
    if (files.Size() == 0)
      throw std::runtime_error(
          "No .keys files were found in /ext/apps_data/findmy.");
    auto filename = files.GetStringAt(0);
    response = m_backend.Post(
        L"/desktop/flipper/keys/import",
        L"{\"filename\":\"" + JsonEscape(filename.c_str()) + L"\"}");
  } catch (std::exception const &error) {
    response = L"{\"ok\":false,\"error\":\"" +
               winrt::to_hstring(error.what()) + L"\"}";
  } catch (hresult_error const &error) {
    response = L"{\"ok\":false,\"error\":\"" + error.message() + L"\"}";
  }
  co_await uiThread;
  if (m_closing)
    co_return;
  m_importFlipperKeysButton.IsEnabled(true);
  try {
    auto result = JsonObject::Parse(response);
    if (!result.GetNamedBoolean(L"ok", false)) {
      KeysInfo().Severity(InfoBarSeverity::Error);
      KeysInfo().Message(result.GetNamedString(
          L"error", L"The Flipper .keys file could not be imported."));
      KeysInfo().IsOpen(true);
      co_return;
    }
    std::wstring error;
    if (!StoreKeyContent(result.GetNamedString(L"raw_content", L"").c_str(),
                         result.GetNamedString(L"filename", L"flipper.keys").c_str(),
                         error)) {
      KeysInfo().Severity(InfoBarSeverity::Error);
      KeysInfo().Message(error);
      KeysInfo().IsOpen(true);
    }
  } catch (...) {
    KeysInfo().Severity(InfoBarSeverity::Error);
    KeysInfo().Message(L"The USB import service returned invalid data.");
    KeysInfo().IsOpen(true);
  }
}

fire_and_forget MainWindow::ImportKeys() {
  FileOpenPicker picker;
  picker.FileTypeFilter().Append(L".keys");
  HWND window{};
  check_hresult(this->try_as<::IWindowNative>()->get_WindowHandle(&window));
  auto initialize = picker.as<::IInitializeWithWindow>();
  check_hresult(initialize->Initialize(window));
  auto file = co_await picker.PickSingleFileAsync();
  if (!file)
    co_return;
  auto raw = co_await FileIO::ReadTextAsync(file);
  std::wstring error;
  if (!StoreKeyContent(raw.c_str(), file.Name().c_str(), error)) {
    KeysInfo().Severity(InfoBarSeverity::Error);
    KeysInfo().Message(error);
    KeysInfo().IsOpen(true);
  }
}

bool MainWindow::StoreKeyContent(std::wstring const &raw,
                                 std::wstring const &filename,
                                 std::wstring &error) {
  auto privateKey =
      ParseKeyField(raw, {L"Private key", L"Private key (Base64)"});
  auto hashedKey = ParseKeyField(
      raw, {L"Hashed adv key", L"Hashed adv key (Base64)"});
  auto mac = ParseKeyField(raw, {L"MAC", L"Generated Find My MAC"});
  auto payload = ParseKeyField(raw, {L"Payload"});
  if (privateKey.empty() || hashedKey.empty() || mac.empty() ||
      payload.empty()) {
    m_keysValid = false;
    ContinueButton().IsEnabled(false);
    error = L"This .keys identity is missing Private key, Hashed adv key, "
            L"MAC, or Payload.";
    return false;
  }

  auto oldKeyId = m_store.Key().id;
  auto keyId = NewId();
  try {
    CredentialService::SavePrivateKey(keyId, privateKey);
    KeyIdentity key{keyId, filename, hashedKey, mac, payload,
                    CredentialService::TargetFor(keyId)};
    m_store.UpdateKey(key);
    auto profile = m_store.Profile();
    if (profile.id.empty())
      profile.id = NewId();
    profile.keyIdentityId = keyId;
    profile.generatedFindMyMac = mac;
    m_store.UpdateProfile(profile);
    if (!oldKeyId.empty() && oldKeyId != keyId)
      CredentialService::DeletePrivateKey(oldKeyId);
  } catch (std::exception const &exception) {
    CredentialService::DeletePrivateKey(keyId);
    error = L"Windows could not protect this private key: " +
            winrt::to_hstring(exception.what());
    return false;
  }

  m_keyRawContent = raw;
  m_keysValid = true;
  ImportedFileLabel().Text(filename);
  SaveKeysButton().Visibility(Visibility::Visible);
  CopyKeysButton().IsEnabled(true);
  KeysInfo().Severity(InfoBarSeverity::Success);
  KeysInfo().Message(L"Identity ready. The private key is protected by "
                     L"Windows Credential Manager, not profile JSON.");
  KeysInfo().IsOpen(true);
  ContinueButton().IsEnabled(true);
  UpdateProfileUI();
  return true;
}

void MainWindow::GenerateKeys_Click(IInspectable const &,
                                    RoutedEventArgs const &) {
  GenerateKeys();
}

fire_and_forget MainWindow::GenerateKeys() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  GenerateKeysButton().IsEnabled(false);
  KeysInfo().Severity(InfoBarSeverity::Informational);
  KeysInfo().Message(L"Generating a new Find My identity locally...");
  KeysInfo().IsOpen(true);
  co_await resume_background();
  std::wstring response;
  try {
    auto health = m_backend.EnsureServices();
    if (!health.backendReady)
      throw std::runtime_error(winrt::to_string(health.message));
    response = m_backend.Post(L"/keys/generate", L"{}");
  } catch (std::exception const &exception) {
    response = L"{\"ok\":false,\"error\":\"" +
               winrt::to_hstring(exception.what()) + L"\"}";
  }
  co_await uiThread;
  GenerateKeysButton().IsEnabled(true);
  try {
    auto result = JsonObject::Parse(response);
    if (!result.GetNamedBoolean(L"ok", false)) {
      KeysInfo().Severity(InfoBarSeverity::Error);
      KeysInfo().Message(
          result.GetNamedString(L"error", L"Key generation failed."));
      co_return;
    }
    std::wstring error;
    StoreKeyContent(result.GetNamedString(L"raw_content", L"").c_str(),
                    L"findmyflipper-generated.keys", error);
    if (!error.empty()) {
      KeysInfo().Severity(InfoBarSeverity::Error);
      KeysInfo().Message(error);
    }
  } catch (winrt::hresult_error const &exception) {
    KeysInfo().Severity(InfoBarSeverity::Error);
    KeysInfo().Message(L"The key service returned invalid data: " +
                       std::wstring(exception.message()));
  }
}

void MainWindow::SaveKeys_Click(IInspectable const &, RoutedEventArgs const &) {
  SaveKeys();
}

fire_and_forget MainWindow::SaveKeys() {
  if (m_keyRawContent.empty())
    co_return;
  FileSavePicker picker;
  picker.SuggestedFileName(L"findmyflipper-generated");
  picker.FileTypeChoices().Insert(L"FindMyFlipper keys", single_threaded_vector<hstring>({L".keys"}));
  HWND window{};
  check_hresult(this->try_as<::IWindowNative>()->get_WindowHandle(&window));
  check_hresult(picker.as<::IInitializeWithWindow>()->Initialize(window));
  auto file = co_await picker.PickSaveFileAsync();
  if (!file)
    co_return;
  co_await FileIO::WriteTextAsync(file, m_keyRawContent);
  KeysInfo().Severity(InfoBarSeverity::Success);
  KeysInfo().Message(L"A portable .keys copy was saved. Keep it private.");
}

void MainWindow::PrepareFlipper_Click(IInspectable const &,
                                      RoutedEventArgs const &) {
  PrepareFlipper();
}

fire_and_forget MainWindow::PrepareFlipper() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  PrepareFlipperButton().IsEnabled(false);
  FlipperUsbStatus().Text(L"Checking for a USB-connected Flipper...");
  co_await resume_background();
  std::wstring response;
  try {
    response = m_backend.Get(L"/desktop/flipper/status");
  } catch (std::exception const &exception) {
    response = L"{\"ok\":false,\"error\":\"" +
               winrt::to_hstring(exception.what()) + L"\"}";
  }
  co_await uiThread;
  PrepareFlipperButton().IsEnabled(true);
  try {
    auto result = JsonObject::Parse(response);
    auto connected = result.GetNamedBoolean(L"connected", false);
    CopyKeysButton().IsEnabled(connected && !m_keyRawContent.empty());
    std::wstring message =
        connected ? std::wstring(L"Flipper found on ") +
                        std::wstring(result.GetNamedString(L"port", L"USB")) +
                        L". Ready to copy."
                  : std::wstring(result.GetNamedString(
                        L"error", L"No Flipper USB serial connection found. "
                                  L"Connect a data cable and close qFlipper."));
    FlipperUsbStatus().Text(message);
  } catch (winrt::hresult_error const &exception) {
    FlipperUsbStatus().Text(L"USB check failed: " +
                            std::wstring(exception.message()));
  }
}

void MainWindow::CopyKeysToFlipper_Click(IInspectable const &,
                                         RoutedEventArgs const &) {
  CopyKeysToFlipper();
}

fire_and_forget MainWindow::CopyKeysToFlipper() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  if (m_keyRawContent.empty()) {
    auto const key = m_store.Key();
    auto privateKey = CredentialService::LoadPrivateKey(key.id);
    if (!privateKey || key.hashedAdvertisementKey.empty() ||
        key.generatedFindMyMac.empty() || key.payload.empty()) {
      m_flipperUsbDetail.Text(
          L"The active identity is incomplete. Import or generate keys first.");
      co_return;
    }
    m_keyRawContent = L"Private key: " + *privateKey +
                      L"\nHashed adv key: " + key.hashedAdvertisementKey +
                      L"\nMAC: " + key.generatedFindMyMac +
                      L"\nPayload: " + key.payload + L"\n";
  }
  CopyKeysButton().IsEnabled(false);
  FlipperUsbStatus().Text(L"Copying keys to /ext/apps_data/findmy...");
  JsonObject request;
  request.SetNamedValue(L"raw_content",
                        JsonValue::CreateStringValue(m_keyRawContent));
  request.SetNamedValue(L"filename", JsonValue::CreateStringValue(
                                          m_store.Key().sourceFileName));
  auto body = std::wstring(request.Stringify());
  co_await resume_background();
  std::wstring response;
  try {
    response = m_backend.Post(L"/desktop/flipper/keys/write", body);
  } catch (std::exception const &exception) {
    response = L"{\"ok\":false,\"error\":\"" +
               winrt::to_hstring(exception.what()) + L"\"}";
  }
  co_await uiThread;
  CopyKeysButton().IsEnabled(true);
  try {
    auto result = JsonObject::Parse(response);
    auto ok = result.GetNamedBoolean(L"ok", false);
    auto message = ok
                       ? L"Keys copied to " + std::wstring(result.GetNamedString(
                                                   L"destination", L"the Flipper SD card"))
                       : std::wstring(result.GetNamedString(
                             L"error", L"The Flipper rejected the keys copy."));
    FlipperUsbStatus().Text(message);
    m_flipperUsbDetail.Text(message);
    if (ok)
      RefreshFlipperDetails();
  } catch (winrt::hresult_error const &exception) {
    FlipperUsbStatus().Text(L"Copy failed: " +
                            std::wstring(exception.message()));
  }
}

fire_and_forget MainWindow::ConfirmRefreshFlipperDetails() {
  ContentDialog dialog;
  dialog.XamlRoot(Content().as<FrameworkElement>().XamlRoot());
  dialog.Title(box_value(L"Refresh firmware and microSD key status?"));
  dialog.Content(box_value(
      L"The app will open the Flipper USB serial connection and read firmware "
      L"information plus .keys filenames from /ext/apps_data/findmy. It will "
      L"not replace or delete any keys."));
  dialog.PrimaryButtonText(L"Refresh now");
  dialog.CloseButtonText(L"Cancel");
  dialog.DefaultButton(ContentDialogButton::Close);
  if (co_await dialog.ShowAsync() == ContentDialogResult::Primary)
    RefreshFlipperDetails();
}

fire_and_forget MainWindow::RefreshFlipperDetails() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  m_refreshFlipperButton.IsEnabled(false);
  m_flipperUsbDetail.Text(
      L"Reading /ext/apps_data/findmy through the Flipper serial CLI...");
  JsonObject request;
  request.SetNamedValue(
      L"hashed_adv_key_base64",
      JsonValue::CreateStringValue(m_store.Key().hashedAdvertisementKey));
  auto body = std::wstring(request.Stringify());
  co_await resume_background();
  std::wstring response;
  try {
    response = m_backend.Post(L"/desktop/flipper/keys/verify", body);
  } catch (std::exception const &exception) {
    auto message = std::wstring(winrt::to_hstring(exception.what()));
    response = L"{\"ok\":false,\"error\":\"" +
               JsonEscape(message) + L"\"}";
  }
  co_await uiThread;
  m_refreshFlipperButton.IsEnabled(true);
  try {
    auto result = JsonObject::Parse(response);
    if (!result.GetNamedBoolean(L"ok", false)) {
      m_flipperUsbDetail.Text(result.GetNamedString(
          L"error", L"No Flipper USB serial connection was found."));
      m_activeKeyMatch.Text(
          L"Connect the Flipper by USB and close qFlipper before refreshing.");
      co_return;
    }
    auto files = result.GetNamedArray(L"files", JsonArray{});
    std::wstring matching;
    auto matchingValue = result.GetNamedValue(L"matching_filename", nullptr);
    if (matchingValue && matchingValue.ValueType() == JsonValueType::String)
      matching = matchingValue.GetString();
    m_flipperUsbDetail.Text(
        files.Size() == 0
            ? L"No .keys files were found on the connected Flipper."
            : std::to_wstring(files.Size()) +
                  L" .keys file(s) found on the connected Flipper.");
    if (!matching.empty()) {
      m_activeKeyMatch.Text(L"Active identity verified as " + matching +
                            L" on the Flipper microSD card.");
    } else {
      m_activeKeyMatch.Text(
          L"The active profile identity does not match any .keys file on the Flipper.");
    }
  } catch (hresult_error const &exception) {
    m_flipperUsbDetail.Text(L"Could not read microSD status: " +
                            std::wstring(exception.message()));
  }
}

void MainWindow::ConnectApple_Click(IInspectable const &,
                                    RoutedEventArgs const &) {
  ConnectApple();
}

fire_and_forget MainWindow::ConnectApple() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  ConnectAppleButton().IsEnabled(false);
  AppleProgress().IsActive(true);
  auto username = std::wstring(AppleIdBox().Text());
  auto password = std::wstring(ApplePasswordBox().Password());
  auto code = std::wstring(TwoFactorBox().Text());
  ApplePasswordBox().Password(L"");
  if (code.empty() && (username.empty() || password.empty())) {
    ConnectAppleButton().IsEnabled(true);
    AppleProgress().IsActive(false);
    AppleInfo().Severity(InfoBarSeverity::Error);
    AppleInfo().Message(
        L"Enter your Apple ID and password to connect Apple access.");
    AppleInfo().IsOpen(true);
    co_return;
  }
  std::wstring secondFactor =
      SecondFactorBox().SelectedIndex() == 1 ? L"sms" : L"trusted_device";
  co_await resume_background();
  std::wstring response;
  try {
    if (!m_backend.IsHealthy()) {
      auto health = m_backend.EnsureServices();
      if (!health.backendReady)
        throw std::runtime_error(winrt::to_string(health.message));
    }
    auto anisetteResponse = JsonObject::Parse(
        m_backend.Post(L"/auth/start-anisette",
                       L"{\"install_if_missing\":false}"));
    if (!anisetteResponse.GetNamedBoolean(L"ok", false))
      throw std::runtime_error(winrt::to_string(anisetteResponse.GetNamedString(
          L"error", L"The local anisette service could not be started.")));
    JsonObject request;
    request.SetNamedValue(L"username", JsonValue::CreateStringValue(username));
    request.SetNamedValue(L"password", JsonValue::CreateStringValue(password));
    request.SetNamedValue(L"second_factor",
                          JsonValue::CreateStringValue(secondFactor));
    if (!code.empty())
      request.SetNamedValue(L"code", JsonValue::CreateStringValue(code));
    response = m_backend.Post(L"/auth/connect", request.Stringify().c_str());
  } catch (std::exception const &error) {
    response = L"{\"ok\":false,\"error\":\"" + winrt::to_hstring(error.what()) +
               L"\"}";
  }
  co_await uiThread;
  ConnectAppleButton().IsEnabled(true);
  AppleProgress().IsActive(false);
  try {
    auto result = JsonObject::Parse(response);
    if (result.GetNamedBoolean(L"ok", false)) {
      m_appleConnected = true;
      ApplePasswordBox().Password(L"");
      TwoFactorBox().Text(L"");
      TwoFactorBox().Visibility(Visibility::Collapsed);
      ConnectAppleButton().Content(box_value(L"Connect with Apple"));
      AppleInfo().Severity(InfoBarSeverity::Success);
      AppleInfo().Message(L"Apple access connected.");
      ContinueButton().IsEnabled(true);
      SettingsAppleStatus().Text(L"Find My reports: Connected");
    } else if (result.GetNamedBoolean(L"requires_2fa", false)) {
      TwoFactorBox().Visibility(Visibility::Visible);
      ConnectAppleButton().Content(box_value(L"Verify Code"));
      AppleInfo().Severity(InfoBarSeverity::Warning);
      AppleInfo().Message(L"Apple sent a two-factor code. Enter it above; this "
                          L"sign-in remains open.");
    } else {
      AppleInfo().Severity(InfoBarSeverity::Error);
      AppleInfo().Message(
          result.GetNamedString(L"error", L"Apple sign-in failed."));
    }
  } catch (...) {
    AppleInfo().Severity(InfoBarSeverity::Error);
    AppleInfo().Message(
        L"The local sign-in service returned an invalid response.");
  }
}

void MainWindow::ScanBluetooth_Click(IInspectable const &,
                                     RoutedEventArgs const &) {
  try {
    m_scanStarted = true;
    BluetoothProgress().IsActive(true);
    BluetoothScanButton().IsEnabled(false);
    BluetoothScanButton().Content(box_value(L"Scanning..."));
    BluetoothStatus().Text(L"Starting Windows Bluetooth LE scan...");
    m_bluetooth.StartScan();
  } catch (hresult_error const &error) {
    BluetoothProgress().IsActive(false);
    BluetoothScanButton().IsEnabled(true);
    BluetoothScanButton().Content(box_value(L"Try Scan Again"));
    BluetoothStatus().Text(L"Bluetooth scan could not start: " +
                           std::wstring(error.message()));
    Trace(L"Bluetooth scan click failure: " + std::wstring(error.message()));
  } catch (...) {
    BluetoothProgress().IsActive(false);
    BluetoothScanButton().IsEnabled(true);
    BluetoothScanButton().Content(box_value(L"Try Scan Again"));
    BluetoothStatus().Text(L"Bluetooth scan could not start.");
    Trace(L"Bluetooth scan click unknown failure.");
  }
}

void MainWindow::ShowUnnamedDevices_Toggled(IInspectable const &,
                                             RoutedEventArgs const &) {
  if (m_closing)
    return;
  RenderBluetoothDevices(m_bluetoothDevices);
}

void MainWindow::OnBluetoothDevices(
    std::vector<BluetoothDevice> const &devices) {
  if (m_closing)
    return;
  {
    std::scoped_lock lock(m_pendingBluetoothMutex);
    m_pendingBluetoothDevices = devices;
  }
  if (m_bluetoothRenderQueued.exchange(true))
    return;

  auto weak = get_weak();
  if (!m_dispatcher.TryEnqueue([weak] {
        auto self = weak.get();
        if (!self || self->m_closing)
          return;
        std::vector<BluetoothDevice> latest;
        {
          std::scoped_lock lock(self->m_pendingBluetoothMutex);
          latest = std::move(self->m_pendingBluetoothDevices);
          self->m_pendingBluetoothDevices.clear();
        }
        self->RenderBluetoothDevices(latest);
        self->m_bluetoothRenderQueued = false;

        std::vector<BluetoothDevice> pending;
        {
          std::scoped_lock lock(self->m_pendingBluetoothMutex);
          pending = self->m_pendingBluetoothDevices;
        }
        if (!pending.empty())
          self->OnBluetoothDevices(pending);
      })) {
    m_bluetoothRenderQueued = false;
  }
}

void MainWindow::RenderBluetoothDevices(
    std::vector<BluetoothDevice> const &devices) {
  if (m_closing)
    return;
  try {
    m_bluetoothDevices = devices;
    uint64_t selectedOrder{};
    if (auto selected = BluetoothList().SelectedItem().try_as<ListViewItem>()) {
      if (auto tag = selected.Tag().try_as<Windows::Foundation::IPropertyValue>();
          tag && tag.Type() == Windows::Foundation::PropertyType::String) {
        auto text = tag.GetString();
        wchar_t *end{};
        auto parsed = std::wcstoull(text.c_str(), &end, 10);
        if (end && end != text.c_str() && *end == L'\0')
          selectedOrder = parsed;
      }
    }
    m_rebuildingBluetoothList = true;
    BluetoothList().Items().Clear();
    auto showUnnamed = ShowUnnamedDevices().IsOn();
    size_t unnamedShown{};
    size_t shown{};
    for (auto const &device : devices) {
      auto unnamed = device.name.empty() || device.name == L"Unknown Device";
      if (unnamed && (!showUnnamed || unnamedShown >= 4))
        continue;
      if (shown >= 14)
        break;
      unnamedShown += unnamed ? 1 : 0;
      ++shown;
      Grid row;
      row.Padding(Thickness{14});
      row.ColumnSpacing(12);
      row.ColumnDefinitions().Append(ColumnDefinition{});
      ColumnDefinition signalColumn;
      signalColumn.Width(GridLength{100, GridUnitType::Pixel});
      row.ColumnDefinitions().Append(signalColumn);
      ColumnDefinition badgeColumn;
      badgeColumn.Width(GridLength{130, GridUnitType::Pixel});
      row.ColumnDefinitions().Append(badgeColumn);
      StackPanel identity;
      TextBlock name;
      name.Text(device.name);
      name.FontWeight(Windows::UI::Text::FontWeights::SemiBold());
      identity.Children().Append(name);
      TextBlock id;
      if (device.paired)
        id.Text(std::wstring(L"Paired in Windows") +
                (device.id.empty() ? L"" : L" · stable reconnect available"));
      else {
        wchar_t address[24]{};
        swprintf_s(address, L"%012llX", device.address);
        id.Text(L"Bluetooth address " + std::wstring(address));
      }
      id.Foreground(Application::Current()
                        .Resources()
                        .Lookup(box_value(L"SecondaryTextBrush"))
                        .as<Brush>());
      identity.Children().Append(id);
      row.Children().Append(identity);
      TextBlock signal;
      signal.Text(std::to_wstring(device.rssi) + L" dBm");
      signal.VerticalAlignment(VerticalAlignment::Center);
      Grid::SetColumn(signal, 1);
      row.Children().Append(signal);
      Border badge;
      badge.CornerRadius(CornerRadius{10});
      badge.Padding(Thickness{9, 5, 9, 5});
      badge.Background(Application::Current()
                           .Resources()
                           .Lookup(box_value(device.paired
                                                 ? L"AccentSoftBrush"
                                                 : L"SurfaceAltBrush"))
                           .as<Brush>());
      Grid::SetColumn(badge, 2);
      TextBlock badgeText;
      badgeText.Text(!device.connectable
                         ? L"Not connectable"
                         : device.paired
                               ? (device.likelyFlipper ? L"Paired Flipper"
                                                       : L"Paired device")
                               : device.likelyFlipper ? L"Possible Flipper"
                                                      : L"Nearby device");
      badgeText.Foreground(Application::Current()
                               .Resources()
                               .Lookup(box_value(device.paired
                                                     ? L"AccentBrush"
                                                     : L"PrimaryTextBrush"))
                               .as<Brush>());
      badge.Child(badgeText);
      row.Children().Append(badge);
      ListViewItem item;
      item.Content(row);
      item.Tag(box_value(std::to_wstring(device.discoveryOrder)));
      item.IsEnabled(device.connectable);
      BluetoothList().Items().Append(item);
      if (selectedOrder != 0 && selectedOrder == device.discoveryOrder)
        BluetoothList().SelectedItem(item);
    }
    m_rebuildingBluetoothList = false;
    BluetoothProgress().IsActive(false);
    BluetoothScanButton().IsEnabled(true);
    BluetoothScanButton().Content(box_value(L"Scan Again"));
    BluetoothStatus().Text(
        shown == 0
            ? L"No named BLE devices found. Open FindMyFlipper on the device, "
              L"pair it in Windows, or show unnamed devices."
            : L"Select your Flipper. This list stays fixed while signal values update.");
  } catch (hresult_error const &error) {
    m_rebuildingBluetoothList = false;
    BluetoothProgress().IsActive(false);
    BluetoothScanButton().IsEnabled(true);
    BluetoothStatus().Text(L"Could not update the Bluetooth list: " +
                           std::wstring(error.message()));
    Trace(L"Bluetooth list WinRT failure: " + std::wstring(error.message()));
  } catch (std::exception const &error) {
    m_rebuildingBluetoothList = false;
    BluetoothProgress().IsActive(false);
    BluetoothScanButton().IsEnabled(true);
    auto message = std::wstring(winrt::to_hstring(error.what()));
    BluetoothStatus().Text(L"Could not update the Bluetooth list.");
    Trace(L"Bluetooth list C++ failure: " + message);
  } catch (...) {
    m_rebuildingBluetoothList = false;
    BluetoothProgress().IsActive(false);
    BluetoothScanButton().IsEnabled(true);
    BluetoothStatus().Text(L"Could not update the Bluetooth list.");
    Trace(L"Bluetooth list unknown failure.");
  }
}

void MainWindow::BluetoothList_SelectionChanged(
    IInspectable const &, SelectionChangedEventArgs const &) {
  if (m_rebuildingBluetoothList)
    return;
  auto item = BluetoothList().SelectedItem().try_as<ListViewItem>();
  if (!item)
    return;
  auto tag = item.Tag().try_as<Windows::Foundation::IPropertyValue>();
  if (!tag || tag.Type() != Windows::Foundation::PropertyType::String)
    return;
  auto text = tag.GetString();
  wchar_t *end{};
  auto discoveryOrder = std::wcstoull(text.c_str(), &end, 10);
  if (!end || end == text.c_str() || *end != L'\0')
    return;
  auto found = std::find_if(
      m_bluetoothDevices.begin(), m_bluetoothDevices.end(),
      [discoveryOrder](auto const &device) {
        return device.discoveryOrder == discoveryOrder;
      });
  if (found == m_bluetoothDevices.end())
    return;
  if (!found->connectable) {
    BluetoothStatus().Text(
        L"That advertisement is not connectable. Choose your physical Flipper Zero.");
    return;
  }
  auto profile = m_store.Profile();
  profile.rssi = found->rssi;
  if (!found->name.empty() && found->name != L"Unknown Device")
    profile.bluetoothName = found->name;
  if (!found->id.empty())
    profile.bluetoothDeviceId = found->id;
  m_store.UpdateProfile(profile);
  UpdateProfileUI();
  m_bluetooth.Connect(*found);
  BluetoothStatus().Text(L"Connecting to " + found->name + L"...");
}

void MainWindow::OnBluetoothStatus(std::wstring const &message, bool connected,
                                   int battery) {
  if (m_closing)
    return;
  auto weak = get_weak();
  m_dispatcher.TryEnqueue([weak, message, connected, battery] {
    auto self = weak.get();
    if (!self || self->m_closing)
      return;
    try {
      auto profile = self->m_store.Profile();
      profile.connected = connected;
      if (connected) {
        profile.bluetoothDeviceId = self->m_bluetooth.ConnectedDeviceId();
        if (!self->m_bluetooth.ConnectedDeviceName().empty())
          profile.bluetoothName = self->m_bluetooth.ConnectedDeviceName();
        if (!self->m_bluetooth.ConnectedBluetoothMac().empty()) {
          profile.bluetoothMac = self->m_bluetooth.ConnectedBluetoothMac();
          profile.bluetoothMacRandom =
              self->m_bluetooth.ConnectedAddressIsRandom();
        }
        if (!self->m_bluetooth.FirmwareVersion().empty())
          profile.firmwareVersion = self->m_bluetooth.FirmwareVersion();
      }
      if (battery >= 0)
        profile.batteryLevel = battery;
      if (connected && self->m_bluetooth.CurrentRssi() > -127)
        profile.rssi = self->m_bluetooth.CurrentRssi();
      self->m_store.UpdateProfile(profile);
      self->BluetoothStatus().Text(message);
      self->BluetoothScanButton().IsEnabled(true);
      if (!connected)
        self->BluetoothScanButton().Content(box_value(L"Scan Again"));
      self->ContinueButton().IsEnabled(self->m_step == 4 && connected);
      self->UpdateProfileUI();
      self->m_tray.UpdateTooltip(profile.displayName, connected,
                                 profile.batteryLevel);
    } catch (hresult_error const &error) {
      Trace(L"Bluetooth status UI failure: " + std::wstring(error.message()));
    } catch (...) {
      Trace(L"Bluetooth status UI unknown failure.");
    }
  });
}

void MainWindow::RunDiagnostics() {
  DiagnosticList().Children().Clear();
  auto privateKeyStored =
      !m_store.Key().id.empty() &&
      CredentialService::LoadPrivateKey(m_store.Key().id).has_value();
  std::vector<std::pair<std::wstring, bool>> checks{
      {L"Keys file valid",
       m_keysValid || !m_store.Key().hashedAdvertisementKey.empty()},
      {L"Private key stored", privateKeyStored},
      {L"Hashed adv key valid", !m_store.Key().hashedAdvertisementKey.empty()},
      {L"Apple access connected", m_appleConnected},
      {L"Backend running", m_backendReady},
      {L"Bluetooth adapter available", m_bluetooth.AdapterAvailable()},
      {L"Flipper selected", !m_store.Profile().bluetoothDeviceId.empty()},
      {L"Reports endpoint", m_backendReady && m_backend.IsHealthy()},
  };
  bool allPassed = true;
  for (auto const &[title, passed] : checks) {
    allPassed &= passed;
    Grid row;
    TextBlock label;
    label.Text(title);
    row.Children().Append(label);
    TextBlock status;
    status.Text(passed ? L"Passed" : L"Needs attention");
    status.HorizontalAlignment(HorizontalAlignment::Right);
    status.Foreground(
        SolidColorBrush(passed ? HexColor(L"#22C55E") : HexColor(L"#EF4444")));
    row.Children().Append(status);
    DiagnosticList().Children().Append(row);
  }
  DiagnosticInfo().IsOpen(true);
  DiagnosticInfo().Severity(allPassed ? InfoBarSeverity::Success
                                      : InfoBarSeverity::Warning);
  DiagnosticInfo().Message(
      allPassed
          ? L"All tests passed. Your setup is ready."
          : L"Resolve the failed checks before relying on report refresh.");
  ContinueButton().IsEnabled(allPassed);
}

void MainWindow::RunDiagnostics_Click(IInspectable const &,
                                      RoutedEventArgs const &) {
  if (AppShell().Visibility() == Visibility::Visible)
    ShowDiagnosticsDialog();
  else
    ShowOnboardingStep(5);
}

void MainWindow::OpenShell(std::wstring const &page) {
  OnboardingRoot().Visibility(Visibility::Collapsed);
  AppShell().Visibility(Visibility::Visible);
  ShowPage(page);
  UpdateProfileUI();
  if (m_windowLoaded)
    InitializeMaps();
}

fire_and_forget MainWindow::InitializeMaps() {
  if (m_closing || !m_windowLoaded ||
      AppShell().Visibility() != Visibility::Visible)
    co_return;

  bool const compact = m_currentPage == L"dashboard";
  if (!compact && m_currentPage != L"map")
    co_return;
  auto &started = compact ? m_dashboardMapInitStarted : m_mainMapInitStarted;
  auto &ready = compact ? m_dashboardMapReady : m_mapReady;
  if (started || ready)
    co_return;
  started = true;

  auto weak = get_weak();
  try {
    auto mapPath = AssetPath(L"Map\\map.html");
    if (!std::filesystem::exists(mapPath))
      throw hresult_error(HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND),
                          L"The packaged map assets are missing.");

    auto view = compact ? DashboardMap() : MapWebView();
    auto mapFolder = mapPath.parent_path().wstring();
    view.CoreWebView2Initialized(
        [weak, compact, mapFolder](
            WebView2 const &initializedView,
            CoreWebView2InitializedEventArgs const &args) {
          auto self = weak.get();
          if (!self || self->m_closing)
            return;
          try {
            auto core = initializedView.CoreWebView2();
            if (!core) {
              auto code = args.Exception();
              winrt::hresult failure =
                  code.value == 0 ? winrt::hresult(E_PENDING) : code;
              throw hresult_error(
                  failure,
                  hstring(code.value == 0
                              ? L"WebView2 browser creation did not complete."
                              : L"WebView2 browser creation failed."));
            }
            core.SetVirtualHostNameToFolderMapping(
                L"appassets.local", mapFolder,
                Microsoft::Web::WebView2::Core::
                    CoreWebView2HostResourceAccessKind::Allow);
            if (!compact) {
              core.WebMessageReceived(
                  [weak](auto const &, Microsoft::Web::WebView2::Core::
                                           CoreWebView2WebMessageReceivedEventArgs
                                               const &args) {
                    if (auto owner = weak.get()) {
                      try {
                        auto message =
                            std::wstring(args.TryGetWebMessageAsString());
                        if (message == L"refreshReports")
                          owner->RefreshReports();
                        else if (message == L"diagnostics")
                          owner->RunDiagnostics();
                        else if (message.rfind(L"openMaps:", 0) == 0) {
                          auto coordinates = message.substr(9);
                          std::replace(coordinates.begin(), coordinates.end(),
                                       L',', L'~');
                          ShellExecuteW(
                              nullptr, L"open",
                              (L"https://www.bing.com/maps?cp=" + coordinates +
                               L"&lvl=16&style=r")
                                  .c_str(),
                              nullptr, nullptr, SW_SHOWNORMAL);
                        }
                      } catch (hresult_error const &error) {
                        Trace(L"Map command failed: " +
                              std::wstring(error.message()));
                      }
                    }
                  });
            }
            core.Navigate(compact
                              ? L"https://appassets.local/map.html?compact=1"
                              : L"https://appassets.local/map.html");
            self->GlobalWarning().IsOpen(false);
          } catch (hresult_error const &error) {
            if (compact)
              self->m_dashboardMapInitStarted = false;
            else
              self->m_mainMapInitStarted = false;
            self->GlobalWarning().Message(L"Map initialization failed: " +
                                          std::wstring(error.message()));
            self->GlobalWarning().IsOpen(true);
            Trace(L"Map initialization callback failed: " +
                  std::wstring(error.message()));
          }
        });
    co_await view.EnsureCoreWebView2Async();
    if (m_closing)
      co_return;
  } catch (hresult_error const &error) {
    started = false;
    if (auto self = weak.get()) {
      self->GlobalWarning().Message(L"Map initialization failed: " +
                                    std::wstring(error.message()));
      self->GlobalWarning().IsOpen(true);
      Trace(L"Map initialization failed: " + std::wstring(error.message()));
    }
  }
}

void MainWindow::ShowPage(std::wstring const &page) {
  m_currentPage = page;
  MapPage().Visibility(page == L"map" ? Visibility::Visible
                                      : Visibility::Collapsed);
  DashboardPage().Visibility(page == L"dashboard" ? Visibility::Visible
                                                  : Visibility::Collapsed);
  ReportsPage().Visibility(page == L"reports" ? Visibility::Visible
                                              : Visibility::Collapsed);
  FlipperPage().Visibility(page == L"flipper" ? Visibility::Visible
                                              : Visibility::Collapsed);
  ProfilesPage().Visibility(page == L"profiles" ? Visibility::Visible
                                                : Visibility::Collapsed);
  SettingsPage().Visibility(page == L"settings" ? Visibility::Visible
                                                : Visibility::Collapsed);
  if (m_windowLoaded && AppShell().Visibility() == Visibility::Visible)
    InitializeMaps();
}

void MainWindow::Navigate_Click(IInspectable const &sender,
                                RoutedEventArgs const &) {
  auto button = sender.as<Button>();
  ShowPage(unbox_value<hstring>(button.Tag()).c_str());
}

void MainWindow::OpenBluetooth_Click(IInspectable const &,
                                     RoutedEventArgs const &) {
  ShowOnboardingStep(4);
}
void MainWindow::PlayAlert_Click(IInspectable const &,
                                 RoutedEventArgs const &) {
  // Bluetooth status callbacks must never return a completed setup to the
  // onboarding surface. Preserve the page the user was on around this action.
  if (m_store.OnboardingComplete()) {
    OnboardingRoot().Visibility(Visibility::Collapsed);
    AppShell().Visibility(Visibility::Visible);
    ShowPage(m_currentPage);
  }
  m_bluetooth.PlayAlert();
  if (m_mapReady)
    MapWebView().ExecuteScriptAsync(L"pulseMarker()");
}
void MainWindow::Disconnect_Click(IInspectable const &,
                                  RoutedEventArgs const &) {
  m_bluetooth.Disconnect();
}
void MainWindow::RefreshReports_Click(IInspectable const &,
                                      RoutedEventArgs const &) {
  RefreshReports();
}

fire_and_forget MainWindow::RefreshReports() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  if (m_demoMode) {
    UpdateProfileUI();
    UpdateMap();
    co_return;
  }
  if (!m_backendReady) {
    GlobalWarning().Message(
        L"Local backend is offline. Restart it from Settings.");
    GlobalWarning().IsOpen(true);
    co_return;
  }
  if (m_reportRefreshBusy.exchange(true))
    co_return;
  auto key = m_store.Key();
  auto privateKey = CredentialService::LoadPrivateKey(key.id);
  if (!privateKey) {
    m_reportRefreshBusy = false;
    GlobalWarning().Message(
        L"The private key is missing from Windows Credential Manager. Import "
        L"the .keys file again.");
    GlobalWarning().IsOpen(true);
    co_return;
  }
  JsonObject request;
  request.SetNamedValue(
      L"hashed_adv_key_base64",
      JsonValue::CreateStringValue(key.hashedAdvertisementKey));
  request.SetNamedValue(L"private_key_base64",
                        JsonValue::CreateStringValue(*privateKey));
  request.SetNamedValue(L"hours", JsonValue::CreateNumberValue(720));
  auto body = std::wstring(request.Stringify());
  co_await resume_background();
  std::wstring response;
  try {
    response = m_backend.Post(L"/reports/decrypted", body);
  } catch (std::exception const &error) {
    response = L"{\"ok\":false,\"error\":\"" + winrt::to_hstring(error.what()) +
               L"\"}";
  }
  co_await uiThread;
  m_reportRefreshBusy = false;
  if (m_closing)
    co_return;
  try {
    auto result = JsonObject::Parse(response);
    if (!result.GetNamedBoolean(L"ok", false)) {
      auto error = std::wstring(
          result.GetNamedString(L"error", L"Report refresh failed."));
      GlobalWarning().Message(error);
      GlobalWarning().IsOpen(true);
      if (error.find(L"authentication") != std::wstring::npos ||
          error.find(L"rejected") != std::wstring::npos) {
        m_appleConnected = false;
        SettingsAppleStatus().Text(L"Find My reports: Sign-in required");
      }
      co_return;
    }
    m_reports.clear();
    for (auto const &value : result.GetNamedArray(L"reports", JsonArray{})) {
      auto report = value.GetObject();
      LocationReport item;
      item.id = report.GetNamedString(L"id", L"");
      item.timestamp =
          static_cast<int64_t>(report.GetNamedNumber(L"timestamp", 0));
      item.latitude = report.GetNamedNumber(L"lat", 0);
      item.longitude = report.GetNamedNumber(L"lon", 0);
      item.confidence =
          static_cast<int>(report.GetNamedNumber(L"confidence", 0));
      item.status = static_cast<int>(report.GetNamedNumber(L"status", 0));
      m_reports.push_back(item);
    }
    GlobalWarning().IsOpen(false);
    UpdateProfileUI();
    UpdateMap();
  } catch (...) {
    GlobalWarning().Message(L"The report service returned invalid data.");
    GlobalWarning().IsOpen(true);
  }
}

void MainWindow::UpdateProfileUI() {
  auto profile = m_store.Profile();
  auto markerIndex = profile.flipperIconStyle == L"black"
                         ? 1
                         : profile.flipperIconStyle == L"transparent" ? 2 : 0;
  if (m_markerPicker && m_markerPicker.SelectedIndex() != markerIndex)
    m_markerPicker.SelectedIndex(markerIndex);
  auto name = profile.displayName.empty() ? L"My Flipper" : profile.displayName;
  DashboardTitle().Text(name);
  MapProfileName().Text(name);
  FlipperTitle().Text(name);
  ProfileCardName().Text(name);
  MapConnectionText().Text(profile.connected ? L"Connected" : L"Disconnected");
  SidebarConnection().Text(profile.connected ? L"Flipper Connected"
                                             : L"Flipper Disconnected");
  SidebarStatusDot().Fill(
      SolidColorBrush(HexColor(profile.connected ? L"#22C55E" : L"#9CA3AF")));
  auto battery = profile.batteryLevel >= 0
                     ? std::to_wstring(profile.batteryLevel) + L"%"
                     : L"--";
  SidebarBattery().Text(battery);
  BatteryValue().Text(battery);
  DetailBattery().Text(battery);
  BluetoothValue().Text(profile.connected ? L"Connected" : L"Disconnected");
  FlipperConnection().Text(profile.connected ? L"Connected" : L"Disconnected");
  DetailConnection().Text(profile.connected ? L"Connected" : L"Disconnected");
  DetailSignal().Text(
      profile.rssi > -127 ? std::to_wstring(profile.rssi) + L" dBm" : L"--");
  DetailLastConnected().Text(profile.connected ? L"Now" : L"Never");
  m_firmwareValue.Text(
      profile.firmwareVersion.empty()
          ? L"Firmware: Not exposed over Bluetooth"
          : L"Firmware: " + profile.firmwareVersion);
  m_alertSupportValue.Text(
      L"Alert support: " + std::wstring(profile.connected
          ? (m_bluetooth.AlertAvailable()
                 ? L"Available"
                 : L"Not exposed by the current Flipper Bluetooth app")
          : L"Connect over Bluetooth to check"));
  NoReportsKeyStatus().Text(m_store.Key().id.empty()
                                ? L"Private key   Not imported"
                                : L"Private key   In Credential Manager");
  NoReportsBluetoothStatus().Text(
      profile.connected ? L"Bluetooth   Connected"
                        : (!profile.bluetoothDeviceId.empty()
                               ? L"Bluetooth   Saved, disconnected"
                               : L"Bluetooth   Not selected"));
  FlipperDeviceId().Text(profile.bluetoothDeviceId.empty()
                             ? L"Windows BLE identifier: Not selected"
                             : L"Windows BLE identifier: " +
                                   profile.bluetoothDeviceId);
  m_bluetoothMacValue.Text(
      profile.bluetoothMac.empty()
          ? L"Bluetooth MAC: Not selected"
          : L"Bluetooth MAC: " + profile.bluetoothMac +
                (profile.bluetoothMacRandom ? L" (random/private)"
                                            : L" (public)"));
  FlipperGeneratedMac().Text(profile.generatedFindMyMac.empty()
                                 ? L"Generated Find My MAC: Not imported"
                                 : L"Generated Find My MAC: " +
                                       profile.generatedFindMyMac);
  ReportsValue().Text(std::to_wstring(m_reports.size()));
  if (!m_reports.empty()) {
    auto age = std::max<int64_t>(0, static_cast<int64_t>(std::time(nullptr)) -
                                        m_reports.front().timestamp);
    auto minutes = age / 60;
    LastSeenValue().Text(minutes < 1 ? L"Now"
                                     : std::to_wstring(minutes) + L"m ago");
  } else {
    LastSeenValue().Text(L"Never");
  }
  ProfileCardReports().Text(
      m_reports.empty() ? L"No reports yet"
                        : std::to_wstring(m_reports.size()) + L" reports");
  ProfileCardMac().Text(profile.generatedFindMyMac.empty()
                            ? L"Find My MAC: --"
                            : L"Find My MAC: " + profile.generatedFindMyMac);
  NoReportsPanel().Visibility(m_reports.empty() ? Visibility::Visible
                                                : Visibility::Collapsed);
  MapWebView().Visibility(m_reports.empty() ? Visibility::Collapsed
                                            : Visibility::Visible);
  MapTopBar().Visibility(m_reports.empty() ? Visibility::Collapsed
                                           : Visibility::Visible);
  UpdateReportsList();
}

void MainWindow::UpdateReportsList() {
  auto selected = ReportFilter().SelectedIndex();
  auto now = static_cast<int64_t>(std::time(nullptr));
  int64_t cutoff = 0;
  if (selected == 0 || selected == 1)
    cutoff = now - 24 * 60 * 60;
  else if (selected == 2)
    cutoff = now - 7 * 24 * 60 * 60;

  m_visibleReports.clear();
  for (auto const &report : m_reports) {
    if (cutoff == 0 || report.timestamp >= cutoff)
      m_visibleReports.push_back(report);
  }

  ReportsList().Items().Clear();
  for (auto const &report : m_visibleReports) {
    ListViewItem row;
    row.Content(box_value(L"Find My Network   " +
                          std::to_wstring(report.latitude) + L", " +
                          std::to_wstring(report.longitude) + L"   Accuracy " +
                          std::to_wstring(report.confidence) + L" m"));
    ReportsList().Items().Append(row);
  }
  ReportsFooter().Text(std::to_wstring(m_visibleReports.size()) + L" shown, " +
                       std::to_wstring(m_reports.size()) + L" total");
}

void MainWindow::ReportFilter_SelectionChanged(
    IInspectable const &, SelectionChangedEventArgs const &) {
  UpdateReportsList();
}

void MainWindow::Map_NavigationCompleted(
    WebView2 const &sender,
    Microsoft::Web::WebView2::Core::
        CoreWebView2NavigationCompletedEventArgs const &) {
  if (sender == MapWebView())
    m_mapReady = true;
  if (sender == DashboardMap())
    m_dashboardMapReady = true;
  auto colors = ResolvedColors(
      static_cast<ThemeOption>(std::max(0, ThemePicker().SelectedIndex())));
  auto themeScript = L"setAccent('" + m_accent + L"');setTheme('" + colors.card +
                     L"','" + colors.primaryText + L"','" + colors.secondaryText +
                     L"','" + colors.border + L"');";
  sender.ExecuteScriptAsync(themeScript);
  UpdateMap();
}

void MainWindow::UpdateMap() {
  if (m_reports.empty())
    return;
  auto const &latest = m_reports.front();
  JsonArray reports;
  for (auto const &report : m_reports) {
    JsonObject point;
    point.SetNamedValue(L"lat", JsonValue::CreateNumberValue(report.latitude));
    point.SetNamedValue(L"lon", JsonValue::CreateNumberValue(report.longitude));
    point.SetNamedValue(L"confidence",
                        JsonValue::CreateNumberValue(report.confidence));
    point.SetNamedValue(L"timestamp",
                        JsonValue::CreateNumberValue(
                            static_cast<double>(report.timestamp)));
    reports.Append(point);
  }
  auto profile = m_store.Profile();
  auto name = profile.displayName.empty() ? L"Flipper" : profile.displayName;
  auto script = L"setReports(" + reports.Stringify() + L",\"" +
                JsonEscape(name) + L"\");setMarkerStyle(\"" +
                JsonEscape(profile.flipperIconStyle) + L"\");";
  if (m_mapReady)
    MapWebView().ExecuteScriptAsync(script);
  if (m_dashboardMapReady)
    DashboardMap().ExecuteScriptAsync(script);
}

void MainWindow::ReportsList_SelectionChanged(
    IInspectable const &, SelectionChangedEventArgs const &) {
  auto index = ReportsList().SelectedIndex();
  if (index >= 0 && static_cast<size_t>(index) < m_visibleReports.size())
    ShowReportDialog(static_cast<size_t>(index));
}

fire_and_forget MainWindow::ShowReportDialog(size_t index) {
  auto const report = m_visibleReports[index];
  ContentDialog dialog;
  dialog.XamlRoot(Content().as<FrameworkElement>().XamlRoot());
  dialog.Title(box_value(L"Report Details"));
  TextBlock text;
  text.Text(L"Latitude: " + std::to_wstring(report.latitude) +
            L"\nLongitude: " + std::to_wstring(report.longitude) +
            L"\nConfidence: " + std::to_wstring(report.confidence) +
            L" m\nSource: Find My Network");
  text.TextWrapping(TextWrapping::Wrap);
  dialog.Content(text);
  dialog.CloseButtonText(L"Close");
  co_await dialog.ShowAsync();
}

void MainWindow::RenameProfile_Click(IInspectable const &,
                                     RoutedEventArgs const &) {
  ShowRenameDialog();
}

void MainWindow::MapActions_Click(IInspectable const &sender,
                                  RoutedEventArgs const &) {
  auto anchor = sender.as<FrameworkElement>();
  MenuFlyout menu;
  MenuFlyoutItem refresh;
  refresh.Text(L"Refresh reports now");
  MenuFlyoutItem diagnostics;
  diagnostics.Text(L"Setup diagnostics");
  FontIcon refreshIcon;
  refreshIcon.Glyph(L"\xE72C");
  refresh.Icon(refreshIcon);
  FontIcon diagnosticsIcon;
  diagnosticsIcon.Glyph(L"\xE9D9");
  diagnostics.Icon(diagnosticsIcon);
  auto weak = get_weak();
  refresh.Click([weak](auto const &, auto const &) {
    if (auto self = weak.get())
      self->RefreshReports();
  });
  diagnostics.Click([weak](auto const &, auto const &) {
    if (auto self = weak.get())
      self->ShowDiagnosticsDialog();
  });
  menu.Items().Append(refresh);
  menu.Items().Append(diagnostics);
  menu.Placement(FlyoutPlacementMode::BottomEdgeAlignedRight);
  menu.ShowAt(anchor);
}

fire_and_forget MainWindow::ShowDiagnosticsDialog() {
  auto lifetime = get_strong();
  StackPanel panel;
  panel.Spacing(10);
  panel.MinWidth(500);
  auto privateKeyStored = !m_store.Key().id.empty() &&
                          CredentialService::LoadPrivateKey(m_store.Key().id).has_value();
  std::vector<std::pair<std::wstring, bool>> checks{
      {L"Keys file valid", m_keysValid || !m_store.Key().hashedAdvertisementKey.empty()},
      {L"Private key stored in Windows Credential Manager", privateKeyStored},
      {L"Apple access connected", m_appleConnected},
      {L"Local backend running", m_backendReady && m_backend.IsHealthy()},
      {L"Bluetooth adapter available", m_bluetooth.AdapterAvailable()},
      {L"Flipper selected", !m_store.Profile().bluetoothDeviceId.empty()},
  };
  for (auto const &[title, passed] : checks) {
    Grid row;
    ColumnDefinition labelColumn;
    labelColumn.Width(GridLengthHelper::FromValueAndType(1, GridUnitType::Star));
    ColumnDefinition statusColumn;
    statusColumn.Width(GridLengthHelper::Auto());
    row.ColumnDefinitions().Append(labelColumn);
    row.ColumnDefinitions().Append(statusColumn);
    TextBlock label;
    label.Text(title);
    label.TextWrapping(TextWrapping::Wrap);
    row.Children().Append(label);
    TextBlock status;
    status.Text(passed ? L"Passed" : L"Needs attention");
    status.Margin(ThicknessHelper::FromLengths(20, 0, 0, 0));
    status.HorizontalAlignment(HorizontalAlignment::Right);
    Grid::SetColumn(status, 1);
    status.Foreground(SolidColorBrush(
        passed ? HexColor(L"#22C55E") : HexColor(L"#EF4444")));
    row.Children().Append(status);
    panel.Children().Append(row);
  }
  ContentDialog dialog;
  dialog.XamlRoot(Content().as<FrameworkElement>().XamlRoot());
  dialog.Title(box_value(L"Setup diagnostics"));
  dialog.Content(panel);
  dialog.CloseButtonText(L"Close");
  co_await dialog.ShowAsync();
}
fire_and_forget MainWindow::ShowRenameDialog() {
  TextBox input;
  input.Text(m_store.Profile().displayName);
  input.Header(box_value(L"Profile name"));
  ContentDialog dialog;
  dialog.XamlRoot(Content().as<FrameworkElement>().XamlRoot());
  dialog.Title(box_value(L"Rename Profile"));
  dialog.Content(input);
  dialog.PrimaryButtonText(L"Save");
  dialog.CloseButtonText(L"Cancel");
  if (co_await dialog.ShowAsync() == ContentDialogResult::Primary) {
    auto profile = m_store.Profile();
    profile.displayName = Trim(std::wstring(input.Text()));
    if (!profile.displayName.empty())
      m_store.UpdateProfile(profile);
    UpdateProfileUI();
    UpdateMap();
  }
}

void MainWindow::AddProfile_Click(IInspectable const &,
                                  RoutedEventArgs const &) {
  GlobalWarning().Message(
      L"Import another .keys identity to add a profile. Multiple profile "
      L"storage is enabled in the data model.");
  GlobalWarning().IsOpen(true);
}

void MainWindow::ApplyTheme(ThemeOption theme) {
  WindowRoot().RequestedTheme(theme == ThemeOption::Light ? ElementTheme::Light
                              : theme == ThemeOption::System
                                  ? ElementTheme::Default
                                  : ElementTheme::Dark);
  auto colors = ResolvedColors(theme);
  m_accent = colors.accent;
  auto resources = Application::Current().Resources();
  SetBrush(resources, L"AccentBrush", colors.accent);
  SetBrush(resources, L"AccentDarkBrush", colors.accentDark);
  SetBrush(resources, L"AccentSoftBrush", colors.accentSoft);
  SetBrush(resources, L"SurfaceBrush", colors.card);
  SetBrush(resources, L"BackgroundBrush", colors.background);
  SetBrush(resources, L"CardBorderBrush", colors.border);
  SetBrush(resources, L"PrimaryTextBrush", colors.primaryText);
  SetBrush(resources, L"SecondaryTextBrush", colors.secondaryText);
  AccentName().Text(theme == ThemeOption::Ocean    ? L"Ocean Blue"
                    : theme == ThemeOption::Forest ? L"Forest Green"
                    : theme == ThemeOption::Purple ? L"Purple"
                                                   : L"Orange");
  auto script = L"setAccent('" + m_accent + L"');setTheme('" + colors.card +
                L"','" + colors.primaryText + L"','" + colors.secondaryText +
                L"','" + colors.border + L"');";
  if (m_mapReady)
    MapWebView().ExecuteScriptAsync(script);
  if (m_dashboardMapReady)
    DashboardMap().ExecuteScriptAsync(script);
}

void MainWindow::ThemePicker_SelectionChanged(
    IInspectable const &, SelectionChangedEventArgs const &) {
  if (ThemePicker().SelectedIndex() >= 0)
    ApplyTheme(static_cast<ThemeOption>(ThemePicker().SelectedIndex()));
}

void MainWindow::MarkerPicker_SelectionChanged(
    IInspectable const &, SelectionChangedEventArgs const &) {
  if (!m_markerPicker || m_markerPicker.SelectedIndex() < 0)
    return;
  static constexpr wchar_t const *styles[] = {L"white", L"black",
                                               L"transparent"};
  auto index = std::min<int32_t>(2, m_markerPicker.SelectedIndex());
  auto profile = m_store.Profile();
  profile.flipperIconStyle = styles[index];
  m_store.UpdateProfile(profile);
  UpdateMap();
}

fire_and_forget MainWindow::RefreshServiceStatus() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  if (m_demoMode)
    co_return;
  if (m_closing || m_servicePollBusy.exchange(true))
    co_return;
  std::wstring response;
  try {
    co_await resume_background();
    if (!m_backend.IsHealthy())
      throw std::runtime_error("Local backend is not responding.");
    response = m_backend.Get(L"/auth/anisette-status");
  } catch (...) {
    response.clear();
  }
  co_await uiThread;
  m_servicePollBusy = false;
  if (m_closing)
    co_return;
  if (response.empty()) {
    m_backendReady = false;
    SettingsBackendStatus().Text(L"Local backend: Offline");
    co_return;
  }
  try {
    auto status = JsonObject::Parse(response);
    auto state = status.GetNamedString(L"state", L"stopped");
    m_backendReady = true;
    m_anisetteReady = state == L"running";
    SettingsBackendStatus().Text(
        state == L"running"  ? L"Local backend: Running · Docker and anisette ready"
        : state == L"starting" ? L"Local backend: Running · Docker is starting"
        : state == L"missing"  ? L"Local backend: Running · Docker Desktop not installed"
                               : L"Local backend: Running · Docker is stopped");
    if (m_step == 3 && !m_anisetteReady) {
      AppleInfo().Severity(InfoBarSeverity::Informational);
      AppleInfo().Message(state == L"starting"
                              ? L"Docker Desktop is starting. Apple access will refresh automatically when it is ready."
                              : L"Waiting for Docker Desktop and the local anisette service.");
      AppleInfo().IsOpen(true);
    }
  } catch (...) {
  }
}

void MainWindow::SignInAgain_Click(IInspectable const &,
                                   RoutedEventArgs const &) {
  m_appleConnected = false;
  GlobalWarning().IsOpen(false);
  ShowOnboardingStep(3);
}
void MainWindow::RestartBackend_Click(IInspectable const &,
                                      RoutedEventArgs const &) {
  RestartBackend();
}

fire_and_forget MainWindow::RestartBackend() {
  auto lifetime = get_strong();
  ResumeOnDispatcher uiThread{m_dispatcher};
  if (m_servicePollBusy.exchange(true))
    co_return;
  SettingsBackendStatus().Text(L"Local backend: Restarting");
  std::wstring error;
  try {
    co_await resume_background();
    m_backend.Restart();
  } catch (hresult_error const &exception) {
    error = exception.message();
  } catch (std::exception const &exception) {
    error = winrt::to_hstring(exception.what());
  } catch (...) {
    error = L"Unknown backend restart failure.";
  }
  co_await uiThread;
  m_servicePollBusy = false;
  if (m_closing)
    co_return;
  if (!error.empty()) {
    m_backendReady = false;
    SettingsBackendStatus().Text(L"Local backend: Offline");
    GlobalWarning().Severity(InfoBarSeverity::Error);
    GlobalWarning().Message(L"Backend restart failed: " + error);
    GlobalWarning().IsOpen(true);
    co_return;
  }
  InitializeServices();
}
void MainWindow::ResetData_Click(IInspectable const &,
                                 RoutedEventArgs const &) {
  if (!m_store.Key().id.empty())
    CredentialService::DeletePrivateKey(m_store.Key().id);
  m_store.Reset();
  m_reports.clear();
  m_keysValid = false;
  m_appleConnected = false;
  ShowOnboardingStep(1);
}

std::filesystem::path
MainWindow::AssetPath(std::wstring const &relative) const {
  return ExecutableDirectory() / relative;
}

std::wstring
MainWindow::ParseKeyField(std::wstring const &raw,
                          std::initializer_list<std::wstring> labels) const {
  std::wistringstream stream(raw);
  std::wstring line;
  while (std::getline(stream, line)) {
    auto delimiter = line.find(L':');
    if (delimiter == std::wstring::npos)
      continue;
    auto key = Trim(line.substr(0, delimiter));
    auto value = Trim(line.substr(delimiter + 1));
    for (auto const &label : labels)
      if (_wcsicmp(key.c_str(), label.c_str()) == 0)
        return value;
  }
  return L"";
}

std::wstring MainWindow::NewId() {
  GUID id{};
  CoCreateGuid(&id);
  wchar_t buffer[40]{};
  StringFromGUID2(id, buffer, 40);
  return buffer;
}

std::wstring MainWindow::JsonEscape(std::wstring const &value) {
  std::wstring result;
  result.reserve(value.size());
  for (auto c : value) {
    if (c == L'\\' || c == L'\"')
      result.push_back(L'\\');
    result.push_back(c);
  }
  return result;
}
} // namespace winrt::FindMyFlipperWindows::implementation
