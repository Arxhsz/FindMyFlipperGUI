#include "pch.h"
#include "TrayIconService.h"

using FindMyFlipper::Services::TrayIconService;

namespace {
constexpr UINT TrayMessage = WM_APP + 41;
constexpr wchar_t TrayWindowClass[] = L"FindMyFlipperTrayWindow";
} // namespace

TrayIconService::TrayIconService() = default;

TrayIconService::~TrayIconService() {
  if (m_window)
    Shell_NotifyIconW(NIM_DELETE, &m_data);
  if (m_icon)
    DestroyIcon(m_icon);
  if (m_window)
    DestroyWindow(m_window);
}

bool TrayIconService::Initialize(std::filesystem::path const &iconPath,
                                 Command command) {
  m_command = std::move(command);
  WNDCLASSEXW windowClass{sizeof(WNDCLASSEXW)};
  windowClass.lpfnWndProc = WindowProc;
  windowClass.hInstance = GetModuleHandleW(nullptr);
  windowClass.lpszClassName = TrayWindowClass;
  RegisterClassExW(&windowClass);
  m_window =
      CreateWindowExW(0, TrayWindowClass, L"FindMyFlipper", 0, 0, 0, 0, 0,
                      HWND_MESSAGE, nullptr, GetModuleHandleW(nullptr), this);
  if (!m_window)
    return false;
  m_icon = static_cast<HICON>(LoadImageW(nullptr, iconPath.c_str(), IMAGE_ICON,
                                         16, 16, LR_LOADFROMFILE));
  if (!m_icon)
    m_icon = LoadIconW(nullptr, IDI_APPLICATION);
  m_data.cbSize = sizeof(m_data);
  m_data.hWnd = m_window;
  m_data.uID = 1;
  m_data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  m_data.uCallbackMessage = TrayMessage;
  m_data.hIcon = m_icon;
  wcscpy_s(m_data.szTip, L"FindMyFlipper");
  return Shell_NotifyIconW(NIM_ADD, &m_data) != FALSE;
}

void TrayIconService::UpdateTooltip(std::wstring const &profileName,
                                    bool connected, int battery) {
  auto text =
      profileName + L" - " + (connected ? L"Connected" : L"Disconnected");
  if (battery >= 0)
    text += L" - " + std::to_wstring(battery) + L"%";
  wcsncpy_s(m_data.szTip, text.c_str(), _TRUNCATE);
  Shell_NotifyIconW(NIM_MODIFY, &m_data);
}

LRESULT CALLBACK TrayIconService::WindowProc(HWND window, UINT message,
                                             WPARAM wParam, LPARAM lParam) {
  auto self = reinterpret_cast<TrayIconService *>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto create = reinterpret_cast<CREATESTRUCTW *>(lParam);
    self = static_cast<TrayIconService *>(create->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (message == TrayMessage && self &&
      (LOWORD(lParam) == WM_CONTEXTMENU || LOWORD(lParam) == WM_LBUTTONUP)) {
    self->ShowMenu();
    return 0;
  }
  if (message == WM_COMMAND && self) {
    if (self->m_command)
      self->m_command(LOWORD(wParam));
    return 0;
  }
  return DefWindowProcW(window, message, wParam, lParam);
}

void TrayIconService::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, OpenDashboard, L"Open Dashboard");
  AppendMenuW(menu, MF_STRING, PlayAlert, L"Play Alert");
  AppendMenuW(menu, MF_STRING, RefreshReports, L"Refresh Reports");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, OpenSettings, L"Settings");
  AppendMenuW(menu, MF_STRING, Quit, L"Quit FindMyFlipper");
  POINT point{};
  GetCursorPos(&point);
  SetForegroundWindow(m_window);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON, point.x, point.y, 0, m_window, nullptr);
  DestroyMenu(menu);
}
