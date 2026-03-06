import AppKit
import SwiftUI

// MARK: - Color Palette

private enum Palette {
    static let accent = Color.accentColor
    static let destructive = Color.red
    static let success = Color.green
    static let warning = Color.orange
    static let muted = Color.secondary
    static let faint = Color.primary.opacity(0.03)
    static let hoverBG = Color.primary.opacity(0.06)
    static let sectionBG = Color.primary.opacity(0.04)
    static let separator = Color.primary.opacity(0.06)
    static let glassFill = Color.primary.opacity(0.03)
    static let glassBorder = Color.primary.opacity(0.08)
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
    @EnvironmentObject private var prefs: TrayPreferences

    var body: some View {
        let d = prefs.density
        HStack(spacing: d.spacingLG) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.06))
                .frame(width: d.iconSize, height: d.iconSize)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.06))
                .frame(width: CGFloat.random(in: d.skeletonTextW), height: d.skeletonTextH)
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.04))
                .frame(width: d.skeletonBarW, height: d.skeletonBarH)
        }
        .padding(.horizontal, d.padMD)
        .padding(.vertical, d.padXS)
        .modifier(ShimmerModifier())
    }
}

struct TrayView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var prefs: TrayPreferences
    @State private var expandedItemID: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Onboarding overlay
            if !appState.hasCompletedOnboarding && !appState.isSignedIn {
                OnboardingView()
                    .environmentObject(appState)
            } else {
                headerBar
                Divider().opacity(0.3)

                if appState.isSignedIn {
                    // Root: show capacities as top-level parents
                    if appState.currentPath.isRoot {
                        if appState.isEditMode {
                            editModeList
                        } else {
                            capacityFirstList
                        }
                    } else if appState.currentPath.isCapacityLevel {
                        // Capacity level: show workspaces in this capacity
                        itemList
                    } else {
                        // Workspace / sub-item level
                        itemList

                        Divider().opacity(0.3)
                        jobsSection
                    }
                } else {
                    signedOutPlaceholder
                }

                statusBar

                Divider().opacity(0.3)
                footerBar
            }
        }
        .frame(width: prefs.density.windowWidth)
        .background(.ultraThinMaterial)
        .task {
            if appState.isSignedIn {
                await appState.refresh()
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        let d = prefs.density
        return HStack(spacing: d.padSM) {
            // Breadcrumb navigation (supports 3 levels)
            HStack(spacing: d.spacingXS) {
                let segments = appState.currentPath.breadcrumbSegments
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: d.fontNano, weight: .bold))
                            .foregroundStyle(.quaternary)
                    }
                    if index == 0 {
                        Button {
                            Task { await appState.navigate(to: .root) }
                        } label: {
                            Image(systemName: "house.fill")
                                .font(.system(size: d.fontBody))
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
                                .frame(maxWidth: d.breadcrumbMaxW)
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
                            .frame(maxWidth: d.breadcrumbMaxW)
                    }
                }
            }

            if appState.isSignedIn {
                // Search field
                HStack(spacing: d.spacingSM) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: d.fontCaption))
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
                                .font(.system(size: d.fontCaption))
                                .foregroundStyle(.quaternary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, d.padSM)
                .padding(.vertical, d.searchFieldVPad)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSearchFocused ? Palette.glassFill.opacity(3) : Palette.glassFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isSearchFocused ? Palette.accent.opacity(0.3) : Palette.glassBorder, lineWidth: 0.5)
                        )
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
                        appState.pendingActionItemID = "__root__"
                        appState.requestCreateWorkspace()
                    } else {
                        appState.pendingActionItemID = "__root__"
                        appState.requestCreateItem()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: d.fontTitle))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
                .help(appState.currentPath.isRoot ? "New workspace (⌘N)" : "New item (⌘N)")
                .keyboardShortcut("n")
                .accessibilityLabel(appState.currentPath.isRoot ? "New workspace" : "New item")
                .popover(isPresented: Binding(
                    get: { appState.pendingAction != nil && appState.pendingActionItemID == "__root__" },
                    set: { if !$0 { appState.dismissAction(); appState.pendingActionItemID = nil } }
                ), arrowEdge: .bottom) {
                    ActionConfirmationView()
                        .environmentObject(appState)
                        .environmentObject(prefs)
                        .frame(width: floor(280 * prefs.density.scale))
                }

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

            // Edit mode toggle (only on root capacity view)
            if appState.isSignedIn && appState.currentPath.isRoot {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.isEditMode.toggle()
                    }
                } label: {
                    Text(appState.isEditMode ? "Done" : "Edit")
                        .font(.system(size: d.fontCaption, weight: .medium))
                        .foregroundStyle(appState.isEditMode ? Palette.accent : Palette.muted)
                }
                .buttonStyle(.plain)
                .help(appState.isEditMode ? "Finish editing" : "Reorder capacities & workspaces")
                .accessibilityLabel(appState.isEditMode ? "Done editing" : "Edit order")
            }
        }
        .padding(.horizontal, d.padMD)
        .padding(.vertical, d.spacingLG)
    }

    private var authButton: some View {
        let d = prefs.density
        return Group {
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
                    HStack(spacing: d.spacingXS) {
                        Circle()
                            .fill(Palette.success)
                            .frame(width: d.iconMicro, height: d.iconMicro)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: d.fontHeading))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(width: floor(28 * prefs.density.scale))
                .help(appState.userEmail ?? "Signed in")
            } else {
                Button {
                    Task { await appState.signIn() }
                } label: {
                    Text("Sign In")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, d.spacingLG)
                        .padding(.vertical, d.padXS)
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
        let d = prefs.density
        // Filter out hidden items
        let visibleItems = appState.filteredItems.filter { !prefs.hiddenItems.contains($0.id) }
        let hiddenCount = appState.filteredItems.count - visibleItems.count

        // Group by item type for collapsible sections
        let typeGroups: [(type: FabricItemType, items: [FabricItem])] = {
            var dict: [FabricItemType: [FabricItem]] = [:]
            for item in visibleItems {
                dict[item.type, default: []].append(item)
            }
            // Sort types: favorites first (mixed), then by count descending
            return dict.sorted { a, b in a.value.count > b.value.count }
                .map { (type: $0.key, items: $0.value) }
        }()

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if appState.isLoading && appState.allItems.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                } else if visibleItems.isEmpty && !appState.isLoading {
                    VStack(spacing: d.spacingSM) {
                        Image(systemName: appState.searchQuery.isEmpty ? "tray" : "magnifyingglass")
                            .font(.system(size: d.fontHero))
                            .foregroundStyle(.quaternary)
                        Text(appState.searchQuery.isEmpty ? "No items" : "No matches for \"\(appState.searchQuery)\"")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, d.padLG)
                    .accessibilityLabel(appState.searchQuery.isEmpty ? "No items found" : "No matches for search query")
                } else if typeGroups.count <= 1 || !appState.searchQuery.isEmpty {
                    // Flat list when single type or searching
                    ForEach(visibleItems) { item in
                        itemRowWithDetail(item)
                    }
                } else {
                    // Grouped by type with collapsible headers
                    let wsID = appState.currentPath.workspaceID ?? ""
                    ForEach(typeGroups, id: \.type) { group in
                        let collapseKey = "\(wsID):\(group.type.rawValue)"
                        let isCollapsed = prefs.collapsedItemTypes.contains(collapseKey)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isCollapsed {
                                    prefs.collapsedItemTypes.remove(collapseKey)
                                } else {
                                    prefs.collapsedItemTypes.insert(collapseKey)
                                }
                            }
                        } label: {
                            HStack(spacing: d.padSM) {
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: d.fontMicro, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: d.iconSmall)
                                Image(systemName: group.items.first?.icon ?? "questionmark.square")
                                    .font(.system(size: d.fontCaption))
                                    .foregroundStyle(Palette.accent)
                                Text(group.type.rawValue)
                                    .font(.system(size: d.fontCaption, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(group.items.count)")
                                    .font(.system(size: d.fontMicro, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, d.padMD)
                            .padding(.vertical, d.padXS)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if !isCollapsed {
                            ForEach(group.items) { item in
                                itemRowWithDetail(item)
                            }
                        }
                    }
                }

                // Hidden items indicator
                if hiddenCount > 0 {
                    HStack(spacing: d.spacingSM) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: d.fontMicro))
                        Text("\(hiddenCount) item\(hiddenCount == 1 ? "" : "s") hidden")
                            .font(.system(size: d.fontMicro))
                    }
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, d.padSM)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: visibleItems.map(\.id))
        }
        .frame(minHeight: prefs.density.minListHeight, maxHeight: prefs.density.maxListHeight)
    }

    private func itemRowWithDetail(_ item: FabricItem) -> some View {
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

    // MARK: - Recents Section

    private var recentsSection: some View {
        let d = prefs.density
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: d.padSM) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: d.fontCaption))
                    .foregroundStyle(Palette.muted)
                Text("Recent")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, d.padMD)
            .padding(.top, d.padSM)
            .padding(.bottom, d.padXS)

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
                    HStack(spacing: d.padSM) {
                        FabricIconView(recent.type, size: d.iconSmall)
                        Text(recent.name)
                            .font(.system(size: d.fontBody))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, d.padMD)
                    .padding(.vertical, d.padMicro)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recent: \(recent.name)")
            }
        }
        .padding(.bottom, d.padXS)
    }

    // MARK: - Signed Out

    private var signedOutPlaceholder: some View {
        let d = prefs.density
        return VStack(spacing: d.rowHPad) {
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
            VStack(alignment: .leading, spacing: d.padSM) {
                featureRow(icon: "folder.fill", text: "Browse workspaces & items")
                featureRow(icon: "play.fill", text: "Run notebooks & pipelines")
                featureRow(icon: "bolt.fill", text: "Monitor jobs in real-time")
                featureRow(icon: "cpu", text: "Manage capacities & access")
            }
            .padding(.top, d.padXS)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, d.padXL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Microsoft Fabric. Sign in to browse workspaces, items, and jobs.")
    }

    private func featureRow(icon: String, text: String) -> some View {
        let d = prefs.density
        return HStack(spacing: d.padSM) {
            Image(systemName: icon)
                .font(.system(size: d.fontCaption))
                .foregroundStyle(Palette.accent.opacity(0.7))
                .frame(width: d.iconSize)
            Text(text)
                .font(.system(size: d.fontBody))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Status Bar (toast / error)

    @ViewBuilder
    private var statusBar: some View {
        if let toast = appState.toastMessage {
            let d = prefs.density
            HStack(spacing: d.padSM) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: d.fontBody))
                    .foregroundStyle(Palette.success)
                Text(toast)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { appState.toastMessage = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: d.fontBody))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, d.rowHPad)
            .padding(.vertical, d.padXS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.success.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Palette.success.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, d.padSM)
            .padding(.vertical, d.padMicro)
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            .accessibilityLabel("Success: \(toast)")
        }

        if let error = appState.errorMessage {
            let d = prefs.density
            HStack(spacing: d.padSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: d.fontBody))
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
                        HStack(spacing: d.spacingXS) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: d.fontMicro))
                            Text("Retry")
                                .font(.system(size: d.fontCaption, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.destructive.opacity(0.8))
                    .accessibilityLabel("Retry failed action")
                }
                Button {
                    withAnimation { appState.errorMessage = nil; appState.lastFailedAction = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: d.fontBody))
                        .foregroundStyle(Palette.destructive.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss error")
            }
            .padding(.horizontal, d.rowHPad)
            .padding(.vertical, d.padXS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.destructive.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Palette.destructive.opacity(0.12), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, d.padSM)
            .padding(.vertical, d.padMicro)
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            .accessibilityLabel("Error: \(error)")
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        let d = prefs.density
        return HStack(spacing: d.spacingLG) {
            if appState.isSignedIn {
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: d.fontBody))
                        .rotationEffect(.degrees(appState.isLoading ? 360 : 0))
                        .animation(appState.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: appState.isLoading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .disabled(appState.isLoading)
                .help("Refresh (⌘R)")
                .accessibilityLabel("Refresh")

                Text("\(appState.filteredItems.count) items")
                    .font(.system(size: d.fontCaption))
                    .foregroundStyle(.quaternary)
                    .accessibilityLabel("\(appState.filteredItems.count) items")

                if appState.totalHourlyBurn > 0 {
                    Text("·")
                        .font(.system(size: d.fontCaption))
                        .foregroundStyle(.quaternary)
                    Text("~\(formatCost(appState.totalHourlyBurn))/hr")
                        .font(.system(size: d.fontCaption, design: .monospaced))
                        .foregroundStyle(spendColor(appState.totalHourlyBurn))
                        .help("Estimated total hourly burn across all active capacities")
                }

                if let time = appState.lastRefreshTime {
                    Text("·")
                        .font(.system(size: d.fontCaption))
                        .foregroundStyle(.quaternary)
                    Text(time, style: .relative)
                        .font(.system(size: d.fontCaption))
                        .foregroundStyle(.quaternary)
                        .accessibilityLabel("Last refreshed")
                }

                if !appState.currentPath.isRoot {
                    Button {
                        appState.requestImport()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: d.fontCaption))
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
                    .font(.system(size: d.fontCaption))
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
            .frame(width: floor(60 * prefs.density.scale))
            .controlSize(.mini)
            .help("Display density")
            .accessibilityLabel("Display density")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: d.fontCaption, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.quaternary)
            .help("Quit FabricTray")
            .keyboardShortcut("q")
            .accessibilityLabel("Quit")
        }
        .padding(.horizontal, d.padMD)
        .padding(.vertical, d.padSM)
    }

    // MARK: - Jobs Section

    private var jobsSection: some View {
        let d = prefs.density
        return DisclosureGroup(isExpanded: $appState.showJobs) {
            if appState.recentJobs.isEmpty {
                Text("No recent jobs")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .padding(.vertical, d.padXS)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.recentJobs.prefix(10)) { job in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: d.padSM) {
                                Image(systemName: job.status.icon)
                                    .font(.system(size: d.fontCaption))
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
                                            .font(.system(size: d.fontCaption))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Palette.destructive.opacity(0.7))
                                    .help("Cancel job")
                                    .accessibilityLabel("Cancel job \(job.itemName)")
                                }
                                Text(job.status.rawValue)
                                    .font(.system(size: d.fontCaption, weight: .medium))
                                    .foregroundStyle(jobStatusColor(job.status).opacity(0.8))
                                if let date = job.startedAt {
                                    Text(date, style: .relative)
                                        .font(.system(size: d.fontCaption))
                                        .foregroundStyle(.quaternary)
                                }
                            }
                            // Show failure reason for failed jobs
                            if job.status == .failed, let reason = job.failureReason, !reason.isEmpty {
                                Text(reason)
                                    .font(.system(size: d.fontCaption))
                                    .foregroundStyle(Palette.destructive.opacity(0.7))
                                    .lineLimit(3)
                                    .padding(.leading, d.padMD + d.padSM)
                                    .padding(.top, d.padMicro)
                                    .textSelection(.enabled)
                            }
                            // Duration for completed/failed jobs
                            if let start = job.startedAt, let end = job.endedAt,
                               (job.status == .completed || job.status == .failed) {
                                let duration = end.timeIntervalSince(start)
                                Text("Duration: \(formatDuration(duration))")
                                    .font(.system(size: d.fontCaption))
                                    .foregroundStyle(.quaternary)
                                    .padding(.leading, d.padMD + d.padSM)
                                    .padding(.top, d.padMicro)
                            }
                            // Link to Fabric portal for investigation
                            if let url = job.fabricPortalURL {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    HStack(spacing: d.padMicro) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: d.fontCaption))
                                        Text("View in Fabric")
                                            .font(.system(size: d.fontCaption))
                                    }
                                    .foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, d.padMD + d.padSM)
                                .padding(.top, d.padMicro)
                                .help("Open item in Fabric portal")
                            }
                        }
                        .padding(.vertical, d.padMicro)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(job.itemName), \(job.status.rawValue)\(job.failureReason.map { ", reason: \($0)" } ?? "")")
                    }
                }
            }
        } label: {
            HStack(spacing: d.padSM) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: d.fontCaption))
                    .foregroundStyle(Palette.warning)
                Text("Jobs")
                    .font(.caption)
                    .fontWeight(.medium)
                let running = appState.recentJobs.filter { $0.status == .inProgress }.count
                if running > 0 {
                    Text("\(running) running")
                        .font(.system(size: d.fontCaption, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, d.badgePadH)
                        .padding(.vertical, d.badgePadV)
                        .background(Capsule().fill(Palette.warning))
                }
                let failed = appState.recentJobs.filter { $0.status == .failed }.count
                if failed > 0 {
                    Text("\(failed) failed")
                        .font(.system(size: d.fontCaption, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, d.badgePadH)
                        .padding(.vertical, d.badgePadV)
                        .background(Capsule().fill(Palette.destructive))
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, d.padMD)
        .padding(.vertical, d.padSM)
        .accessibilityLabel("Jobs section")
    }

    // MARK: - Capacity Spend Bar

    private var capacitySpendBar: some View {
        let d = prefs.density
        return HStack(spacing: d.spacingLG) {
            Image(systemName: "dollarsign.gauge.chart.lefthalf.righthalf")
                .font(.system(size: d.fontBody))
                .foregroundStyle(spendColor(appState.totalHourlyBurn))
            VStack(alignment: .leading, spacing: d.badgePadV) {
                Text("Estimated Burn Rate")
                    .font(.system(size: d.fontCaption, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: d.padSM) {
                    Text("\(formatCost(appState.totalHourlyBurn))/hr")
                        .font(.system(size: d.fontTitle, weight: .bold, design: .monospaced))
                        .foregroundStyle(spendColor(appState.totalHourlyBurn))
                    Text("≈ \(formatCost(appState.totalMonthlyEstimate))/mo")
                        .font(.system(size: d.fontCaption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            let active = appState.capacities.filter(\.isActive).count
            let total = appState.capacities.count
            VStack(alignment: .trailing, spacing: d.badgePadV) {
                Text("\(active)/\(total) active")
                    .font(.system(size: d.fontCaption, weight: .medium))
                    .foregroundStyle(.secondary)
                let totalCU = appState.capacities.filter(\.isActive).reduce(0) { $0 + $1.capacityUnits }
                Text("\(totalCU) CU")
                    .font(.system(size: d.fontBody, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, d.padMD)
        .padding(.vertical, d.padSM)
        .background(Palette.sectionBG)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Estimated burn rate \(formatCost(appState.totalHourlyBurn)) per hour")
    }

    // MARK: - Capacity-First List

    private var capacityFirstList: some View {
        let d = prefs.density
        let groups = appState.orderedWorkspacesByCapacity(
            capacityOrder: prefs.capacityOrder,
            workspaceOrder: prefs.workspaceOrder,
            hiddenCapacities: prefs.hiddenCapacities,
            hiddenWorkspaces: prefs.hiddenWorkspaces
        )
        return ScrollView {
            LazyVStack(spacing: 0) {
                if groups.isEmpty && !appState.isLoading {
                    if appState.allItems.isEmpty {
                        VStack(spacing: d.padSM) {
                            Image(systemName: "cpu")
                                .font(.system(size: d.iconHero))
                                .foregroundStyle(.quaternary)
                            Text("No workspaces found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, d.iconHero)
                    }
                } else if appState.isLoading && appState.allItems.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                } else {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 {
                            Divider().opacity(0.3).padding(.horizontal, d.padMD)
                        }

                        let capKey = group.capacity?.id ?? ""
                        let isCollapsed = prefs.collapsedCapacities.contains(capKey)
                        let hiddenCount = countHiddenWorkspaces(capacityId: capKey)

                        // Capacity header — tappable to collapse/expand
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isCollapsed {
                                    prefs.collapsedCapacities.remove(capKey)
                                } else {
                                    prefs.collapsedCapacities.insert(capKey)
                                }
                            }
                        } label: {
                            HStack(spacing: 0) {
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: d.fontMicro, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: d.iconSize)
                                    .padding(.leading, d.padSM)

                                if let cap = group.capacity {
                                    capacityGroupHeader(cap, workspaceCount: group.workspaces.count)
                                } else {
                                    noCapacityGroupHeader(workspaceCount: group.workspaces.count)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // Collapsed summary + hidden count
                        if isCollapsed {
                            HStack(spacing: d.padSM) {
                                Text("\(group.workspaces.count) workspace\(group.workspaces.count == 1 ? "" : "s")")
                                    .font(.system(size: d.fontMicro))
                                    .foregroundStyle(.tertiary)
                                if hiddenCount > 0 {
                                    Text("· \(hiddenCount) hidden")
                                        .font(.system(size: d.fontMicro))
                                        .foregroundStyle(.quaternary)
                                }
                            }
                            .padding(.leading, d.padMD + d.iconSize + d.padSM)
                            .padding(.bottom, d.padXS)
                        }

                        // Workspace rows (only when expanded)
                        if !isCollapsed {
                            ForEach(group.workspaces, id: \.id) { ws in
                                Button {
                                    Task { await appState.enter(item: ws) }
                                } label: {
                                    HStack(spacing: d.padSM) {
                                        Image(systemName: ws.icon)
                                            .font(.system(size: d.fontBody))
                                            .foregroundStyle(Palette.accent)
                                            .frame(width: d.iconSize)
                                        Text(ws.name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                        if appState.isFavorite(ws.id) {
                                            Image(systemName: "star.fill")
                                                .font(.system(size: d.fontNano))
                                                .foregroundStyle(.yellow)
                                        }
                                        Spacer()
                                        if let role = ws.role {
                                            Text(role.rawValue)
                                                .font(.system(size: d.fontMicro))
                                                .foregroundStyle(.secondary)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: d.fontNano))
                                            .foregroundStyle(.quaternary)
                                    }
                                    .padding(.horizontal, d.padMD)
                                    .padding(.leading, d.rowHPad)
                                    .padding(.vertical, d.padXS)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(ws.name) workspace")
                            }

                            // Hidden workspaces indicator
                            if hiddenCount > 0 {
                                HStack(spacing: d.spacingSM) {
                                    Image(systemName: "eye.slash")
                                        .font(.system(size: d.fontMicro))
                                    Text("\(hiddenCount) hidden")
                                        .font(.system(size: d.fontMicro))
                                }
                                .foregroundStyle(.quaternary)
                                .padding(.leading, d.padMD + d.rowHPad)
                                .padding(.vertical, d.padMicro)
                            }
                        }
                    }

                    // Global hidden capacities indicator
                    if !prefs.hiddenCapacities.isEmpty {
                        HStack(spacing: d.spacingSM) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: d.fontMicro))
                            Text("\(prefs.hiddenCapacities.count) capacit\(prefs.hiddenCapacities.count == 1 ? "y" : "ies") hidden")
                                .font(.system(size: d.fontMicro))
                        }
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, d.padSM)
                    }
                }
            }
        }
        .frame(maxHeight: prefs.density.maxListHeight)
    }

    private func countHiddenWorkspaces(capacityId: String) -> Int {
        appState.allItems
            .filter { $0.type == .workspace && ($0.capacityId ?? "") == capacityId && prefs.hiddenWorkspaces.contains($0.id) }
            .count
    }

    // MARK: - Edit Mode List

    private var editModeList: some View {
        let d = prefs.density
        let groups = appState.orderedWorkspacesByCapacity(
            capacityOrder: prefs.capacityOrder,
            workspaceOrder: prefs.workspaceOrder,
            showHidden: true
        )
        let hasAnyHidden = !prefs.hiddenCapacities.isEmpty || !prefs.hiddenWorkspaces.isEmpty
        return List {
            // Show All reset button
            if hasAnyHidden {
                Button {
                    withAnimation { prefs.unhideAll() }
                } label: {
                    HStack(spacing: d.padSM) {
                        Image(systemName: "eye")
                            .font(.system(size: d.fontCaption))
                        Text("Show All Hidden")
                            .font(.system(size: d.fontCaption, weight: .medium))
                    }
                    .foregroundStyle(Palette.accent)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: d.padSM, bottom: 4, trailing: d.padSM))
            }

            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                let capKey = group.capacity?.id ?? ""
                let isCapHidden = prefs.hiddenCapacities.contains(capKey)
                Section {
                    ForEach(group.workspaces, id: \.id) { ws in
                        let isWSHidden = prefs.hiddenWorkspaces.contains(ws.id)
                        HStack(spacing: d.padSM) {
                            Button {
                                withAnimation {
                                    if isWSHidden {
                                        prefs.hiddenWorkspaces.remove(ws.id)
                                    } else {
                                        prefs.hiddenWorkspaces.insert(ws.id)
                                    }
                                }
                            } label: {
                                Image(systemName: isWSHidden ? "eye.slash" : "eye")
                                    .font(.system(size: d.fontCaption))
                                    .foregroundStyle(isWSHidden ? Palette.muted.opacity(0.4) : Palette.accent)
                            }
                            .buttonStyle(.plain)

                            Image(systemName: ws.icon)
                                .font(.system(size: d.fontCaption))
                                .foregroundStyle(isWSHidden ? Palette.muted.opacity(0.3) : Palette.accent)
                                .frame(width: 16)
                            Text(ws.name)
                                .font(.system(size: d.fontCaption))
                                .lineLimit(1)
                                .foregroundStyle(isWSHidden ? .secondary : .primary)
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: d.padSM, bottom: 2, trailing: d.padSM))
                    }
                    .onMove { from, to in
                        var ids = group.workspaces.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        prefs.workspaceOrder[capKey] = ids
                    }
                } header: {
                    HStack(spacing: d.padSM) {
                        // Hide/show capacity toggle
                        Button {
                            withAnimation {
                                if isCapHidden {
                                    prefs.hiddenCapacities.remove(capKey)
                                } else {
                                    prefs.hiddenCapacities.insert(capKey)
                                }
                            }
                        } label: {
                            Image(systemName: isCapHidden ? "eye.slash" : "eye")
                                .font(.system(size: 11))
                                .foregroundStyle(isCapHidden ? Palette.muted.opacity(0.4) : Palette.accent)
                        }
                        .buttonStyle(.plain)

                        Text(group.capacity?.displayName ?? "No Capacity")
                            .font(.system(size: d.fontCaption, weight: .semibold))
                            .textCase(nil)
                            .foregroundStyle(isCapHidden ? .secondary : .primary)
                        Spacer()
                        Button {
                            moveCapacityGroup(at: index, direction: -1, groups: groups)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(index > 0 ? Palette.accent : Palette.muted.opacity(0.3))
                        .disabled(index == 0)
                        Button {
                            moveCapacityGroup(at: index, direction: 1, groups: groups)
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(index < groups.count - 1 ? Palette.accent : Palette.muted.opacity(0.3))
                        .disabled(index >= groups.count - 1)
                        Text("\(group.workspaces.count)")
                            .font(.system(size: d.fontMicro))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: prefs.density.maxListHeight)
    }

    private func moveCapacityGroup(at index: Int, direction: Int, groups: [(capacity: FabricCapacity?, workspaces: [FabricItem])]) {
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < groups.count else { return }
        var order = groups.map { $0.capacity?.id ?? "" }
        withAnimation(.easeInOut(duration: 0.2)) {
            order.swapAt(index, newIndex)
            prefs.capacityOrder = order
        }
    }

    /// Rich header for a capacity we have full details on.
    private func capacityGroupHeader(_ cap: FabricCapacity, workspaceCount: Int) -> some View {
        let d = prefs.density
        return VStack(alignment: .leading, spacing: d.spacingSM) {
            // Top row: SKU badge, name, status
            HStack(spacing: d.padSM) {
                if !cap.sku.isEmpty {
                    Text(cap.sku)
                        .font(.system(size: d.fontCaption, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, d.badgePadH)
                        .padding(.vertical, d.padMicro)
                        .background(RoundedRectangle(cornerRadius: 4).fill(capacityColor(cap)))
                } else {
                    Image(systemName: "lock.shield")
                        .font(.system(size: d.fontBody))
                        .foregroundStyle(.orange)
                        .frame(width: d.iconSize)
                }
                VStack(alignment: .leading, spacing: d.badgePadV) {
                    Text(cap.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    HStack(spacing: d.spacingSM) {
                        if cap.capacityUnits > 0 {
                            Text("\(cap.capacityUnits) CU")
                                .font(.system(size: d.fontCaption, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.accent)
                        }
                        if !cap.region.isEmpty {
                            if cap.capacityUnits > 0 {
                                Text("·").foregroundStyle(.quaternary)
                            }
                            Text(cap.region)
                                .font(.system(size: d.fontCaption))
                                .foregroundStyle(.secondary)
                        }
                        if cap.sku.isEmpty {
                            Text("Admin access required for details")
                                .font(.system(size: d.fontCaption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if !cap.sku.isEmpty {
                    HStack(spacing: d.spacingXS) {
                        Circle()
                            .fill(cap.isActive ? Palette.success : Palette.destructive)
                            .frame(width: d.padSM, height: d.padSM)
                        Text(cap.isActive ? "Active" : "Paused")
                            .font(.system(size: d.fontCaption, weight: .medium))
                            .foregroundStyle(cap.isActive ? Palette.success : Palette.destructive)
                    }
                }
            }
            // Burn rate row (per capacity)
            if !cap.sku.isEmpty && cap.hourlyRate > 0 {
                HStack(spacing: d.padSM) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: d.fontMicro))
                        .foregroundStyle(cap.isActive ? spendColor(cap.hourlyRate) : .secondary)
                    if cap.isActive {
                        Text("\(formatCost(cap.hourlyRate))/hr")
                            .font(.system(size: d.fontBody, weight: .semibold, design: .monospaced))
                            .foregroundStyle(spendColor(cap.hourlyRate))
                        Text("·").foregroundStyle(.quaternary)
                        Text("~\(formatCost(cap.monthlyEstimate))/mo")
                            .font(.system(size: d.fontCaption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let util = appState.capacityUtilization[cap.id] {
                            Text("·").foregroundStyle(.quaternary)
                            Text("\(Int(util))% CU")
                                .font(.system(size: d.fontCaption, weight: .semibold, design: .rounded))
                                .foregroundStyle(utilizationColor(util))
                        }
                    } else {
                        Text("Paused — $0/hr")
                            .font(.system(size: d.fontBody, weight: .medium))
                            .foregroundStyle(Palette.success)
                    }
                    Spacer()
                }
            } else if cap.licenseType == "Trial" {
                HStack(spacing: d.spacingSM) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: d.fontMicro))
                        .foregroundStyle(Palette.success)
                    Text("Trial — Free")
                        .font(.system(size: d.fontCaption, weight: .medium))
                        .foregroundStyle(Palette.success)
                }
            }
            // Pause / Resume button (always shown when available)
            if cap.canPauseResume {
                HStack {
                    if appState.capacityActionInProgress == cap.id {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: d.progressSize, height: d.progressSize)
                        Text(cap.isActive ? "Pausing…" : "Resuming…")
                            .font(.system(size: d.fontCaption, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task {
                                if cap.isActive {
                                    await appState.pauseCapacity(cap)
                                } else {
                                    await appState.resumeCapacity(cap)
                                }
                            }
                        } label: {
                            HStack(spacing: d.spacingXS) {
                                Image(systemName: cap.isActive ? "pause.fill" : "play.fill")
                                    .font(.system(size: d.fontMicro))
                                Text(cap.isActive ? "Pause Capacity" : "Resume Capacity")
                                    .font(.system(size: d.fontCaption, weight: .medium))
                            }
                            .foregroundStyle(cap.isActive ? Palette.warning : Palette.success)
                            .padding(.horizontal, d.padSM)
                            .padding(.vertical, d.padXS)
                            .background(
                                Capsule()
                                    .fill((cap.isActive ? Palette.warning : Palette.success).opacity(0.08))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder((cap.isActive ? Palette.warning : Palette.success).opacity(0.25), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            // Mini spend gauge
            if !cap.sku.isEmpty && cap.isActive && cap.hourlyRate > 0 {
                let maxRate = max(appState.capacities.map(\.hourlyRate).max() ?? 1, 1)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(spendColor(cap.hourlyRate).opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(cap.hourlyRate / maxRate), height: 3)
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, d.padMD)
        .padding(.vertical, d.padSM)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Palette.glassBorder, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, d.padSM)
        .padding(.top, d.padSM)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cap.displayName), \(cap.sku.isEmpty ? "" : cap.sku + ", ")\(workspaceCount) workspaces")
    }

    /// Header for workspaces with no capacity assigned.
    private func noCapacityGroupHeader(workspaceCount: Int) -> some View {
        let d = prefs.density
        return HStack(spacing: d.padSM) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: d.fontCaption))
                .foregroundStyle(.secondary)
                .frame(width: d.iconSize)
            VStack(alignment: .leading, spacing: d.badgePadV) {
                Text("Shared Capacity")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("Managed by your organization")
                    .font(.system(size: d.fontCaption))
                    .foregroundStyle(.quaternary)
            }
            Spacer()
            Text("\(workspaceCount)")
                .font(.system(size: d.fontCaption, weight: .medium, design: .rounded))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, d.padMD)
        .padding(.vertical, d.padSM)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Palette.glassBorder, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, d.padSM)
        .padding(.top, d.padSM)
        .accessibilityLabel("Shared capacity, \(workspaceCount) workspaces")
    }

    // MARK: - Cost Formatting

    private func formatCost(_ amount: Double) -> String {
        if amount >= 1000 {
            return String(format: "$%.0f", amount)
        } else if amount >= 1 {
            return String(format: "$%.2f", amount)
        } else {
            return String(format: "$%.2f", amount)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    private func spendColor(_ hourlyRate: Double) -> Color {
        if hourlyRate <= 0 { return .secondary }
        if hourlyRate < 5 { return Palette.success }
        if hourlyRate < 20 { return Palette.warning }
        return Palette.destructive
    }

    private func utilizationColor(_ pct: Double) -> Color {
        if pct < 50 { return Palette.success }
        if pct < 80 { return Palette.warning }
        return Palette.destructive
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
    @EnvironmentObject private var prefs: TrayPreferences
    @State private var isLoading = true

    var body: some View {
        let d = prefs.density
        VStack(alignment: .leading, spacing: d.padSM) {
            if isLoading {
                HStack(spacing: d.padSM) {
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
            HStack(spacing: d.spacingXS) {
                Text("ID")
                    .font(.system(size: d.fontCaption, weight: .medium))
                    .foregroundStyle(.quaternary)
                Text(item.id)
                    .font(.system(size: d.fontCaption, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.id, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: d.fontNano))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.quaternary)
                .help("Copy ID")
            }
        }
        .padding(.horizontal, d.padXL + d.padXS)
        .padding(.vertical, d.padSM)
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
        let d = prefs.density
        return Group {
            if let cap = item.capacity {
                HStack(spacing: d.padSM) {
                    Text(cap.sku)
                        .font(.system(size: d.fontCaption, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, d.padXS)
                        .padding(.vertical, d.padMicro)
                        .background(RoundedRectangle(cornerRadius: 4).fill(capColor(cap)))
                    Text(cap.displayName)
                        .font(.system(size: d.fontCaption))
                        .foregroundStyle(Palette.muted)
                    Text(cap.region)
                        .font(.system(size: d.fontCaption))
                        .foregroundStyle(.tertiary)
                    if !cap.isActive {
                        Text("PAUSED")
                            .font(.system(size: d.fontCaption, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, d.padXS)
                            .padding(.vertical, d.badgePadV)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.destructive))
                    }
                }
                .padding(.bottom, d.padXS)
            }

            if appState.roleAssignments.isEmpty {
                Text("No access info")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.roleAssignments) { ra in
                        HStack(spacing: d.padSM) {
                            Image(systemName: ra.role.icon)
                                .font(.system(size: d.fontCaption))
                                .foregroundStyle(Palette.muted)
                                .frame(width: d.fontTitle)
                            Text(ra.principalName)
                                .font(.system(size: d.fontBody))
                                .lineLimit(1)
                            Spacer()
                            Text(ra.principalType)
                                .font(.system(size: d.fontCaption))
                                .foregroundStyle(.quaternary)
                                .padding(.horizontal, d.padXS)
                                .padding(.vertical, d.badgePadV)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.faint))
                            Button {
                                appState.requestRemoveRole(ra, workspaceID: item.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: d.fontCaption))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.destructive.opacity(0.5))
                            .help("Remove access")
                            .accessibilityLabel("Remove access for \(ra.principalName)")
                        }
                        .padding(.vertical, d.padMicro)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            Button {
                appState.requestAddRole(workspaceID: item.id)
            } label: {
                HStack(spacing: d.spacingXS) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: d.fontCaption))
                    Text("Add access")
                        .font(.system(size: d.fontCaption, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
            .padding(.top, d.padMicro)
            .accessibilityLabel("Add access")
        }
    }

    private var detailView: some View {
        let d = prefs.density
        return Group {
            if let detail = appState.itemDetail {
                VStack(alignment: .leading, spacing: d.spacingSM) {
                    HStack(spacing: d.spacingSM) {
                        Text("Type")
                            .font(.system(size: d.fontCaption, weight: .medium))
                            .foregroundStyle(.quaternary)
                        Text(item.type.rawValue)
                            .font(.system(size: d.fontCaption, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                    if let desc = detail.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: d.fontBody))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(3)
                    }
                    if let label = detail.sensitivityLabel {
                        HStack(spacing: d.spacingXS) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: d.fontCaption))
                            Text(label.name)
                                .font(.system(size: d.fontCaption, weight: .medium))
                        }
                        .foregroundStyle(Palette.warning)
                        .padding(.horizontal, d.badgePadH)
                        .padding(.vertical, d.padMicro)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.warning.opacity(0.1)))
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
        let d = prefs.density
        return HStack(spacing: d.padSM) {
            // Favorite indicator
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: d.fontNano))
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
                        .font(.system(size: d.fontCaption))
                        .foregroundStyle(.tertiary)
                        .help(role.rawValue)
                }
                if item.isOnCapacity {
                    if let cap = item.capacity {
                        HStack(spacing: d.spacingXS) {
                            Text(cap.sku)
                                .font(.system(size: d.fontCaption, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, d.padXS)
                                .padding(.vertical, d.badgePadV)
                                .background(RoundedRectangle(cornerRadius: 4).fill(skuColor(cap)))
                            if !cap.isActive {
                                Image(systemName: "pause.circle.fill")
                                    .font(.system(size: d.fontCaption))
                                    .foregroundStyle(Palette.destructive)
                                    .help("Capacity paused")
                            }
                        }
                        .help("\(cap.displayName) · \(cap.licenseType) · \(cap.region)")
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: d.badgePadH, height: d.badgePadH)
                    }
                }
            } else {
                if let label = item.sensitivityLabel {
                    Text(label.name)
                        .font(.system(size: d.fontCaption, weight: .medium))
                        .foregroundStyle(Palette.warning)
                        .padding(.horizontal, d.padXS)
                        .padding(.vertical, d.badgePadV)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.warning.opacity(0.12)))
                        .lineLimit(1)
                }
                Text(item.type.rawValue)
                    .font(.system(size: d.fontCaption))
                    .foregroundStyle(.quaternary)
            }

            Spacer()

            // Action buttons — visible on hover
            Group {
                Button { onToggleExpand() } label: {
                    Image(systemName: isExpanded ? "info.circle.fill" : "info.circle")
                        .font(.system(size: d.fontBody))
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
                            .font(.system(size: d.fontCaption))
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
                        .font(.system(size: d.fontCaption))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted.opacity(0.5))
                .help("Open in browser")
                .accessibilityLabel("Open \(item.name) in browser")
            }
            .opacity(isHovered || isExpanded ? 1 : 0)
        }
        .padding(.horizontal, d.padMD)
        .padding(.vertical, d.rowVPad)
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
                .frame(width: floor(280 * prefs.density.scale))
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
    @EnvironmentObject private var prefs: TrayPreferences
    @State private var textInput = ""
    @State private var textInput2 = ""
    @State private var selectedType: FabricItemType = .notebook
    @State private var selectedRole: WorkspaceRole = .viewer
    @State private var selectedCapacityID = ""

    private var action: PendingAction? { appState.pendingAction }

    var body: some View {
        let d = prefs.density
        if let action = action {
            VStack(alignment: .leading, spacing: d.spacingLG) {
                // Header
                HStack(spacing: d.padSM) {
                    Image(systemName: action.acceptIcon)
                        .font(.system(size: d.fontTitle))
                        .foregroundStyle(action.isDestructive ? Palette.destructive : Palette.accent)
                        .frame(width: d.iconLarge)
                    Text(action.title)
                        .font(.system(.caption, weight: .semibold))
                        .lineLimit(1)
                }

                // Form fields
                formFields(for: action)

                // Buttons
                HStack(spacing: d.spacingLG) {
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
                        HStack(spacing: d.spacingSM) {
                            Image(systemName: action.acceptIcon)
                                .font(.system(size: d.fontMicro))
                            Text(action.acceptLabel)
                                .font(.system(.caption2, weight: .medium))
                        }
                        .padding(.horizontal, d.padXS)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(action.isDestructive ? Palette.destructive : Palette.accent)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(.horizontal, d.rowHPad)
            .padding(.vertical, d.padMD)
            .background(Palette.sectionBG)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Confirm action: \(action.title)")
        }
    }

    @ViewBuilder
    private func formFields(for action: PendingAction) -> some View {
        let d = prefs.density
        switch action.kind {
        case .run:
            if action.supportsParameters {
                VStack(alignment: .leading, spacing: d.spacingXS) {
                    Text("Execution parameters (JSON)")
                        .font(.system(size: d.fontCaption, weight: .medium)).foregroundStyle(.tertiary)
                    TextField("{\"key\": \"value\"}", text: $textInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: d.fontBody, design: .monospaced))
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
            VStack(spacing: d.spacingSM) {
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
                HStack(spacing: d.spacingSM) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: d.fontCaption))
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
            VStack(spacing: d.spacingSM) {
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
            VStack(spacing: d.spacingSM) {
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
    @EnvironmentObject private var prefs: TrayPreferences
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
        let d = prefs.density
        return VStack(spacing: d.rowHPad) {
            // Step indicator
            HStack(spacing: d.spacingSM) {
                ForEach(0..<steps.count, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentStep ? Palette.accent : Color.primary.opacity(0.15))
                        .frame(width: d.padSM, height: d.padSM)
                }
            }
            .padding(.top, d.rowHPad)

            // Content
            VStack(spacing: d.spacingLG) {
                Image(systemName: steps[currentStep].icon)
                    .font(.system(size: floor(28 * d.scale)))
                    .foregroundStyle(Palette.accent)
                    .frame(height: floor(36 * d.scale))

                Text(steps[currentStep].title)
                    .font(.system(.caption, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(steps[currentStep].description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, d.iconHero)
            }
            .animation(.easeInOut(duration: 0.2), value: currentStep)

            // Navigation
            HStack(spacing: d.rowHPad) {
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
                            .padding(.horizontal, d.rowHPad)
                            .padding(.vertical, d.padXS)
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
                            .padding(.horizontal, d.rowHPad)
                            .padding(.vertical, d.padXS)
                            .background(Palette.accent)
                            .foregroundStyle(.white)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, d.padLG)

            Button("Skip") {
                appState.completeOnboarding()
            }
            .font(.system(size: d.fontBody))
            .buttonStyle(.plain)
            .foregroundStyle(.quaternary)
            .padding(.bottom, d.spacingLG)
        }
        .frame(width: floor(300 * d.scale))
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