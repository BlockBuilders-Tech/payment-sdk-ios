import Foundation

/// Configuration for initiating a payment session.
public struct PaymentConfig {

    /// Where the hosted checkout lives, when the caller does not say.
    ///
    /// Production. A merchant testing against another environment passes
    /// `serverURL:` instead — they cannot edit this file. Swift Package
    /// Manager checks the package out read-only into DerivedData and discards
    /// local changes on the next resolve, so "edit the constant" is advice
    /// nobody consuming this package can follow.
    public static let defaultServerURL = "https://portaltest.qredit.tech/plugin/"

    public let ereference: String
    public let token: String
    public let url: String
    public let lang: String

    /// The gateway to load. Defaults to ``defaultServerURL``.
    ///
    /// Mirrors `serverUrl` on the web widget, so the two SDKs are pointed at a
    /// test environment the same way.
    public let serverURL: String

    /// Added with a default value, which keeps this a MINOR change: existing
    /// call sites still compile untouched.
    public init(
        ereference: String,
        token: String,
        url: String,
        lang: String = "en",
        serverURL: String = PaymentConfig.defaultServerURL
    ) {
        self.ereference = ereference
        self.token = token
        self.url = url
        self.lang = lang
        self.serverURL = serverURL
    }

    /// Basic validation before launching the payment screen.
    /// Returns `nil` when the config is valid, or a message describing the problem.
    public func validate() -> String? {
        if ereference.trimmed.isEmpty { return "ereference is required" }
        if token.trimmed.isEmpty { return "token is required" }
        if url.trimmed.isEmpty { return "url is required" }

        guard let parsed = URL(string: url),
              let scheme = parsed.scheme,
              !scheme.isEmpty
        else {
            return "url is not a valid URL"
        }

        // Caught here rather than at load time: a typo in an overridden
        // gateway would otherwise surface as a blank screen with no
        // explanation, long after the call that caused it.
        if serverURL.trimmed.isEmpty { return "serverURL is required" }

        guard let gateway = URL(string: serverURL),
              let gatewayScheme = gateway.scheme?.lowercased(),
              gatewayScheme == "https" || gatewayScheme == "http"
        else {
            return "serverURL is not a valid http(s) URL"
        }

        return nil // nil == valid
    }

    /// The config as query items appended to the gateway URL.
    public var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "ereference", value: ereference),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "lang", value: lang)
        ]
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
