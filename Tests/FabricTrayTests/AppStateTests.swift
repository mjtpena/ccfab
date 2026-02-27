@testable import FabricTray
import XCTest

/// Tests for AppState focusing on synchronous state changes.
/// Async network calls are tested through FabricAPIClientTests.
@MainActor
final class AppStateTests: XCTestCase {

    private func makeItem(
        id: String = "item-1", name: String = "TestItem",
        type: FabricItemType = .notebook, workspaceID: String? = "ws-1"
    ) -> FabricItem {
        FabricItem(id: id, name: name, type: type, workspaceID: workspaceID,
                   role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)
    }

    private func makeJobRun(
        id: String = "job-1", itemID: String = "item-1", status: JobRunStatus = .inProgress
    ) -> JobRun {
        JobRun(id: id, itemID: itemID, itemName: "TestItem", status: status, startedAt: nil)
    }

    // MARK: - Initial State

    func testInitialState() {
        let state = AppState()
        XCTAssertFalse(state.isSignedIn)
        XCTAssertFalse(state.isAuthenticating)
        XCTAssertNil(state.userName)
        XCTAssertNil(state.userEmail)
        XCTAssertTrue(state.currentPath.isRoot)
        XCTAssertTrue(state.allItems.isEmpty)
        XCTAssertTrue(state.searchQuery.isEmpty)
        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.recentJobs.isEmpty)
        XCTAssertFalse(state.showJobs)
        XCTAssertTrue(state.capacities.isEmpty)
        XCTAssertTrue(state.roleAssignments.isEmpty)
        XCTAssertNil(state.itemDetail)
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(state.toastMessage)
        XCTAssertNil(state.pendingAction)
        XCTAssertTrue(state.notificationsEnabled)
        XCTAssertEqual(state.trayStatus, .idle)
    }

    // MARK: - Filtered Items

    func testFilteredItemsNoQuery() {
        let state = AppState()
        let items = [makeItem(name: "Alpha"), makeItem(name: "Beta")]
        state.allItems = items
        XCTAssertEqual(state.filteredItems.count, 2)
    }

    func testFilteredItemsWithQuery() {
        let state = AppState()
        state.allItems = [
            makeItem(id: "1", name: "Sales Report"),
            makeItem(id: "2", name: "HR Dashboard"),
            makeItem(id: "3", name: "Sales Pipeline")
        ]
        state.searchQuery = "Sales"
        XCTAssertEqual(state.filteredItems.count, 2)
        XCTAssertTrue(state.filteredItems.allSatisfy { $0.name.contains("Sales") })
    }

    func testFilteredItemsCaseInsensitive() {
        let state = AppState()
        state.allItems = [
            makeItem(id: "1", name: "MyNotebook"),
            makeItem(id: "2", name: "Other")
        ]
        state.searchQuery = "mynotebook"
        XCTAssertEqual(state.filteredItems.count, 1)
        XCTAssertEqual(state.filteredItems[0].name, "MyNotebook")
    }

    // MARK: - Sign Out

    func testSignOutClearsState() {
        let state = AppState()
        state.isSignedIn = true
        state.userName = "Alice"
        state.userEmail = "alice@example.com"
        state.allItems = [makeItem()]
        state.searchQuery = "test"
        state.recentJobs = [makeJobRun()]
        state.toastMessage = "Done"
        state.errorMessage = "Oops"

        state.signOut()

        XCTAssertFalse(state.isSignedIn)
        XCTAssertNil(state.userName)
        XCTAssertNil(state.userEmail)
        XCTAssertTrue(state.allItems.isEmpty)
        XCTAssertTrue(state.searchQuery.isEmpty)
        XCTAssertTrue(state.recentJobs.isEmpty)
        XCTAssertTrue(state.capacities.isEmpty)
        XCTAssertTrue(state.roleAssignments.isEmpty)
        XCTAssertNil(state.itemDetail)
        XCTAssertNil(state.toastMessage)
        XCTAssertNil(state.errorMessage)
        XCTAssertTrue(state.currentPath.isRoot)
        XCTAssertEqual(state.trayStatus, .idle)
    }

    // MARK: - Notifications Toggle

    func testToggleNotifications() {
        let state = AppState()
        XCTAssertTrue(state.notificationsEnabled)

        state.toggleNotifications(false)
        XCTAssertFalse(state.notificationsEnabled)

        state.toggleNotifications(true)
        XCTAssertTrue(state.notificationsEnabled)
    }

    // MARK: - Request Actions

    func testRequestRun() {
        let state = AppState()
        let item = makeItem()
        state.requestRun(item)
        XCTAssertNotNil(state.pendingAction)
        if case .run(let i) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
        } else {
            XCTFail("Expected .run action")
        }
    }

    func testRequestCancelJob() {
        let state = AppState()
        let job = makeJobRun()
        state.requestCancelJob(job)
        if case .cancelJob(let j) = state.pendingAction?.kind {
            XCTAssertEqual(j.id, job.id)
        } else {
            XCTFail("Expected .cancelJob action")
        }
    }

    func testRequestDelete() {
        let state = AppState()
        let item = makeItem()
        state.requestDelete(item)
        if case .deleteItem(let i) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
        } else {
            XCTFail("Expected .deleteItem action")
        }
    }

    func testRequestRename() {
        let state = AppState()
        let item = makeItem()
        state.requestRename(item)
        if case .renameItem(let i) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
        } else {
            XCTFail("Expected .renameItem action")
        }
    }

    func testRequestCreateWorkspace() {
        let state = AppState()
        state.requestCreateWorkspace()
        if case .createWorkspace = state.pendingAction?.kind {
            // OK
        } else {
            XCTFail("Expected .createWorkspace action")
        }
    }

    func testRequestCreateItemRequiresWorkspace() {
        let state = AppState()
        // At root (no workspace), should not set pending action
        state.requestCreateItem()
        XCTAssertNil(state.pendingAction)
    }

    func testRequestCreateItemInWorkspace() {
        let state = AppState()
        state.currentPath = NavigationPath(workspaceID: "ws-1", workspaceName: "WS")
        state.requestCreateItem()
        if case .createItem(let wsID) = state.pendingAction?.kind {
            XCTAssertEqual(wsID, "ws-1")
        } else {
            XCTFail("Expected .createItem action")
        }
    }

    func testRequestAssignCapacity() {
        let state = AppState()
        let item = makeItem(type: .workspace)
        state.requestAssignCapacity(item)
        if case .assignCapacity(let i) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
        } else {
            XCTFail("Expected .assignCapacity action")
        }
    }

    func testRequestUnassignCapacity() {
        let state = AppState()
        let item = makeItem(type: .workspace)
        state.requestUnassignCapacity(item)
        if case .unassignCapacity(let i) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
        } else {
            XCTFail("Expected .unassignCapacity action")
        }
    }

    func testRequestAddRole() {
        let state = AppState()
        state.requestAddRole(workspaceID: "ws-1")
        if case .addRole(let wsID) = state.pendingAction?.kind {
            XCTAssertEqual(wsID, "ws-1")
        } else {
            XCTFail("Expected .addRole action")
        }
    }

    func testRequestRemoveRole() {
        let state = AppState()
        let ra = RoleAssignment(id: "ra-1", principalName: "Alice", principalType: "User", role: .admin)
        state.requestRemoveRole(ra, workspaceID: "ws-1")
        if case .removeRole(let r, let wsID) = state.pendingAction?.kind {
            XCTAssertEqual(r.id, "ra-1")
            XCTAssertEqual(wsID, "ws-1")
        } else {
            XCTFail("Expected .removeRole action")
        }
    }

    func testRequestSetLabel() {
        let state = AppState()
        let item = makeItem()
        state.requestSetLabel(item)
        if case .setLabel(let i, let wsID) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
            XCTAssertEqual(wsID, "ws-1")
        } else {
            XCTFail("Expected .setLabel action")
        }
    }

    func testRequestRemoveLabel() {
        let state = AppState()
        let item = makeItem()
        state.requestRemoveLabel(item)
        if case .removeLabel(let i, let wsID) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
            XCTAssertEqual(wsID, "ws-1")
        } else {
            XCTFail("Expected .removeLabel action")
        }
    }

    func testRequestExport() {
        let state = AppState()
        let item = makeItem()
        state.requestExport(item)
        if case .exportDefinition(let i, let wsID) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
            XCTAssertEqual(wsID, "ws-1")
        } else {
            XCTFail("Expected .exportDefinition action")
        }
    }

    func testRequestImportRequiresWorkspace() {
        let state = AppState()
        state.requestImport()
        XCTAssertNil(state.pendingAction)
    }

    func testRequestImportInWorkspace() {
        let state = AppState()
        state.currentPath = NavigationPath(workspaceID: "ws-1", workspaceName: "WS")
        state.requestImport()
        if case .importItem(let wsID) = state.pendingAction?.kind {
            XCTAssertEqual(wsID, "ws-1")
        } else {
            XCTFail("Expected .importItem action")
        }
    }

    func testRequestCreateShortcut() {
        let state = AppState()
        let item = makeItem(type: .lakehouse)
        state.requestCreateShortcut(item)
        if case .createShortcut(let i, let wsID) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
            XCTAssertEqual(wsID, "ws-1")
        } else {
            XCTFail("Expected .createShortcut action")
        }
    }

    func testRequestUploadFile() {
        let state = AppState()
        state.currentPath = NavigationPath(workspaceID: "ws-1", workspaceName: "My WS")
        let item = makeItem(type: .lakehouse)
        state.requestUploadFile(item)
        if case .uploadFile(let i, let wsName) = state.pendingAction?.kind {
            XCTAssertEqual(i.id, item.id)
            XCTAssertEqual(wsName, "My WS")
        } else {
            XCTFail("Expected .uploadFile action")
        }
    }

    func testRequestLoadTable() {
        let state = AppState()
        state.currentPath = NavigationPath(workspaceID: "ws-1", workspaceName: "WS")
        // loadTable is set directly, not through a request method
        let action = PendingAction(kind: .loadTable(workspaceID: "ws-1", lakehouseID: "lh-1", tableName: "sales"))
        state.pendingAction = action
        XCTAssertNotNil(state.pendingAction)
        if case .loadTable(let wsID, let lhID, let table) = state.pendingAction?.kind {
            XCTAssertEqual(wsID, "ws-1")
            XCTAssertEqual(lhID, "lh-1")
            XCTAssertEqual(table, "sales")
        } else {
            XCTFail("Expected .loadTable action")
        }
    }

    // MARK: - Dismiss Action

    func testDismissAction() {
        let state = AppState()
        state.requestCreateWorkspace()
        XCTAssertNotNil(state.pendingAction)

        state.dismissAction()
        XCTAssertNil(state.pendingAction)
    }

    func testDismissActionWhenNil() {
        let state = AppState()
        state.dismissAction()
        XCTAssertNil(state.pendingAction)
    }

    // MARK: - Actions Overwrite Previous

    func testNewRequestOverwritesPrevious() {
        let state = AppState()
        state.requestCreateWorkspace()
        XCTAssertNotNil(state.pendingAction)

        let item = makeItem()
        state.requestDelete(item)
        if case .deleteItem = state.pendingAction?.kind {
            // OK — replaced
        } else {
            XCTFail("Expected new action to overwrite previous")
        }
    }
}
