#pragma once

namespace FindMyFlipper::Services {
class CredentialService final {
public:
  static std::wstring TargetFor(std::wstring const &keyId);
  static void SavePrivateKey(std::wstring const &keyId,
                             std::wstring const &privateKey);
  static std::optional<std::wstring> LoadPrivateKey(std::wstring const &keyId);
  static void DeletePrivateKey(std::wstring const &keyId);
};
} // namespace FindMyFlipper::Services
