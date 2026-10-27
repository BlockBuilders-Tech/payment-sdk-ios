// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaymentSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "PaymentSDK",
            targets: ["PaymentSDK"]
        )
    ],
    targets: [
        .target(
            name: "PaymentSDK",
            path: "Sources/PaymentSDK"
        )
    ]
)
