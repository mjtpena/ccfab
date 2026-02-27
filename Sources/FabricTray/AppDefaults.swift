import Foundation

enum AppDefaults {
    static let tenantID = sanitized(
        ProcessInfo.processInfo.environment["FABRIC_TRAY_TENANT_ID"],
        fallback: "organizations"
    )

    static let clientID = sanitized(
        ProcessInfo.processInfo.environment["FABRIC_TRAY_CLIENT_ID"],
        fallback: "3e377a6d-020e-47c0-a652-ef26154d5770"
    )

    private static func sanitized(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
