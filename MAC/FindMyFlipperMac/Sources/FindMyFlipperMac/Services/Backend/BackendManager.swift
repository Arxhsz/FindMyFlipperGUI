import Foundation

@MainActor
final class BackendManager: ObservableObject {
    @Published var status: BackendStatus = .stopped
    @Published var lastError: BackendError?

    private var process: Process?
    private let client: BackendClient
    private let backendScriptPath: URL

    init(client: BackendClient = BackendClient(),
         backendScriptPath: URL? = nil) {
        self.client = client
        // Default: look for Backend/ relative to bundle or project root
        self.backendScriptPath = backendScriptPath ?? Self.defaultBackendPath()
    }

    nonisolated func startBackend() async {
        let currentStatus = await status
        if currentStatus == .running, await checkHealth() {
            return
        }
        await MainActor.run { [self] in
            status = .starting
            lastError = nil
            if process?.isRunning == false {
                process = nil
            }
        }

        do {
            if await checkHealth() {
                await MainActor.run { [self] in status = .running }
                return
            }

            try await MainActor.run { [self] in try launchProcess() }

            // Poll /health for up to 10 seconds — Task.sleep yields cooperatively,
            // so this loop does NOT block the main thread.
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                if await checkHealth() {
                    await MainActor.run { [self] in status = .running }
                    return
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            await MainActor.run { [self] in
                status = .error("Backend did not respond within 10 seconds.")
                lastError = .networkUnavailable
            }
        } catch {
            await MainActor.run { [self] in
                status = .error("Failed to start backend: \(error.localizedDescription)")
                lastError = .networkUnavailable
            }
        }
    }

    func stopBackend() {
        process?.terminate()
        process = nil
        status = .stopped
    }

    func restartBackend() async {
        stopBackend()
        await startBackend()
    }

    nonisolated func checkHealth() async -> Bool {
        do {
            let response = try await client.health()
            return response.status == "ok"
        } catch {
            return false
        }
    }

    private func launchProcess() throws {
        let python = findPython()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = ["-m", "findmy_gateway.server"]
        proc.currentDirectoryURL = backendScriptPath
        proc.environment = Self.processEnvironment(backendPath: backendScriptPath)
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.terminationHandler = { [weak self, weak proc] _ in
            Task { @MainActor in
                guard let self, let proc, self.process === proc else { return }
                let shouldRestart = self.status == .running || self.status == .starting
                self.process = nil
                if shouldRestart {
                    self.status = .stopped
                    Task.detached(priority: .utility) { [backendManager = self] in
                        await backendManager.startBackend()
                    }
                }
            }
        }
        try proc.run()
        process = proc
    }

    private func findPython() -> String {
        let candidates = [
            backendScriptPath.appendingPathComponent("venv/bin/python3").path,
            backendScriptPath.appendingPathComponent(".venv/bin/python3").path,
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3",
            "/usr/local/bin/python3"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/bin/python3"
    }

    private static func defaultBackendPath() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundledBackendURL = resourceURL.appendingPathComponent("Backend")
            let bundledGatewayURL = bundledBackendURL.appendingPathComponent("findmy_gateway")
            if FileManager.default.fileExists(atPath: bundledGatewayURL.path) {
                return bundledBackendURL
            }
        }

        var currentURL = Bundle.main.bundleURL
        
        // Traverse up to find a directory containing Backend/findmy_gateway
        for _ in 0..<10 {
            let backendURL = currentURL.appendingPathComponent("Backend")
            let gatewayURL = backendURL.appendingPathComponent("findmy_gateway")
            if FileManager.default.fileExists(atPath: gatewayURL.path) {
                return backendURL
            }
            let parent = currentURL.deletingLastPathComponent()
            if parent == currentURL { break }
            currentURL = parent
        }
        
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Backend")
    }

    private static func processEnvironment(backendPath: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = [
            backendPath.appendingPathComponent("venv/bin").path,
            backendPath.appendingPathComponent(".venv/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (extraPaths + [existingPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        return environment
    }
}
