import UIKit
import WebKit

/// The payment screen. Loads the gateway in a `WKWebView` and listens for the
/// result on two transports (see `bridgeScript`).
public final class PaymentViewController: UIViewController {

    // MARK: - Constants

    private static let channelName = "PaymentChannel"

    /// Listens on BOTH transports the gateway may use:
    ///
    ///  1. `payment-result` CustomEvent — the SDK/WebView path.
    ///  2. `postMessage` — the same path paymentwidget.js uses on the web.
    ///     Inside a WKWebView there is no parent frame, so the gateway's
    ///     `window.parent.postMessage(...)` lands back on this window.
    ///
    /// Listening to both means one gateway build drives web, Android and iOS
    /// with no user-agent branching. Duplicate payloads are de-duped here.
    ///
    /// WebKit injects this on every navigation automatically, so unlike Android
    /// there is no manual re-injection.
    private static let bridgeScript = """
    (function() {
      if (window.__paymentBridgeInstalled) return;
      window.__paymentBridgeInstalled = true;

      var lastPayload = null;

      function post(payload) {
        try {
          window.webkit.messageHandlers.\(channelName).postMessage(payload);
        } catch (err) {
          console.error('PaymentSDK bridge error:', err);
        }
      }

      // Shim so gateway code written for the Android bridge works unchanged.
      if (!window.PaymentChannel) {
        window.PaymentChannel = { postMessage: post };
      }

      function forward(raw) {
        if (!raw) return;
        var d = raw;
        if (typeof d === 'string') {
          try { d = JSON.parse(d); } catch (e) { return; }
        }
        if (!d || typeof d.status !== 'string') return;

        var s = JSON.stringify(d);
        if (s === lastPayload) return;   // de-dupe both transports
        lastPayload = s;
        post(s);
      }

      window.addEventListener('payment-result', function(e) {
        forward(e.detail);
      });

      window.addEventListener('message', function(e) {
        forward(e.data);
      });
    })();
    """

    // MARK: - State

    private let config: PaymentConfig
    private let callbacks: PaymentCallbacks
    private var didFinish = false
    private var didFireOnLoad = false

    // MARK: - Views

    private var webView: WKWebView!
    private let spinner = UIActivityIndicatorView(style: .large)
    private let errorContainer = UIStackView()
    private let errorDetail = UILabel()

    // MARK: - Init

    public init(config: PaymentConfig, callbacks: PaymentCallbacks) {
        self.config = config
        self.callbacks = callbacks
        super.init(nibName: nil, bundle: nil)
    }

    /// Convenience for callers that only care about the terminal result.
    public convenience init(
        config: PaymentConfig,
        onFinish: @escaping (PaymentResult) -> Void
    ) {
        self.init(config: config, callbacks: PaymentCallbacks(onFinish: onFinish))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — use init(config:callbacks:)")
    }

    deinit {
        // The user content controller retains message handlers strongly.
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.channelName)
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = "Payment"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        setupWebView()
        setupOverlays()

        if let validationError = config.validate() {
            finish(with: .error(message: "Invalid config: \(validationError)"))
            return
        }

