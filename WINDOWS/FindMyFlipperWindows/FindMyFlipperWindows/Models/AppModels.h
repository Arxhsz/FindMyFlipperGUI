#pragma once

namespace FindMyFlipper::Models {
enum class ThemeOption {
  Light,
  Dark,
  System,
  Sunset,
  Ocean,
  Forest,
  Purple,
};

struct ThemeColors {
  std::wstring accent;
  std::wstring accentDark;
  std::wstring accentSoft;
  std::wstring background;
  std::wstring sidebar;
  std::wstring card;
  std::wstring border;
  std::wstring primaryText;
  std::wstring secondaryText;
};

inline ThemeColors ColorsFor(ThemeOption theme) {
  switch (theme) {
  case ThemeOption::Dark:
    return {L"#FF6A1A", L"#E84D00", L"#2A1A10", L"#0F1115", L"#14171D",
            L"#1B1F27", L"#2A2F3A", L"#F9FAFB", L"#A1A1AA"};
  case ThemeOption::Sunset:
    return {L"#F97316", L"#EA580C", L"#2D1B0E", L"#1A0E0A", L"#231208",
            L"#2D1B0E", L"#6B2D1A", L"#FEF3C7", L"#D97706"};
  case ThemeOption::Ocean:
    return {L"#0EA5E9", L"#0284C7", L"#0C1F2F", L"#070F18", L"#0B1825",
            L"#0F2133", L"#164E63", L"#E0F2FE", L"#7DD3FC"};
  case ThemeOption::Forest:
    return {L"#22C55E", L"#16A34A", L"#0D1F11", L"#081008", L"#0C160C",
            L"#111E11", L"#1B3A1B", L"#DCFCE7", L"#86EFAC"};
  case ThemeOption::Purple:
    return {L"#A855F7", L"#9333EA", L"#1B0D2A", L"#0D0814", L"#140B1E",
            L"#1B0D2A", L"#3B1F5E", L"#F5F3FF", L"#C4B5FD"};
  default:
    return {L"#FF5A00", L"#E84D00", L"#FFF1E8", L"#F7F7F5", L"#FFFFFF",
            L"#FFFFFF", L"#E9E5DF", L"#1F2328", L"#6B7280"};
  }
}

struct KeyIdentity {
  std::wstring id;
  std::wstring sourceFileName;
  std::wstring hashedAdvertisementKey;
  std::wstring generatedFindMyMac;
  std::wstring payload;
  std::wstring credentialTarget;
};

struct FlipperProfile {
  std::wstring id;
  std::wstring displayName{L"My Flipper"};
  std::wstring keyIdentityId;
  std::wstring generatedFindMyMac;
  std::wstring bluetoothDeviceId;
  std::wstring bluetoothName;
  std::wstring bluetoothMac;
  bool bluetoothMacRandom{false};
  std::wstring firmwareVersion;
  int batteryLevel{-1};
  int rssi{-127};
  bool connected{false};
  bool autoReconnect{true};
  std::wstring flipperIconStyle{L"white"};
};

struct BluetoothDevice {
  uint64_t address{};
  bool randomAddress{false};
  bool connectable{false};
  bool paired{false};
  std::wstring id;
  std::wstring name{L"Unknown Device"};
  int rssi{-127};
  bool likelyFlipper{false};
  uint64_t discoveryOrder{};
};

struct LocationReport {
  std::wstring id;
  int64_t timestamp{};
  double latitude{};
  double longitude{};
  int confidence{};
  int status{};
  std::wstring source{L"Find My Network"};
};
} // namespace FindMyFlipper::Models
