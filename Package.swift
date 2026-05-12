// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "CodexMultiusage",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "CodexMultiusageCore", targets: ["CodexMultiusageCore"]),
    .executable(name: "CodexMultiusage", targets: ["CodexMultiusage"])
  ],
  targets: [
    .target(name: "CodexMultiusageCore"),
    .executableTarget(
      name: "CodexMultiusage",
      dependencies: ["CodexMultiusageCore"]
    ),
    .executableTarget(
      name: "CodexMultiusageCoreChecks",
      dependencies: ["CodexMultiusageCore"]
    )
  ]
)