        loadPayment()
    }

    // MARK: - Setup

    private func setupWebView() {
        let controller = WKUserContentController()

        // WeakScriptMessageHandler avoids the retain cycle:
        // controller -> handler -> self -> webView -> controller
        controller.add(
            WeakScriptMessageHandler(delegate: self),
            name: Self.channelName
        )

        controller.addUserScript(
            WKUserScript(
                source: Self.bridgeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupOverlays() {
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        let title = UILabel()
        title.text = "Something went wrong"
        title.font = .preferredFont(forTextStyle: .headline)
        title.textAlignment = .center

        errorDetail.font = .preferredFont(forTextStyle: .body)
        errorDetail.textColor = .secondaryLabel
        errorDetail.textAlignment = .center
        errorDetail.numberOfLines = 0

        let retry = UIButton(type: .system)
        retry.setTitle("Retry", for: .normal)
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        errorContainer.axis = .vertical
        errorContainer.spacing = 12
        errorContainer.alignment = .center
        errorContainer.isHidden = true
        errorContainer.backgroundColor = .systemBackground
        errorContainer.isLayoutMarginsRelativeArrangement = true
        errorContainer.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        errorContainer.translatesAutoresizingMaskIntoConstraints = false

        [title, errorDetail, retry].forEach { errorContainer.addArrangedSubview($0) }
        view.addSubview(errorContainer)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            errorContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    // MARK: - Loading

    private func loadPayment() {
        guard var components = URLComponents(string: config.serverURL) else {
            finish(with: .error(message: "Invalid gateway URL"))
            return
        }

        // Cache-buster, same as the web widget's `_t` param — stops WebKit
        // serving a stale gateway page.
        let cacheBuster = URLQueryItem(
            name: "_t",
            value: String(Int(Date().timeIntervalSince1970 * 1000))
        )
        components.queryItems = config.queryItems + [cacheBuster]

        guard let url = components.url else {
            finish(with: .error(message: "Could not build gateway URL"))
            return
        }

        errorContainer.isHidden = true
        webView.load(URLRequest(url: url))
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        finish(with: .cancel())
    }

    @objc private func retryTapped() {
        loadPayment()
    }

    // MARK: - Result delivery

    private func showError(_ description: String) {
        spinner.stopAnimating()
        errorDetail.text = description
        errorContainer.isHidden = false

        // The web widget routes iframe-load failures to onError too. NOT
        // terminal — the user can still tap Retry.
        callbacks.onError?(.error(message: description))
    }

    /// Dispatches callbacks, dismisses, and delivers the terminal result (once).
    private func finish(with result: PaymentResult) {
        guard !didFinish else { return }
        didFinish = true

        switch result.status {
        case .success:
            callbacks.onSuccess?(result)
        case .cancel:
            callbacks.onCancel?(result)
        case .error:
            // Web fires both onFail and onError for a failed payment.
            callbacks.onFail?(result)
            callbacks.onError?(result)
        case .pending:
            callbacks.onPending?(result)
        }

        let deliver = { [callbacks] in callbacks.onFinish?(result) }

        if let presenting = presentingViewController {
            presenting.dismiss(animated: true, completion: deliver)
        } else {
            navigationController?.popViewController(animated: true)
            deliver()
        }
    }

    /// Diagnostics, debug builds only.
    ///
    /// A published SDK writing to a merchant's console is noise they did not
    /// ask for and cannot switch off. `#if DEBUG` follows the package's own
    /// build configuration, so this is compiled out of their release builds
    /// while staying available while developing against the SDK.
    private func log(_ message: String) {
        #if DEBUG
        print("PaymentSDK: \(message)")
        #endif
    }

    /// Called by the JS bridge.
    fileprivate func handleBridgeMessage(_ body: Any) {
        guard let raw = body as? String,
              let result = PaymentResult.fromJSON(raw)
        else {
            log("failed to parse JS message")
            return
        }

        // `pending` is NOT terminal — keep the screen open so the user sees the
        // gateway's processing view. Same as the web widget's onPending.
        if result.isPending {
            log("status pending — staying on screen")
            callbacks.onPending?(result)
            return
        }

        finish(with: result)
    }
}

// MARK: - WKNavigationDelegate

extension PaymentViewController: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url?.absoluteString ?? ""

        // Legacy custom-scheme fallbacks (older gateway builds).
        if url.hasPrefix("payment-success") {
            decisionHandler(.cancel)
            finish(with: .success(message: "Payment completed"))
            return
        }
        if url.hasPrefix("payment-cancel") {
            decisionHandler(.cancel)
            finish(with: .cancel())
            return
        }
        if url.hasPrefix("payment-error") {
            decisionHandler(.cancel)
            finish(with: .error(message: "Payment failed"))
            return
        }

        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        spinner.startAnimating()
        errorContainer.isHidden = true
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()

        // Mirrors the web widget's onLoad, which fires once per init.
        if !didFireOnLoad {
            didFireOnLoad = true
            callbacks.onLoad?()
        }
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    private func handleNavigationError(_ error: Error) {
        // A cancelled load is normal when we block a custom scheme above.
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else {
            spinner.stopAnimating()
            return
        }
        showError(nsError.localizedDescription)
    }
}

// MARK: - JS bridge plumbing

/// `WKUserContentController` retains its message handlers strongly, which would
/// otherwise keep the view controller alive forever. This proxy breaks the cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {

    private weak var delegate: PaymentViewController?

    init(delegate: PaymentViewController) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.handleBridgeMessage(message.body)
    }
}