import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

enum AuthServiceError: LocalizedError {
    case missingConfiguration
    case invalidEndpoint
    case server(String)
    case invalidResponse
    case userCancelled
    case unableToStartAuthSession
    case missingAuthorizationCode

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Tenant ID and Client ID are required before signing in."
        case .invalidEndpoint:
            return "Failed to build Microsoft identity endpoint URL."
        case .server(let message):
            return message
        case .invalidResponse:
            return "Microsoft sign-in returned an invalid response."
        case .userCancelled:
            return "Sign-in was cancelled."
        case .unableToStartAuthSession:
            return "Unable to start Microsoft sign-in."
        case .missingAuthorizationCode:
            return "Microsoft sign-in did not return an authorization code."
        }
    }
}

final class MicrosoftAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let session: URLSession
    private let tokenStore: TokenStore
    private var activeAuthSession: ASWebAuthenticationSession?

    init(session: URLSession = .shared, tokenStore: TokenStore) {
        self.session = session
        self.tokenStore = tokenStore
    }

    func authenticate(configuration: AppConfiguration) async throws -> StoredAuthToken {
        guard configuration.isComplete else {
            throw AuthServiceError.missingConfiguration
        }

        let authorization = try await requestAuthorizationCode(configuration: configuration)
        let token = try await exchangeCodeForToken(configuration: configuration, authorization: authorization)
        try tokenStore.save(token)
        return token
    }

    func currentToken(for configuration: AppConfiguration) throws -> StoredAuthToken? {
        guard let token = try tokenStore.read() else {
            return nil
        }
        guard token.matches(configuration), !token.isExpired else {
            return nil
        }
        return token
    }

    func clearToken() throws {
        try tokenStore.clear()
    }

    func refreshAccessToken(configuration: AppConfiguration) async throws -> StoredAuthToken {
        guard let existing = try tokenStore.read(),
              let refreshToken = existing.refreshToken else {
            throw AuthServiceError.invalidResponse
        }
        guard let url = URL(string: "https://login.microsoftonline.com/\(configuration.sanitizedTenantID)/oauth2/v2.0/token") else {
            throw AuthServiceError.invalidEndpoint
        }
        let body = [
            "grant_type": "refresh_token",
            "client_id": configuration.sanitizedClientID,
            "refresh_token": refreshToken,
            "scope": Self.scope
        ]
        let (data, _) = try await performFormRequest(url: url, body: body, acceptedStatusCodes: 200..<500)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(TokenResponse.self, from: data)
        if let accessToken = response.accessToken, let expiresIn = response.expiresIn {
            let token = StoredAuthToken(
                accessToken: accessToken,
                refreshToken: response.refreshToken ?? refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
                tenantID: configuration.sanitizedTenantID,
                clientID: configuration.sanitizedClientID
            )
            try tokenStore.save(token)
            return token
        }
        if let errorCode = response.error {
            throw AuthServiceError.server(response.errorDescription ?? "Token refresh failed: \(errorCode).")
        }
        throw AuthServiceError.invalidResponse
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }

    private func requestAuthorizationCode(configuration: AppConfiguration) async throws -> OAuthAuthorization {
        guard var components = URLComponents(string: "https://login.microsoftonline.com/\(configuration.sanitizedTenantID)/oauth2/v2.0/authorize") else {
            throw AuthServiceError.invalidEndpoint
        }

        let codeVerifier = try Self.generateCodeVerifier(length: 64)
        let codeChallenge = Self.codeChallenge(from: codeVerifier)
        let redirectURI = Self.redirectURI
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.sanitizedClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]

        guard let authorizeURL = components.url else {
            throw AuthServiceError.invalidResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            let authenticationSession = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: Self.redirectScheme
            ) { [weak self] callbackURL, error in
                defer {
                    self?.activeAuthSession = nil
                }

                if let authError = error {
                    if let webError = authError as? ASWebAuthenticationSessionError, webError.code == .canceledLogin {
                        continuation.resume(throwing: AuthServiceError.userCancelled)
                    } else {
                        continuation.resume(throwing: AuthServiceError.server(authError.localizedDescription))
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: AuthServiceError.invalidResponse)
                    return
                }

                do {
                    let authorizationCode = try Self.extractAuthorizationCode(from: callbackURL)
                    continuation.resume(returning: OAuthAuthorization(code: authorizationCode, codeVerifier: codeVerifier))
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            authenticationSession.presentationContextProvider = self
            authenticationSession.prefersEphemeralWebBrowserSession = false
            activeAuthSession = authenticationSession

            guard authenticationSession.start() else {
                activeAuthSession = nil
                continuation.resume(throwing: AuthServiceError.unableToStartAuthSession)
                return
            }
        }
    }

    private func exchangeCodeForToken(configuration: AppConfiguration, authorization: OAuthAuthorization) async throws -> StoredAuthToken {
        guard let url = URL(string: "https://login.microsoftonline.com/\(configuration.sanitizedTenantID)/oauth2/v2.0/token") else {
            throw AuthServiceError.invalidEndpoint
        }

        let body = [
            "grant_type": "authorization_code",
            "client_id": configuration.sanitizedClientID,
            "code": authorization.code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": authorization.codeVerifier,
            "scope": Self.scope
        ]

        let (data, _) = try await performFormRequest(url: url, body: body, acceptedStatusCodes: 200..<500)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(TokenResponse.self, from: data)

        if let accessToken = response.accessToken, let expiresIn = response.expiresIn {
            return StoredAuthToken(
                accessToken: accessToken,
                refreshToken: response.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
                tenantID: configuration.sanitizedTenantID,
                clientID: configuration.sanitizedClientID
            )
        }

        if let errorCode = response.error {
            let description = response.errorDescription ?? "Authentication failed: \(errorCode)."
            throw AuthServiceError.server(description)
        }

        throw AuthServiceError.invalidResponse
    }

    private func performFormRequest(url: URL, body: [String: String], acceptedStatusCodes: Range<Int>) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
            .map { key, value in
                "\(Self.percentEncode(key))=\(Self.percentEncode(value))"
            }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }
        guard acceptedStatusCodes.contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw AuthServiceError.server("Authentication request failed: \(message)")
        }
        return (data, httpResponse)
    }

    private static func percentEncode(_ value: String) -> String {
        let reserved = CharacterSet(charactersIn: "+&=?")
        return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(reserved)) ?? value
    }

    private static func extractAuthorizationCode(from callbackURL: URL) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AuthServiceError.invalidResponse
        }

        let queryItems = components.queryItems ?? []
        if let errorCode = queryItems.first(where: { $0.name == "error" })?.value {
            let message = queryItems.first(where: { $0.name == "error_description" })?.value ?? "Authentication failed: \(errorCode)."
            throw AuthServiceError.server(message)
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw AuthServiceError.missingAuthorizationCode
        }
        return code
    }

    private static func generateCodeVerifier(length: Int) throws -> String {
        let validCharacters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &randomBytes)
        guard status == errSecSuccess else {
            throw AuthServiceError.server("Unable to generate secure PKCE verifier.")
        }
        return String(randomBytes.map { validCharacters[Int($0) % validCharacters.count] })
    }

    private static func codeChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let redirectURI = "fabrictray://oauth-callback"
    private static let redirectScheme = "fabrictray"
    private static let scope = "https://api.fabric.microsoft.com/.default offline_access openid profile"
}

private struct OAuthAuthorization {
    let code: String
    let codeVerifier: String
}

private struct TokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let error: String?
    let errorDescription: String?
}
