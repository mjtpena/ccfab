@testable import FabricTray
import XCTest

final class ModelsTests: XCTestCase {

    // MARK: - AppConfiguration

    func testAppConfigurationIsComplete() {
        let complete = AppConfiguration(tenantID: "tenant", clientID: "client")
        XCTAssertTrue(complete.isComplete)

        let noTenant = AppConfiguration(tenantID: "", clientID: "client")
        XCTAssertFalse(noTenant.isComplete)

        let noClient = AppConfiguration(tenantID: "tenant", clientID: "")
        XCTAssertFalse(noClient.isComplete)

        let whitespace = AppConfiguration(tenantID: "  ", clientID: "  ")
        XCTAssertFalse(whitespace.isComplete)
    }

    func testAppConfigurationSanitized() {
        let config = AppConfiguration(tenantID: "  abc  ", clientID: "\nxyz\n")
        XCTAssertEqual(config.sanitizedTenantID, "abc")
        XCTAssertEqual(config.sanitizedClientID, "xyz")
    }

    // MARK: - StoredAuthToken

    func testTokenExpiry() {
        let expired = StoredAuthToken(
            accessToken: "tok", refreshToken: nil,
            expiresAt: Date().addingTimeInterval(-10),
            tenantID: "t", clientID: "c"
        )
        XCTAssertTrue(expired.isExpired)
        XCTAssertTrue(expired.isNearExpiry)

        let fresh = StoredAuthToken(
            accessToken: "tok", refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(3600),
            tenantID: "t", clientID: "c"
        )
        XCTAssertFalse(fresh.isExpired)
        XCTAssertFalse(fresh.isNearExpiry)

        let nearExpiry = StoredAuthToken(
            accessToken: "tok", refreshToken: nil,
            expiresAt: Date().addingTimeInterval(200),
            tenantID: "t", clientID: "c"
        )
        XCTAssertFalse(nearExpiry.isExpired)
        XCTAssertTrue(nearExpiry.isNearExpiry)
    }

    func testTokenMatches() {
        let token = StoredAuthToken(
            accessToken: "tok", refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
            tenantID: "TenantA", clientID: "ClientB"
        )
        let matching = AppConfiguration(tenantID: "tenanta", clientID: "clientb")
        XCTAssertTrue(token.matches(matching))

        let nonMatching = AppConfiguration(tenantID: "other", clientID: "clientb")
        XCTAssertFalse(token.matches(nonMatching))
    }

    // MARK: - FabricItemType

    func testFabricItemTypeFrom() {
        XCTAssertEqual(FabricItemType.from("Notebook"), .notebook)
        XCTAssertEqual(FabricItemType.from("notebook"), .notebook)
        XCTAssertEqual(FabricItemType.from("NOTEBOOK"), .notebook)
        XCTAssertEqual(FabricItemType.from("DataPipeline"), .dataPipeline)
        XCTAssertEqual(FabricItemType.from("Lakehouse"), .lakehouse)
        XCTAssertEqual(FabricItemType.from("SomethingNew"), .unknown)
    }

    func testFabricItemTypeIsRunnable() {
        XCTAssertTrue(FabricItemType.notebook.isRunnable)
        XCTAssertTrue(FabricItemType.dataPipeline.isRunnable)
        XCTAssertTrue(FabricItemType.sparkJobDefinition.isRunnable)
        XCTAssertFalse(FabricItemType.lakehouse.isRunnable)
        XCTAssertFalse(FabricItemType.report.isRunnable)
        XCTAssertFalse(FabricItemType.workspace.isRunnable)
    }

    func testFabricItemTypeSupportsShortcuts() {
        XCTAssertTrue(FabricItemType.lakehouse.supportsShortcuts)
        XCTAssertTrue(FabricItemType.warehouse.supportsShortcuts)
        XCTAssertTrue(FabricItemType.kqlDatabase.supportsShortcuts)
        XCTAssertFalse(FabricItemType.notebook.supportsShortcuts)
        XCTAssertFalse(FabricItemType.report.supportsShortcuts)
    }

    func testFabricItemTypeSupportsUpload() {
        XCTAssertTrue(FabricItemType.lakehouse.supportsUpload)
        XCTAssertFalse(FabricItemType.warehouse.supportsUpload)
        XCTAssertFalse(FabricItemType.notebook.supportsUpload)
    }

    func testCreatableTypes() {
        let types = FabricItemType.creatableTypes
        XCTAssertTrue(types.contains(.notebook))
        XCTAssertTrue(types.contains(.dataPipeline))
        XCTAssertTrue(types.contains(.lakehouse))
        XCTAssertFalse(types.contains(.workspace))
        XCTAssertFalse(types.contains(.unknown))
        XCTAssertTrue(types.count >= 14)
    }

    func testAllItemTypesHaveSvgIconName() {
        for type in FabricItemType.allCases {
            XCTAssertFalse(type.svgIconName.isEmpty, "\(type.rawValue) has empty svgIconName")
        }
    }

    func testAllItemTypesHaveSfSymbol() {
        for type in FabricItemType.allCases {
            XCTAssertFalse(type.icon.isEmpty, "\(type.rawValue) has empty icon")
        }
    }

    func testUrlPathSegments() {
        XCTAssertEqual(FabricItemType.notebook.urlPathSegment, "synapsenotebooks")
        XCTAssertEqual(FabricItemType.dataPipeline.urlPathSegment, "datapipelines")
        XCTAssertEqual(FabricItemType.lakehouse.urlPathSegment, "lakehouses")
        XCTAssertEqual(FabricItemType.warehouse.urlPathSegment, "datawarehouses")
        XCTAssertEqual(FabricItemType.semanticModel.urlPathSegment, "datasets")
        XCTAssertEqual(FabricItemType.paginatedReport.urlPathSegment, "rdlreports")
        XCTAssertEqual(FabricItemType.workspace.urlPathSegment, "")
        XCTAssertEqual(FabricItemType.unknown.urlPathSegment, "")
    }

