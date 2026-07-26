#pragma once

namespace FindMyFlipper::Services {
struct ServiceHealth {
  bool backendReady{false};
  bool anisetteReady{false};
  std::wstring message;
};

class BackendManager final {
public:
  BackendManager();
  ~BackendManager();
  ServiceHealth EnsureServices();
  std::wstring Get(std::wstring const &path) const;
  std::wstring Post(std::wstring const &path,
                    std::wstring const &jsonBody) const;
  void Restart();
  bool IsHealthy() const;

private:
  bool CreateProcessJob();
  void StopOwnedProcesses();
  bool StartProcess(std::filesystem::path const &executable,
                    std::wstring const &arguments,
                    PROCESS_INFORMATION &process,
                    std::filesystem::path const &workingDirectory = {});
  std::wstring Request(std::wstring const &method, std::wstring const &path,
                       std::wstring const &body) const;
  std::filesystem::path m_root;
  HANDLE m_processJob{};
  PROCESS_INFORMATION m_backend{};
  PROCESS_INFORMATION m_anisette{};
  mutable std::recursive_mutex m_mutex;
};
} // namespace FindMyFlipper::Services
