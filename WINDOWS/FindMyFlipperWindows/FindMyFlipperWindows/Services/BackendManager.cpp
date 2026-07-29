#include "pch.h"
#include "BackendManager.h"

using FindMyFlipper::Services::BackendManager;
using FindMyFlipper::Services::ServiceHealth;

namespace {
constexpr wchar_t Host[] = L"127.0.0.1";
constexpr INTERNET_PORT Port = 8765;

std::filesystem::path ExecutableDirectory() {
  std::wstring path(32768, L'\0');
  auto length =
      GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  path.resize(length);
  return std::filesystem::path(path).parent_path();
}

void CloseProcess(PROCESS_INFORMATION &process) {
  if (process.hThread)
    CloseHandle(process.hThread);
  if (process.hProcess)
    CloseHandle(process.hProcess);
  process = {};
}

struct HttpHandle {
  HINTERNET value{};
  explicit HttpHandle(HINTERNET handle) : value(handle) {}
  ~HttpHandle() {
    if (value)
      WinHttpCloseHandle(value);
  }
  HttpHandle(HttpHandle const &) = delete;
  HttpHandle &operator=(HttpHandle const &) = delete;
  operator HINTERNET() const noexcept { return value; }
};

std::filesystem::path FindOnPath(wchar_t const *filename) {
  std::wstring buffer(32768, L'\0');
  auto length = SearchPathW(nullptr, filename, nullptr,
                            static_cast<DWORD>(buffer.size()), buffer.data(),
                            nullptr);
  if (length == 0 || length >= buffer.size())
    return {};
  buffer.resize(length);
  return buffer;
}
} // namespace

BackendManager::BackendManager() : m_root(ExecutableDirectory()) {
  CreateProcessJob();
}

BackendManager::~BackendManager() {
  StopOwnedProcesses();
}

bool BackendManager::CreateProcessJob() {
  m_processJob = CreateJobObjectW(nullptr, nullptr);
  if (!m_processJob)
    return false;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(m_processJob, JobObjectExtendedLimitInformation,
                               &limits, sizeof(limits))) {
    CloseHandle(m_processJob);
    m_processJob = nullptr;
    return false;
  }
  return true;
}

void BackendManager::StopOwnedProcesses() {
  if (m_processJob) {
    TerminateJobObject(m_processJob, 0);
    CloseHandle(m_processJob);
    m_processJob = nullptr;
  } else if (m_backend.hProcess &&
             WaitForSingleObject(m_backend.hProcess, 0) == WAIT_TIMEOUT) {
    TerminateProcess(m_backend.hProcess, 0);
  }
  CloseProcess(m_backend);
  CloseProcess(m_anisette);
}

ServiceHealth BackendManager::EnsureServices() {
  std::scoped_lock lock(m_mutex);
  ServiceHealth result;
  if (!IsHealthy()) {
    auto executable = m_root / L"FindMyFlipperBackend.exe";
    if (!std::filesystem::exists(executable))
      executable = m_root / L"runtime" / L"FindMyFlipperBackend.exe";
    if (!std::filesystem::exists(executable)) {
      // Debug output lives at <solution>/build/<platform>/<configuration>.
      // Use the checked-in Python entry point only for that development tree;
      // portable and installed builds continue to require the frozen EXE.
      auto source = m_root.parent_path().parent_path().parent_path() /
                    L"Backend" / L"backend_entry.py";
      auto python = FindOnPath(L"py.exe");
      std::wstring prefix = L"-3 ";
      if (python.empty()) {
        python = FindOnPath(L"python.exe");
        prefix.clear();
      }
      if (!std::filesystem::exists(source) || python.empty()) {
        result.message = L"The bundled FindMyFlipper backend is missing. "
                         L"Reinstall the app, or install Python for a Debug build.";
        return result;
      }
      if (!StartProcess(python, prefix + L"\"" + source.wstring() + L"\"",
                        m_backend, source.parent_path())) {
        result.message = L"Windows could not start the development backend.";
        return result;
      }
    } else if (!StartProcess(executable, L"", m_backend)) {
      result.message =
          L"Windows could not start the bundled FindMyFlipper backend.";
      return result;
    }
    for (int attempt = 0; attempt < 150 && !IsHealthy(); ++attempt)
      Sleep(200);
  }
  result.backendReady = IsHealthy();
  if (!result.backendReady) {
    result.message =
        L"The local backend did not become healthy on 127.0.0.1:8765.";
    return result;
  }

  // Backend readiness must stay independent of Docker and anisette. Starting
  // anisette can take minutes while Docker Desktop boots. Coupling it to this
  // method serialized every unrelated request (key generation, USB access,
  // reports, and diagnostics) behind that startup and made the desktop app
  // appear hung. Apple sign-in starts anisette explicitly when it is needed.
  result.anisetteReady = false;
  result.message = L"Local backend is ready.";
  try {
    auto response = Get(L"/auth/anisette-status");
    result.anisetteReady =
        response.find(L"\"state\":\"running\"") != std::wstring::npos ||
        response.find(L"\"state\": \"running\"") != std::wstring::npos;
  } catch (...) {
    // Anisette status is supplemental. It must never make a healthy local
    // backend unavailable to features that do not use Apple authentication.
  }
  return result;
}

