import Foundation
import Darwin

/// Transfers FindMyFlipper key bundles to the Flipper microSD card over the
/// official USB serial CLI. The Flipper does not mount its SD card as a macOS
/// volume, so ordinary FileManager volume discovery cannot reach it.
struct FlipperSDCardService {
    static let destinationDirectory = "/ext/apps_data/findmy"
    private static let serialPrefix = "cu.usbmodemflip_"

    static var isFlipperConnected: Bool {
        findFlipperSerialPort() != nil
    }

    static var connectedDeviceName: String? {
        guard let port = findFlipperSerialPort() else { return nil }
        return port.lastPathComponent.replacingOccurrences(of: serialPrefix, with: "")
    }

    static func findFlipperSerialPort(in deviceDirectory: URL = URL(fileURLWithPath: "/dev")) -> URL? {
        let ports = (try? FileManager.default.contentsOfDirectory(
            at: deviceDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return ports
            .filter { $0.lastPathComponent.hasPrefix(serialPrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    static func prepareImportFolder() async throws -> String {
        try await performWithSession { session in
            try session.prepareImportFolder()
            return destinationDirectory
        }
    }

    @discardableResult
    static func writeKeysToFlipperSD(rawContent: String, filename: String) async throws -> String {
        guard let bytes = rawContent.data(using: .utf8), !bytes.isEmpty else {
            throw FlipperSDCardError.invalidKeysData
        }
        let safeFilename = sanitizedKeysFilename(filename)
        return try await performWithSession { session in
            try session.prepareImportFolder()
            let destination = "\(destinationDirectory)/\(safeFilename)"
            try session.write(bytes, to: destination)
            return destination
        }
    }

    static func listKeysFiles() async throws -> [String] {
        try await performWithSession { session in
            try session.prepareImportFolder()
            return try session.listKeysFiles()
        }
    }

    /// Deletes only direct `.keys` children of the app-owned Flipper folder.
    /// The newly generated file can be retained to make rotation atomic.
    @discardableResult
    static func deleteKeysFiles(except retainedFilename: String? = nil) async throws -> [String] {
        let retained = retainedFilename.map(sanitizedKeysFilename)
        return try await performWithSession { session in
            try session.prepareImportFolder()
            let files = try session.listKeysFiles()
            let deleted = files.filter { $0.caseInsensitiveCompare(retained ?? "") != .orderedSame }
            for filename in deleted {
                try session.removeKeysFile(named: filename)
            }
            return deleted
        }
    }

    static func deleteKeysFile(named filename: String) async throws {
        let safeFilename = sanitizedKeysFilename(filename)
        guard safeFilename == filename else {
            throw FlipperSDCardError.transferFailed("An unsafe key filename was refused.")
        }
        try await performWithSession { session in
            try session.removeKeysFile(named: safeFilename)
        }
    }

    static func matchingKeysFilename(hashedAdvKeyBase64: String) async throws -> String? {
        try await performWithSession { session in
            try session.prepareImportFolder()
            for filename in try session.listKeysFiles() {
                guard let content = try? session.readKeysFile(named: filename) else { continue }
                if parsedHashedAdvKey(from: content) == hashedAdvKeyBase64 {
                    return filename
                }
            }
            return nil
        }
    }

    static func hashedAdvKey(forKeysFilename filename: String) async throws -> String {
        try await performWithSession { session in
            let content = try session.readKeysFile(named: filename)
            guard let hashedKey = parsedHashedAdvKey(from: content) else {
                throw FlipperSDCardError.transferFailed("The .keys file does not contain a hashed advertisement key.")
            }
            return hashedKey
        }
    }

    static func parsedHashedAdvKey(from content: String) -> String? {
        for line in content.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }
            let label = parts[0].lowercased()
            if label == "hashed adv key" || label == "hashed adv key (base64)" {
                return parts[1]
            }
        }
        return nil
    }

    static func parseKeysFilenames(from storageListOutput: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)([A-Za-z0-9][A-Za-z0-9._-]*\.keys)"#) else { return [] }
        let range = NSRange(storageListOutput.startIndex..., in: storageListOutput)
        var seen = Set<String>()
        return regex.matches(in: storageListOutput, range: range).compactMap { match in
            guard let tokenRange = Range(match.range(at: 1), in: storageListOutput) else { return nil }
            let filename = String(storageListOutput[tokenRange])
            let key = filename.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return filename
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func sanitizedKeysFilename(_ filename: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleanedScalars = filename.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        var result = String(cleanedScalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        if result.isEmpty { result = "findmyflipper" }
        if !result.lowercased().hasSuffix(".keys") { result += ".keys" }
        return result
    }

    private static func performWithSession<T>(_ operation: @escaping (FlipperSerialSession) throws -> T) async throws -> T {
        guard let port = findFlipperSerialPort() else {
            throw FlipperSDCardError.notConnected
        }
        return try await Task.detached(priority: .userInitiated) {
            let session = try FlipperSerialSession(port: port)
            defer { session.close() }
            return try operation(session)
        }.value
    }
}

private final class FlipperSerialSession: @unchecked Sendable {
    private let handle: FileHandle
    private let descriptor: Int32
    private let prompt = Data(">: ".utf8)

    init(port: URL) throws {
        try Self.configure(port: port)
        do {
            handle = try FileHandle(forUpdating: port)
        } catch {
            throw FlipperSDCardError.portBusy
        }
        descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        }

        try write(Data([0x03, 0x0D]))
        usleep(180_000)
        drainInput()
    }

    func close() {
        try? handle.close()
    }

    func prepareImportFolder() throws {
        _ = try command("storage info /ext")
        _ = try command("storage mkdir /ext/apps_data", allowsStorageError: true)
        _ = try command("storage mkdir \(FlipperSDCardService.destinationDirectory)", allowsStorageError: true)
    }

    func write(_ data: Data, to path: String) throws {
        _ = try command("storage remove \(path)", allowsStorageError: true)

        for chunkStart in stride(from: 0, to: data.count, by: 512) {
            let chunkEnd = min(chunkStart + 512, data.count)
            let chunk = data.subdata(in: chunkStart..<chunkEnd)
            try write(Data("storage write_chunk \(path) \(chunk.count)\r".utf8))
            usleep(80_000)
            try write(chunk)
            let response = try readUntilPrompt(timeout: 4)
            if response.contains(Data("Storage error".utf8)) {
                throw FlipperSDCardError.transferFailed("The Flipper rejected a file chunk.")
            }
        }

        let stat = try command("storage stat \(path)")
        guard stat.contains("File, size: \(data.count)b") else {
            throw FlipperSDCardError.transferFailed("The copied file size did not match the generated key file.")
        }
    }

    func listKeysFiles() throws -> [String] {
        let response = try command("storage list \(FlipperSDCardService.destinationDirectory)")
        return FlipperSDCardService.parseKeysFilenames(from: response)
    }

    func removeKeysFile(named filename: String) throws {
        let safeFilename = FlipperSDCardService.sanitizedKeysFilename(filename)
        guard safeFilename == filename else {
            throw FlipperSDCardError.transferFailed("An unsafe key filename was refused.")
        }
        _ = try command("storage remove \(FlipperSDCardService.destinationDirectory)/\(safeFilename)")
    }

    func readKeysFile(named filename: String) throws -> String {
        let safeFilename = FlipperSDCardService.sanitizedKeysFilename(filename)
        guard safeFilename == filename else {
            throw FlipperSDCardError.transferFailed("An unsafe key filename was refused.")
        }
        let response = try command("storage read \(FlipperSDCardService.destinationDirectory)/\(safeFilename)")
        guard let contentStart = response.range(of: "Private key", options: [.caseInsensitive])?.lowerBound else {
            throw FlipperSDCardError.transferFailed("The Flipper returned an unreadable .keys file.")
        }
        var content = String(response[contentStart...])
        if let promptRange = content.range(of: "\n>: ", options: [.backwards]) {
            content = String(content[..<promptRange.lowerBound])
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func command(_ command: String, allowsStorageError: Bool = false) throws -> String {
        try write(Data("\(command)\r".utf8))
        let responseData = try readUntilPrompt(timeout: 4)
        let response = String(decoding: responseData, as: UTF8.self)
        if !allowsStorageError && response.contains("Storage error") {
            throw FlipperSDCardError.transferFailed("The Flipper SD card rejected the requested operation.")
        }
        return response
    }

    private func write(_ data: Data) throws {
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw FlipperSDCardError.connectionLost
        }
    }

    private func readUntilPrompt(timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while Date() < deadline {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                received.append(buffer, count: count)
                if received.range(of: prompt) != nil {
                    return received
                }
            } else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
                throw FlipperSDCardError.connectionLost
            }
            usleep(30_000)
        }
        throw FlipperSDCardError.timedOut
    }

    private func drainInput() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Darwin.read(descriptor, &buffer, buffer.count) > 0 {}
    }

    private static func configure(port: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/stty")
        process.arguments = ["-f", port.path, "230400", "raw", "-echo"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw FlipperSDCardError.portBusy
        }
        guard process.terminationStatus == 0 else {
            throw FlipperSDCardError.portBusy
        }
    }
}

enum FlipperSDCardError: LocalizedError {
    case notConnected
    case portBusy
    case invalidKeysData
    case connectionLost
    case timedOut
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No Flipper Zero USB connection was found. Connect it with a data-capable USB cable and keep qFlipper closed."
        case .portBusy:
            return "The Flipper USB connection is busy. Quit qFlipper or any serial terminal, then try again."
        case .invalidKeysData:
            return "The generated .keys data is empty or invalid."
        case .connectionLost:
            return "The Flipper USB connection was lost during transfer."
        case .timedOut:
            return "The Flipper did not answer in time. Unlock it, close qFlipper, and reconnect the USB cable."
        case .transferFailed(let detail):
            return "Could not copy the .keys file to the Flipper SD card. \(detail)"
        }
    }
}
