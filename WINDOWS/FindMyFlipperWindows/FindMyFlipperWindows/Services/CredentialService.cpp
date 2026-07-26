#include "pch.h"
#include "CredentialService.h"

using FindMyFlipper::Services::CredentialService;

std::wstring CredentialService::TargetFor(std::wstring const &keyId) {
  return L"FindMyFlipper/private-key/" + keyId;
}

void CredentialService::SavePrivateKey(std::wstring const &keyId,
                                       std::wstring const &privateKey) {
  auto bytes = winrt::to_string(privateKey);
  CREDENTIALW credential{};
  auto target = TargetFor(keyId);
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = target.data();
  credential.CredentialBlobSize = static_cast<DWORD>(bytes.size());
  credential.CredentialBlob = reinterpret_cast<BYTE *>(bytes.data());
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  credential.UserName = const_cast<wchar_t *>(L"FindMyFlipper");
  if (!CredWriteW(&credential, 0)) {
    winrt::throw_last_error();
  }
}

std::optional<std::wstring>
CredentialService::LoadPrivateKey(std::wstring const &keyId) {
  PCREDENTIALW credential{};
  auto target = TargetFor(keyId);
  if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &credential)) {
    if (GetLastError() == ERROR_NOT_FOUND)
      return std::nullopt;
    winrt::throw_last_error();
  }

  std::string bytes(reinterpret_cast<char const *>(credential->CredentialBlob),
                    reinterpret_cast<char const *>(credential->CredentialBlob) +
                        credential->CredentialBlobSize);
  CredFree(credential);
  return winrt::to_hstring(bytes).c_str();
}

void CredentialService::DeletePrivateKey(std::wstring const &keyId) {
  auto target = TargetFor(keyId);
  if (!CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0) &&
      GetLastError() != ERROR_NOT_FOUND) {
    winrt::throw_last_error();
  }
}
