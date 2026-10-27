import UIKit

/// Web-style callbacks, mirroring `PaymentWidget.init({ onSuccess, ... })`
/// from paymentwidget.js v1.0.8. Every hook is optional.
///
/// | web         | here                                                |
/// |-------------|-----------------------------------------------------|
/// | `onLoad`    | `onLoad` — first successful page load only           |
/// | `onSuccess` | `onSuccess`                                          |
/// | `onCancel`  | `onCancel`                                           |
/// | `onFail`    | `onFail`                                             |
/// | `onError`   | `onError` — payment errors *and* page-load failures  |
/// | `onPending` | `onPending` — screen stays open                      |
/// | *(none)*    | `onFinish` — always last for a terminal result       |
///
/// All hooks are invoked on the main thread.
public struct PaymentCallbacks {

    public var onLoad: (() -> Void)?
    public var onSuccess: ((PaymentResult) -> Void)?
    public var onCancel: ((PaymentResult) -> Void)?
    public var onFail: ((PaymentResult) -> Void)?
    public var onError: ((PaymentResult) -> Void)?
    public var onPending: ((PaymentResult) -> Void)?
    public var onFinish: ((PaymentResult) -> Void)?

    public init(
        onLoad: (() -> Void)? = nil,
        onSuccess: ((PaymentResult) -> Void)? = nil,
        onCancel: ((PaymentResult) -> Void)? = nil,
        onFail: ((PaymentResult) -> Void)? = nil,
        onError: ((PaymentResult) -> Void)? = nil,
        onPending: ((PaymentResult) -> Void)? = nil,
        onFinish: ((PaymentResult) -> Void)? = nil
    ) {
        self.onLoad = onLoad
        self.onSuccess = onSuccess
        self.onCancel = onCancel
        self.onFail = onFail
        self.onError = onError
        self.onPending = onPending
        self.onFinish = onFinish
    }
}

/// The main entry point for the Payment SDK.
public enum PaymentSDK {

    // MARK: - Web-style callbacks

    /// Presents the payment screen and reports progress through `callbacks` —
    /// the closest analogue to `PaymentWidget.init({...})`.
    ///
    /// ```swift
    /// PaymentSDK.start(
    ///     from: self,
    ///     config: config,
    ///     callbacks: PaymentCallbacks(
    ///         onSuccess: { print("paid", $0.transactionId ?? "") },
    ///         onCancel:  { _ in print("cancelled") },
    ///         onFail:    { print("failed:", $0.message ?? "") },
    ///         onPending: { _ in print("processing…") }
    ///     )
    /// )
    /// ```
    ///
    /// An invalid config never shows UI — it reports `onError` + `onFinish`
    /// immediately, matching the web widget's fail-fast validation.
    public static func start(
        from presenter: UIViewController,
        config: PaymentConfig,
        allowSwipeToDismiss: Bool = false,
        callbacks: PaymentCallbacks
    ) {
        if let validationError = config.validate() {
            let result = PaymentResult.error(message: "Invalid config: \(validationError)")
            callbacks.onError?(result)
            callbacks.onFinish?(result)
            return
        }

        let paymentVC = PaymentViewController(config: config, callbacks: callbacks)

        let navigation = UINavigationController(rootViewController: paymentVC)
        navigation.modalPresentationStyle = .fullScreen
        navigation.isModalInPresentation = !allowSwipeToDismiss

        presenter.present(navigation, animated: true)
    }

    // MARK: - Single-result convenience

    /// Presents the payment screen and calls `completion` exactly once with the
    /// terminal result. Use this when you don't need the intermediate
    /// `onLoad` / `onPending` hooks.
    public static func startPayment(
        from presenter: UIViewController,
        config: PaymentConfig,
        allowSwipeToDismiss: Bool = false,
        completion: @escaping (PaymentResult) -> Void
    ) {
        start(
            from: presenter,
            config: config,
            allowSwipeToDismiss: allowSwipeToDismiss,
            callbacks: PaymentCallbacks(onFinish: completion)
        )
    }

    /// `async` variant of `startPayment(from:config:allowSwipeToDismiss:completion:)`.
    @available(iOS 13.0, *)
    @MainActor
    public static func startPayment(
        from presenter: UIViewController,
        config: PaymentConfig,
        allowSwipeToDismiss: Bool = false
    ) async -> PaymentResult {
        await withCheckedContinuation { continuation in
            startPayment(
                from: presenter,
                config: config,
                allowSwipeToDismiss: allowSwipeToDismiss
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }
}