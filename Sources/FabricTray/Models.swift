import Foundation
import UserNotifications

// MARK: - Auth

struct AppConfiguration: Equatable {
    var tenantID: String
    var clientID: String

    var sanitizedTenantID: String {
        tenantID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sanitizedClientID: String {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !sanitizedTenantID.isEmpty && !sanitizedClientID.isEmpty
    }
}

struct StoredAuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let tenantID: String
    let clientID: String

    var isExpired: Bool {
        expiresAt <= Date()
    }

    var isNearExpiry: Bool {
        expiresAt <= Date().addingTimeInterval(300)
    }

    func matches(_ configuration: AppConfiguration) -> Bool {
        tenantID.caseInsensitiveCompare(configuration.sanitizedTenantID) == .orderedSame &&
            clientID.caseInsensitiveCompare(configuration.sanitizedClientID) == .orderedSame
    }
}

// MARK: - Fabric Items

enum FabricItemType: String, CaseIterable {
    // Core
    case workspace = "Workspace"
    case notebook = "Notebook"
    case dataPipeline = "DataPipeline"
    case lakehouse = "Lakehouse"
    case warehouse = "Warehouse"
    case report = "Report"
    case semanticModel = "SemanticModel"
    case sparkJobDefinition = "SparkJobDefinition"
    // Real-Time Intelligence
    case kqlDatabase = "KQLDatabase"
    case kqlQueryset = "KQLQueryset"
    case kqlDashboard = "KQLDashboard"
    case eventhouse = "Eventhouse"
    case eventstream = "Eventstream"
    // Databases & Mirroring
    case mirroredDatabase = "MirroredDatabase"
    case mirroredWarehouse = "MirroredWarehouse"
    case sqlDatabase = "SQLDatabase"
    case sqlEndpoint = "SQLEndpoint"
    case snowflakeDatabase = "SnowflakeDatabase"
    // Power BI
    case datamart = "Datamart"
    case dashboard = "Dashboard"
    case paginatedReport = "PaginatedReport"
    case dataflow = "Dataflow"
    // Data Science
    case mlModel = "MLModel"
    case mlExperiment = "MLExperiment"
    // Data Factory
    case copyJob = "CopyJob"
    case dataBuildToolJob = "DataBuildToolJob"
    case mountedDataFactory = "MountedDataFactory"
    // Developer
    case environment = "Environment"
    case graphQLApi = "GraphQLApi"
    // Other
    case ontology = "Ontology"
    case variableLibrary = "VariableLibrary"
    case userDataFunction = "UserDataFunction"
    case digitalTwinBuilder = "DigitalTwinBuilder"
    case map = "Map"
    case unknown = "Unknown"

    /// Name of the SVG file in Resources/Icons (without extension)
    var svgIconName: String {
        switch self {
        case .workspace: return "workspace"
        case .notebook: return "notebook"
        case .dataPipeline: return "pipeline"
        case .lakehouse: return "lakehouse"
        case .warehouse: return "warehouse"
        case .report: return "report"
        case .semanticModel: return "semantic_model"
        case .sparkJobDefinition: return "spark_job"
        case .kqlDatabase: return "kql_database"
        case .kqlQueryset: return "kql_queryset"
        case .kqlDashboard: return "dashboard"
        case .eventhouse: return "eventhouse"
        case .eventstream: return "eventstream"
        case .mirroredDatabase, .mirroredWarehouse: return "mirrored_database"
        case .sqlDatabase: return "sql_database"
        case .sqlEndpoint: return "sql_endpoint"
        case .snowflakeDatabase: return "mirrored_database"
        case .datamart: return "datamart"
        case .dashboard: return "dashboard"
        case .paginatedReport: return "paginated_report"
        case .dataflow: return "dataflow"
        case .mlModel: return "ml_model"
        case .mlExperiment: return "ml_experiment"
        case .copyJob: return "copy_job"
        case .dataBuildToolJob: return "pipeline"
        case .mountedDataFactory: return "dataflow"
        case .environment: return "environment"
        case .graphQLApi: return "graphql_api"
        case .ontology: return "exploration"
        case .variableLibrary: return "function"
        case .userDataFunction: return "function"
        case .digitalTwinBuilder: return "digital_twin"
        case .map: return "exploration"
        case .unknown: return "unknown"
        }
    }

