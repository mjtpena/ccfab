import AppKit
import SwiftUI

struct TrayView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var prefs: TrayPreferences
    @State private var expandedItemID: String?
    @State private var showCapacities = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()

            if appState.isSignedIn {
                itemList

                if !appState.currentPath.isRoot {
                    Divider()
                    jobsSection
                }

                if appState.currentPath.isRoot && !appState.capacities.isEmpty {
                    Divider()
                    capacitiesSection
                }
            } else {
                signedOutPlaceholder
            }

            if let toast = appState.toastMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(toast)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .transition(.opacity)
            }

            if let error = appState.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
            }

            if appState.pendingAction != nil {
                Divider()
                ActionConfirmationView()
                    .environmentObject(appState)
            }

            Divider()
            footerBar
        }
        .frame(width: prefs.density.windowWidth)
        .task {
            if appState.isSignedIn && appState.allItems.isEmpty {
                await appState.refresh()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 4) {
            Button {
                Task { await appState.navigateUp() }
            } label: {
                Text("/")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(appState.currentPath.isRoot ? Color.primary : Color.blue)
            .disabled(!appState.isSignedIn || appState.currentPath.isRoot)

            if let wsName = appState.currentPath.workspaceName {
                Text(wsName)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 100)
                Text("/")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if appState.isSignedIn {
                TextField(
                    appState.currentPath.isRoot ? "search workspaces..." : "filter items...",
                    text: $appState.searchQuery
                )
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
            } else {
                Text("fab")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if appState.isLoading || appState.isAuthenticating {
                ProgressView()
                    .controlSize(.small)
            }

            if appState.isSignedIn {
                Button {
                    if appState.currentPath.isRoot {
                        appState.requestCreateWorkspace()
                    } else {
                        appState.requestCreateItem()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help(appState.currentPath.isRoot ? "New workspace" : "New item")
            }

            Circle()
                .fill(appState.isSignedIn ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .help(appState.userEmail ?? (appState.isSignedIn ? "Signed in" : "Not signed in"))

            if appState.isSignedIn {
                Button("Sign Out") {
                    appState.signOut()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Button("Sign In") {
                    Task { await appState.signIn() }
                }
                .font(.caption2)
                .disabled(appState.isAuthenticating)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Item List

    private var itemList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if appState.filteredItems.isEmpty && !appState.isLoading {
                    Text(appState.searchQuery.isEmpty ? "No items" : "No matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                } else {
                    ForEach(appState.filteredItems) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            ItemRow(item: item, isExpanded: expandedItemID == item.id) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    expandedItemID = expandedItemID == item.id ? nil : item.id
                                }
                            }
                            .environmentObject(appState)

                            if expandedItemID == item.id {
                                ItemDetailView(item: item)
                                    .environmentObject(appState)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: prefs.density.maxListHeight)
    }

    // MARK: - Signed Out

    private var signedOutPlaceholder: some View {
        VStack(spacing: 6) {
            FabricIconView(.workspace, size: 24)
            Text("Sign in to browse Fabric")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 6) {
            if appState.isSignedIn {
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(appState.isLoading)

                Text("\(appState.filteredItems.count)\(appState.searchQuery.isEmpty ? "" : "/\(appState.allItems.count)") items")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if let time = appState.lastRefreshTime {
                    Text(time, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }

                if !appState.currentPath.isRoot {
                    Button {
                        appState.requestImport()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Import definition")
                }
            }

            Spacer()

            Button {
                appState.toggleNotifications(!appState.notificationsEnabled)
            } label: {
                Image(systemName: appState.notificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(appState.notificationsEnabled ? .secondary : .tertiary)
            .help(appState.notificationsEnabled ? "Notifications on" : "Notifications off")

            Picker("", selection: $prefs.density) {
                ForEach(TrayDensity.allCases) { d in
                    Text(d.rawValue).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 66)
            .controlSize(.mini)
            .help("Display density")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: - Jobs Section

    private var jobsSection: some View {
        DisclosureGroup(isExpanded: $appState.showJobs) {
            if appState.recentJobs.isEmpty {
                Text("No recent jobs")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(appState.recentJobs.prefix(10)) { job in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(jobStatusColor(job.status))
                            .frame(width: 6, height: 6)
                        Text(job.itemName.isEmpty ? String(job.itemID.prefix(8)) : job.itemName)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        if job.status == .inProgress {
                            Button {
                                appState.requestCancelJob(job)
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 7))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .help("Cancel job")
                        }
                        Text(job.status.rawValue)
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        if let date = job.startedAt {
                            Text(date, style: .relative)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                Text("Jobs")
                    .font(.caption)
                    .fontWeight(.medium)
                let running = appState.recentJobs.filter { $0.status == .inProgress }.count
                if running > 0 {
                    Text("\(running)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.orange))
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Capacities Section

    private var capacitiesSection: some View {
        DisclosureGroup(isExpanded: $showCapacities) {
            ForEach(appState.capacities, id: \.id) { cap in
                HStack(spacing: 6) {
                    Text(cap.sku)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(capacityColor(cap)))
                    Text(cap.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer()
                    Circle()
                        .fill(cap.isActive ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(cap.isActive ? cap.region : "Paused")
                        .font(.system(size: 8))
                        .foregroundStyle(cap.isActive ? Color.secondary : Color.red)
                }
                .padding(.vertical, 1)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 9))
                Text("Capacities")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\(appState.capacities.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                let paused = appState.capacities.filter { !$0.isActive }.count
                if paused > 0 {
                    Text("\(paused) paused")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func jobStatusColor(_ status: JobRunStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .inProgress: return .orange
        case .cancelled: return .gray
        case .notStarted: return .blue
        case .deduped, .unknown: return .gray
        }
    }

    private func capacityColor(_ cap: FabricCapacity) -> Color {
        switch cap.licenseType {
        case "Fabric": return .orange
        case "Premium": return .purple
        case "Trial": return .green
        case "Embedded": return .blue
        default: return .gray
        }
    }
}

// MARK: - Item Detail View

struct ItemDetailView: View {
    let item: FabricItem
    @EnvironmentObject private var appState: AppState
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if item.type == .workspace {
                aclView
            } else {
                detailView
            }

            // Always show ID
            HStack(spacing: 2) {
                Text("ID:")
                    .font(.system(size: 8))
                    .foregroundStyle(.quaternary)
                Text(item.id)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.03))
        .task {
            isLoading = true
            if item.type == .workspace {
                await appState.fetchRoleAssignments(workspaceID: item.id)
            } else {
                let wsID = item.workspaceID ?? appState.currentPath.workspaceID ?? ""
                await appState.fetchItemDetail(workspaceID: wsID, itemID: item.id)
            }
            isLoading = false
        }
    }

    private var aclView: some View {
        Group {
            if let cap = item.capacity {
                HStack(spacing: 4) {
                    Text(cap.sku)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(capColor(cap)))
                    Text(cap.displayName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(cap.region)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    if !cap.isActive {
                        Text("PAUSED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 2)
            }

            if appState.roleAssignments.isEmpty {
                Text("No access info")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(appState.roleAssignments) { ra in
                    HStack(spacing: 4) {
                        Image(systemName: ra.role.icon)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(ra.principalName)
                            .font(.system(size: 10))
                            .lineLimit(1)
                        Spacer()
                        Text(ra.principalType)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Button {
                            appState.requestRemoveRole(ra, workspaceID: item.id)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red.opacity(0.6))
                        .help("Remove access")
                    }
                }
            }
            Button {
                appState.requestAddRole(workspaceID: item.id)
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 8))
                    Text("Add access")
                        .font(.system(size: 9))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
    }

    private var detailView: some View {
        Group {
            if let detail = appState.itemDetail {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Type:")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(item.type.rawValue)
                            .font(.system(size: 9, weight: .medium))
                    }
                    if let desc = detail.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    if let label = detail.sensitivityLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 8))
                            Text(label.name)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.orange)
                    }
                }
            } else {
                Text("No details available")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func capColor(_ cap: FabricCapacity) -> Color {
        switch cap.licenseType {
        case "Fabric": return .orange
        case "Premium": return .purple
        case "Trial": return .green
        case "Embedded": return .blue
        default: return .gray
        }
    }
}

// MARK: - Item Row

struct ItemRow: View {
    let item: FabricItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var prefs: TrayPreferences
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            FabricIconView(item.type)
                .frame(width: prefs.density.iconSize, height: prefs.density.iconSize)

            Button {
                Task { await appState.enter(item: item) }
            } label: {
                Text(item.name)
                    .font(.system(size: prefs.density.captionSize))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .disabled(item.type != .workspace)

            if item.type == .workspace {
                if let role = item.role {
                    Image(systemName: role.icon)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .help(role.rawValue)
                }
                if item.isOnCapacity {
                    if let cap = item.capacity {
                        HStack(spacing: 2) {
                            Text(cap.sku)
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(skuColor(cap)))
                            if !cap.isActive {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.red)
                                    .help("Capacity paused")
                            }
                        }
                        .help("\(cap.displayName) (\(cap.licenseType), \(cap.region))")
                    } else {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 6, height: 6)
                    }
                }
            } else {
                if let label = item.sensitivityLabel {
                    Text(label.name)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .lineLimit(1)
                }
                Text(item.type.rawValue)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button { onToggleExpand() } label: {
                Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isExpanded ? Color.blue : Color.secondary)
            .help("Details")

            if item.type.isRunnable {
                Button {
                    appState.requestRun(item)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help("Run")
            }

            Button {
                appState.openItem(item)
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open in browser")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, prefs.density.rowVPad)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy Name") { copyToClipboard(item.name) }
            Button("Copy ID") { copyToClipboard(item.id) }
            Divider()
            Button("Open in Browser") { appState.openItem(item) }
            Divider()
            if item.type.isRunnable {
                Button("Run...") { appState.requestRun(item) }
            }
            Button("Rename...") { appState.requestRename(item) }
            Button("Delete...") { appState.requestDelete(item) }
            if item.type == .workspace {
                Divider()
                Button("Assign Capacity...") { appState.requestAssignCapacity(item) }
                if item.isOnCapacity {
                    Button("Unassign Capacity...") { appState.requestUnassignCapacity(item) }
                }
            } else {
                Divider()
                Button("Export Definition...") { appState.requestExport(item) }
                Button("Set Label...") { appState.requestSetLabel(item) }
                if item.sensitivityLabel != nil {
                    Button("Remove Label...") { appState.requestRemoveLabel(item) }
                }
                if item.type.supportsShortcuts {
                    Divider()
                    Button("Create Shortcut...") { appState.requestCreateShortcut(item) }
                }
                if item.type.supportsUpload {
                    Button("Upload File...") { appState.requestUploadFile(item) }
                }
            }
        }
    }

    private func skuColor(_ cap: FabricCapacity) -> Color {
        switch cap.licenseType {
        case "Fabric": return .orange
        case "Premium": return .purple
        case "Trial": return .green
        case "Embedded": return .blue
        default: return .gray
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Action Confirmation

struct ActionConfirmationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var textInput = ""
    @State private var textInput2 = ""
    @State private var selectedType: FabricItemType = .notebook
    @State private var selectedRole: WorkspaceRole = .viewer
    @State private var selectedCapacityID = ""

    private var action: PendingAction? { appState.pendingAction }

    var body: some View {
        if let action = action {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: action.acceptIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(action.isDestructive ? Color.red : Color.blue)
                    Text(action.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                formFields(for: action)

                HStack {
                    Spacer()
                    Button("Dismiss") { appState.dismissAction() }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.escape, modifiers: [])

                    Button {
                        Task {
                            await appState.confirmAction(
                                textInput: textInput,
                                textInput2: textInput2,
                                selectedType: selectedType,
                                selectedRole: selectedRole,
                                selectedCapacityID: selectedCapacityID
                            )
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: action.acceptIcon)
                                .font(.system(size: 8))
                            Text(action.acceptLabel)
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(action.isDestructive ? .red : .blue)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))
        }
    }

    @ViewBuilder
    private func formFields(for action: PendingAction) -> some View {
        switch action.kind {
        case .run:
            if action.supportsParameters {
                Text("Parameters (JSON)")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                TextField("{\"key\": \"value\"}", text: $textInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
            }

        case .renameItem(let item):
            TextField("New name", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)
                .onAppear { textInput = item.name }

        case .createWorkspace:
            TextField("Workspace name", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)

        case .createItem:
            TextField("Item name", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)
            Picker("Type", selection: $selectedType) {
                ForEach(FabricItemType.creatableTypes, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .font(.caption2)
            .labelsHidden()

        case .assignCapacity:
            if appState.capacities.isEmpty {
                Text("No capacities available")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Picker("Capacity", selection: $selectedCapacityID) {
                    ForEach(appState.capacities, id: \.id) { cap in
                        Text("\(cap.displayName) (\(cap.sku))").tag(cap.id)
                    }
                }
                .font(.caption2)
                .labelsHidden()
                .onAppear { selectedCapacityID = appState.capacities.first?.id ?? "" }
            }

        case .addRole:
            TextField("Email or object ID", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)
            Picker("Role", selection: $selectedRole) {
                Text("Admin").tag(WorkspaceRole.admin)
                Text("Member").tag(WorkspaceRole.member)
                Text("Contributor").tag(WorkspaceRole.contributor)
                Text("Viewer").tag(WorkspaceRole.viewer)
            }
            .font(.caption2)
            .labelsHidden()

        case .setLabel:
            TextField("Sensitivity label ID", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)

        case .createShortcut:
            TextField("Shortcut name", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)
            TextField("Target path (workspace/item/path)", text: $textInput2)
                .textFieldStyle(.roundedBorder).font(.caption)

        case .loadTable:
            TextField("Relative path to data file", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)

        default:
            EmptyView()
        }
    }
}

private extension ActionKind {
    var isRun: Bool {
        if case .run = self { return true }
        return false
    }
}
