#include "pch.h"
#include "ProfileStore.h"

using namespace winrt::Windows::Data::Json;
using namespace FindMyFlipper::Models;
using FindMyFlipper::Services::ProfileStore;

namespace {
bool DemoModeEnabled() noexcept {
  wchar_t value[8]{};
  return GetEnvironmentVariableW(L"FINDMYFLIPPER_DEMO", value,
                                 static_cast<DWORD>(std::size(value))) > 0 &&
         value[0] == L'1';
}

std::wstring StringOr(JsonObject const &object, wchar_t const *key,
                      std::wstring const &fallback = L"") {
  return object.HasKey(key) ? std::wstring(object.GetNamedString(key))
                            : fallback;
}
} // namespace

ProfileStore::ProfileStore() {
  wchar_t *localAppData{};
  size_t ignored{};
  _wdupenv_s(&localAppData, &ignored, L"LOCALAPPDATA");
  auto root = localAppData ? std::filesystem::path(localAppData)
                           : std::filesystem::temp_directory_path();
  free(localAppData);
  // Demo sessions are deliberately isolated from real profiles and secrets.
  root /= DemoModeEnabled() ? L"FindMyFlipperDemo" : L"FindMyFlipper";
  std::filesystem::create_directories(root);
  m_path = root / L"profile.json";
  Load();
}

bool ProfileStore::OnboardingComplete() const noexcept {
  return m_onboardingComplete;
}
FlipperProfile const &ProfileStore::Profile() const noexcept {
  return m_profile;
}
KeyIdentity const &ProfileStore::Key() const noexcept { return m_key; }

void ProfileStore::SetOnboardingComplete(bool complete) {
  m_onboardingComplete = complete;
  Save();
}
void ProfileStore::UpdateProfile(FlipperProfile const &profile) {
  m_profile = profile;
  Save();
}
void ProfileStore::UpdateKey(KeyIdentity const &key) {
  m_key = key;
  Save();
}

void ProfileStore::Reset() {
  m_onboardingComplete = false;
  m_profile = {};
  m_key = {};
  std::error_code ignored;
  std::filesystem::remove(m_path, ignored);
}

void ProfileStore::Load() {
  if (!std::filesystem::exists(m_path))
    return;
  try {
    std::ifstream stream(m_path, std::ios::binary);
    std::string raw((std::istreambuf_iterator<char>(stream)), {});
    auto root = JsonObject::Parse(winrt::to_hstring(raw));
    m_onboardingComplete = root.GetNamedBoolean(L"onboardingComplete", false);
    auto profile = root.GetNamedObject(L"profile", JsonObject{});
    m_profile.id = StringOr(profile, L"id");
    m_profile.displayName = StringOr(profile, L"displayName", L"My Flipper");
    m_profile.keyIdentityId = StringOr(profile, L"keyIdentityId");
    m_profile.generatedFindMyMac = StringOr(profile, L"generatedFindMyMac");
    m_profile.bluetoothDeviceId = StringOr(profile, L"bluetoothDeviceId");
    m_profile.bluetoothName = StringOr(profile, L"bluetoothName");
    m_profile.bluetoothMac = StringOr(profile, L"bluetoothMac");
    m_profile.bluetoothMacRandom =
        profile.GetNamedBoolean(L"bluetoothMacRandom", false);
    m_profile.firmwareVersion = StringOr(profile, L"firmwareVersion");
    m_profile.batteryLevel =
        static_cast<int>(profile.GetNamedNumber(L"batteryLevel", -1));
    m_profile.rssi = static_cast<int>(profile.GetNamedNumber(L"rssi", -127));
    m_profile.autoReconnect = profile.GetNamedBoolean(L"autoReconnect", true);
    m_profile.flipperIconStyle =
        StringOr(profile, L"flipperIconStyle", L"white");
    auto key = root.GetNamedObject(L"key", JsonObject{});
    m_key.id = StringOr(key, L"id");
    m_key.sourceFileName = StringOr(key, L"sourceFileName");
    m_key.hashedAdvertisementKey = StringOr(key, L"hashedAdvertisementKey");
    m_key.generatedFindMyMac = StringOr(key, L"generatedFindMyMac");
    m_key.payload = StringOr(key, L"payload");
    m_key.credentialTarget = StringOr(key, L"credentialTarget");
  } catch (...) {
    m_onboardingComplete = false;
  }
}

void ProfileStore::Save() const {
  JsonObject profile;
  profile.SetNamedValue(L"id", JsonValue::CreateStringValue(m_profile.id));
  profile.SetNamedValue(L"displayName",
                        JsonValue::CreateStringValue(m_profile.displayName));
  profile.SetNamedValue(L"keyIdentityId",
                        JsonValue::CreateStringValue(m_profile.keyIdentityId));
  profile.SetNamedValue(
      L"generatedFindMyMac",
      JsonValue::CreateStringValue(m_profile.generatedFindMyMac));
  profile.SetNamedValue(L"bluetoothDeviceId", JsonValue::CreateStringValue(
                                                  m_profile.bluetoothDeviceId));
  profile.SetNamedValue(L"bluetoothName",
                        JsonValue::CreateStringValue(m_profile.bluetoothName));
  profile.SetNamedValue(L"bluetoothMac",
                        JsonValue::CreateStringValue(m_profile.bluetoothMac));
  profile.SetNamedValue(
      L"bluetoothMacRandom",
      JsonValue::CreateBooleanValue(m_profile.bluetoothMacRandom));
  profile.SetNamedValue(
      L"firmwareVersion",
      JsonValue::CreateStringValue(m_profile.firmwareVersion));
  profile.SetNamedValue(L"batteryLevel",
                        JsonValue::CreateNumberValue(m_profile.batteryLevel));
  profile.SetNamedValue(L"rssi", JsonValue::CreateNumberValue(m_profile.rssi));
  profile.SetNamedValue(L"autoReconnect",
                        JsonValue::CreateBooleanValue(m_profile.autoReconnect));
  profile.SetNamedValue(
      L"flipperIconStyle",
      JsonValue::CreateStringValue(m_profile.flipperIconStyle));

  JsonObject key;
  key.SetNamedValue(L"id", JsonValue::CreateStringValue(m_key.id));
  key.SetNamedValue(L"sourceFileName",
                    JsonValue::CreateStringValue(m_key.sourceFileName));
  key.SetNamedValue(L"hashedAdvertisementKey",
                    JsonValue::CreateStringValue(m_key.hashedAdvertisementKey));
  key.SetNamedValue(L"generatedFindMyMac",
                    JsonValue::CreateStringValue(m_key.generatedFindMyMac));
  key.SetNamedValue(L"payload", JsonValue::CreateStringValue(m_key.payload));
  key.SetNamedValue(L"credentialTarget",
                    JsonValue::CreateStringValue(m_key.credentialTarget));

  JsonObject root;
  root.SetNamedValue(L"onboardingComplete",
                     JsonValue::CreateBooleanValue(m_onboardingComplete));
  root.SetNamedValue(L"profile", profile);
  root.SetNamedValue(L"key", key);
  std::ofstream stream(m_path, std::ios::binary | std::ios::trunc);
  stream << winrt::to_string(root.Stringify());
}
