// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "SpringCard_PcSc_Like",
  platforms: [
    .iOS(.v12)
  ],
  products: [
    .library(
      name: "SpringCard_PcSc_Like",
      targets: ["SpringCard_PcSc_Like"]
    )
  ],
  dependencies: [
      .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMajor(from: "1.3.0"))
    ],
  targets: [
    .target(name: "SpringCard_PcSc_Like", dependencies: ["CryptoSwift"], path: "SpringCard_PcSc_Like"),
  ],
  swiftLanguageVersions: [.v5]
)