    /// SF Symbol fallback when SVG not available
    var icon: String {
        switch self {
        case .workspace: return "folder.fill"
        case .notebook: return "doc.text.fill"
        case .dataPipeline: return "arrow.triangle.branch"
        case .lakehouse: return "building.columns.fill"
        case .warehouse: return "shippingbox.fill"
        case .report: return "chart.bar.fill"
        case .semanticModel: return "cube.fill"
        case .sparkJobDefinition: return "bolt.fill"
        case .kqlDatabase, .kqlQueryset, .kqlDashboard: return "cylinder.fill"
        case .eventhouse, .eventstream: return "waveform.path"
        case .mirroredDatabase, .mirroredWarehouse, .snowflakeDatabase: return "externaldrive.fill"
        case .sqlDatabase, .sqlEndpoint: return "cylinder.fill"
        case .datamart: return "tray.2.fill"
        case .dashboard: return "square.grid.2x2.fill"
        case .paginatedReport: return "doc.richtext.fill"
        case .dataflow: return "arrow.2.squarepath"
        case .mlModel: return "brain"
        case .mlExperiment: return "flask.fill"
        case .copyJob, .dataBuildToolJob: return "doc.on.doc.fill"
        case .mountedDataFactory: return "gearshape.2.fill"
        case .environment: return "leaf.fill"
        case .graphQLApi: return "network"
        case .ontology, .map: return "map.fill"
        case .variableLibrary: return "books.vertical.fill"
        case .userDataFunction: return "function"
        case .digitalTwinBuilder: return "building.2.fill"
        case .unknown: return "questionmark.square.fill"
        }
    }

    /// URL path segment for opening in browser
    var urlPathSegment: String {
        switch self {
        case .workspace: return ""
        case .notebook: return "synapsenotebooks"
        case .dataPipeline: return "datapipelines"
        case .lakehouse: return "lakehouses"
        case .warehouse: return "datawarehouses"
        case .report: return "reports"
        case .semanticModel: return "datasets"
        case .sparkJobDefinition: return "sparkjobdefinitions"
        case .kqlDatabase: return "kqldatabases"
        case .kqlQueryset: return "kqlquerysets"
        case .kqlDashboard: return "kqldashboards"
        case .eventhouse: return "eventhouses"
        case .eventstream: return "eventstreams"
        case .mirroredDatabase, .mirroredWarehouse: return "mirroreddatabases"
        case .sqlDatabase: return "sqldatabases"
        case .sqlEndpoint: return "sqlendpoints"
        case .snowflakeDatabase: return "snowflakedatabases"
        case .datamart: return "datamarts"
        case .dashboard: return "dashboards"
        case .paginatedReport: return "rdlreports"
        case .dataflow: return "dataflows"
        case .mlModel: return "mlmodels"
        case .mlExperiment: return "mlexperiments"
        case .copyJob: return "copyjobs"
        case .dataBuildToolJob: return "databuildtooljobs"
        case .mountedDataFactory: return "mounteddatafactories"
        case .environment: return "environments"
        case .graphQLApi: return "graphqlapis"
        case .ontology: return "ontologies"
        case .variableLibrary: return "variablelibraries"
        case .userDataFunction: return "userdatafunctions"
        case .digitalTwinBuilder: return "digitaltwinbuilders"
        case .map: return "maps"
        case .unknown: return ""
        }
    }

    var isRunnable: Bool {
        switch self {
        case .notebook, .dataPipeline, .sparkJobDefinition: return true
        default: return false
        }
    }

