import XCTest
@testable import FindMyFlipperMac

final class FlipperSDCardServiceTests: XCTestCase {
    func testFindFlipperSerialPortIgnoresUnrelatedDevices() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlipperPorts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(atPath: directory.appendingPathComponent("cu.Bluetooth-Incoming-Port").path, contents: Data())
        FileManager.default.createFile(atPath: directory.appendingPathComponent("cu.usbmodemflip_TestDevice1").path, contents: Data())

        let result = FlipperSDCardService.findFlipperSerialPort(in: directory)

        XCTAssertEqual(result?.lastPathComponent, "cu.usbmodemflip_TestDevice1")
    }

    func testSanitizedKeysFilenamePreventsPathTraversal() {
        XCTAssertEqual(
            FlipperSDCardService.sanitizedKeysFilename("../../My Flipper.keys"),
            "My-Flipper.keys"
        )
        XCTAssertEqual(FlipperSDCardService.sanitizedKeysFilename("new-tag"), "new-tag.keys")
    }

    func testParsesAndDeduplicatesKeysFromFlipperStorageListing() {
        let output = """
        storage list /ext/apps_data/findmy
        [F] FMFG_ea042d20f40d.keys 403
        [F] findmyflipper-20260710-082900.keys 401
        [F] FMFG_ea042d20f40d.keys 403
        [F] readme.txt 12
        >:
        """

        XCTAssertEqual(
            FlipperSDCardService.parseKeysFilenames(from: output),
            ["findmyflipper-20260710-082900.keys", "FMFG_ea042d20f40d.keys"]
        )
    }

    func testParsesHashedAdvertisementKeyWithoutRetainingOtherFields() {
        let content = """
        Private key: secret-value
        Hashed adv key (Base64): aGFzaGVkLWtleQ==
        MAC: AABBCCDDEEFF
        """

        XCTAssertEqual(
            FlipperSDCardService.parsedHashedAdvKey(from: content),
            "aGFzaGVkLWtleQ=="
        )
    }

    func testLivePrepareImportFolderWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["FINDMYFLIPPER_LIVE_USB_TEST"] == "1" else {
            throw XCTSkip("Set FINDMYFLIPPER_LIVE_USB_TEST=1 with a Flipper connected to run this test.")
        }

        let destination = try await FlipperSDCardService.prepareImportFolder()

        XCTAssertEqual(destination, "/ext/apps_data/findmy")
    }

    func testLiveListKeysFilesWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["FINDMYFLIPPER_LIVE_USB_TEST"] == "1" else {
            throw XCTSkip("Set FINDMYFLIPPER_LIVE_USB_TEST=1 with a Flipper connected to run this test.")
        }

        let files = try await FlipperSDCardService.listKeysFiles()

        XCTAssertTrue(files.allSatisfy { $0.lowercased().hasSuffix(".keys") })
        print("Live Flipper .keys files: \(files)")
    }

    func testLiveWriteListAndDeleteTemporaryFileWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["FINDMYFLIPPER_LIVE_USB_TEST"] == "1" else {
            throw XCTSkip("Set FINDMYFLIPPER_LIVE_USB_TEST=1 with a Flipper connected to run this test.")
        }
        let filename = "findmyflipper-transfer-check.keys"

        do {
            _ = try await FlipperSDCardService.writeKeysToFlipperSD(
                rawContent: "FindMyFlipper USB transfer verification\n",
                filename: filename
            )
            let filesAfterWrite = try await FlipperSDCardService.listKeysFiles()
            XCTAssertTrue(filesAfterWrite.contains(filename))
            try await FlipperSDCardService.deleteKeysFile(named: filename)
            let filesAfterDelete = try await FlipperSDCardService.listKeysFiles()
            XCTAssertFalse(filesAfterDelete.contains(filename))
        } catch {
            try? await FlipperSDCardService.deleteKeysFile(named: filename)
            throw error
        }
    }

    func testLiveReadExistingKeyIdentityWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["FINDMYFLIPPER_LIVE_USB_TEST"] == "1" else {
            throw XCTSkip("Set FINDMYFLIPPER_LIVE_USB_TEST=1 with a Flipper connected to run this test.")
        }
        let files = try await FlipperSDCardService.listKeysFiles()
        let filename = try XCTUnwrap(files.first)

        let hashedKey = try await FlipperSDCardService.hashedAdvKey(forKeysFilename: filename)
        let match = try await FlipperSDCardService.matchingKeysFilename(hashedAdvKeyBase64: hashedKey)

        XCTAssertNotNil(match)
    }

    func testLiveExpectedIdentityExistsWhenProvided() async throws {
        guard ProcessInfo.processInfo.environment["FINDMYFLIPPER_LIVE_USB_TEST"] == "1",
              let expectedHash = ProcessInfo.processInfo.environment["FINDMYFLIPPER_EXPECTED_HASH"],
              !expectedHash.isEmpty else {
            throw XCTSkip("Set the live USB flag and expected hash to verify the active identity.")
        }

        let filename = try await FlipperSDCardService.matchingKeysFilename(
            hashedAdvKeyBase64: expectedHash
        )

        XCTAssertNotNil(filename, "The active Mac identity is not present on the Flipper microSD card.")
    }
}
