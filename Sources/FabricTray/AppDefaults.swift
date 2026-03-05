import Foundation

enum AppDefaults {
    static let tenantID = sanitized(
        ProcessInfo.processInfo.environment["FABRIC_TRAY_TENANT_ID"],
        fallback: "4b7e9d9f-8e54-43da-a1dd-2d1cc793721a"
    )

    static let clientID = sanitized(
        ProcessInfo.processInfo.environment["FABRIC_TRAY_CLIENT_ID"],
        fallback: "5c510dab-9dc3-4be3-ab81-8f6243dc1597"
    )

    private static func sanitized(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