    var isOpenable: Bool { true }

    var supportsShortcuts: Bool {
        switch self {
        case .lakehouse, .warehouse, .kqlDatabase: return true
        default: return false
        }
    }

    var supportsUpload: Bool {
        switch self {
        case .lakehouse: return true
        default: return false
        }
    }

    static var creatableTypes: [FabricItemType] {
        [.notebook, .dataPipeline, .lakehouse, .warehouse, .semanticModel,
         .report, .sparkJobDefinition, .kqlDatabase, .kqlQueryset,
         .eventstream, .dataflow, .mlModel, .mlExperiment, .environment]
    }

    static func from(_ rawType: String) -> FabricItemType {
        allCases.first { $0.rawValue.caseInsensitiveCompare(rawType) == .orderedSame } ?? .unknown
    }
}

enum WorkspaceRole: String, Hashable {
    case admin = "Admin"
    case member = "Member"
    case contributor = "Contributor"
    case viewer = "Viewer"

    var icon: String {
        switch self {
        case .admin: return "shield.fill"
        case .member: return "person.2.fill"
        case .contributor: return "hammer.fill"
        case .viewer: return "eye.fill"
        }
    }

    static func from(_ raw: String) -> WorkspaceRole? {
        WorkspaceRole(rawValue: raw)
    }
}

struct FabricCapacity: Hashable {
    let id: String
    let displayName: String
    let sku: String
    let region: String
    let state: String

    /// License family derived from SKU prefix
    var licenseType: String {
        if sku.hasPrefix("FT") { return "Trial" }
        if sku.hasPrefix("F") { return "Fabric" }
        if sku.hasPrefix("P") { return "Premium" }
        if sku.hasPrefix("EM") { return "Embedded" }
        if sku.hasPrefix("A") { return "Azure" }
        return "Unknown"
    }

    var isActive: Bool { state == "Active" }
}

struct SensitivityLabel: Hashable {
    let id: String
    let name: String
}

struct RoleAssignment: Identifiable, Hashable {
    let id: String
    let principalName: String
    let principalType: String
    let role: WorkspaceRole
}

struct ItemDetail {
    let description: String?
    let sensitivityLabel: SensitivityLabel?
}

struct FabricItem: Identifiable, Hashable {
    let id: String
    let name: String
    let type: FabricItemType
    let workspaceID: String?
    let role: WorkspaceRole?
    let capacityId: String?
    let capacity: FabricCapacity?
    let sensitivityLabel: SensitivityLabel?

    var icon: String {
        guard type == .workspace else { return type.icon }
        if let role = role { return role.icon }
        if capacityId != nil { return "building.2.fill" }
        return "folder"
    }

    var isOnCapacity: Bool { capacityId != nil }
}

// MARK: - Job Runs

enum JobRunStatus: String {
    case inProgress = "InProgress"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case notStarted = "NotStarted"
    case deduped = "Deduped"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .cancelled: return "minus.circle"
        case .notStarted: return "clock"
        case .deduped, .unknown: return "questionmark.circle"
        }
    }

    static func from(_ raw: String) -> JobRunStatus {
        JobRunStatus(rawValue: raw) ?? .unknown
    }
}

struct JobRun: Identifiable {
    let id: String
    let itemID: String
    let itemName: String
    let status: JobRunStatus
    let startedAt: Date?
}

// MARK: - Tray Status (CCMenu-style)

enum TrayStatus: Equatable {
    case idle
    case running(count: Int)
    case attention

    var icon: String {
        switch self {
        case .idle: return "diamond.fill"
        case .running: return "diamond.fill"
        case .attention: return "exclamationmark.diamond.fill"
        }
    }

    var badgeCount: Int {
        switch self {
        case .running(let count): return count
        default: return 0
        }
    }
}

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Tapping the notification could open the app / navigate — no-op for now
    }
}

// MARK: - Navigation

struct NavigationPath: Equatable {
    let workspaceID: String?
    let workspaceName: String?

