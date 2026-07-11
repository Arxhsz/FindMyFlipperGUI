import XCTest
@testable import FindMyFlipperMac

@MainActor
final class DiagnosticsServiceTests: XCTestCase {
    var tempDir: URL!
    var profileStore: ProfileStore!
    var keychain: KeychainService!
    var backendManager: BackendManager!
    var backendClient: BackendClient!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        profileStore = ProfileStore(containerURL: tempDir)
        keychain = KeychainService(service: "com.findmyflipper.mac.diag-tests-\(UUID().uuidString)")

        // Stub client that returns "not running" for health
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        backendClient = BackendClient(baseURL: URL(string: "http://127.0.0.1:8765")!, session: session)
        backendManager = BackendManager(client: backendClient)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func makeSUT() -> SetupDiagnosticsService {
        SetupDiagnosticsService(
            keychainService: keychain,
            backendClient: backendClient,
            backendManager: backendManager,
            profileStore: profileStore
        )
    }

    // Property test: runAll() returns exactly DiagnosticID.allCases.count results
    func testRunAllReturnsExactlyOneResultPerDiagnosticID() async {
        MockURLProtocol.requestHandler = { _ in
            let r = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (r, "{\"connected\":false}".data(using: .utf8)!)
        }
        let sut = makeSUT()
        let results = await sut.runAll()

        // Must have exactly 8 results
        XCTAssertEqual(results.count, DiagnosticID.allCases.count)

        // Each DiagnosticID must appear exactly once
        for id in DiagnosticID.allCases {
            let matching = results.filter { $0.id == id }
            XCTAssertEqual(matching.count, 1, "Expected exactly 1 result for \(id), got \(matching.count)")
        }
    }

    // Results should be in DiagnosticID.allCases order
    func testRunAllResultsAreInAllCasesOrder() async {
        MockURLProtocol.requestHandler = { _ in
            let r = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (r, "{\"connected\":false}".data(using: .utf8)!)
        }
        let sut = makeSUT()
        let results = await sut.runAll()
        let resultIDs = results.map { $0.id }
        XCTAssertEqual(resultIDs, DiagnosticID.allCases)
    }

    // No active profile → keysFileValid should fail
    func testNoProfileMakesKeysFileValidFail() async {
        let sut = makeSUT()
        let result = await sut.run(.keysFileValid)
        XCTAssertEqual(result.state, .fail)
    }

    // Backend stopped → backendRunning should fail and have a fixAction
    func testBackendStoppedHasFixAction() async {
        // backendManager.status is .stopped by default
        let sut = makeSUT()
        let result = await sut.run(.backendRunning)
        XCTAssertEqual(result.state, .fail)
        XCTAssertNotNil(result.fixAction, "Failed backendRunning should provide a fixAction")
    }
}
