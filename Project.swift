import ProjectDescription

let project = Project(
    name: "CodexPill",
    organizationName: "raphaelgrau",
    targets: [
        .target(
            name: "CodexPill",
            destinations: .macOS,
            product: .app,
            bundleId: "com.raphhgg.codexpill",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(
                with: [
                    "LSUIElement": true,
                    "CFBundleDisplayName": "CodexPill",
                    "CFBundleIconFile": "AppIcon",
                    "CFBundleIconName": "AppIcon",
                ]
            ),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            ])
        ),
        .target(
            name: "CodexPillTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.raphhgg.codexpill.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "CodexPill")
            ]
        )
    ]
)
