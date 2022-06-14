// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ARDataLogger",
    platforms: [.iOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "ARDataLogger",
            targets: ["ARDataLogger"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "Firebase", url: "https://github.com/firebase/firebase-ios-sdk.git", from: "9.0.0"),
        .package(name: "SwiftProtobuf", url: "https://github.com/apple/swift-protobuf.git", from: "1.6.0"),
        .package(name: "BitByteData", url: "https://github.com/tsolomko/BitByteData", from: "2.0.1"),
        .package(name: "SWCompression", url: "https://github.com/tsolomko/SWCompression", from: "4.6.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "ARDataLogger",
            dependencies: [.product(name: "FirebaseStorage", package: "Firebase"),
                           .product(name: "FirebaseDatabase", package: "Firebase"),
                           .product(name: "FirebaseAuth", package: "Firebase"),
                           .product(name: "SwiftProtobuf", package: "SwiftProtobuf"),
                           .product(name: "BitByteData", package: "BitByteData"),
                           .product(name: "SWCompression", package: "SWCompression")])
    ]
)
