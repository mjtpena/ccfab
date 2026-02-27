import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    // Auth
    @Published var isSignedIn = false
    @Published var isAuthenticating = false
    @Published var userName: String?
    @Published var userEmail: String?

    // Navigation
    @Published var currentPath = NavigationPath.root
    @Published var allItems: [FabricItem] = []
    @Published var searchQuery = ""
    @Published var isLoading = false

    var filteredItems: [FabricItem] {
        guard !searchQuery.isEmpty else { return allItems }
        return allItems.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    // Jobs
    @Published var recentJobs: [JobRun] = []
    @Published var showJobs = false

    // Capacities
    @Published var capacities: [FabricCapacity] = []

    // ACL / Detail
    @Published var roleAssignments: [RoleAssignment] = []
    @Published var itemDetail: ItemDetail?

    // Status
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var lastRefreshTime: Date?

    // Confirmation workflow
    @Published var pendingAction: PendingAction?

    private let tokenStore = TokenStore()
    private lazy var authService = MicrosoftAuthService(tokenStore: tokenStore)
    private let api = FabricAPIClient()
    private let config = AppConfiguration(
        tenantID: AppDefaults.tenantID,
        clientID: AppDefaults.clientID
    )
    private var jobPollTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?

    init() {
        Task { @MainActor [weak self] in
            self?.restoreSession()
        }
    }

    // MARK: - Auth

    func signIn() async {
        guard config.isComplete else { return }
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let token = try await authService.authenticate(configuration: config)
            isSignedIn = true
            extractUserInfo(from: token.accessToken)
            await navigate(to: .root)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func signOut() {
        try? authService.clearToken()
        stopJobPolling()
        isSignedIn = false
        allItems = []
        searchQuery = ""
        recentJobs = []
        capacities = []
        roleAssignments = []
        itemDetail = nil
        userName = nil
        userEmail = nil
        toastMessage = nil
        lastRefreshTime = nil
        currentPath = .root
        errorMessage = nil
    }

    // MARK: - Navigation

    func navigate(to path: NavigationPath) async {
        currentPath = path
        searchQuery = ""
        await refresh()
        if !path.isRoot {
            startJobPolling()
        } else {
            stopJobPolling()
        }
    }

    func navigateUp() async {
        await navigate(to: .root)
    }

    func enter(item: FabricItem) async {
        if item.type == .workspace {
            await navigate(to: NavigationPath(workspaceID: item.id, workspaceName: item.name))
        }
    }

    func refresh() async {
        guard let token = await validToken() else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if currentPath.isRoot {
                allItems = try await api.listWorkspaces(accessToken: token.accessToken)
                Task { await enrichWorkspaces() }
            } else if let wsID = currentPath.workspaceID {
                allItems = try await api.listItems(workspaceID: wsID, accessToken: token.accessToken)
                Task { await fetchJobs() }
            }
            lastRefreshTime = Date()
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - Action Requests

    func requestRun(_ item: FabricItem) {
        pendingAction = PendingAction(kind: .run(item))
    }

    func requestCancelJob(_ job: JobRun) {
        pendingAction = PendingAction(kind: .cancelJob(job))
    }

    func requestDelete(_ item: FabricItem) {
        pendingAction = PendingAction(kind: .deleteItem(item))
    }

    func requestRename(_ item: FabricItem) {
        pendingAction = PendingAction(kind: .renameItem(item))
    }

    func requestCreateWorkspace() {
        pendingAction = PendingAction(kind: .createWorkspace)
    }

    func requestCreateItem() {
        guard let wsID = currentPath.workspaceID else { return }
        pendingAction = PendingAction(kind: .createItem(workspaceID: wsID))
    }

    func requestAssignCapacity(_ item: FabricItem) {
        pendingAction = PendingAction(kind: .assignCapacity(item))
    }

    func requestUnassignCapacity(_ item: FabricItem) {
        pendingAction = PendingAction(kind: .unassignCapacity(item))
    }

    func requestAddRole(workspaceID: String) {
        pendingAction = PendingAction(kind: .addRole(workspaceID: workspaceID))
    }

    func requestRemoveRole(_ ra: RoleAssignment, workspaceID: String) {
        pendingAction = PendingAction(kind: .removeRole(ra, workspaceID: workspaceID))
    }

    func requestSetLabel(_ item: FabricItem) {
        let wsID = item.workspaceID ?? currentPath.workspaceID ?? ""
        pendingAction = PendingAction(kind: .setLabel(item, workspaceID: wsID))
    }

    func requestRemoveLabel(_ item: FabricItem) {
        let wsID = item.workspaceID ?? currentPath.workspaceID ?? ""
        pendingAction = PendingAction(kind: .removeLabel(item, workspaceID: wsID))
    }

    func requestExport(_ item: FabricItem) {
        let wsID = item.workspaceID ?? currentPath.workspaceID ?? ""
        pendingAction = PendingAction(kind: .exportDefinition(item, workspaceID: wsID))
    }

    func requestImport() {
        guard let wsID = currentPath.workspaceID else { return }
        pendingAction = PendingAction(kind: .importItem(workspaceID: wsID))
    }

    func requestCreateShortcut(_ item: FabricItem) {
        let wsID = item.workspaceID ?? currentPath.workspaceID ?? ""
        pendingAction = PendingAction(kind: .createShortcut(item, workspaceID: wsID))
    }

    func requestUploadFile(_ item: FabricItem) {
        let wsName = currentPath.workspaceName ?? ""
        pendingAction = PendingAction(kind: .uploadFile(item, workspaceName: wsName))
    }

    func dismissAction() {
        pendingAction = nil
    }

    // MARK: - Confirm Action

    func confirmAction(textInput: String = "", textInput2: String = "", selectedType: FabricItemType = .notebook, selectedRole: WorkspaceRole = .viewer, selectedCapacityID: String = "") async {
        guard let action = pendingAction else { return }
        pendingAction = nil

        switch action.kind {
        case .run(let item):
            await executeRun(item, parameters: textInput)
            return
        case .cancelJob(let job):
            await executeCancelJob(job)
            return
        case .exportDefinition(let item, let wsID):
            await performExport(item: item, workspaceID: wsID)
            return
        default:
            break
        }

        guard let token = await validToken() else { return }
        let at = token.accessToken

        do {
            switch action.kind {
            case .deleteItem(let item):
                if item.type == .workspace {
                    try await api.deleteWorkspace(workspaceID: item.id, accessToken: at)
                } else {
                    let wsID = item.workspaceID ?? currentPath.workspaceID ?? ""
                    try await api.deleteItem(workspaceID: wsID, itemID: item.id, accessToken: at)
                }
                showToast("\(item.name) deleted")

            case .renameItem(let item):
                if item.type == .workspace {
                    try await api.updateWorkspace(workspaceID: item.id, displayName: textInput, description: nil, accessToken: at)
                } else {
                    let wsID = item.workspaceID ?? currentPath.workspaceID ?? ""
                    try await api.updateItem(workspaceID: wsID, itemID: item.id, displayName: textInput, description: nil, accessToken: at)
                }
                showToast("Renamed to \(textInput)")

            case .createWorkspace:
                try await api.createWorkspace(name: textInput, accessToken: at)
                showToast("\(textInput) created")

            case .createItem(let wsID):
                try await api.createItem(workspaceID: wsID, name: textInput, type: selectedType, accessToken: at)
                showToast("\(textInput) created")

            case .assignCapacity(let item):
                try await api.assignCapacity(workspaceID: item.id, capacityID: selectedCapacityID, accessToken: at)
                showToast("Capacity assigned")

            case .unassignCapacity(let item):
                try await api.unassignCapacity(workspaceID: item.id, accessToken: at)
                showToast("Capacity unassigned")

            case .addRole(let wsID):
                try await api.addRoleAssignment(workspaceID: wsID, principalID: textInput, principalType: "User", role: selectedRole.rawValue, accessToken: at)
                showToast("Access added")

            case .removeRole(let ra, let wsID):
                try await api.deleteRoleAssignment(workspaceID: wsID, assignmentID: ra.id, accessToken: at)
                showToast("Access removed")

            case .setLabel(let item, let wsID):
                try await api.setSensitivityLabel(workspaceID: wsID, itemID: item.id, labelID: textInput, accessToken: at)
                showToast("Label set")

            case .removeLabel(let item, let wsID):
                try await api.removeSensitivityLabel(workspaceID: wsID, itemID: item.id, accessToken: at)
                showToast("Label removed")

            case .importItem(let wsID):
                await performImport(workspaceID: wsID)
                return

            case .createShortcut(let item, let wsID):
                try await api.createShortcut(workspaceID: wsID, itemID: item.id, shortcutPath: textInput, shortcutName: textInput, targetWorkspaceID: "", targetItemID: "", targetPath: textInput2, accessToken: at)
                showToast("Shortcut created")

            case .uploadFile(let item, let wsName):
                await performUpload(item: item, workspaceName: wsName)
                return

            case .loadTable(let wsID, let lhID, let table):
                try await api.loadTable(workspaceID: wsID, lakehouseID: lhID, tableName: table, relativePath: textInput, pathType: "File", mode: "Overwrite", accessToken: at)
                showToast("Table \(table) loaded")

            default: break
            }
            await refresh()
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - Actions (internal)

    private func executeRun(_ item: FabricItem, parameters: String = "") async {
        guard item.type.isRunnable, let wsID = item.workspaceID ?? currentPath.workspaceID else { return }
        guard let token = await validToken() else { return }

        do {
            let execData = parameters.isEmpty ? nil : parameters
            _ = try await api.runItem(workspaceID: wsID, itemID: item.id, itemType: item.type, executionData: execData, accessToken: token.accessToken)
            showToast("\(item.name) started")
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await fetchJobs()
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func executeCancelJob(_ job: JobRun) async {
        guard let wsID = currentPath.workspaceID else { return }
        guard let token = await validToken() else { return }
        do {
            try await api.cancelJob(workspaceID: wsID, itemID: job.itemID, jobID: job.id, accessToken: token.accessToken)
            showToast("Job cancelled")
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await fetchJobs()
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func performExport(item: FabricItem, workspaceID: String) async {
        guard let token = await validToken() else { return }
        do {
            let data = try await api.getItemDefinition(workspaceID: workspaceID, itemID: item.id, accessToken: token.accessToken)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(item.name).json"
            panel.allowedContentTypes = [.json]
            let result = panel.runModal()
            if result == .OK, let url = panel.url {
                try data.write(to: url)
                showToast("\(item.name) exported")
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func performImport(workspaceID: String) async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        let result = panel.runModal()
        guard result == .OK, let url = panel.url else { return }
        guard let token = await validToken() else { return }
        do {
            let data = try Data(contentsOf: url)
            // Try to parse as definition to determine item ID, or create new
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let _ = json["definition"] {
                // Has definition structure — could update existing item
                // For import, we just update if we can determine the item
                showToast("Definition loaded. Use updateDefinition on specific item.")
            } else {
                showToast("Imported \(url.lastPathComponent)")
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func performUpload(item: FabricItem, workspaceName: String) async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.message = "Select file to upload to \(item.name)/Files/"
        let result = panel.runModal()
        guard result == .OK, let url = panel.url else { return }
        guard let token = await validToken() else { return }
        do {
            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            try await api.uploadToOneLake(
                workspaceName: workspaceName, itemName: item.name,
                itemType: item.type.rawValue, destinationPath: "Files/\(fileName)",
                fileData: data, accessToken: token.accessToken
            )
            showToast("\(fileName) uploaded")
        } catch {
            showError(error.localizedDescription)
        }
    }

    func openItem(_ item: FabricItem) {
        api.openInBrowser(item: item)
    }

    // MARK: - Jobs

    func fetchJobs() async {
        guard let wsID = currentPath.workspaceID,
              let token = await validToken() else { return }
        recentJobs = await api.listWorkspaceJobs(
            workspaceID: wsID, items: allItems, accessToken: token.accessToken
        )
    }

    // MARK: - ACL

    func fetchRoleAssignments(workspaceID: String) async {
        guard let token = await validToken() else { return }
        do {
            roleAssignments = try await api.listAllRoleAssignments(
                workspaceID: workspaceID, accessToken: token.accessToken
            )
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - Item Detail

    func fetchItemDetail(workspaceID: String, itemID: String) async {
        guard let token = await validToken() else { return }
        do {
            itemDetail = try await api.getItemDetail(
                workspaceID: workspaceID, itemID: itemID, accessToken: token.accessToken
            )
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func validToken() async -> StoredAuthToken? {
        if let token = try? authService.currentToken(for: config), !token.isExpired {
            return token
        }
        // Try silent refresh
        if let refreshed = try? await authService.refreshAccessToken(configuration: config) {
            extractUserInfo(from: refreshed.accessToken)
            return refreshed
        }
        isSignedIn = false
        errorMessage = "Session expired. Please sign in again."
        return nil
    }

    private func extractUserInfo(from accessToken: String) {
        let info = FabricAPIClient.userInfo(from: accessToken)
        userName = info.name
        userEmail = info.email
    }

    private func showError(_ message: String) {
        errorMessage = message
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            if self.errorMessage == message { self.errorMessage = nil }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            if self.toastMessage == message { self.toastMessage = nil }
        }
    }

    private func startJobPolling() {
        stopJobPolling()
        guard currentPath.workspaceID != nil else { return }
        jobPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await fetchJobs()
            }
        }
    }

    private func stopJobPolling() {
        jobPollTask?.cancel()
        jobPollTask = nil
    }

    private func restoreSession() {
        guard config.isComplete,
              let token = try? authService.currentToken(for: config),
              !token.isExpired else {
            isSignedIn = false
            return
        }
        isSignedIn = true
        extractUserInfo(from: token.accessToken)
    }

    private func enrichWorkspaces() async {
        guard let token = await validToken() else { return }
        let accessToken = token.accessToken

        async let capsTask: [String: FabricCapacity] = {
            (try? await api.listCapacities(accessToken: accessToken)) ?? [:]
        }()
        async let rolesTask: [String: WorkspaceRole] = {
            await self.fetchRolesMap(accessToken: accessToken)
        }()

        let capsMap = await capsTask
        let roles = await rolesTask

        self.capacities = Array(capsMap.values).sorted { $0.displayName < $1.displayName }

        guard !capsMap.isEmpty || !roles.isEmpty else { return }
        allItems = allItems.map { item in
            guard item.type == .workspace else { return item }
            let cap = item.capacityId.flatMap { capsMap[$0] } ?? item.capacity
            let role = roles[item.id] ?? item.role
            guard cap != item.capacity || role != item.role else { return item }
            return FabricItem(
                id: item.id, name: item.name, type: item.type,
                workspaceID: item.workspaceID, role: role,
                capacityId: item.capacityId, capacity: cap,
                sensitivityLabel: item.sensitivityLabel
            )
        }
    }

    private func fetchRolesMap(accessToken: String) async -> [String: WorkspaceRole] {
        guard let oid = FabricAPIClient.userObjectId(from: accessToken) else { return [:] }
        let apiClient = api
        let workspaceIds = allItems.filter { $0.type == .workspace }.map { $0.id }

        return await withTaskGroup(
            of: (String, WorkspaceRole?).self,
            returning: [String: WorkspaceRole].self
        ) { group in
            for wsId in workspaceIds {
                group.addTask {
                    let role = await apiClient.fetchRoleAssignment(
                        workspaceID: wsId, userObjectId: oid, accessToken: accessToken
                    )
                    return (wsId, role)
                }
            }
            var result: [String: WorkspaceRole] = [:]
            for await (wsId, role) in group {
                if let role = role { result[wsId] = role }
            }
            return result
        }
    }
}
