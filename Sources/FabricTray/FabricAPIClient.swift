import AppKit
import Foundation

enum FabricAPIError: LocalizedError {
    case invalidEndpoint
    case unauthorized
    case unexpectedStatus(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Invalid Fabric API URL."
        case .unauthorized: return "Unauthorized. Sign in again."
        case .unexpectedStatus(let code, let body):
            return body.isEmpty ? "API error \(code)." : "API error \(code): \(body)"
        case .invalidResponse: return "Invalid API response."
        }
    }
}

final class FabricAPIClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Workspaces

    func listWorkspaces(accessToken: String) async throws -> [FabricItem] {
        let objects = try await getAll(path: "v1/workspaces", accessToken: accessToken)
        return parseItemObjects(objects, type: .workspace, workspaceID: nil)
    }

    // MARK: - Capacities

    func listCapacities(accessToken: String) async throws -> [String: FabricCapacity] {
        let data = try await get(path: "v1/capacities", accessToken: accessToken)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let objects = root["value"] as? [[String: Any]] else { return [:] }
        var map: [String: FabricCapacity] = [:]
        for obj in objects {
            guard let id = obj["id"] as? String else { continue }
            map[id] = FabricCapacity(
                id: id,
                displayName: (obj["displayName"] as? String) ?? "",
                sku: (obj["sku"] as? String) ?? "",
                region: (obj["region"] as? String) ?? "",
                state: (obj["state"] as? String) ?? ""
            )
        }
        return map
    }

    // MARK: - Items in workspace

    func listItems(workspaceID: String, accessToken: String) async throws -> [FabricItem] {
        let objects = try await getAll(path: "v1/workspaces/\(workspaceID)/items", accessToken: accessToken)
        return parseItemObjects(objects, type: nil, workspaceID: workspaceID)
    }

    // MARK: - Run item (notebook / pipeline)

    func runItem(workspaceID: String, itemID: String, itemType: FabricItemType, executionData: String? = nil, accessToken: String) async throws -> String? {
        let jobType: String
        switch itemType {
        case .dataPipeline: jobType = "Pipeline"
        case .sparkJobDefinition: jobType = "SparkJobDefinition"
        default: jobType = "RunNotebook"
        }
        let url = apiURL("v1/workspaces/\(workspaceID)/items/\(itemID)/jobs/instances?jobType=\(jobType)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let execData = executionData, !execData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let jsonData = execData.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: jsonData)) != nil {
            request.httpBody = "{\"executionData\":\(execData)}".data(using: .utf8)
        } else {
            request.httpBody = "{}".data(using: .utf8)
        }

        let (data, response) = try await session.data(for: request)
        let httpResponse = try httpOK(response, data: data, accepted: 200..<300)

        if let location = httpResponse.value(forHTTPHeaderField: "Location"),
           let jobID = location.components(separatedBy: "/").last {
            return jobID
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return json?["id"] as? String
    }

    // MARK: - Job status

    func jobInstances(workspaceID: String, itemID: String, accessToken: String) async throws -> [JobRun] {
        let data = try await get(
            path: "v1/workspaces/\(workspaceID)/items/\(itemID)/jobs/instances?limit=5",
            accessToken: accessToken
        )
        return parseJobRuns(from: data, itemName: "")
    }

    func cancelJob(workspaceID: String, itemID: String, jobID: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/items/\(itemID)/jobs/instances/\(jobID)/cancel")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.httpBody = "{}".data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - Open in browser

    func openInBrowser(item: FabricItem) {
        let base = "https://app.fabric.microsoft.com"
        let urlString: String
        if item.type == .workspace {
            urlString = "\(base)/groups/\(item.id)"
        } else if let wsID = item.workspaceID, !item.type.urlPathSegment.isEmpty {
            urlString = "\(base)/groups/\(wsID)/\(item.type.urlPathSegment)/\(item.id)"
        } else if let wsID = item.workspaceID {
            urlString = "\(base)/groups/\(wsID)"
        } else {
            return
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Role assignments

    func fetchRoleAssignment(workspaceID: String, userObjectId: String, accessToken: String) async -> WorkspaceRole? {
        guard let data = try? await get(
            path: "v1/workspaces/\(workspaceID)/roleAssignments",
            accessToken: accessToken
        ) else { return nil }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let assignments = root["value"] as? [[String: Any]] else { return nil }
        for assignment in assignments {
            if let principal = assignment["principal"] as? [String: Any],
               let pid = principal["id"] as? String,
               pid.caseInsensitiveCompare(userObjectId) == .orderedSame,
               let roleStr = assignment["role"] as? String {
                return WorkspaceRole.from(roleStr)
            }
        }
        return nil
    }

    // MARK: - All role assignments (ACL)

    func listAllRoleAssignments(workspaceID: String, accessToken: String) async throws -> [RoleAssignment] {
        let data = try await get(path: "v1/workspaces/\(workspaceID)/roleAssignments", accessToken: accessToken)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let assignments = root["value"] as? [[String: Any]] else { return [] }
        return assignments.compactMap { obj in
            guard let id = obj["id"] as? String,
                  let roleStr = obj["role"] as? String,
                  let role = WorkspaceRole.from(roleStr),
                  let principal = obj["principal"] as? [String: Any] else { return nil }
            let name = (principal["displayName"] as? String) ?? (principal["id"] as? String) ?? "Unknown"
            let pType = (principal["type"] as? String) ?? "User"
            return RoleAssignment(id: id, principalName: name, principalType: pType, role: role)
        }
    }

    // MARK: - Workspace jobs (aggregated)

    func listWorkspaceJobs(workspaceID: String, items: [FabricItem], accessToken: String) async -> [JobRun] {
        let runnableItems = Array(items.filter { $0.type.isRunnable }.prefix(10))
        guard !runnableItems.isEmpty else { return [] }
        return await withTaskGroup(of: [JobRun].self, returning: [JobRun].self) { group in
            for item in runnableItems {
                let itemName = item.name
                let itemID = item.id
                group.addTask { [self] in
                    guard let data = try? await self.get(
                        path: "v1/workspaces/\(workspaceID)/items/\(itemID)/jobs/instances?limit=3",
                        accessToken: accessToken
                    ) else { return [] }
                    return self.parseJobRuns(from: data, itemName: itemName)
                }
            }
            var all: [JobRun] = []
            for await jobs in group { all.append(contentsOf: jobs) }
            return all.sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        }
    }

    // MARK: - Item detail

    func getItemDetail(workspaceID: String, itemID: String, accessToken: String) async throws -> ItemDetail {
        let data = try await get(path: "v1/workspaces/\(workspaceID)/items/\(itemID)", accessToken: accessToken)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ItemDetail(description: nil, sensitivityLabel: nil)
        }
        let desc = obj["description"] as? String
        var label: SensitivityLabel?
        if let labelObj = obj["sensitivityLabel"] as? [String: Any],
           let lid = labelObj["labelId"] as? String,
           let lname = labelObj["label"] as? String {
            label = SensitivityLabel(id: lid, name: lname)
        }
        return ItemDetail(description: desc, sensitivityLabel: label)
    }

    // MARK: - JWT helpers

    static func userObjectId(from accessToken: String) -> String? {
        jwtClaim(from: accessToken, key: "oid")
    }

    static func userInfo(from accessToken: String) -> (name: String?, email: String?) {
        let name = jwtClaim(from: accessToken, key: "name")
        let email = jwtClaim(from: accessToken, key: "preferred_username") ?? jwtClaim(from: accessToken, key: "upn")
        return (name, email)
    }

    private static func jwtClaim(from accessToken: String, key: String) -> String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - base64.count % 4) % 4
        if pad < 4 { base64 += String(repeating: "=", count: pad) }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json[key] as? String
    }

    // MARK: - Delete

    func deleteWorkspace(workspaceID: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    func deleteItem(workspaceID: String, itemID: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/items/\(itemID)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - Create

    func createWorkspace(name: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["displayName": name])
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    func createItem(workspaceID: String, name: String, type: FabricItemType, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/items")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["displayName": name, "type": type.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - Rename / Update

    func updateWorkspace(workspaceID: String, displayName: String?, description: String?, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let n = displayName { body["displayName"] = n }
        if let d = description { body["description"] = d }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    func updateItem(workspaceID: String, itemID: String, displayName: String?, description: String?, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/items/\(itemID)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [:]
        if let n = displayName { body["displayName"] = n }
        if let d = description { body["description"] = d }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - Capacity assignment

    func assignCapacity(workspaceID: String, capacityID: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/assignToCapacity")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["capacityId": capacityID])
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    func unassignCapacity(workspaceID: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/unassignFromCapacity")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - Role assignments (write)

    func addRoleAssignment(workspaceID: String, principalID: String, principalType: String, role: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/roleAssignments")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["principal": ["id": principalID, "type": principalType], "role": role]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    func deleteRoleAssignment(workspaceID: String, assignmentID: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/roleAssignments/\(assignmentID)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "DELETE"
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - Sensitivity labels (write)

    func setSensitivityLabel(workspaceID: String, itemID: String, labelID: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/items/\(itemID)/setSensitivityLabel")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["labelId": labelID])
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    func removeSensitivityLabel(workspaceID: String, itemID: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/items/\(itemID)/removeSensitivityLabel")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - Item definitions (export / import)

    func getItemDefinition(workspaceID: String, itemID: String, accessToken: String) async throws -> Data {
        let url = apiURL("v1/workspaces/\(workspaceID)/items/\(itemID)/getDefinition")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
        return data
    }

    func updateItemDefinition(workspaceID: String, itemID: String, definition: Data, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/items/\(itemID)/updateDefinition")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = definition
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - Lakehouse tables

    func listTables(workspaceID: String, lakehouseID: String, accessToken: String) async throws -> [[String: Any]] {
        let data = try await get(path: "v1/workspaces/\(workspaceID)/lakehouses/\(lakehouseID)/tables", accessToken: accessToken)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tables = root["data"] as? [[String: Any]] else { return [] }
        return tables
    }

    func loadTable(workspaceID: String, lakehouseID: String, tableName: String, relativePath: String, pathType: String, mode: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/lakehouses/\(lakehouseID)/tables/\(tableName)/load")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["relativePath": relativePath, "pathType": pathType, "mode": mode]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - Shortcuts

    func createShortcut(workspaceID: String, itemID: String, shortcutPath: String, shortcutName: String, targetWorkspaceID: String, targetItemID: String, targetPath: String, accessToken: String) async throws {
        let url = apiURL("v1/workspaces/\(workspaceID)/items/\(itemID)/shortcuts")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "path": shortcutPath,
            "name": shortcutName,
            "target": ["oneLake": ["workspaceId": targetWorkspaceID, "itemId": targetItemID, "path": targetPath]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
    }

    // MARK: - OneLake file upload

    func uploadToOneLake(workspaceName: String, itemName: String, itemType: String, destinationPath: String, fileData: Data, accessToken: String) async throws {
        let encoded = destinationPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? destinationPath
        let base = "https://onelake.dfs.fabric.microsoft.com/\(workspaceName)/\(itemName).\(itemType)/\(encoded)"

        guard let createURL = URL(string: "\(base)?resource=file") else { throw FabricAPIError.invalidEndpoint }
        var createReq = authorizedRequest(url: createURL, accessToken: accessToken)
        createReq.httpMethod = "PUT"
        let (_, createResp) = try await session.data(for: createReq)
        _ = try httpOK(createResp, data: Data(), accepted: 200..<300)

        guard let appendURL = URL(string: "\(base)?action=append&position=0") else { throw FabricAPIError.invalidEndpoint }
        var appendReq = authorizedRequest(url: appendURL, accessToken: accessToken)
        appendReq.httpMethod = "PATCH"
        appendReq.httpBody = fileData
        appendReq.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, appendResp) = try await session.data(for: appendReq)
        _ = try httpOK(appendResp, data: Data(), accepted: 200..<300)

        guard let flushURL = URL(string: "\(base)?action=flush&position=\(fileData.count)") else { throw FabricAPIError.invalidEndpoint }
        var flushReq = authorizedRequest(url: flushURL, accessToken: accessToken)
        flushReq.httpMethod = "PATCH"
        let (_, flushResp) = try await session.data(for: flushReq)
        _ = try httpOK(flushResp, data: Data(), accepted: 200..<300)
    }

    // MARK: - Private

    private func getFromURL(_ url: URL, accessToken: String) async throws -> Data {
        let request = authorizedRequest(url: url, accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        _ = try httpOK(response, data: data, accepted: 200..<300)
        return data
    }

    private func get(path: String, accessToken: String) async throws -> Data {
        try await getFromURL(apiURL(path), accessToken: accessToken)
    }

    private func getAll(path: String, accessToken: String) async throws -> [[String: Any]] {
        var allObjects: [[String: Any]] = []
        var nextURL: URL? = apiURL(path)
        while let url = nextURL {
            let data = try await getFromURL(url, accessToken: accessToken)
            guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { break }
            if let objects = root["value"] as? [[String: Any]] {
                allObjects.append(contentsOf: objects)
            }
            nextURL = nil
            if let continuationUri = root["continuationUri"] as? String,
               let uri = URL(string: continuationUri) {
                nextURL = uri
            } else if let token = root["continuationToken"] as? String, !token.isEmpty {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var items = components?.queryItems ?? []
                items.removeAll { $0.name == "continuationToken" }
                items.append(URLQueryItem(name: "continuationToken", value: token))
                components?.queryItems = items
                nextURL = components?.url
            }
        }
        return allObjects
    }

    private func apiURL(_ path: String) -> URL {
        URL(string: "https://api.fabric.microsoft.com/\(path)")!
    }

    private func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    @discardableResult
    private func httpOK(_ response: URLResponse, data: Data, accepted: Range<Int>) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw FabricAPIError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw FabricAPIError.unauthorized
        }
        guard accepted.contains(http.statusCode) else {
            throw FabricAPIError.unexpectedStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return http
    }

    private func parseItemObjects(_ objects: [[String: Any]], type: FabricItemType?, workspaceID: String?) -> [FabricItem] {
        return objects.compactMap { obj -> FabricItem? in
            guard let id = (obj["id"] ?? obj["workspaceId"]) as? String else { return nil }
            let name = (obj["displayName"] ?? obj["name"]) as? String ?? "Untitled"
            let itemType = type ?? FabricItemType.from((obj["type"] as? String) ?? "Unknown")
            let role = (obj["role"] as? String).flatMap { WorkspaceRole.from($0) }
            let capId = obj["capacityId"] as? String
            let label: SensitivityLabel? = (obj["sensitivityLabel"] as? [String: Any]).flatMap { lo in
                guard let lid = lo["labelId"] as? String,
                      let lname = lo["label"] as? String else { return nil }
                return SensitivityLabel(id: lid, name: lname)
            }
            return FabricItem(id: id, name: name, type: itemType, workspaceID: workspaceID, role: role, capacityId: capId, capacity: nil, sensitivityLabel: label)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseJobRuns(from data: Data, itemName: String) -> [JobRun] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        let objects = (root["value"] as? [[String: Any]]) ?? []

        return objects.compactMap { obj -> JobRun? in
            guard let id = obj["id"] as? String else { return nil }
            let status = JobRunStatus.from((obj["status"] as? String) ?? "Unknown")
            let itemID = (obj["itemId"] as? String) ?? ""
            var startedAt: Date?
            if let ts = obj["startTimeUtc"] as? String {
                startedAt = ISO8601DateFormatter().date(from: ts)
            }
            return JobRun(id: id, itemID: itemID, itemName: itemName, status: status, startedAt: startedAt)
        }
    }
}