    static let root = NavigationPath(workspaceID: nil, workspaceName: nil)

    var isRoot: Bool { workspaceID == nil }

    var breadcrumb: String {
        if let name = workspaceName {
            return "/ \(name)"
        }
        return "/"
    }
}

enum ActionKind {
    case run(FabricItem)
    case cancelJob(JobRun)
    case deleteItem(FabricItem)
    case renameItem(FabricItem)
    case createWorkspace
    case createItem(workspaceID: String)
    case assignCapacity(FabricItem)
    case unassignCapacity(FabricItem)
    case addRole(workspaceID: String)
    case removeRole(RoleAssignment, workspaceID: String)
    case setLabel(FabricItem, workspaceID: String)
    case removeLabel(FabricItem, workspaceID: String)
    case exportDefinition(FabricItem, workspaceID: String)
    case importItem(workspaceID: String)
    case createShortcut(FabricItem, workspaceID: String)
    case uploadFile(FabricItem, workspaceName: String)
    case loadTable(workspaceID: String, lakehouseID: String, tableName: String)
}

struct PendingAction {
    let kind: ActionKind

    var title: String {
        switch kind {
        case .run(let i): return "Run \(i.name)?"
        case .cancelJob: return "Cancel this job?"
        case .deleteItem(let i): return "Delete \(i.name)?"
        case .renameItem(let i): return "Rename \(i.name)"
        case .createWorkspace: return "New Workspace"
        case .createItem: return "New Item"
        case .assignCapacity: return "Assign Capacity"
        case .unassignCapacity(let i): return "Unassign capacity from \(i.name)?"
        case .addRole: return "Add Access"
        case .removeRole(let ra, _): return "Remove \(ra.principalName)?"
        case .setLabel: return "Set Sensitivity Label"
        case .removeLabel(let i, _): return "Remove label from \(i.name)?"
        case .exportDefinition(let i, _): return "Export \(i.name)"
        case .importItem: return "Import Definition"
        case .createShortcut: return "Create Shortcut"
        case .uploadFile: return "Upload to OneLake"
        case .loadTable(_, _, let t): return "Load table \(t)?"
        }
    }

    var acceptLabel: String {
        switch kind {
        case .run: return "Run"
        case .cancelJob: return "Cancel Job"
        case .deleteItem: return "Delete"
        case .renameItem: return "Rename"
        case .createWorkspace, .createItem: return "Create"
        case .assignCapacity: return "Assign"
        case .unassignCapacity: return "Unassign"
        case .addRole: return "Add"
        case .removeRole: return "Remove"
        case .setLabel: return "Set"
        case .removeLabel: return "Remove"
        case .exportDefinition: return "Export"
        case .importItem: return "Import"
        case .createShortcut: return "Create"
        case .uploadFile: return "Upload"
        case .loadTable: return "Load"
        }
    }

    var acceptIcon: String {
        switch kind {
        case .run: return "play.fill"
        case .cancelJob: return "stop.fill"
        case .deleteItem, .removeRole, .removeLabel: return "trash.fill"
        case .renameItem: return "pencil"
        case .createWorkspace, .createItem, .addRole, .createShortcut: return "plus"
        case .assignCapacity, .unassignCapacity: return "cpu"
        case .setLabel: return "tag.fill"
        case .exportDefinition: return "square.and.arrow.down"
        case .importItem: return "square.and.arrow.up"
        case .uploadFile: return "arrow.up.doc"
        case .loadTable: return "arrow.down.to.line"
        }
    }

    var isDestructive: Bool {
        switch kind {
        case .deleteItem, .removeRole, .removeLabel, .cancelJob, .unassignCapacity: return true
        default: return false
        }
    }

    var supportsParameters: Bool {
        if case .run(let item) = kind {
            return item.type == .notebook || item.type == .dataPipeline || item.type == .sparkJobDefinition
        }
        return false
    }
}
