// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "fork_scroll_momentum",
  platforms: [
    .macOS("10.15")
  ],
  products: [
    .library(name: "fork-scroll-momentum", targets: ["fork_scroll_momentum"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "fork_scroll_momentum",
      dependencies: []
    )
  ]
)
