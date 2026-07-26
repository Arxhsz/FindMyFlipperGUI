#pragma once

#include "MainWindow.g.h"
#include "Models/AppModels.h"
#include "Services/BackendManager.h"
#include "Services/BluetoothManager.h"
#include "Services/ProfileStore.h"
#include "Services/TrayIconService.h"

namespace winrt::FindMyFlipperWindows::implementation {
struct MainWindow : MainWindowT<MainWindow> {
  MainWindow();
  ~MainWindow();
  void InitializeAfterXaml();

  void Continue_Click(IInspectable const &,
                      Microsoft::UI::Xaml::RoutedEventArgs const &);
  void Back_Click(IInspectable const &,
                  Microsoft::UI::Xaml::RoutedEventArgs const &);
  void ChooseKeys_Click(IInspectable const &,
                        Microsoft::UI::Xaml::RoutedEventArgs const &);
  void ImportFlipperKeys_Click(IInspectable const &,
                               Microsoft::UI::Xaml::RoutedEventArgs const &);
  void GenerateKeys_Click(IInspectable const &,
                          Microsoft::UI::Xaml::RoutedEventArgs const &);
  void SaveKeys_Click(IInspectable const &,
                      Microsoft::UI::Xaml::RoutedEventArgs const &);
  void PrepareFlipper_Click(IInspectable const &,
                            Microsoft::UI::Xaml::RoutedEventArgs const &);
  void CopyKeysToFlipper_Click(IInspectable const &,
                               Microsoft::UI::Xaml::RoutedEventArgs const &);
  void ConnectApple_Click(IInspectable const &,
                          Microsoft::UI::Xaml::RoutedEventArgs const &);
  void ScanBluetooth_Click(IInspectable const &,
                           Microsoft::UI::Xaml::RoutedEventArgs const &);
  void BluetoothList_SelectionChanged(
      IInspectable const &,
      Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const &);
  void ShowUnnamedDevices_Toggled(IInspectable const &,
                                  Microsoft::UI::Xaml::RoutedEventArgs const &);
  void Navigate_Click(IInspectable const &,
                      Microsoft::UI::Xaml::RoutedEventArgs const &);
  void RefreshReports_Click(IInspectable const &,
                            Microsoft::UI::Xaml::RoutedEventArgs const &);
  void PlayAlert_Click(IInspectable const &,
                       Microsoft::UI::Xaml::RoutedEventArgs const &);
  void OpenBluetooth_Click(IInspectable const &,
                           Microsoft::UI::Xaml::RoutedEventArgs const &);
  void RunDiagnostics_Click(IInspectable const &,
                            Microsoft::UI::Xaml::RoutedEventArgs const &);
  void ReportsList_SelectionChanged(
      IInspectable const &,
      Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const &);
  void ReportFilter_SelectionChanged(
      IInspectable const &,
      Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const &);
  void Disconnect_Click(IInspectable const &,
                        Microsoft::UI::Xaml::RoutedEventArgs const &);
  void AddProfile_Click(IInspectable const &,
                        Microsoft::UI::Xaml::RoutedEventArgs const &);
  void RenameProfile_Click(IInspectable const &,
                           Microsoft::UI::Xaml::RoutedEventArgs const &);
  void MapActions_Click(IInspectable const &,
                        Microsoft::UI::Xaml::RoutedEventArgs const &);
  void ThemePicker_SelectionChanged(
      IInspectable const &,
      Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const &);
  void MarkerPicker_SelectionChanged(
      IInspectable const &,
      Microsoft::UI::Xaml::Controls::SelectionChangedEventArgs const &);
  void SignInAgain_Click(IInspectable const &,
                         Microsoft::UI::Xaml::RoutedEventArgs const &);
  void RestartBackend_Click(IInspectable const &,
                            Microsoft::UI::Xaml::RoutedEventArgs const &);
  void ResetData_Click(IInspectable const &,
                       Microsoft::UI::Xaml::RoutedEventArgs const &);
  void
  Map_NavigationCompleted(Microsoft::UI::Xaml::Controls::WebView2 const &,
                          Microsoft::Web::WebView2::Core::
                              CoreWebView2NavigationCompletedEventArgs const &);

private:
  void ShowOnboardingStep(int step);
  void OpenShell(std::wstring const &page = L"map");
  void ShowPage(std::wstring const &page);
  void UpdateProfileUI();
  void InitializeFlipperDetailsUI();
  void InitializePolishUI();
  void SeedDemoData();
  void RunDiagnostics();
  void ApplyTheme(FindMyFlipper::Models::ThemeOption theme);
  void OnBluetoothDevices(
      std::vector<FindMyFlipper::Models::BluetoothDevice> const &devices);
  void RenderBluetoothDevices(
      std::vector<FindMyFlipper::Models::BluetoothDevice> const &devices);
  void OnBluetoothStatus(std::wstring const &message, bool connected,
                         int battery);
  winrt::fire_and_forget InitializeServices();
  winrt::fire_and_forget ImportKeys();
  winrt::fire_and_forget ImportKeysFromFlipper();
  winrt::fire_and_forget GenerateKeys();
  winrt::fire_and_forget SaveKeys();
  winrt::fire_and_forget PrepareFlipper();
  winrt::fire_and_forget CopyKeysToFlipper();
  winrt::fire_and_forget ConfirmRefreshFlipperDetails();
  winrt::fire_and_forget RefreshFlipperDetails();
  winrt::fire_and_forget ConnectApple();
  winrt::fire_and_forget RefreshReports();
  winrt::fire_and_forget InitializeMaps();
  winrt::fire_and_forget RefreshServiceStatus();
  winrt::fire_and_forget RestartBackend();
  winrt::fire_and_forget ShowRenameDialog();
  winrt::fire_and_forget ShowReportDialog(size_t index);
  winrt::fire_and_forget ShowDiagnosticsDialog();
  void UpdateMap();
  void UpdateReportsList();
  bool StoreKeyContent(std::wstring const &raw, std::wstring const &filename,
                       std::wstring &error);
  std::filesystem::path AssetPath(std::wstring const &relative) const;
  std::wstring ParseKeyField(std::wstring const &raw,
                             std::initializer_list<std::wstring> labels) const;
  static std::wstring NewId();
  static std::wstring JsonEscape(std::wstring const &value);

