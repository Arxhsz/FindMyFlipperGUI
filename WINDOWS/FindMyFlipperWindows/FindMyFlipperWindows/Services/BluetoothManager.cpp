#include "pch.h"
#include "BluetoothManager.h"

using namespace winrt;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Bluetooth::Advertisement;
using namespace Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace Windows::Devices::Enumeration;
using namespace Windows::Storage::Streams;
using FindMyFlipper::Services::BluetoothManager;
using BluetoothDeviceRecord = FindMyFlipper::Models::BluetoothDevice;

namespace {
guid const BatteryService{0x0000180F,
                          0x0000,
                          0x1000,
                          {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
guid const BatteryLevel{0x00002A19,
                        0x0000,
                        0x1000,
                        {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
guid const DeviceInformationService{
    0x0000180A, 0x0000, 0x1000,
    {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
guid const FirmwareRevision{
    0x00002A26, 0x0000, 0x1000,
    {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
guid const SoftwareRevision{
    0x00002A28, 0x0000, 0x1000,
    {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
guid const ImmediateAlert{0x00001802,
                          0x0000,
                          0x1000,
                          {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
guid const AlertLevel{0x00002A06,
                      0x0000,
                      0x1000,
                      {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
guid const FindMyAlert{0x19ED82AE,
                       0xED21,
                       0x4C9D,
                       {0x41, 0x45, 0x22, 0x8E, 0x62, 0xFE, 0x00, 0x00}};

bool IsLikelyFlipper(std::wstring const &name) {
  auto lowered = name;
  std::transform(lowered.begin(), lowered.end(), lowered.begin(), towlower);
  return lowered.find(L"flipper") != std::wstring::npos ||
         lowered.rfind(L"fz", 0) == 0;
}

void SortDevices(std::vector<BluetoothDeviceRecord> &devices) {
  std::stable_sort(devices.begin(), devices.end(), [](auto const &a, auto const &b) {
    if (a.paired != b.paired)
      return a.paired;
    if (a.likelyFlipper != b.likelyFlipper)
      return a.likelyFlipper;
    return a.discoveryOrder < b.discoveryOrder;
  });
}
} // namespace

BluetoothManager::BluetoothManager() {
  m_watcher = BluetoothLEAdvertisementWatcher();
  m_watcher.ScanningMode(BluetoothLEScanningMode::Active);
  m_receivedToken =
      m_watcher.Received({this, &BluetoothManager::OnAdvertisement});
}

BluetoothManager::~BluetoothManager() {
  StopScan();
  if (m_watcher)
    m_watcher.Received(m_receivedToken);
  {
    std::scoped_lock lock(m_callbackMutex);
    m_devicesChanged = {};
    m_statusChanged = {};
  }
  Disconnect();
}

void BluetoothManager::SetDevicesChanged(DevicesChanged callback) {
  std::scoped_lock lock(m_callbackMutex);
  m_devicesChanged = std::move(callback);
}
void BluetoothManager::SetStatusChanged(StatusChanged callback) {
  std::scoped_lock lock(m_callbackMutex);
  m_statusChanged = std::move(callback);
}

void BluetoothManager::NotifyStatus(std::wstring const &message,
                                    bool connected, int battery) noexcept {
  try {
    StatusChanged callback;
    {
      std::scoped_lock lock(m_callbackMutex);
      callback = m_statusChanged;
    }
    if (callback)
      callback(message, connected, battery);
  } catch (...) {
    OutputDebugStringW(L"[FindMyFlipper] Bluetooth status callback failed.\n");
  }
}

fire_and_forget BluetoothManager::StartScan() {
  try {
    StopScan();
    auto adapter = co_await BluetoothAdapter::GetDefaultAsync();
    if (!adapter) {
      m_adapterAvailable = false;
      NotifyStatus(L"Bluetooth is unavailable. In a VM, attach a USB BLE "
                   L"adapter or enable Bluetooth sharing.",
                   false, -1);
      co_return;
    }
    m_adapterAvailable = true;
    {
      std::scoped_lock lock(m_mutex);
      m_devices.clear();
    }
    m_nextDiscoveryOrder = 1;

    // Advertisement-only scans often show a rotating anonymous address while
    // the stable, paired Flipper identity remains in Windows' device catalog.
    // Merge paired Flipper devices into the same list so reconnects do not
    // depend on a transient advertisement address.
    try {
      auto paired = co_await DeviceInformation::FindAllAsync(
          BluetoothLEDevice::GetDeviceSelectorFromPairingState(true));
      for (auto const &info : paired) {
        std::wstring name = info.Name().c_str();
        if (name.empty())
          continue;
        auto device = co_await BluetoothLEDevice::FromIdAsync(info.Id());
        if (!device)
          continue;
        BluetoothDeviceRecord record;
        record.address = device.BluetoothAddress();
        record.randomAddress =
            device.BluetoothAddressType() == BluetoothAddressType::Random;
        record.connectable = true;
        record.paired = true;
        record.id = info.Id().c_str();
        record.name = name;
        record.rssi = -50;
        record.likelyFlipper = IsLikelyFlipper(name);
        record.discoveryOrder = m_nextDiscoveryOrder++;
        std::vector<BluetoothDeviceRecord> snapshot;
        {
          std::scoped_lock lock(m_mutex);
          m_devices[record.address] = record;
          for (auto const &[_, candidate] : m_devices)
            snapshot.push_back(candidate);
        }
        SortDevices(snapshot);
        DevicesChanged callback;
        {
          std::scoped_lock callbackLock(m_callbackMutex);
          callback = m_devicesChanged;
        }
        if (callback) {
          try {
            callback(snapshot);
          } catch (...) {
            OutputDebugStringW(
                L"[FindMyFlipper] Paired-device callback failed.\n");
          }
        }
      }
    } catch (hresult_error const &) {
      // Active advertisement scanning remains useful when the paired-device
      // catalog is unavailable or Bluetooth privacy blocks enumeration.
    }
    m_watcher.Start();
    NotifyStatus(L"Scanning. Paired and named devices stay in a fixed order.",
                 false, -1);
  } catch (hresult_error const &error) {
    NotifyStatus(L"Bluetooth scan could not start: " +
                     std::wstring(error.message()),
                 false, -1);
  } catch (std::exception const &error) {
    NotifyStatus(L"Bluetooth scan could not start: " +
                     std::wstring(winrt::to_hstring(error.what())),
                 false, -1);
  } catch (...) {
    NotifyStatus(L"Bluetooth scan could not start because Windows returned an unknown error.",
                 false, -1);
  }
}

void BluetoothManager::StopScan() {
  if (m_watcher &&
      m_watcher.Status() == BluetoothLEAdvertisementWatcherStatus::Started)
    m_watcher.Stop();
}

void BluetoothManager::OnAdvertisement(
    BluetoothLEAdvertisementWatcher const &,
    BluetoothLEAdvertisementReceivedEventArgs const &args) {
  BluetoothDeviceRecord record;
  record.address = args.BluetoothAddress();
  record.randomAddress =
      args.BluetoothAddressType() == BluetoothAddressType::Random;
  record.connectable = args.IsConnectable();
  record.rssi = args.RawSignalStrengthInDBm();
  record.name = args.Advertisement().LocalName().empty()
                    ? L"Unknown Device"
                    : args.Advertisement().LocalName().c_str();
  record.likelyFlipper = IsLikelyFlipper(record.name);
  {
    std::scoped_lock lock(m_mutex);
    if (auto existing = m_devices.find(record.address);
        existing != m_devices.end()) {
      record.discoveryOrder = existing->second.discoveryOrder;
      record.paired = existing->second.paired;
      record.id = existing->second.id;
      if (record.name == L"Unknown Device" &&
          existing->second.name != L"Unknown Device")
        record.name = existing->second.name;
      record.likelyFlipper = record.likelyFlipper || existing->second.likelyFlipper;
    } else {
      record.discoveryOrder = m_nextDiscoveryOrder++;
    }
    m_devices[record.address] = record;

    // Anonymous advertisements can rotate addresses rapidly. Keep enough
    // history for troubleshooting without allowing an unbounded device map.
    while (m_devices.size() > 80) {
      auto oldest = m_devices.end();
      for (auto candidate = m_devices.begin(); candidate != m_devices.end();
           ++candidate) {
        auto const &device = candidate->second;
        auto unnamed = device.name.empty() || device.name == L"Unknown Device";
        if (device.paired || !unnamed)
          continue;
        if (oldest == m_devices.end() ||
            device.discoveryOrder < oldest->second.discoveryOrder)
          oldest = candidate;
      }
      if (oldest == m_devices.end())
        break;
      m_devices.erase(oldest);
    }
  }

  // Active BLE scanners can receive hundreds of updates per second. Publishing
  // every packet floods the WinUI dispatcher and made simple toggle/click
  // actions appear to crash. Four UI snapshots per second is responsive while
  // keeping the message queue bounded.
  auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
                 std::chrono::steady_clock::now().time_since_epoch())
                 .count();
  auto last = m_lastAdvertisementPublishMs.load();
  if (now - last < 250 ||
      !m_lastAdvertisementPublishMs.compare_exchange_strong(last, now))
    return;

  std::vector<BluetoothDeviceRecord> snapshot;
  {
    std::scoped_lock lock(m_mutex);
    for (auto const &[_, device] : m_devices)
      snapshot.push_back(device);
  }
  SortDevices(snapshot);
  DevicesChanged callback;
  {
    std::scoped_lock callbackLock(m_callbackMutex);
    callback = m_devicesChanged;
  }
  if (callback) {
    try {
      callback(snapshot);
    } catch (...) {
      OutputDebugStringW(
          L"[FindMyFlipper] Advertisement callback failed.\n");
    }
  }
}

fire_and_forget BluetoothManager::Connect(BluetoothDeviceRecord selected,
                                          bool reconnect) {
  auto generation = ++m_connectionGeneration;
  if (!reconnect) {
    m_pendingAlert = false;
    if (m_connectedAddress != 0 && m_connectedAddress != selected.address)
      m_alertSupported = false;
  }
  m_connectedAddress = selected.address;
  m_connectedAddressRandom = selected.randomAddress;
  m_currentRssi = selected.rssi;
  m_manualDisconnect = false;
  m_reconnectScheduled = false;
  if (m_device && m_connectionStatusToken.value) {
    m_device.ConnectionStatusChanged(m_connectionStatusToken);
    m_connectionStatusToken = {};
  }
  if (m_session)
    m_session.MaintainConnection(false);
  m_session = nullptr;
  m_device = nullptr;
  m_alertCharacteristic = nullptr;
  m_firmwareVersion.clear();
  StopScan();
  NotifyStatus(L"Connecting...", false, -1);
  try {
    if (!selected.id.empty())
      m_device = co_await BluetoothLEDevice::FromIdAsync(selected.id);
    if (!m_device)
      m_device = co_await BluetoothLEDevice::FromBluetoothAddressAsync(
          selected.address,
          selected.randomAddress ? BluetoothAddressType::Random
                                 : BluetoothAddressType::Public);
    if (generation != m_connectionGeneration)
      co_return;
    if (!m_device)
      throw hresult_error(E_FAIL,
                          L"Windows could not open this Bluetooth device.");
    m_adapterAvailable = true;
    m_connectedName = m_device.Name().c_str();
    m_savedDeviceId = m_device.DeviceId().c_str();
    // Request the live AEP signal-strength property as well as retaining the
    // advertisement RSSI. This repairs profiles created by older revisions,
    // where the scan value was not persisted before the connection began.
    try {
      auto requested = single_threaded_vector<hstring>();
      requested.Append(L"System.Devices.Aep.SignalStrength");
      auto deviceInfo = co_await DeviceInformation::CreateFromIdAsync(
          m_savedDeviceId, requested);
      if (deviceInfo) {
        auto properties = deviceInfo.Properties();
        if (properties.HasKey(L"System.Devices.Aep.SignalStrength")) {
          auto value = properties.Lookup(L"System.Devices.Aep.SignalStrength")
                           .try_as<Windows::Foundation::IPropertyValue>();
          if (value) {
            if (value.Type() == Windows::Foundation::PropertyType::Int32)
              m_currentRssi = value.GetInt32();
            else if (value.Type() == Windows::Foundation::PropertyType::Int16)
              m_currentRssi = value.GetInt16();
          }
        }
      }
    } catch (...) {
      // The selected advertisement RSSI remains valid when a Windows driver
      // does not publish the optional AEP signal-strength property.
    }
    m_connectionStatusToken = m_device.ConnectionStatusChanged(
        [this, generation](BluetoothLEDevice const &device,
               winrt::Windows::Foundation::IInspectable const &) {
          if (device.ConnectionStatus() != BluetoothConnectionStatus::Disconnected ||
              generation != m_connectionGeneration || m_manualDisconnect)
            return;
          NotifyStatus(L"Flipper connection was interrupted. Reconnecting...",
                       true, -1);
          HandleUnexpectedDisconnect(generation, m_savedDeviceId);
        });
    m_alertCharacteristic = nullptr;
    m_session = co_await GattSession::FromDeviceIdAsync(
        m_device.BluetoothDeviceId());
    if (generation != m_connectionGeneration)
      co_return;
    if (m_session)
      m_session.MaintainConnection(true);
    int battery = -1;
    auto services =
        co_await m_device.GetGattServicesAsync(BluetoothCacheMode::Uncached);
    if (services.Status() != GattCommunicationStatus::Success) {
      co_await resume_after(std::chrono::milliseconds(500));
      services =
          co_await m_device.GetGattServicesAsync(BluetoothCacheMode::Cached);
    }
    if (services.Status() != GattCommunicationStatus::Success) {
      NotifyStatus(
          services.Status() == GattCommunicationStatus::AccessDenied
              ? L"Bluetooth connected, but Windows denied service access. Remove and re-pair this Flipper, then reopen its FindMyFlipper app."
              : L"Bluetooth connected. Start the FindMyFlipper app on the Flipper to enable battery and alert services.",
          true, -1);
      co_return;
    }
    bool flipperEvidence = IsLikelyFlipper(m_connectedName);
    bool alertDiscovered = false;
    for (auto const &service : services.Services()) {
      auto characteristics = co_await service.GetCharacteristicsAsync(
          BluetoothCacheMode::Uncached);
      if (characteristics.Status() != GattCommunicationStatus::Success)
        continue;
      for (auto const &characteristic : characteristics.Characteristics()) {
        if (characteristic.Uuid() == FindMyAlert) {
          flipperEvidence = true;
          m_alertCharacteristic = characteristic;
          alertDiscovered = true;
        } else if (characteristic.Uuid() == AlertLevel) {
          m_alertCharacteristic = characteristic;
          alertDiscovered = true;
        }
        if (service.Uuid() == BatteryService &&
            characteristic.Uuid() == BatteryLevel) {
          auto read = co_await characteristic.ReadValueAsync(
              BluetoothCacheMode::Uncached);
          if (read.Status() == GattCommunicationStatus::Success &&
              read.Value().Length() > 0) {
            DataReader reader = DataReader::FromBuffer(read.Value());
            battery = reader.ReadByte();
          }
        } else if (service.Uuid() == DeviceInformationService &&
                   (characteristic.Uuid() == FirmwareRevision ||
                    characteristic.Uuid() == SoftwareRevision)) {
          auto read = co_await characteristic.ReadValueAsync(
              BluetoothCacheMode::Uncached);
          if (read.Status() == GattCommunicationStatus::Success &&
              read.Value().Length() > 0) {
            auto value = Windows::Security::Cryptography::CryptographicBuffer::
                ConvertBinaryToString(
                    Windows::Security::Cryptography::BinaryStringEncoding::Utf8,
                    read.Value());
            std::wstring firmware(value);
            firmware.erase(
                std::find(firmware.begin(), firmware.end(), L'\0'),
                firmware.end());
            if (!firmware.empty())
              m_firmwareVersion = std::move(firmware);
          }
        }
      }
    }
    if (generation != m_connectionGeneration)
      co_return;
    if (alertDiscovered)
      m_alertSupported = true;
    NotifyStatus(!flipperEvidence
                     ? L"Connected. Start the FindMyFlipper app on the selected Flipper to expose alert services."
                     : (m_device.Name().empty() ? L"Flipper"
                                               : m_device.Name().c_str()),
                 true, battery);
    if (m_pendingAlert.exchange(false)) {
      if (m_alertCharacteristic)
        SendAlert(true);
      else {
        NotifyStatus(
            L"Connected, but the current Flipper app is not exposing its alert service.",
            true, -1);
      }
    }
  } catch (hresult_error const &error) {
    Disconnect();
    NotifyStatus(error.message().c_str(), false, -1);
  } catch (std::exception const &error) {
    Disconnect();
    NotifyStatus(std::wstring(winrt::to_hstring(error.what())), false, -1);
  } catch (...) {
    Disconnect();
    NotifyStatus(L"Bluetooth connection failed with an unknown Windows error.",
                 false, -1);
  }
}

fire_and_forget BluetoothManager::HandleUnexpectedDisconnect(
    uint64_t generation, std::wstring deviceId) {
  if (deviceId.empty() || m_reconnectScheduled.exchange(true))
    co_return;
  co_await resume_after(std::chrono::seconds(2));
  if (m_manualDisconnect || generation != m_connectionGeneration) {
    m_reconnectScheduled = false;
    co_return;
  }
  m_reconnectScheduled = false;
  Reconnect(std::move(deviceId));
}

fire_and_forget BluetoothManager::Reconnect(std::wstring deviceId) {
  if (deviceId.empty())
    co_return;
  try {
    auto savedDevice = co_await BluetoothLEDevice::FromIdAsync(deviceId);
    if (!savedDevice)
      throw hresult_error(
          E_FAIL, L"Saved Flipper was not found. Scan and select it again.");
    m_adapterAvailable = true;
    BluetoothDeviceRecord saved;
    saved.id = deviceId;
    saved.address = savedDevice.BluetoothAddress();
    saved.randomAddress =
        savedDevice.BluetoothAddressType() == BluetoothAddressType::Random;
    saved.connectable = true;
    saved.paired = true;
    saved.name = savedDevice.Name().c_str();
    Connect(saved, true);
  } catch (hresult_error const &error) {
    NotifyStatus(error.message().c_str(), false, -1);
  } catch (...) {
    NotifyStatus(L"Saved-device reconnect failed.", false, -1);
  }
}

void BluetoothManager::PlayAlert() {
  SendAlert(false);
}

fire_and_forget BluetoothManager::SendAlert(bool retrying) {
  try {
    if (!m_alertCharacteristic || !DeviceConnected()) {
      if (!m_savedDeviceId.empty() && !retrying) {
        m_pendingAlert = true;
        NotifyStatus(L"Restoring the Flipper alert service...", true, -1);
        Reconnect(m_savedDeviceId);
      } else {
        m_pendingAlert = false;
        NotifyStatus(
            L"The current Flipper app is not exposing its alert service. Open FindMyFlipper on the device and try again.",
            DeviceConnected(), -1);
      }
      co_return;
    }
    DataWriter writer;
    if (m_alertCharacteristic.Uuid() == FindMyAlert) {
      std::array<uint8_t, 4> payload{0x03, 0xB2, 0x02, 0x00};
      writer.WriteBytes(payload);
    } else
      writer.WriteByte(2);
    auto properties = m_alertCharacteristic.CharacteristicProperties();
    auto writeOption =
        (properties & GattCharacteristicProperties::Write) ==
                GattCharacteristicProperties::Write
            ? GattWriteOption::WriteWithResponse
            : GattWriteOption::WriteWithoutResponse;
    auto status = co_await m_alertCharacteristic.WriteValueWithResultAsync(
        writer.DetachBuffer(), writeOption);
    if (status.Status() == GattCommunicationStatus::Success) {
      m_alertSupported = true;
      NotifyStatus(L"Flipper confirmed the alert command.", true, -1);
    } else if (!retrying && !m_savedDeviceId.empty()) {
      m_alertCharacteristic = nullptr;
      m_pendingAlert = true;
      NotifyStatus(L"The alert service changed. Reconnecting and retrying...",
                   true, -1);
      Reconnect(m_savedDeviceId);
    } else {
      NotifyStatus(L"The Flipper rejected the alert command.",
                   DeviceConnected(), -1);
    }
  } catch (hresult_error const &error) {
    if (!retrying && !m_savedDeviceId.empty()) {
      m_alertCharacteristic = nullptr;
      m_pendingAlert = true;
      NotifyStatus(L"The alert connection changed. Reconnecting and retrying...",
                   true, -1);
      Reconnect(m_savedDeviceId);
    } else {
      NotifyStatus(L"Alert failed: " + std::wstring(error.message()),
                   DeviceConnected(), -1);
    }
  } catch (...) {
    NotifyStatus(L"Alert failed with an unknown Bluetooth error.",
                 DeviceConnected(), -1);
  }
}

void BluetoothManager::Disconnect() {
  m_manualDisconnect = true;
  m_reconnectScheduled = false;
  ++m_connectionGeneration;
  m_alertCharacteristic = nullptr;
  if (m_session)
    m_session.MaintainConnection(false);
  m_session = nullptr;
  if (m_device && m_connectionStatusToken.value) {
    m_device.ConnectionStatusChanged(m_connectionStatusToken);
    m_connectionStatusToken = {};
  }
  m_device = nullptr;
  m_connectedName.clear();
  m_firmwareVersion.clear();
  NotifyStatus(L"Disconnected", false, -1);
}
bool BluetoothManager::DeviceConnected() const noexcept {
  try {
    return m_device &&
           m_device.ConnectionStatus() == BluetoothConnectionStatus::Connected;
  } catch (...) {
    return false;
  }
}
std::wstring BluetoothManager::ConnectedDeviceId() const {
  return m_device ? std::wstring(m_device.DeviceId()) : L"";
}
std::wstring BluetoothManager::ConnectedDeviceName() const {
  return m_connectedName;
}
std::wstring BluetoothManager::ConnectedBluetoothMac() const {
  if (m_connectedAddress == 0)
    return L"";
  wchar_t value[18]{};
  swprintf_s(value, L"%02X:%02X:%02X:%02X:%02X:%02X",
             static_cast<unsigned>((m_connectedAddress >> 40) & 0xFF),
             static_cast<unsigned>((m_connectedAddress >> 32) & 0xFF),
             static_cast<unsigned>((m_connectedAddress >> 24) & 0xFF),
             static_cast<unsigned>((m_connectedAddress >> 16) & 0xFF),
             static_cast<unsigned>((m_connectedAddress >> 8) & 0xFF),
             static_cast<unsigned>(m_connectedAddress & 0xFF));
  return value;
}
bool BluetoothManager::ConnectedAddressIsRandom() const noexcept {
  return m_connectedAddressRandom;
}
std::wstring BluetoothManager::FirmwareVersion() const {
  return m_firmwareVersion;
}
int BluetoothManager::CurrentRssi() const noexcept { return m_currentRssi; }
bool BluetoothManager::AlertAvailable() const noexcept {
  return m_alertSupported;
}
bool BluetoothManager::AdapterAvailable() const noexcept {
  return m_adapterAvailable;
}
