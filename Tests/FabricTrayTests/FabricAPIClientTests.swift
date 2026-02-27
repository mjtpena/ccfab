@testable import FabricTray
import XCTest

// MARK: - Mock URL Protocol

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// Helper to read request body (URLSession may convert httpBody to httpBodyStream)
extension URLRequest {
    func bodyData() -> Data? {
        if let data = httpBody { return data }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - API Client Tests

final class FabricAPIClientTests: XCTestCase {
    private var client: FabricAPIClient!
    private let token = "test-access-token"

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = FabricAPIClient(session: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func mockResponse(json: [String: Any], statusCode: Int = 200, for expectedPath: String? = nil) {
        MockURLProtocol.requestHandler = { request in
            if let path = expectedPath {
                XCTAssertTrue(request.url?.absoluteString.contains(path) ?? false,
                              "Expected path \(path) in \(request.url?.absoluteString ?? "")")
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
            let data = try JSONSerialization.data(withJSONObject: json)
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    // MARK: - List Workspaces

    func testListWorkspaces() async throws {
        mockResponse(json: [
            "value": [
                ["id": "ws-1", "displayName": "Workspace One", "type": "Workspace"],
                ["id": "ws-2", "displayName": "Workspace Two", "type": "Workspace", "capacityId": "cap-1"]
            ]
        ], for: "v1/workspaces")

        let items = try await client.listWorkspaces(accessToken: token)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.type == .workspace })
        XCTAssertTrue(items.contains { $0.name == "Workspace One" })
        XCTAssertTrue(items.contains { $0.name == "Workspace Two" })
    }

    // MARK: - List Items

    func testListItems() async throws {
        mockResponse(json: [
            "value": [
                ["id": "nb-1", "displayName": "My Notebook", "type": "Notebook"],
                ["id": "pl-1", "displayName": "ETL Pipeline", "type": "DataPipeline"],
                ["id": "lh-1", "displayName": "Raw Data", "type": "Lakehouse"]
            ]
        ], for: "v1/workspaces/ws-1/items")

        let items = try await client.listItems(workspaceID: "ws-1", accessToken: token)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.contains { $0.type == .notebook })
        XCTAssertTrue(items.contains { $0.type == .dataPipeline })
        XCTAssertTrue(items.contains { $0.type == .lakehouse })
        XCTAssertTrue(items.allSatisfy { $0.workspaceID == "ws-1" })
    }

    // MARK: - List Capacities

    func testListCapacities() async throws {
        mockResponse(json: [
            "value": [
                ["id": "cap-1", "displayName": "Prod Capacity", "sku": "F64", "region": "westus", "state": "Active"],
                ["id": "cap-2", "displayName": "Dev Capacity", "sku": "FT1", "region": "eastus", "state": "Paused"]
            ]
        ], for: "v1/capacities")

        let caps = try await client.listCapacities(accessToken: token)
        XCTAssertEqual(caps.count, 2)
        XCTAssertEqual(caps["cap-1"]?.sku, "F64")
        XCTAssertEqual(caps["cap-1"]?.licenseType, "Fabric")
        XCTAssertTrue(caps["cap-1"]?.isActive ?? false)
        XCTAssertEqual(caps["cap-2"]?.licenseType, "Trial")
        XCTAssertFalse(caps["cap-2"]?.isActive ?? true)
    }

    // MARK: - Run Item

    func testRunItemSendsCorrectJobType() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("jobType=Pipeline") ?? false)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let data = try JSONSerialization.data(withJSONObject: ["id": "job-1"])
            let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let jobID = try await client.runItem(workspaceID: "ws-1", itemID: "pl-1", itemType: .dataPipeline, accessToken: token)
        XCTAssertEqual(jobID, "job-1")
    }

    func testRunItemNotebookJobType() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("jobType=RunNotebook") ?? false)
            let data = try JSONSerialization.data(withJSONObject: ["id": "job-2"])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        _ = try await client.runItem(workspaceID: "ws-1", itemID: "nb-1", itemType: .notebook, accessToken: token)
    }

    func testRunItemWithExecutionData() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = String(data: request.bodyData() ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("executionData"), "Body should contain executionData: \(body)")
            let data = try JSONSerialization.data(withJSONObject: ["id": "job-3"])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        _ = try await client.runItem(
            workspaceID: "ws-1", itemID: "pl-1", itemType: .dataPipeline,
            executionData: "{\"param1\": \"value1\"}", accessToken: token
        )
    }

    func testRunItemEmptyExecutionDataSendsEmptyBody() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = String(data: request.bodyData() ?? Data(), encoding: .utf8) ?? ""
            XCTAssertEqual(body, "{}")
            let data = try JSONSerialization.data(withJSONObject: ["id": "job-4"])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        _ = try await client.runItem(
            workspaceID: "ws-1", itemID: "nb-1", itemType: .notebook,
            executionData: "", accessToken: token
        )
    }

    // MARK: - Cancel Job

    func testCancelJob() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("cancel") ?? false)
            XCTAssertTrue(request.url?.absoluteString.contains("jobs/instances/job-1/cancel") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.cancelJob(workspaceID: "ws-1", itemID: "nb-1", jobID: "job-1", accessToken: token)
    }

    // MARK: - Delete

    func testDeleteWorkspace() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.hasSuffix("v1/workspaces/ws-1") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        try await client.deleteWorkspace(workspaceID: "ws-1", accessToken: token)
    }

    func testDeleteItem() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("ws-1/items/item-1") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        try await client.deleteItem(workspaceID: "ws-1", itemID: "item-1", accessToken: token)
    }

    // MARK: - Create

    func testCreateWorkspace() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: request.bodyData()!) as! [String: String]
            XCTAssertEqual(body["displayName"], "New WS")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.createWorkspace(name: "New WS", accessToken: token)
    }

    func testCreateItem() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: request.bodyData()!) as! [String: String]
            XCTAssertEqual(body["displayName"], "My Notebook")
            XCTAssertEqual(body["type"], "Notebook")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.createItem(workspaceID: "ws-1", name: "My Notebook", type: .notebook, accessToken: token)
    }

    // MARK: - Rename / Update

    func testUpdateWorkspace() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try JSONSerialization.jsonObject(with: request.bodyData()!) as! [String: String]
            XCTAssertEqual(body["displayName"], "Renamed WS")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.updateWorkspace(workspaceID: "ws-1", displayName: "Renamed WS", description: nil, accessToken: token)
    }

    func testUpdateItemWithDescription() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            let body = try JSONSerialization.jsonObject(with: request.bodyData()!) as! [String: String]
            XCTAssertEqual(body["displayName"], "New Name")
            XCTAssertEqual(body["description"], "New description")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.updateItem(workspaceID: "ws-1", itemID: "item-1", displayName: "New Name", description: "New description", accessToken: token)
    }

    // MARK: - Capacity Assignment

    func testAssignCapacity() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("assignToCapacity") ?? false)
            let body = try JSONSerialization.jsonObject(with: request.bodyData()!) as! [String: String]
            XCTAssertEqual(body["capacityId"], "cap-1")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.assignCapacity(workspaceID: "ws-1", capacityID: "cap-1", accessToken: token)
    }

    func testUnassignCapacity() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("unassignFromCapacity") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.unassignCapacity(workspaceID: "ws-1", accessToken: token)
    }

    // MARK: - Role Assignments

    func testAddRoleAssignment() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("roleAssignments") ?? false)
            let body = try JSONSerialization.jsonObject(with: request.bodyData()!) as! [String: Any]
            let principal = body["principal"] as! [String: String]
            XCTAssertEqual(principal["id"], "user@example.com")
            XCTAssertEqual(principal["type"], "User")
            XCTAssertEqual(body["role"] as? String, "Contributor")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.addRoleAssignment(
            workspaceID: "ws-1", principalID: "user@example.com",
            principalType: "User", role: "Contributor", accessToken: token
        )
    }

    func testDeleteRoleAssignment() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertTrue(request.url?.absoluteString.contains("roleAssignments/ra-1") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        try await client.deleteRoleAssignment(workspaceID: "ws-1", assignmentID: "ra-1", accessToken: token)
    }

    func testListAllRoleAssignments() async throws {
        mockResponse(json: [
            "value": [
                ["id": "ra-1", "role": "Admin", "principal": ["id": "uid-1", "displayName": "Alice", "type": "User"]],
                ["id": "ra-2", "role": "Viewer", "principal": ["id": "uid-2", "displayName": "Bob", "type": "Group"]]
            ]
        ])

        let assignments = try await client.listAllRoleAssignments(workspaceID: "ws-1", accessToken: token)
        XCTAssertEqual(assignments.count, 2)
        XCTAssertEqual(assignments[0].principalName, "Alice")
        XCTAssertEqual(assignments[0].role, .admin)
        XCTAssertEqual(assignments[1].principalName, "Bob")
        XCTAssertEqual(assignments[1].principalType, "Group")
    }

    // MARK: - Sensitivity Labels

    func testSetSensitivityLabel() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("setSensitivityLabel") ?? false)
            let body = try JSONSerialization.jsonObject(with: request.bodyData()!) as! [String: String]
            XCTAssertEqual(body["labelId"], "label-123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.setSensitivityLabel(workspaceID: "ws-1", itemID: "item-1", labelID: "label-123", accessToken: token)
    }

    func testRemoveSensitivityLabel() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("removeSensitivityLabel") ?? false)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.removeSensitivityLabel(workspaceID: "ws-1", itemID: "item-1", accessToken: token)
    }

    // MARK: - Item Definition

    func testGetItemDefinition() async throws {
        let defJson: [String: Any] = ["definition": ["parts": []]]
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("getDefinition") ?? false)
            let data = try JSONSerialization.data(withJSONObject: defJson)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let data = try await client.getItemDefinition(workspaceID: "ws-1", itemID: "nb-1", accessToken: token)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["definition"])
    }

    func testUpdateItemDefinition() async throws {
        let definition = Data("{\"definition\":{}}".utf8)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("updateDefinition") ?? false)
            XCTAssertEqual(request.bodyData(), definition)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.updateItemDefinition(workspaceID: "ws-1", itemID: "nb-1", definition: definition, accessToken: token)
    }

    // MARK: - Tables

    func testListTables() async throws {
        mockResponse(json: [
            "data": [
                ["name": "sales", "format": "delta", "location": "Tables/sales"],
                ["name": "products", "format": "delta", "location": "Tables/products"]
            ]
        ])

        let tables = try await client.listTables(workspaceID: "ws-1", lakehouseID: "lh-1", accessToken: token)
        XCTAssertEqual(tables.count, 2)
    }

    func testLoadTable() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("tables/sales/load") ?? false)
            let body = try JSONSerialization.jsonObject(with: request.bodyData()!) as! [String: Any]
            XCTAssertEqual(body["relativePath"] as? String, "Files/data.csv")
            XCTAssertEqual(body["mode"] as? String, "Overwrite")
            let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.loadTable(
            workspaceID: "ws-1", lakehouseID: "lh-1", tableName: "sales",
            relativePath: "Files/data.csv", pathType: "File", mode: "Overwrite",
            accessToken: token
        )
    }

    // MARK: - Shortcuts

    func testCreateShortcut() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.absoluteString.contains("shortcuts") ?? false)
            let body = try JSONSerialization.jsonObject(with: request.bodyData()!) as! [String: Any]
            XCTAssertEqual(body["name"] as? String, "mylink")
            XCTAssertNotNil(body["target"])
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (Data("{}".utf8), response)
        }

        try await client.createShortcut(
            workspaceID: "ws-1", itemID: "lh-1", shortcutPath: "Tables",
            shortcutName: "mylink", targetWorkspaceID: "ws-2",
            targetItemID: "lh-2", targetPath: "Tables/shared",
            accessToken: token
        )
    }

    // MARK: - Item Detail

    func testGetItemDetail() async throws {
        mockResponse(json: [
            "id": "item-1",
            "displayName": "Test Item",
            "description": "A test item",
            "sensitivityLabel": ["labelId": "lbl-1", "label": "Confidential"]
        ])

        let detail = try await client.getItemDetail(workspaceID: "ws-1", itemID: "item-1", accessToken: token)
        XCTAssertEqual(detail.description, "A test item")
        XCTAssertEqual(detail.sensitivityLabel?.id, "lbl-1")
        XCTAssertEqual(detail.sensitivityLabel?.name, "Confidential")
    }

    func testGetItemDetailNoLabel() async throws {
        mockResponse(json: ["id": "item-1", "displayName": "Test"])

        let detail = try await client.getItemDetail(workspaceID: "ws-1", itemID: "item-1", accessToken: token)
        XCTAssertNil(detail.sensitivityLabel)
    }

    // MARK: - Error Handling

    func testUnauthorizedThrows() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        do {
            _ = try await client.listWorkspaces(accessToken: token)
            XCTFail("Should throw unauthorized")
        } catch let error as FabricAPIError {
            if case .unauthorized = error {
                // expected
            } else {
                XCTFail("Expected unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testServerErrorThrows() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data("Internal Server Error".utf8), response)
        }

        do {
            _ = try await client.listWorkspaces(accessToken: token)
            XCTFail("Should throw")
        } catch let error as FabricAPIError {
            if case .unexpectedStatus(let code, _) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected unexpectedStatus, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - JWT Helpers

    func testUserObjectIdFromJWT() {
        // JWT: {"oid": "user-123"} base64url encoded
        let payload = #"{"oid":"user-123","name":"Test User"}"#
        let b64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let fakeJWT = "header.\(b64).signature"

        XCTAssertEqual(FabricAPIClient.userObjectId(from: fakeJWT), "user-123")
    }

    func testUserInfoFromJWT() {
        let payload = #"{"name":"Alice Smith","preferred_username":"alice@example.com"}"#
        let b64 = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let fakeJWT = "header.\(b64).signature"

        let info = FabricAPIClient.userInfo(from: fakeJWT)
        XCTAssertEqual(info.name, "Alice Smith")
        XCTAssertEqual(info.email, "alice@example.com")
    }

    func testInvalidJWTReturnsNil() {
        XCTAssertNil(FabricAPIClient.userObjectId(from: ""))
        XCTAssertNil(FabricAPIClient.userObjectId(from: "not.a.jwt"))
        XCTAssertNil(FabricAPIClient.userObjectId(from: "a.!!!invalid!!!.b"))
    }

    // MARK: - Open in Browser

    func testOpenInBrowserURLFormation() {
        let ws = FabricItem(id: "ws-1", name: "WS", type: .workspace, workspaceID: nil, role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)
        // Just verify it doesn't crash - actual browser opening can't be tested
        client.openInBrowser(item: ws)

        let nb = FabricItem(id: "nb-1", name: "NB", type: .notebook, workspaceID: "ws-1", role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)
        client.openInBrowser(item: nb)
    }
}
