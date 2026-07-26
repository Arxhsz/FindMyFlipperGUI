#pragma once

#include "../Models/AppModels.h"

namespace FindMyFlipper::Services {
class BluetoothManager final {
public:
  using DevicesChanged =
      std::function<void(std::vector<Models::BluetoothDevice> const &)>;
  using StatusChanged = std::function<void(std::wstring const &, bool, int)>;

  BluetoothManager();
  ~BluetoothManager();
  void SetDevicesChanged(DevicesChanged callback);
  void SetStatusChanged(StatusChanged callback);
  winrt::fire_and_forget StartScan();
  void StopScan();
  winrt::fire_and_forget Connect(Models::BluetoothDevice device,
                                 bool reconnect = false);
  winrt::fire_and_forget Reconnect(std::wstring deviceId);
  winrt::fire_and_forget PlayAlert();
  void Disconnect();
  std::wstring ConnectedDeviceId() const;
  std::wstring ConnectedDeviceName() const;
  std::wstring ConnectedBluetoothMac() const;
  bool ConnectedAddressIsRandom() const noexcept;
  std::wstring FirmwareVersion() const;
  int CurrentRssi() const noexcept;
  bool AlertAvailable() const noexcept;
  bool AdapterAvailable() const noexcept;

private:
  winrt::fire_and_forget HandleUnexpectedDisconnect(uint64_t generation,
                                                     std::wstring deviceId);
  bool DeviceConnected() const noexcept;
  void NotifyStatus(std::wstring const &message, bool connected, int battery)
      noexcept;
  void
  OnAdvertisement(winrt::Windows::Devices::Bluetooth::Advertisement::
                      BluetoothLEAdvertisementWatcher const &,
                  winrt::Windows::Devices::Bluetooth::Advertisement::
                      BluetoothLEAdvertisementReceivedEventArgs const &args);
  winrt::Windows::Devices::Bluetooth::Advertisement::
      BluetoothLEAdvertisementWatcher m_watcher;
  winrt::Windows::Devices::Bluetooth::BluetoothLEDevice m_device{nullptr};
  winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
      GattCharacteristic m_alertCharacteristic{nullptr};
  winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::GattSession
      m_session{nullptr};
  std::map<uint64_t, Models::BluetoothDevice> m_devices;
  mutable std::mutex m_mutex;
  mutable std::mutex m_callbackMutex;
  DevicesChanged m_devicesChanged;
  StatusChanged m_statusChanged;
  winrt::event_token m_receivedToken{};
  winrt::event_token m_connectionStatusToken{};
  std::atomic_bool m_adapterAvailable{false};
  std::atomic_uint64_t m_connectionGeneration{0};
  std::atomic_bool m_manualDisconnect{false};
  std::atomic_bool m_reconnectScheduled{false};
  std::atomic_uint64_t m_nextDiscoveryOrder{1};
  std::atomic_int64_t m_lastAdvertisementPublishMs{0};
  std::atomic_int m_currentRssi{-127};
  std::atomic_bool m_alertSupported{false};
  std::atomic_bool m_pendingAlert{false};
  std::atomic_int m_alertRetryCount{0};
  uint64_t m_connectedAddress{};
  bool m_connectedAddressRandom{false};
  std::wstring m_connectedName;
  std::wstring m_savedDeviceId;
  std::wstring m_firmwareVersion;
};
} // namespace FindMyFlipper::Services