  int m_step{1};
  bool m_keysValid{false};
  bool m_appleConnected{false};
  bool m_backendReady{false};
  bool m_anisetteReady{false};
  bool m_mapReady{false};
  bool m_dashboardMapReady{false};
  bool m_windowLoaded{false};
  bool m_mainMapInitStarted{false};
  bool m_dashboardMapInitStarted{false};
  bool m_scanStarted{false};
  bool m_demoMode{false};
  bool m_rebuildingBluetoothList{false};
  std::atomic_bool m_closing{false};
  std::atomic_bool m_bluetoothRenderQueued{false};
  std::atomic_bool m_servicePollBusy{false};
  std::atomic_bool m_reportRefreshBusy{false};
  std::mutex m_pendingBluetoothMutex;
  std::vector<FindMyFlipper::Models::BluetoothDevice> m_pendingBluetoothDevices;
  std::wstring m_accent{L"#FF5A00"};
  std::wstring m_currentPage{L"map"};
  std::wstring m_keyRawContent;
  std::vector<FindMyFlipper::Models::BluetoothDevice> m_bluetoothDevices;
  std::vector<FindMyFlipper::Models::LocationReport> m_reports;
  std::vector<FindMyFlipper::Models::LocationReport> m_visibleReports;
  Microsoft::UI::Dispatching::DispatcherQueue m_dispatcher{nullptr};
  Microsoft::UI::Dispatching::DispatcherQueueTimer m_servicePollTimer{nullptr};
  FindMyFlipper::Services::ProfileStore m_store;
  FindMyFlipper::Services::BackendManager m_backend;
  FindMyFlipper::Services::BluetoothManager m_bluetooth;
  FindMyFlipper::Services::TrayIconService m_tray;
  Microsoft::UI::Xaml::Controls::TextBlock m_firmwareValue{nullptr};
  Microsoft::UI::Xaml::Controls::TextBlock m_bluetoothMacValue{nullptr};
  Microsoft::UI::Xaml::Controls::TextBlock m_alertSupportValue{nullptr};
  Microsoft::UI::Xaml::Controls::TextBlock m_flipperUsbDetail{nullptr};
  Microsoft::UI::Xaml::Controls::TextBlock m_activeKeyMatch{nullptr};
  Microsoft::UI::Xaml::Controls::Button m_refreshFlipperButton{nullptr};
  Microsoft::UI::Xaml::Controls::Button m_importFlipperKeysButton{nullptr};
  Microsoft::UI::Xaml::Controls::ComboBox m_markerPicker{nullptr};
  Microsoft::UI::Xaml::Controls::Button m_mapActionsButton{nullptr};
};
} // namespace winrt::FindMyFlipperWindows::implementation

namespace winrt::FindMyFlipperWindows::factory_implementation {
struct MainWindow
    : MainWindowT<MainWindow, implementation::MainWindow> {};
} // namespace winrt::FindMyFlipperWindows::factory_implementation
