import Foundation
import CoreBluetooth

@MainActor
final class PermissionService: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var bluetoothAuthorization: CBManagerAuthorization = CBCentralManager.authorization

    private var centralManager: CBCentralManager?

    func requestBluetoothPermission() {
        // Instantiating CBCentralManager triggers the permission prompt
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothAuthorization = CBCentralManager.authorization
        }
    }
}
