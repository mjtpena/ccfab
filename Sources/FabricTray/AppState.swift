import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

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

    // Favorites & Recents
    @Published var favoriteIDs: Set<String> = []
    @Published var recentItems: [(id: String, name: String, type: FabricItemType)] = []

    var filteredItems: [FabricItem] {
        let base: [FabricItem]
        if searchQuery.isEmpty {
            // Show favorites first, then the rest
            let favs = allItems.filter { favoriteIDs.contains($0.id) }
            let rest = allItems.filter { !favoriteIDs.contains($0.id) }
            base = favs + rest
        } else {
            base = allItems.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }
        return base
    }

    // Jobs
    @Published var recentJobs: [JobRun] = []
    @Published var showJobs = false

    // Capacities
    @Published var capacities: [FabricCapacity] = []
    /// CU utilization % per capacity ID (from Azure Monitor)
    @Published var capacityUtilization: [String: Double] = [:]

    /// Total estimated hourly cost across all active capacities (USD).
    var totalHourlyBurn: Double {
        capacities.filter(\.isActive).reduce(0) { $0 + $1.hourlyRate }
    }

    /// Estimated monthly cost across all active capacities (USD).
    var totalMonthlyEstimate: Double { totalHourlyBurn * 730.0 }

    /// Workspaces grouped by their capacity. Groups with known capacity details show rich info;
    /// workspaces on unknown capacities (no admin access) get a placeholder; unassigned get nil.
    var workspacesByCapacity: [(capacity: FabricCapacity?, workspaces: [FabricItem])] {
        let wsItems = allItems.filter { $0.type == .workspace }
        var grouped: [String: [FabricItem]] = [:]
        for ws in wsItems {
            let key = ws.capacityId ?? ""
            grouped[key, default: []].append(ws)
        }
        // Build capacity map from both self.capacities AND per-workspace capacity data
        var capMap: [String: FabricCapacity] = [:]
        for cap in capacities { capMap[cap.id] = cap }
        for ws in wsItems {
            if let capId = ws.capacityId, let cap = ws.capacity, capMap[capId] == nil {
                capMap[capId] = cap
            }
        }
        var result: [(FabricCapacity?, [FabricItem])] = []

        // Known capacities first (active then inactive, alphabetical)
        let knownKeys = grouped.keys.filter { !$0.isEmpty && capMap[$0] != nil }.sorted { a, b in
            let capA = capMap[a]!
            let capB = capMap[b]!
            if capA.isActive != capB.isActive { return capA.isActive }
            return capA.displayName < capB.displayName
        }
        for key in knownKeys {
            result.append((capMap[key], grouped[key] ?? []))
        }

        // Unknown capacities (have ID but no details at all) — one group per capacity ID
        let unknownKeys = grouped.keys.filter { !$0.isEmpty && capMap[$0] == nil }.sorted()
        for key in unknownKeys {
            let shortId = String(key.prefix(8))
            let placeholder = FabricCapacity(
                id: key, displayName: "Capacity (\(shortId)…)", sku: "",
                region: "", state: "Active"
            )
            result.append((placeholder, grouped[key] ?? []))
        }

        // No capacity
        if let unassigned = grouped[""], !unassigned.isEmpty {
            result.append((nil, unassigned))
        }
        return result
    }

    // ACL / Detail
    @Published var roleAssignments: [RoleAssignment] = []
    @Published var itemDetail: ItemDetail?

    // Status
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var lastRefreshTime: Date?
    @Published var lastFailedAction: (() async -> Void)?

    // Confirmation workflow
    @Published var pendingAction: PendingAction?
    @Published var pendingActionItemID: String?

    // Onboarding
    @Published var hasCompletedOnboarding: Bool

    // Notifications
    @Published var notificationsEnabled = true
    @Published var trayStatus: TrayStatus = .idle

    private let tokenStore = TokenStore()
    private lazy var authService = MicrosoftAuthService(tokenStore: tokenStore)
    private let api = FabricAPIClient()
    private let notificationDelegate = NotificationDelegate()
    private let config = AppConfiguration(
        tenantID: AppDefaults.tenantID,
        clientID: AppDefaults.clientID
    )
    private var jobPollTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?
    private var previousJobStatuses: [String: JobRunStatus] = [:]

    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        Task { @MainActor [weak self] in
            self?.setupNotifications()
            self?.restoreSession()
            self?.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
            self?.loadFavorites()
            self?.loadRecents()
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
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
        previousJobStatuses = [:]
        trayStatus = .idle
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
        await navigate(to: currentPath.parent)
    }

    func enter(item: FabricItem) async {
        if item.type == .workspace {
            addRecent(id: item.id, name: item.name, type: item.type)
            await navigate(to: NavigationPath(
                capacityID: currentPath.capacityID, capacityName: currentPath.capacityName,
                workspaceID: item.id, workspaceName: item.name
            ))
        } else if item.type == .lakehouse, let wsID = currentPath.workspaceID {
            addRecent(id: item.id, name: item.name, type: item.type)
            await navigate(to: NavigationPath(
                capacityID: currentPath.capacityID, capacityName: currentPath.capacityName,
                workspaceID: wsID, workspaceName: currentPath.workspaceName,
                subItemID: item.id, subItemName: item.name, subItemType: item.type
            ))
        }
    }

    /// Enter a capacity-scoped view showing its workspaces.
    func enterCapacity(_ cap: FabricCapacity) async {
        await navigate(to: .capacity(id: cap.id, name: cap.displayName))
    }

    func refresh() async {
        guard let token = await validToken() else { return }

        isLoading = true
        errorMessage = nil
        lastFailedAction = nil
        defer { isLoading = false }

        do {
            if currentPath.isCapacityLevel {
                // Show workspaces assigned to this capacity
                let allWS = try await api.listWorkspaces(accessToken: token.accessToken)
                allItems = allWS.filter { $0.capacityId == currentPath.capacityID }
                Task { await enrichWorkspaces() }
            } else if currentPath.isRoot {
                allItems = try await api.listWorkspaces(accessToken: token.accessToken)
                Task { await enrichWorkspaces() }
            } else if let wsID = currentPath.workspaceID, currentPath.isSubItem {
                // Sub-item level (e.g., lakehouse tables)
                if let lhID = currentPath.subItemID, currentPath.subItemType == .lakehouse {
                    let rawTables = try await api.listTables(workspaceID: wsID, lakehouseID: lhID, accessToken: token.accessToken)
                    allItems = rawTables.compactMap { dict -> FabricItem? in
                        guard let name = dict["name"] as? String else { return nil }
                        let tblType = dict["type"] as? String ?? ""
                        return FabricItem(
                            id: "\(lhID)_\(name)",
                            name: name,
                            type: .unknown,
                            workspaceID: wsID,
                            role: nil,
                            capacityId: nil,
                            capacity: nil,
                            sensitivityLabel: nil
                        )
                    }
                }
                Task { await fetchJobs() }
            } else if let wsID = currentPath.workspaceID {
                allItems = try await api.listItems(workspaceID: wsID, accessToken: token.accessToken)
                Task { await fetchJobs() }
            }
            lastRefreshTime = Date()
        } catch {
            lastFailedAction = { [weak self] in await self?.refresh() ?? () }
            showError(error.localizedDescription)
        }
    }

    func retryLastAction() async {
        if let action = lastFailedAction {
            await action()
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
        let newJobs = await api.listWorkspaceJobs(
            workspaceID: wsID, items: allItems, accessToken: token.accessToken
        )
        detectJobTransitions(oldJobs: recentJobs, newJobs: newJobs)
        recentJobs = newJobs
        updateTrayStatus()
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

    // MARK: - Notifications

    func toggleNotifications(_ enabled: Bool) {
        notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notificationsEnabled")
    }

    private func setupNotifications() {
        // UNUserNotificationCenter requires a valid app bundle; skip gracefully
        // when running as a bare executable (e.g. `swift run` without .app wrapper).
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func detectJobTransitions(oldJobs: [JobRun], newJobs: [JobRun]) {
        guard notificationsEnabled, !oldJobs.isEmpty else {
            // Seed the status map on first fetch so we don't spam on app launch
            for job in newJobs {
                previousJobStatuses[job.id] = job.status
            }
            return
        }
        let oldMap = Dictionary(uniqueKeysWithValues: oldJobs.map { ($0.id, $0.status) })
            .merging(previousJobStatuses) { current, _ in current }

        for job in newJobs {
            let prev = oldMap[job.id]
            if let prev, prev == .inProgress, job.status != .inProgress {
                sendJobNotification(job)
            }
            previousJobStatuses[job.id] = job.status
        }
    }

    private func sendJobNotification(_ job: JobRun) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        switch job.status {
        case .completed:
            content.title = "✅ Job Completed"
            content.body = "\(job.itemName) finished successfully."
            content.sound = .default
        case .failed:
            content.title = "❌ Job Failed"
            content.body = "\(job.itemName) failed."
            content.sound = UNNotificationSound.defaultCritical
        case .cancelled:
            content.title = "⏹ Job Cancelled"
            content.body = "\(job.itemName) was cancelled."
            content.sound = .default
        default:
            content.title = "Job Update"
            content.body = "\(job.itemName): \(job.status.rawValue)"
            content.sound = .default
        }
        content.categoryIdentifier = "JOB_STATUS"
        content.userInfo = ["jobId": job.id, "itemId": job.itemID]

        let request = UNNotificationRequest(
            identifier: "job-\(job.id)-\(job.status.rawValue)",
            content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func updateTrayStatus() {
        let activeJobs = recentJobs.filter { $0.status == .inProgress }
        let hasFailed = recentJobs.contains { $0.status == .failed }

        if !activeJobs.isEmpty {
            trayStatus = .running(count: activeJobs.count)
        } else if hasFailed {
            trayStatus = .attention
        } else {
            trayStatus = .idle
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
        withAnimation(.easeInOut(duration: 0.25)) {
            errorMessage = message
        }
        errorDismissTask?.cancel()
        errorDismissTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            if self.errorMessage == message {
                withAnimation(.easeInOut(duration: 0.25)) { self.errorMessage = nil }
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            toastMessage = message
        }
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            if self.toastMessage == message {
                withAnimation(.easeInOut(duration: 0.25)) { self.toastMessage = nil }
            }
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

        var capsMap = await capsTask
        let roles = await rolesTask

        // For capacity IDs not returned by the Fabric API, try Azure Resource Manager
        let unknownCapIds = Set(
            allItems.compactMap { $0.capacityId }.filter { !$0.isEmpty && capsMap[$0] == nil }
        )
        if !unknownCapIds.isEmpty {
            // Try ARM API — uses same identity, different scope
            let armCaps = await fetchCapacitiesViaARM()
            for (k, v) in armCaps where capsMap[k] == nil {
                capsMap[k] = v
            }

            // For anything still unknown, try direct Fabric capacity endpoint
            let stillUnknown = unknownCapIds.filter { capsMap[$0] == nil }
            if !stillUnknown.isEmpty {
                let apiClient = api
                await withTaskGroup(of: (String, FabricCapacity?).self) { group in
                    for capId in stillUnknown {
                        group.addTask {
                            return (capId, await apiClient.getCapacity(id: capId, accessToken: accessToken))
                        }
                    }
                    for await (capId, cap) in group {
                        if let cap = cap { capsMap[capId] = cap }
                    }
                }
            }
        }

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

        // Fetch real utilization metrics via Azure Monitor for capacities with ARM IDs
        await fetchCapacityUtilization()
    }

    private func fetchCapacityUtilization() async {
        let capsWithARM = capacities.filter { $0.armResourceId != nil && $0.isActive }
        guard !capsWithARM.isEmpty,
              let armToken = try? await authService.armAccessToken(configuration: config) else { return }
        let apiClient = api
        await withTaskGroup(of: (String, Double?).self) { group in
            for cap in capsWithARM {
                group.addTask {
                    let util = await apiClient.capacityUtilization(
                        armResourceId: cap.armResourceId!, armAccessToken: armToken
                    )
                    return (cap.id, util)
                }
            }
            for await (capId, util) in group {
                if let util = util {
                    self.capacityUtilization[capId] = util
                }
            }
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

    /// Fetch Fabric capacities via Azure Resource Manager using a separate ARM-scoped token.
    private func fetchCapacitiesViaARM() async -> [String: FabricCapacity] {
        guard let armToken = try? await authService.armAccessToken(configuration: config) else {
            return [:]
        }
        return await api.listCapacitiesViaARM(armAccessToken: armToken)
    }

    // MARK: - Capacity Pause / Resume

    @Published var capacityActionInProgress: String?

    func pauseCapacity(_ cap: FabricCapacity) async {
        guard let armId = cap.armResourceId else {
            toastMessage = "Cannot pause: missing ARM resource info"
            return
        }
        capacityActionInProgress = cap.id
        do {
            let armToken = try await authService.armAccessToken(configuration: config)
            try await api.suspendCapacity(armResourceId: armId, armAccessToken: armToken)
            // Update local state
            if let idx = capacities.firstIndex(where: { $0.id == cap.id }) {
                capacities[idx].state = "Paused"
            }
            toastMessage = "\(cap.displayName) paused"
        } catch {
            toastMessage = "Failed to pause: \(error.localizedDescription)"
        }
        capacityActionInProgress = nil
    }

    func resumeCapacity(_ cap: FabricCapacity) async {
        guard let armId = cap.armResourceId else {
            toastMessage = "Cannot resume: missing ARM resource info"
            return
        }
        capacityActionInProgress = cap.id
        do {
            let armToken = try await authService.armAccessToken(configuration: config)
            try await api.resumeCapacity(armResourceId: armId, armAccessToken: armToken)
            if let idx = capacities.firstIndex(where: { $0.id == cap.id }) {
                capacities[idx].state = "Active"
            }
            toastMessage = "\(cap.displayName) resumed"
        } catch {
            toastMessage = "Failed to resume: \(error.localizedDescription)"
        }
        capacityActionInProgress = nil
    }

    // MARK: - Favorites

    func toggleFavorite(_ itemID: String) {
        if favoriteIDs.contains(itemID) {
            favoriteIDs.remove(itemID)
        } else {
            favoriteIDs.insert(itemID)
        }
        saveFavorites()
    }

    func isFavorite(_ itemID: String) -> Bool {
        favoriteIDs.contains(itemID)
    }

    private func loadFavorites() {
        let stored = UserDefaults.standard.stringArray(forKey: "favoriteItemIDs") ?? []
        favoriteIDs = Set(stored)
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: "favoriteItemIDs")
    }

    // MARK: - Recents

    private func addRecent(id: String, name: String, type: FabricItemType) {
        recentItems.removeAll { $0.id == id }
        recentItems.insert((id: id, name: name, type: type), at: 0)
        if recentItems.count > 5 { recentItems = Array(recentItems.prefix(5)) }
        saveRecents()
    }

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: "recentItems"),
              let decoded = try? JSONDecoder().decode([[String: String]].self, from: data) else { return }
        recentItems = decoded.compactMap { dict in
            guard let id = dict["id"], let name = dict["name"], let typeRaw = dict["type"] else { return nil }
            return (id: id, name: name, type: FabricItemType.from(typeRaw))
        }
    }

    private func saveRecents() {
        let encoded = recentItems.map { ["id": $0.id, "name": $0.name, "type": $0.type.rawValue] }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: "recentItems")
        }
    }
}
