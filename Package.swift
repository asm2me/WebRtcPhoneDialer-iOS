// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WebRtcPhoneDialer-iOS",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "WebRtcPhoneDialer-iOS",
            targets: ["WebRtcPhoneDialer-iOS"]
        )
    ],
    targets: [
        .target(
            name: "WebRtcPhoneDialer-iOS",
            path: "WebRtcPhoneDialer-iOS"
        )
    ]
)
