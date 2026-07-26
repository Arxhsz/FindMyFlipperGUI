#pragma once

namespace FindMyFlipper::Services {
class TrayIconService final {
public:
  using Command = std::function<void(unsigned)>;
  TrayIconService();
  ~TrayIconService();
  bool Initialize(std::filesystem::path const &iconPath, Command command);
  void UpdateTooltip(std::wstring const &profileName, bool connected,
                     int battery);

  static constexpr unsigned OpenDashboard = 1001;
  static constexpr unsigned PlayAlert = 1002;
  static constexpr unsigned RefreshReports = 1003;
  static constexpr unsigned OpenSettings = 1004;
  static constexpr unsigned Quit = 1005;

private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wParam,
                                     LPARAM lParam);
  void ShowMenu();
  HWND m_window{};
  HICON m_icon{};
  NOTIFYICONDATAW m_data{};
  Command m_command;
};
} // namespace FindMyFlipper::Services
