@testable import FabricTray
import XCTest

final class PendingActionTests: XCTestCase {

    private let sampleItem = FabricItem(
        id: "item-1", name: "TestNotebook", type: .notebook,
        workspaceID: "ws-1", role: nil, capacityId: nil,
        capacity: nil, sensitivityLabel: nil
    )

    private let sampleWorkspace = FabricItem(
        id: "ws-1", name: "My Workspace", type: .workspace,
        workspaceID: nil, role: .admin, capacityId: "cap-1",
        capacity: nil, sensitivityLabel: nil
    )

    private let sampleRole = RoleAssignment(
        id: "ra-1", principalName: "Alice", principalType: "User", role: .contributor
    )

    // MARK: - Title

    func testRunTitle() {
        let action = PendingAction(kind: .run(sampleItem))
        XCTAssertEqual(action.title, "Run TestNotebook?")
    }

    func testDeleteTitle() {
        let action = PendingAction(kind: .deleteItem(sampleWorkspace))
        XCTAssertEqual(action.title, "Delete My Workspace?")
    }

    func testRenameTitle() {
        let action = PendingAction(kind: .renameItem(sampleItem))
        XCTAssertEqual(action.title, "Rename TestNotebook")
    }

    func testCreateWorkspaceTitle() {
        let action = PendingAction(kind: .createWorkspace)
        XCTAssertEqual(action.title, "New Workspace")
    }

    func testCreateItemTitle() {
        let action = PendingAction(kind: .createItem(workspaceID: "ws-1"))
        XCTAssertEqual(action.title, "New Item")
    }

    func testRemoveRoleTitle() {
        let action = PendingAction(kind: .removeRole(sampleRole, workspaceID: "ws-1"))
        XCTAssertEqual(action.title, "Remove Alice?")
    }

    func testLoadTableTitle() {
        let action = PendingAction(kind: .loadTable(workspaceID: "ws-1", lakehouseID: "lh-1", tableName: "sales"))
        XCTAssertEqual(action.title, "Load table sales?")
    }

    // MARK: - Accept Labels

    func testAcceptLabels() {
        XCTAssertEqual(PendingAction(kind: .run(sampleItem)).acceptLabel, "Run")
        XCTAssertEqual(PendingAction(kind: .deleteItem(sampleItem)).acceptLabel, "Delete")
        XCTAssertEqual(PendingAction(kind: .renameItem(sampleItem)).acceptLabel, "Rename")
        XCTAssertEqual(PendingAction(kind: .createWorkspace).acceptLabel, "Create")
        XCTAssertEqual(PendingAction(kind: .assignCapacity(sampleWorkspace)).acceptLabel, "Assign")
        XCTAssertEqual(PendingAction(kind: .addRole(workspaceID: "ws-1")).acceptLabel, "Add")
        XCTAssertEqual(PendingAction(kind: .setLabel(sampleItem, workspaceID: "ws-1")).acceptLabel, "Set")
        XCTAssertEqual(PendingAction(kind: .exportDefinition(sampleItem, workspaceID: "ws-1")).acceptLabel, "Export")
        XCTAssertEqual(PendingAction(kind: .importItem(workspaceID: "ws-1")).acceptLabel, "Import")
        XCTAssertEqual(PendingAction(kind: .uploadFile(sampleItem, workspaceName: "ws")).acceptLabel, "Upload")
        XCTAssertEqual(PendingAction(kind: .loadTable(workspaceID: "ws-1", lakehouseID: "lh-1", tableName: "t")).acceptLabel, "Load")
    }

    // MARK: - Accept Icons

    func testAcceptIcons() {
        XCTAssertEqual(PendingAction(kind: .run(sampleItem)).acceptIcon, "play.fill")
        XCTAssertEqual(PendingAction(kind: .deleteItem(sampleItem)).acceptIcon, "trash.fill")
        XCTAssertEqual(PendingAction(kind: .renameItem(sampleItem)).acceptIcon, "pencil")
        XCTAssertEqual(PendingAction(kind: .createWorkspace).acceptIcon, "plus")
        XCTAssertEqual(PendingAction(kind: .assignCapacity(sampleWorkspace)).acceptIcon, "cpu")
    }

    // MARK: - Destructive

    func testIsDestructive() {
        XCTAssertTrue(PendingAction(kind: .deleteItem(sampleItem)).isDestructive)
        XCTAssertTrue(PendingAction(kind: .removeRole(sampleRole, workspaceID: "ws-1")).isDestructive)
        XCTAssertTrue(PendingAction(kind: .removeLabel(sampleItem, workspaceID: "ws-1")).isDestructive)
        XCTAssertTrue(PendingAction(kind: .cancelJob(JobRun(id: "j1", itemID: "i1", itemName: "N", status: .inProgress, startedAt: nil))).isDestructive)
        XCTAssertTrue(PendingAction(kind: .unassignCapacity(sampleWorkspace)).isDestructive)

        XCTAssertFalse(PendingAction(kind: .run(sampleItem)).isDestructive)
        XCTAssertFalse(PendingAction(kind: .createWorkspace).isDestructive)
        XCTAssertFalse(PendingAction(kind: .renameItem(sampleItem)).isDestructive)
        XCTAssertFalse(PendingAction(kind: .assignCapacity(sampleWorkspace)).isDestructive)
        XCTAssertFalse(PendingAction(kind: .addRole(workspaceID: "ws-1")).isDestructive)
    }

    // MARK: - Supports Parameters

    func testSupportsParameters() {
        let notebook = FabricItem(id: "1", name: "NB", type: .notebook, workspaceID: "ws-1", role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)
        let pipeline = FabricItem(id: "2", name: "PL", type: .dataPipeline, workspaceID: "ws-1", role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)
        let spark = FabricItem(id: "3", name: "SJ", type: .sparkJobDefinition, workspaceID: "ws-1", role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)
        let report = FabricItem(id: "4", name: "RP", type: .report, workspaceID: "ws-1", role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)

        XCTAssertTrue(PendingAction(kind: .run(notebook)).supportsParameters)
        XCTAssertTrue(PendingAction(kind: .run(pipeline)).supportsParameters)
        XCTAssertTrue(PendingAction(kind: .run(spark)).supportsParameters)
        XCTAssertFalse(PendingAction(kind: .run(report)).supportsParameters)

        // Non-run actions never support parameters
        XCTAssertFalse(PendingAction(kind: .deleteItem(notebook)).supportsParameters)
        XCTAssertFalse(PendingAction(kind: .createWorkspace).supportsParameters)
    }
}