void BackendManager::Restart() {
  std::scoped_lock lock(m_mutex);
  StopOwnedProcesses();
  CreateProcessJob();
  EnsureServices();
}

bool BackendManager::IsHealthy() const {
  try {
    auto response = Get(L"/health");
    return response.find(L"\"status\":\"ok\"") != std::wstring::npos ||
           response.find(L"\"status\": \"ok\"") != std::wstring::npos;
  } catch (...) {
    return false;
  }
}

bool BackendManager::StartProcess(std::filesystem::path const &executable,
                                  std::wstring const &arguments,
                                  PROCESS_INFORMATION &process,
                                  std::filesystem::path const &workingDirectory) {
  if (process.hProcess &&
      WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT)
    return true;
  CloseProcess(process);
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  auto command = L"\"" + executable.wstring() + L"\"" +
                 (arguments.empty() ? L"" : L" " + arguments);
  DWORD flags = CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT;
  if (m_processJob)
    flags |= CREATE_SUSPENDED;
  auto directory = workingDirectory.empty() ? executable.parent_path()
                                             : workingDirectory;
  if (!CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr,
                      FALSE, flags, nullptr, directory.c_str(), &startup,
                      &process))
    return false;
  if (m_processJob && !AssignProcessToJobObject(m_processJob, process.hProcess)) {
    TerminateProcess(process.hProcess, ERROR_ACCESS_DENIED);
    CloseProcess(process);
    return false;
  }
  if (m_processJob && ResumeThread(process.hThread) == static_cast<DWORD>(-1)) {
    TerminateProcess(process.hProcess, GetLastError());
    CloseProcess(process);
    return false;
  }
  return true;
}

std::wstring BackendManager::Get(std::wstring const &path) const {
  return Request(L"GET", path, L"");
}
std::wstring BackendManager::Post(std::wstring const &path,
                                  std::wstring const &body) const {
  return Request(L"POST", path, body);
}

std::wstring BackendManager::Request(std::wstring const &method,
                                     std::wstring const &path,
                                     std::wstring const &body) const {
  HttpHandle session{WinHttpOpen(L"FindMyFlipper/1.0",
                                 WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, nullptr,
                                 nullptr, 0)};
  if (!session.value)
    winrt::throw_last_error();
  WinHttpSetTimeouts(session, 3000, 3000, 3000, 30000);
  HttpHandle connection{WinHttpConnect(session, Host, Port, 0)};
  if (!connection.value)
    winrt::throw_last_error();
  HttpHandle request{
      WinHttpOpenRequest(connection, method.c_str(), path.c_str(), nullptr,
                         WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0)};
  if (!request.value)
    winrt::throw_last_error();
  std::string utf8 = winrt::to_string(body);
  auto headers =
      L"Content-Type: application/json\r\nAccept: application/json\r\n";
  if (!WinHttpSendRequest(request, headers, static_cast<DWORD>(-1L),
                          utf8.empty() ? WINHTTP_NO_REQUEST_DATA : utf8.data(),
                          static_cast<DWORD>(utf8.size()),
                          static_cast<DWORD>(utf8.size()), 0) ||
      !WinHttpReceiveResponse(request, nullptr)) {
    winrt::throw_last_error();
  }
  DWORD status{};
  DWORD statusSize = sizeof(status);
  WinHttpQueryHeaders(request,
                      WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                      WINHTTP_HEADER_NAME_BY_INDEX, &status, &statusSize,
                      WINHTTP_NO_HEADER_INDEX);
  std::string response;
  for (;;) {
    DWORD available{};
    if (!WinHttpQueryDataAvailable(request, &available) || available == 0)
      break;
    auto offset = response.size();
    response.resize(offset + available);
    DWORD read{};
    if (!WinHttpReadData(request, response.data() + offset, available, &read))
      winrt::throw_last_error();
    response.resize(offset + read);
  }
  if (status >= 400)
    throw std::runtime_error("Backend returned HTTP " + std::to_string(status));
  return winrt::to_hstring(response).c_str();
}
