// swift-tools-version:5.1

import PackageDescription

let package = Package(
  name: "Echo",
  products: [
    .library(
      name: "Echo",
      targets: ["Echo"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.0")
  ],
  targets: [
    .target(
      name: "CEcho",
      dependencies: []
    ),
    .target(
      name: "Echo",
      dependencies: ["CEcho", "Atomics"]
    ),
    .testTarget(
      name: "EchoTests",
      dependencies: ["Echo"]
    )
  ]
)

