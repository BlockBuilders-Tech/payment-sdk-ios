# PaymentSDK — iOS (Swift Package)

iOS port of the payment SDK. Same gateway, same `payment-result` JS bridge
contract, same result types as the Android and Flutter versions.

```
PaymentSDK-iOS/
├── Package.swift
├── README.md
└── Sources/PaymentSDK/
    ├── PaymentConfig.swift
    ├── PaymentResult.swift
    ├── PaymentViewController.swift
    └── PaymentSDK.swift
```

Requires iOS 13+. No third-party dependencies.

---

## Use it

```swift
import PaymentSDK

PaymentSDK.startPayment(
    from: self,
    config: PaymentConfig(
        ereference: "ORDER_123",
        token: "your_token",
        url: "https://your-callback.com",
        lang: "en"
        // serverURL: "https://portaltest.qredit.tech/plugin/"  // test env
    )
) { result in
    switch result.status {
    case .success: print("Paid:", result.message ?? "", result.data ?? [:])
    case .cancel:  print("Cancelled")
    case .error:   print("Error:", result.message ?? "")
    case .pending: break   // not normally delivered — screen stays open
    }
}
```

Or with async/await:
```swift
let result = await PaymentSDK.startPayment(from: self, config: config)
```

No `Info.plist` changes needed — the gateway is HTTPS, so App Transport
Security is satisfied out of the box.

---

## Publish it

iOS is much simpler than Android here: **Swift Package Manager resolves straight
from Git tags.** There is no registry, no account, no signing, no upload, and
no propagation delay. Merchants need no tokens.

1. Push this folder to a repo, e.g. `github.com/YOUR_USER/payment-sdk-ios`
   (`Package.swift` must be at the repo root).
2. Tag it:
   ```bash
   git tag 1.0.0
   git push origin 1.0.0
   ```

That's the whole release. Merchants add it in Xcode via
**File → Add Package Dependencies →** paste the repo URL, or in their own
`Package.swift`:

```swift
.package(url: "https://github.com/YOUR_USER/payment-sdk-ios.git", from: "1.0.0")
```

A **private** repo works identically — merchants just need read access to it;
Xcode uses their existing Git credentials.

---

## Checking it builds

`codemagic.yaml` builds the package for iOS on every push and tag.

This is verification, not publication — see above, a tag *is* the release. It
earns its place for a different reason: this package is developed on Windows,
where there is no Swift compiler and no Xcode, so without a macOS runner the
first person to discover it does not compile is a merchant.

One trap it encodes: **`swift build` is the wrong command here.** On a macOS
runner it targets macOS, `PaymentViewController` imports UIKit, and the build
fails with `no such module 'UIKit'` — which reads like a broken package rather
than a toolchain mismatch. The workflow names an iOS destination instead, and
builds for device and simulator separately, since a package can pass one and
fail the other.

It also writes out the public API surface as a build artifact. Diff it between
two builds to tell a MINOR release from a MAJOR one instead of guessing.

---

## Versioning

The Git tag *is* the version — there's no version string in any file to keep in
sync. Same semver rules as the Android SDK:

| Change | Bump |
| --- | --- |
| Bug fix | `1.0.0 → 1.0.1` |
| New feature, existing code still compiles | `1.0.1 → 1.1.0` |
| Merchant code breaks | `1.1.0 → 2.0.0` |

`from: "1.0.0"` means "any 1.x", so merchants pick up your patches and minors
automatically but never a breaking 2.0.

Swift-specific breaking changes worth watching, both of which mirror Kotlin:

- **Adding a case to `PaymentStatus` breaks every exhaustive `switch`** a
  merchant wrote. That's a MAJOR bump.
- **Adding an `init` parameter without a default value** is MAJOR. With a
  default, it's MINOR.

And the same golden rule: never move a tag that's already published. Merchants'
`Package.resolved` files pin the commit hash, so a moved tag causes checksum
mismatches. Broke `1.0.1`? Ship `1.0.2`.

---

## Notes

- **Bridge injection is automatic.** On Android the bridge is re-injected
  manually on every `onPageFinished`. WebKit's `WKUserScript` does that for you
  on every navigation, including the gateway's internal ones.
- **Gateway compatibility shim.** The bridge installs `window.PaymentChannel`
  pointing at `webkit.messageHandlers`, so gateway JS written for the Android
  bridge works unchanged.
- **Swipe-to-dismiss is disabled by default** so an accidental swipe can't kill
  a transaction; the Close button returns `.cancel`. Pass
  `allowSwipeToDismiss: true` to change that.
- **To change the gateway URL**, pass `serverURL:` in `PaymentConfig` — do not
  look for a constant to edit. Swift Package Manager checks this package out
  read-only into DerivedData and throws local edits away on the next resolve,
  so a merchant consuming it over SPM cannot change a line in it. Mirrors
  `serverUrl` on the web widget.
- **`fromJSON`** makes the same assumptions as the Kotlin version: reads
  `status` and `message`, collects everything else into `data`. If your real
  payload differs, both platforms need the same edit.
