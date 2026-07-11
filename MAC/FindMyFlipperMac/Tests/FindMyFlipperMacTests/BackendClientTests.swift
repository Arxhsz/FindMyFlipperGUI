import XCTest
@testable import FindMyFlipperMac

// MARK: - URLProtocol stub

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

// MARK: - Tests

final class BackendClientTests: XCTestCase {
    var sut: BackendClient!
    var session: URLSession!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        sut = BackendClient(
            baseURL: URL(string: "http://127.0.0.1:8765")!,
            session: session
        )
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        sut = nil
        session = nil
    }

    func stub(statusCode: Int, json: String) {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil
            )!
            return (response, json.data(using: .utf8)!)
        }
    }

    func requestBodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }

        return data
    }

    func testHealthSuccess() async throws {
        stub(statusCode: 200, json: "{\"status\":\"ok\",\"version\":\"1.0.0\"}")
        let r = try await sut.health()
        XCTAssertEqual(r.status, "ok")
    }

    func testHttpError500ThrowsHttpError() async {
        stub(statusCode: 500, json: "{}")
        do {
            _ = try await sut.health()
            XCTFail("Expected throw")
        } catch BackendError.httpError(let code) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testHttp401ThrowsAuthRequired() async {
        stub(statusCode: 401, json: "{}")
        do {
            _ = try await sut.health()
            XCTFail("Expected throw")
        } catch BackendError.authRequired {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testInvalidJsonThrowsDecodingFailed() async {
        stub(statusCode: 200, json: "not json")
        do {
            _ = try await sut.health()
            XCTFail("Expected throw")
        } catch BackendError.decodingFailed {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testNetworkErrorThrowsNetworkUnavailable() async {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await sut.health()
            XCTFail("Expected throw")
        } catch BackendError.networkUnavailable {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchDecryptedReportsAuthErrorInBody() async {
        stub(statusCode: 200, json: "{\"ok\":false,\"reports\":[],\"error\":\"auth required\"}")
        do {
            _ = try await sut.fetchDecryptedReports(hashedAdvKey: "abc", privateKeyBase64: "xyz")
            XCTFail("Expected throw")
        } catch BackendError.authRequired {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchDecryptedReportsPreservesBackendErrorInsteadOfInventingHttpZero() async {
        stub(statusCode: 200, json: "{\"ok\":false,\"reports\":[],\"error\":\"Apple reports endpoint returned HTTP 503\"}")
        do {
            _ = try await sut.fetchDecryptedReports(hashedAdvKey: "abc", privateKeyBase64: "xyz")
            XCTFail("Expected throw")
        } catch BackendError.server(let detail) {
            XCTAssertEqual(detail, "Apple reports endpoint returned HTTP 503")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testStartAnisetteSendsInstallFlag() async throws {
        var requestBody: Data?
        MockURLProtocol.requestHandler = { request in
            requestBody = self.requestBodyData(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let data = """
            {"ok":true,"installed":true,"started":true,"runtime":"docker","message":"ready"}
            """.data(using: .utf8)!
            return (response, data)
        }

        let response = try await sut.startAnisette(installIfMissing: true)

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.installed, true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requestBody)) as? [String: Bool])
        XCTAssertEqual(json["install_if_missing"], true)
    }

    func testConnectAuthSendsCredentialsAnd2FAFields() async throws {
        var requestBody: Data?
        MockURLProtocol.requestHandler = { request in
            requestBody = self.requestBodyData(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            let data = """
            {"ok":true,"account_identifier":"user@example.com"}
            """.data(using: .utf8)!
            return (response, data)
        }

        let response = try await sut.connectAuth(
            username: "user@example.com",
            password: "secret",
            secondFactor: "sms",
            code: "123456"
        )

        XCTAssertTrue(response.ok)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requestBody)) as? [String: String])
        XCTAssertEqual(json["username"], "user@example.com")
        XCTAssertEqual(json["password"], "secret")
        XCTAssertEqual(json["second_factor"], "sms")
        XCTAssertEqual(json["code"], "123456")
    }
}
