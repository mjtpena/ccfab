import AppKit
import SwiftUI

// MARK: - Color Palette

private enum Palette {
    static let accent = Color.accentColor
    static let destructive = Color.red
    static let success = Color.green
    static let warning = Color.orange
    static let muted = Color.secondary
    static let faint = Color.primary.opacity(0.04)
    static let hoverBG = Color.primary.opacity(0.07)
    static let sectionBG = Color.primary.opacity(0.025)
    static let separator = Color.primary.opacity(0.08)
}

// MARK: - Shimmer Loading

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.15), .clear]),
                    startPoint: .leading, endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 200
                }
            }
    }
}

private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 14, height: 14)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.06))
                .frame(width: CGFloat.random(in: 80...160), height: 10)
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.04))
                .frame(width: 40, height: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .modifier(ShimmerModifier())
    }
}

struct TrayView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var prefs: TrayPreferences
    @State private var expandedItemID: String?
    @State private var showCapacities = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Onboarding overlay
            if !appState.hasCompletedOnboarding && !appState.isSignedIn {
                OnboardingView()
                    .environmentObject(appState)
            } else {
                headerBar
                Divider().opacity(0.5)

                if appState.isSignedIn {
                    // Recent items (root only, when not searching)
                    if appState.currentPath.isRoot && appState.searchQuery.isEmpty && !appState.recentItems.isEmpty {
                        recentsSection
                        Divider().opacity(0.5)
                    }

                    itemList

                    if !appState.currentPath.isRoot {
                        Divider().opacity(0.5)
                        jobsSection
                    }

                    if appState.currentPath.isRoot && !appState.capacities.isEmpty {
                        Divider().opacity(0.5)
                        capacitiesSection
                    }
                } else {
                    signedOutPlaceholder
                }

                statusBar

                Divider().opacity(0.5)
                footerBar
            }
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
        HStack(spacing: 6) {
            // Breadcrumb navigation (supports 3 levels)
            HStack(spacing: 2) {
                let segments = appState.currentPath.breadcrumbSegments
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.quaternary)
                    }
                    if index == 0 {
                        Button {
                            Task { await appState.navigate(to: .root) }
                        } label: {
                            Image(systemName: "house.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(appState.currentPath.isRoot ? Palette.muted : Palette.accent)
                        .disabled(!appState.isSignedIn || appState.currentPath.isRoot)
                        .accessibilityLabel("Home")
                    } else if index < segments.count - 1 {
                        // Clickable intermediate segment
                        Button {
                            Task { await appState.navigate(to: segment.path) }
                        } label: {
                            Text(segment.label)
                                .font(.system(.caption2, design: .default))
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 90)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.accent)
                    } else {
                        // Current (non-clickable) segment
                        Text(segment.label)
                            .font(.system(.caption2, design: .default))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 90)
                    }
                }
            }

            if appState.isSignedIn {
                // Search field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                    TextField(
                        appState.currentPath.isRoot ? "Search workspaces…" : "Filter items…",
                        text: $appState.searchQuery
                    )
                    .textFieldStyle(.plain)
                    .font(.system(.caption2))
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search items")
                    if !appState.searchQuery.isEmpty {
                        Button {
                            appState.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.quaternary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSearchFocused ? Palette.faint.opacity(2) : Palette.faint)
                )
            } else {
                Spacer()
            }

            if appState.isLoading || appState.isAuthenticating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading")
            }

            // Actions with keyboard shortcuts
            if appState.isSignedIn {
                Button {
                    if appState.currentPath.isRoot {
                        appState.requestCreateWorkspace()
                    } else {
                        appState.requestCreateItem()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
                .help(appState.currentPath.isRoot ? "New workspace (⌘N)" : "New item (⌘N)")
                .keyboardShortcut("n")
                .accessibilityLabel(appState.currentPath.isRoot ? "New workspace" : "New item")

                Button { isSearchFocused = true } label: { EmptyView() }
                    .keyboardShortcut("f")
                    .frame(width: 0, height: 0)
                    .opacity(0)

                Button { Task { await appState.refresh() } } label: { EmptyView() }
                    .keyboardShortcut("r")
                    .frame(width: 0, height: 0)
                    .opacity(0)
            }

            authButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var authButton: some View {
        Group {
            if appState.isSignedIn {
                Menu {
                    if let name = appState.userName {
                        Text(name).font(.caption)
                    }
                    if let email = appState.userEmail {
                        Text(email).font(.caption2)
                    }
                    Divider()
                    Button("Sign Out") { appState.signOut() }
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Palette.success)
                            .frame(width: 7, height: 7)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help(appState.userEmail ?? "Signed in")
            } else {
                Button {
                    Task { await appState.signIn() }
                } label: {
                    Text("Sign In")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Palette.accent)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(appState.isAuthenticating)
            }
        }
    }

    // MARK: - Item List

    private var itemList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if appState.isLoading && appState.allItems.isEmpty {
                    // Skeleton loading state
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonRow()
                    }
                } else if appState.filteredItems.isEmpty && !appState.isLoading {
                    VStack(spacing: 4) {
                        Image(systemName: appState.searchQuery.isEmpty ? "tray" : "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(.quaternary)
                        Text(appState.searchQuery.isEmpty ? "No items" : "No matches for \"\(appState.searchQuery)\"")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .accessibilityLabel(appState.searchQuery.isEmpty ? "No items found" : "No matches for search query")
                } else {
                    ForEach(appState.filteredItems) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            ItemRow(
                                item: item,
                                isExpanded: expandedItemID == item.id,
                                isFavorite: appState.isFavorite(item.id)
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    expandedItemID = expandedItemID == item.id ? nil : item.id
                                }
                            }
                            .environmentObject(appState)

                            if expandedItemID == item.id {
                                ItemDetailView(item: item)
                                    .environmentObject(appState)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appState.filteredItems.map(\.id))
        }
        .frame(minHeight: prefs.density.minListHeight, maxHeight: prefs.density.maxListHeight)
    }

    // MARK: - Recents Section

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.muted)
                Text("Recent")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 10)
            .padding(.top, 5)
            .padding(.bottom, 3)

            ForEach(appState.recentItems.prefix(3), id: \.id) { recent in
                Button {
                    Task {
                        let item = FabricItem(
                            id: recent.id, name: recent.name, type: recent.type,
                            workspaceID: nil, role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil
                        )
                        await appState.enter(item: item)
                    }
                } label: {
                    HStack(spacing: 6) {
                        FabricIconView(recent.type, size: 10)
                        Text(recent.name)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recent: \(recent.name)")
            }
        }
        .padding(.bottom, 3)
    }

    // MARK: - Signed Out

    private var signedOutPlaceholder: some View {
        VStack(spacing: 12) {
            FabricIconView(.workspace, size: 32)
                .opacity(0.6)
            Text("Microsoft Fabric")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Sign in to browse workspaces, items, and jobs")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // Feature highlights
            VStack(alignment: .leading, spacing: 6) {
                featureRow(icon: "folder.fill", text: "Browse workspaces & items")
                featureRow(icon: "play.fill", text: "Run notebooks & pipelines")
                featureRow(icon: "bolt.fill", text: "Monitor jobs in real-time")
                featureRow(icon: "cpu", text: "Manage capacities & access")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Microsoft Fabric. Sign in to browse workspaces, items, and jobs.")
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(Palette.accent.opacity(0.7))
                .frame(width: 14)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Status Bar (toast / error)

    @ViewBuilder
    private var statusBar: some View {
        if let toast = appState.toastMessage {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.success)
                Text(toast)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.success.opacity(0.08))
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            .accessibilityLabel("Success: \(toast)")
        }

        if let error = appState.errorMessage {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.destructive)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Palette.destructive.opacity(0.9))
                    .lineLimit(2)
                Spacer()
                if appState.lastFailedAction != nil {
                    Button {
                        Task { await appState.retryLastAction() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 8))
                            Text("Retry")
                                .font(.system(size: 9, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.destructive.opacity(0.8))
                    .accessibilityLabel("Retry failed action")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.destructive.opacity(0.06))
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            .accessibilityLabel("Error: \(error)")
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 8) {
            if appState.isSignedIn {
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(appState.isLoading ? 360 : 0))
                        .animation(appState.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: appState.isLoading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .disabled(appState.isLoading)
                .help("Refresh (⌘R)")
                .accessibilityLabel("Refresh")

                Text("\(appState.filteredItems.count) items")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
                    .accessibilityLabel("\(appState.filteredItems.count) items")

                if let time = appState.lastRefreshTime {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                    Text(time, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                        .accessibilityLabel("Last refreshed")
                }

                if !appState.currentPath.isRoot {
                    Button {
                        appState.requestImport()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                    .help("Import definition")
                    .accessibilityLabel("Import definition")
                }
            }

            Spacer()

            Button {
                appState.toggleNotifications(!appState.notificationsEnabled)
            } label: {
                Image(systemName: appState.notificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(appState.notificationsEnabled ? Palette.muted : Color.gray)
            .help(appState.notificationsEnabled ? "Notifications on" : "Notifications off")
            .accessibilityLabel(appState.notificationsEnabled ? "Disable notifications" : "Enable notifications")

            Picker("", selection: $prefs.density) {
                ForEach(TrayDensity.allCases) { d in
                    Text(d.rawValue).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 60)
            .controlSize(.mini)
            .help("Display density")
            .accessibilityLabel("Display density")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.quaternary)
            .help("Quit FabricTray")
            .keyboardShortcut("q")
            .accessibilityLabel("Quit")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Jobs Section

    private var jobsSection: some View {
        DisclosureGroup(isExpanded: $appState.showJobs) {
            if appState.recentJobs.isEmpty {
                Text("No recent jobs")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.recentJobs.prefix(10)) { job in
                        HStack(spacing: 6) {
                            Image(systemName: job.status.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(jobStatusColor(job.status))
                            Text(job.itemName.isEmpty ? String(job.itemID.prefix(8)) : job.itemName)
                                .font(.caption2)
                                .lineLimit(1)
                            Spacer()
                            if job.status == .inProgress {
                                Button {
                                    appState.requestCancelJob(job)
                                } label: {
                                    Image(systemName: "stop.circle.fill")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Palette.destructive.opacity(0.7))
                                .help("Cancel job")
                                .accessibilityLabel("Cancel job \(job.itemName)")
                            }
                            Text(job.status.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(jobStatusColor(job.status).opacity(0.8))
                            if let date = job.startedAt {
                                Text(date, style: .relative)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(job.itemName), \(job.status.rawValue)")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.warning)
                Text("Jobs")
                    .font(.caption)
                    .fontWeight(.medium)
                let running = appState.recentJobs.filter { $0.status == .inProgress }.count
                if running > 0 {
                    Text("\(running) running")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Palette.warning))
                }
                let failed = appState.recentJobs.filter { $0.status == .failed }.count
                if failed > 0 {
                    Text("\(failed) failed")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Palette.destructive))
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .accessibilityLabel("Jobs section")
    }

    // MARK: - Capacities Section

    private var capacitiesSection: some View {
        DisclosureGroup(isExpanded: $showCapacities) {
            VStack(spacing: 0) {
                ForEach(appState.capacities, id: \.id) { cap in
                    HStack(spacing: 6) {
                        Text(cap.sku)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(capacityColor(cap)))
                        Text(cap.displayName)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        HStack(spacing: 3) {
                            Circle()
                                .fill(cap.isActive ? Palette.success : Palette.destructive)
                                .frame(width: 5, height: 5)
                            Text(cap.isActive ? cap.region : "Paused")
                                .font(.system(size: 9))
                                .foregroundStyle(cap.isActive ? Color.secondary : Palette.destructive)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(cap.displayName), \(cap.sku), \(cap.isActive ? cap.region : "Paused")")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.accent)
                Text("Capacities")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\(appState.capacities.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
                let paused = appState.capacities.filter { !$0.isActive }.count
                if paused > 0 {
                    Text("\(paused) paused")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Palette.destructive))
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .accessibilityLabel("Capacities section")
    }

    private func jobStatusColor(_ status: JobRunStatus) -> Color {
        switch status {
        case .completed: return Palette.success
        case .failed: return Palette.destructive
        case .inProgress: return Palette.warning
        case .cancelled: return .gray
        case .notStarted: return Palette.accent
        case .deduped, .unknown: return .gray
        }
    }

    private func capacityColor(_ cap: FabricCapacity) -> Color {
        switch cap.licenseType {
        case "Fabric": return Palette.warning
        case "Premium": return .purple
        case "Trial": return Palette.success
        case "Embedded": return Palette.accent
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
        VStack(alignment: .leading, spacing: 5) {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading…")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            } else if item.type == .workspace {
                aclView
            } else {
                detailView
            }

            // ID row
            HStack(spacing: 3) {
                Text("ID")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.quaternary)
                Text(item.id)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.id, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.quaternary)
                .help("Copy ID")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
        .background(Palette.sectionBG)
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
                HStack(spacing: 5) {
                    Text(cap.sku)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(capColor(cap)))
                    Text(cap.displayName)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.muted)
                    Text(cap.region)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    if !cap.isActive {
                        Text("PAUSED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Palette.destructive))
                    }
                }
                .padding(.bottom, 3)
            }

            if appState.roleAssignments.isEmpty {
                Text("No access info")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.roleAssignments) { ra in
                        HStack(spacing: 5) {
                            Image(systemName: ra.role.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.muted)
                                .frame(width: 12)
                            Text(ra.principalName)
                                .font(.system(size: 10))
                                .lineLimit(1)
                            Spacer()
                            Text(ra.principalType)
                                .font(.system(size: 9))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Palette.faint))
                            Button {
                                appState.requestRemoveRole(ra, workspaceID: item.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.destructive.opacity(0.5))
                            .help("Remove access")
                            .accessibilityLabel("Remove access for \(ra.principalName)")
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Button {
                appState.requestAddRole(workspaceID: item.id)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 9))
                    Text("Add access")
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
            .padding(.top, 2)
            .accessibilityLabel("Add access")
        }
    }

    private var detailView: some View {
        Group {
            if let detail = appState.itemDetail {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Type")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.quaternary)
                        Text(item.type.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                    if let desc = detail.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(3)
                    }
                    if let label = detail.sensitivityLabel {
                        HStack(spacing: 3) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 9))
                            Text(label.name)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(Palette.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Palette.warning.opacity(0.1)))
                    }
                }
            } else {
                Text("No details available")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private func capColor(_ cap: FabricCapacity) -> Color {
        switch cap.licenseType {
        case "Fabric": return Palette.warning
        case "Premium": return .purple
        case "Trial": return Palette.success
        case "Embedded": return Palette.accent
        default: return .gray
        }
    }
}

// MARK: - Item Row

struct ItemRow: View {
    let item: FabricItem
    let isExpanded: Bool
    let isFavorite: Bool
    let onToggleExpand: () -> Void
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var prefs: TrayPreferences
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // Favorite indicator
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Palette.warning)
                    .accessibilityLabel("Favorited")
            }

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
            .disabled(item.type != .workspace && item.type != .lakehouse)

            if item.type == .workspace {
                if let role = item.role {
                    Image(systemName: role.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .help(role.rawValue)
                }
                if item.isOnCapacity {
                    if let cap = item.capacity {
                        HStack(spacing: 2) {
                            Text(cap.sku)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(skuColor(cap)))
                            if !cap.isActive {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Palette.destructive)
                                    .help("Capacity paused")
                            }
                        }
                        .help("\(cap.displayName) · \(cap.licenseType) · \(cap.region)")
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 5, height: 5)
                    }
                }
            } else {
                if let label = item.sensitivityLabel {
                    Text(label.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Palette.warning)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Palette.warning.opacity(0.12)))
                        .lineLimit(1)
                }
                Text(item.type.rawValue)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            Spacer()

            // Action buttons — visible on hover
            Group {
                Button { onToggleExpand() } label: {
                    Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isExpanded ? Palette.accent : Palette.muted.opacity(0.5))
                .help("Details")
                .accessibilityLabel("Show details for \(item.name)")

                if item.type.isRunnable {
                    Button {
                        appState.pendingActionItemID = item.id
                        appState.requestRun(item)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                    .help("Run")
                    .accessibilityLabel("Run \(item.name)")
                }

                Button {
                    appState.openItem(item)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted.opacity(0.5))
                .help("Open in browser")
                .accessibilityLabel("Open \(item.name) in browser")
            }
            .opacity(isHovered || isExpanded ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, prefs.density.rowVPad)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Palette.hoverBG : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .popover(isPresented: Binding(
            get: { appState.pendingAction != nil && appState.pendingActionItemID == item.id },
            set: { if !$0 { appState.dismissAction(); appState.pendingActionItemID = nil } }
        ), arrowEdge: .trailing) {
            ActionConfirmationView()
                .environmentObject(appState)
                .frame(width: 280)
        }
        .contextMenu {
            Section {
                Button {
                    appState.toggleFavorite(item.id)
                } label: {
                    Label(
                        isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        systemImage: isFavorite ? "star.slash" : "star"
                    )
                }
                Button { copyToClipboard(item.name) } label: {
                    Label("Copy Name", systemImage: "doc.on.clipboard")
                }
                Button { copyToClipboard(item.id) } label: {
                    Label("Copy ID", systemImage: "number")
                }
                Button { appState.openItem(item) } label: {
                    Label("Open in Browser", systemImage: "arrow.up.right.square")
                }
            }
            if item.type.isRunnable {
                Section {
                    Button {
                        appState.pendingActionItemID = item.id
                        appState.requestRun(item)
                    } label: {
                        Label("Run…", systemImage: "play.fill")
                    }
                }
            }
            Section {
                Button {
                    appState.pendingActionItemID = item.id
                    appState.requestRename(item)
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    appState.pendingActionItemID = item.id
                    appState.requestDelete(item)
                } label: {
                    Label("Delete…", systemImage: "trash")
                }
            }
            if item.type == .workspace {
                Section("Capacity") {
                    Button {
                        appState.pendingActionItemID = item.id
                        appState.requestAssignCapacity(item)
                    } label: {
                        Label("Assign Capacity…", systemImage: "cpu")
                    }
                    if item.isOnCapacity {
                        Button(role: .destructive) {
                            appState.pendingActionItemID = item.id
                            appState.requestUnassignCapacity(item)
                        } label: {
                            Label("Unassign Capacity…", systemImage: "cpu.fill")
                        }
                    }
                }
            } else {
                Section("Advanced") {
                    Button {
                        appState.pendingActionItemID = item.id
                        appState.requestExport(item)
                    } label: {
                        Label("Export Definition…", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        appState.pendingActionItemID = item.id
                        appState.requestSetLabel(item)
                    } label: {
                        Label("Set Label…", systemImage: "tag")
                    }
                    if item.sensitivityLabel != nil {
                        Button(role: .destructive) {
                            appState.pendingActionItemID = item.id
                            appState.requestRemoveLabel(item)
                        } label: {
                            Label("Remove Label…", systemImage: "tag.slash")
                        }
                    }
                    if item.type.supportsShortcuts {
                        Button {
                            appState.pendingActionItemID = item.id
                            appState.requestCreateShortcut(item)
                        } label: {
                            Label("Create Shortcut…", systemImage: "link")
                        }
                    }
                    if item.type.supportsUpload {
                        Button {
                            appState.pendingActionItemID = item.id
                            appState.requestUploadFile(item)
                        } label: {
                            Label("Upload File…", systemImage: "arrow.up.doc")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.type.rawValue)")
    }

    private func skuColor(_ cap: FabricCapacity) -> Color {
        switch cap.licenseType {
        case "Fabric": return Palette.warning
        case "Premium": return .purple
        case "Trial": return Palette.success
        case "Embedded": return Palette.accent
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
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: action.acceptIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(action.isDestructive ? Palette.destructive : Palette.accent)
                        .frame(width: 16)
                    Text(action.title)
                        .font(.system(.caption, weight: .semibold))
                        .lineLimit(1)
                }

                // Form fields
                formFields(for: action)

                // Buttons
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { appState.dismissAction() }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.muted)
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
                        HStack(spacing: 4) {
                            Image(systemName: action.acceptIcon)
                                .font(.system(size: 8))
                            Text(action.acceptLabel)
                                .font(.system(.caption2, weight: .medium))
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(action.isDestructive ? Palette.destructive : Palette.accent)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.sectionBG)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Confirm action: \(action.title)")
        }
    }

    @ViewBuilder
    private func formFields(for action: PendingAction) -> some View {
        switch action.kind {
        case .run:
            if action.supportsParameters {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Execution parameters (JSON)")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                    TextField("{\"key\": \"value\"}", text: $textInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .accessibilityLabel("Execution parameters")
                }
            }

        case .renameItem(let item):
            TextField("New name", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)
                .onAppear { textInput = item.name }
                .accessibilityLabel("New name")

        case .createWorkspace:
            TextField("Workspace name", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)
                .accessibilityLabel("Workspace name")

        case .createItem:
            VStack(spacing: 4) {
                TextField("Item name", text: $textInput)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .accessibilityLabel("Item name")
                Picker("Type", selection: $selectedType) {
                    ForEach(FabricItemType.creatableTypes, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .font(.caption2)
                .labelsHidden()
                .accessibilityLabel("Item type")
            }

        case .assignCapacity:
            if appState.capacities.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 9))
                    Text("No capacities available")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            } else {
                Picker("Capacity", selection: $selectedCapacityID) {
                    ForEach(appState.capacities, id: \.id) { cap in
                        Text("\(cap.displayName) (\(cap.sku))").tag(cap.id)
                    }
                }
                .font(.caption2)
                .labelsHidden()
                .onAppear { selectedCapacityID = appState.capacities.first?.id ?? "" }
                .accessibilityLabel("Select capacity")
            }

        case .addRole:
            VStack(spacing: 4) {
                TextField("Email or object ID", text: $textInput)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .accessibilityLabel("Email or object ID")
                Picker("Role", selection: $selectedRole) {
                    Text("Admin").tag(WorkspaceRole.admin)
                    Text("Member").tag(WorkspaceRole.member)
                    Text("Contributor").tag(WorkspaceRole.contributor)
                    Text("Viewer").tag(WorkspaceRole.viewer)
                }
                .font(.caption2)
                .labelsHidden()
                .accessibilityLabel("Role")
            }

        case .setLabel:
            TextField("Sensitivity label ID", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)
                .accessibilityLabel("Sensitivity label ID")

        case .createShortcut:
            VStack(spacing: 4) {
                TextField("Shortcut name", text: $textInput)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .accessibilityLabel("Shortcut name")
                TextField("Target path (workspace/item/path)", text: $textInput2)
                    .textFieldStyle(.roundedBorder).font(.caption)
                    .accessibilityLabel("Target path")
            }

        case .loadTable:
            TextField("Relative path to data file", text: $textInput)
                .textFieldStyle(.roundedBorder).font(.caption)
                .accessibilityLabel("Relative path to data file")

        default:
            EmptyView()
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, description: String)] = [
        ("diamond.fill", "Welcome to FabricTray",
         "A native macOS menu bar companion for Microsoft Fabric. Browse, manage, and monitor — all from your tray."),
        ("folder.fill", "Browse & Navigate",
         "Explore workspaces and items with breadcrumb navigation. Search instantly with ⌘F, refresh with ⌘R."),
        ("play.fill", "Run & Monitor",
         "Execute notebooks, pipelines, and Spark jobs. Monitor running jobs with live status updates and notifications."),
        ("star.fill", "Pin Your Favorites",
         "Right-click any workspace or item to pin it. Favorites appear at the top of your list for quick access."),
        ("gearshape.fill", "Customize Your View",
         "Use the S / M / L density picker in the footer to adjust the layout. Adjust notifications with the bell icon.")
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Step indicator
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentStep ? Palette.accent : Color.primary.opacity(0.15))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 12)

            // Content
            VStack(spacing: 8) {
                Image(systemName: steps[currentStep].icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Palette.accent)
                    .frame(height: 36)

                Text(steps[currentStep].title)
                    .font(.system(.caption, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(steps[currentStep].description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            .animation(.easeInOut(duration: 0.2), value: currentStep)

            // Navigation
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button {
                        currentStep += 1
                    } label: {
                        Text("Next")
                            .font(.system(.caption2, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Palette.accent)
                            .foregroundStyle(.white)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        appState.completeOnboarding()
                    } label: {
                        Text("Get Started")
                            .font(.system(.caption2, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Palette.accent)
                            .foregroundStyle(.white)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            Button("Skip") {
                appState.completeOnboarding()
            }
            .font(.system(size: 10))
            .buttonStyle(.plain)
            .foregroundStyle(.quaternary)
            .padding(.bottom, 8)
        }
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome tour, step \(currentStep + 1) of \(steps.count)")
    }
}

private extension ActionKind {
    var isRun: Bool {
        if case .run = self { return true }
        return false
    }
}
