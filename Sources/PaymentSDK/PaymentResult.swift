import Foundation

public enum PaymentStatus: String {
    case success
    case error
    case cancel
    case pending
}

/// Result of a payment session.
///
/// Fields mirror the gateway's `MerchantPaymentCallback` payload, the same one
/// the web widget receives:
/// `{ status, reference, orderReference, transactionId, amount, currency,
///    message, timestamp, data }`
public struct PaymentResult {

    public let status: PaymentStatus
    public let message: String?
    public let reference: String?
    public let orderReference: String?
    public let transactionId: String?
    public let amount: String?
    public let currency: String?
    public let timestamp: String?

    /// Any field not mapped above. The gateway's nested `data` object lands
    /// here under the key `"data"`, as raw JSON.
    public let extras: [String: String]

    /// The exact JSON the gateway sent, for logging or custom parsing.
    public let rawJSON: String?

    public init(
        status: PaymentStatus,
        message: String? = nil,
        reference: String? = nil,
        orderReference: String? = nil,
        transactionId: String? = nil,
        amount: String? = nil,
        currency: String? = nil,
        timestamp: String? = nil,
        extras: [String: String] = [:],
        rawJSON: String? = nil
    ) {
        self.status = status
        self.message = message
        self.reference = reference
        self.orderReference = orderReference
        self.transactionId = transactionId
        self.amount = amount
        self.currency = currency
        self.timestamp = timestamp
        self.extras = extras
        self.rawJSON = rawJSON
    }

    public var isSuccess: Bool { status == .success }
    public var isError: Bool { status == .error }
    public var isCancelled: Bool { status == .cancel }
    public var isPending: Bool { status == .pending }

    /// `amount` parsed as a number, or nil if absent/unparseable.
    public var amountValue: Double? { amount.flatMap(Double.init) }

    // MARK: - Factories

    public static func success(
        message: String? = nil,
        extras: [String: String] = [:]
    ) -> PaymentResult {
        PaymentResult(status: .success, message: message, extras: extras)
    }

    public static func error(message: String? = nil) -> PaymentResult {
        PaymentResult(status: .error, message: message)
    }

    public static func cancel() -> PaymentResult {
        PaymentResult(status: .cancel, message: "Payment cancelled by user")
    }

    // MARK: - Parsing

    private static let mappedKeys: Set<String> = [
        "status", "message", "reference", "orderReference",
        "transactionId", "amount", "currency", "timestamp"
    ]

    /// Parses the gateway payload delivered through the JS bridge.
    /// Status matching is case-insensitive and accepts common synonyms.
    /// Returns `nil` if the payload is not a JSON object.
    public static func fromJSON(_ raw: String) -> PaymentResult? {
        guard
            let jsonData = raw.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: jsonData),
            let dict = object as? [String: Any]
        else {
            return nil
        }

        func str(_ key: String) -> String? {
            guard let value = dict[key], !(value is NSNull) else { return nil }
            let text = value as? String ?? String(describing: value)
            return text.isEmpty ? nil : text
        }

        let rawStatus = (dict["status"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        let status: PaymentStatus
        switch rawStatus {
        case "success", "paid", "completed":
            status = .success
        case "cancel", "cancelled", "canceled":
            status = .cancel
        case "pending", "processing":
            status = .pending
        default:
            status = .error
        }

        var extras: [String: String] = [:]
        for (key, value) in dict where !mappedKeys.contains(key) && !(value is NSNull) {
            if let nested = try? JSONSerialization.data(withJSONObject: value),
               let text = String(data: nested, encoding: .utf8) {
                extras[key] = text          // nested objects/arrays as raw JSON
            } else {
                extras[key] = value as? String ?? String(describing: value)
            }
        }

        return PaymentResult(
            status: status,
            message: str("message"),
            reference: str("reference"),
            orderReference: str("orderReference"),
            transactionId: str("transactionId"),
            amount: str("amount"),
            currency: str("currency"),
            timestamp: str("timestamp"),
            extras: extras,
            rawJSON: raw
        )
    }
}

extension PaymentResult: CustomStringConvertible {
    public var description: String {
        "PaymentResult(status: \(status.rawValue), message: \(message ?? "nil"), "
            + "reference: \(reference ?? "nil"), transactionId: \(transactionId ?? "nil"), "
            + "amount: \(amount ?? "nil") \(currency ?? ""), extras: \(extras))"
    }
}