    // MARK: - WorkspaceRole

    func testWorkspaceRoleFrom() {
        XCTAssertEqual(WorkspaceRole.from("Admin"), .admin)
        XCTAssertEqual(WorkspaceRole.from("Member"), .member)
        XCTAssertEqual(WorkspaceRole.from("Contributor"), .contributor)
        XCTAssertEqual(WorkspaceRole.from("Viewer"), .viewer)
        XCTAssertNil(WorkspaceRole.from("Invalid"))
        XCTAssertNil(WorkspaceRole.from(""))
    }

    func testWorkspaceRoleIcons() {
        XCTAssertEqual(WorkspaceRole.admin.icon, "shield.fill")
        XCTAssertEqual(WorkspaceRole.member.icon, "person.2.fill")
        XCTAssertEqual(WorkspaceRole.contributor.icon, "hammer.fill")
        XCTAssertEqual(WorkspaceRole.viewer.icon, "eye.fill")
    }

    // MARK: - FabricCapacity

    func testCapacityLicenseType() {
        XCTAssertEqual(FabricCapacity(id: "1", displayName: "", sku: "F64", region: "", state: "").licenseType, "Fabric")
        XCTAssertEqual(FabricCapacity(id: "1", displayName: "", sku: "FT1", region: "", state: "").licenseType, "Trial")
        XCTAssertEqual(FabricCapacity(id: "1", displayName: "", sku: "P1", region: "", state: "").licenseType, "Premium")
        XCTAssertEqual(FabricCapacity(id: "1", displayName: "", sku: "EM1", region: "", state: "").licenseType, "Embedded")
        XCTAssertEqual(FabricCapacity(id: "1", displayName: "", sku: "A1", region: "", state: "").licenseType, "Azure")
        XCTAssertEqual(FabricCapacity(id: "1", displayName: "", sku: "X1", region: "", state: "").licenseType, "Unknown")
    }

    func testCapacityIsActive() {
        XCTAssertTrue(FabricCapacity(id: "1", displayName: "", sku: "F64", region: "", state: "Active").isActive)
        XCTAssertFalse(FabricCapacity(id: "1", displayName: "", sku: "F64", region: "", state: "Paused").isActive)
        XCTAssertFalse(FabricCapacity(id: "1", displayName: "", sku: "F64", region: "", state: "").isActive)
    }

    // MARK: - NavigationPath

    func testNavigationPathRoot() {
        let root = NavigationPath.root
        XCTAssertTrue(root.isRoot)
        XCTAssertNil(root.workspaceID)
        XCTAssertNil(root.workspaceName)
        XCTAssertEqual(root.breadcrumb, "/")
    }

    func testNavigationPathWorkspace() {
        let path = NavigationPath(workspaceID: "ws-123", workspaceName: "My Workspace")
        XCTAssertFalse(path.isRoot)
        XCTAssertEqual(path.workspaceID, "ws-123")
        XCTAssertEqual(path.breadcrumb, "/ My Workspace")
    }

    // MARK: - JobRunStatus

    func testJobRunStatusFrom() {
        XCTAssertEqual(JobRunStatus.from("InProgress"), .inProgress)
        XCTAssertEqual(JobRunStatus.from("Completed"), .completed)
        XCTAssertEqual(JobRunStatus.from("Failed"), .failed)
        XCTAssertEqual(JobRunStatus.from("Cancelled"), .cancelled)
        XCTAssertEqual(JobRunStatus.from("NotStarted"), .notStarted)
        XCTAssertEqual(JobRunStatus.from("Deduped"), .deduped)
        XCTAssertEqual(JobRunStatus.from("Whatever"), .unknown)
    }

    func testJobRunStatusIcons() {
        XCTAssertFalse(JobRunStatus.inProgress.icon.isEmpty)
        XCTAssertFalse(JobRunStatus.completed.icon.isEmpty)
        XCTAssertFalse(JobRunStatus.failed.icon.isEmpty)
    }

    // MARK: - FabricItem

    func testFabricItemIconForWorkspace() {
        let adminWs = FabricItem(id: "1", name: "WS", type: .workspace, workspaceID: nil, role: .admin, capacityId: nil, capacity: nil, sensitivityLabel: nil)
        XCTAssertEqual(adminWs.icon, "shield.fill")

        let noRoleCapWs = FabricItem(id: "1", name: "WS", type: .workspace, workspaceID: nil, role: nil, capacityId: "cap-1", capacity: nil, sensitivityLabel: nil)
        XCTAssertEqual(noRoleCapWs.icon, "building.2.fill")

        let plainWs = FabricItem(id: "1", name: "WS", type: .workspace, workspaceID: nil, role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)
        XCTAssertEqual(plainWs.icon, "folder")
    }

    func testFabricItemIsOnCapacity() {
        let withCap = FabricItem(id: "1", name: "WS", type: .workspace, workspaceID: nil, role: nil, capacityId: "cap-1", capacity: nil, sensitivityLabel: nil)
        XCTAssertTrue(withCap.isOnCapacity)

        let noCap = FabricItem(id: "1", name: "WS", type: .workspace, workspaceID: nil, role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)
        XCTAssertFalse(noCap.isOnCapacity)
    }

    func testFabricItemIconForNonWorkspace() {
        let notebook = FabricItem(id: "1", name: "NB", type: .notebook, workspaceID: "ws-1", role: nil, capacityId: nil, capacity: nil, sensitivityLabel: nil)
        XCTAssertEqual(notebook.icon, FabricItemType.notebook.icon)
    }
}
