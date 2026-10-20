import ProjectDescription

let project = Project(
    name: "RUsage",
    organizationName: "raphhgg",
    packages: [],
    targets: [
        .target(
            name: "RUsage",
            destinations: .macOS,
            product: .app,
            productName: "rusage",
            bundleId: "com.raphhgg.rusage",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": "en",
                "CFBundleDisplayName": "rusage",
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
                "CFBundleInfoDictionaryVersion": "6.0",
                "CFBundleName": "$(PRODUCT_NAME)",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
                "LSUIElement": true,
                "NSPrincipalClass": "NSApplication",
            ]),
            sources: ["Sources/**"],
            resources: [
                "Resources/AppIcon.icon",
                "Resources/Assets.xcassets",
            ],
            dependencies: [],
            settings: .settings(base: [
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "NO",
                "CURRENT_PROJECT_VERSION": "2",
                "ENABLE_DEBUG_DYLIB": "NO",
                // "rusage" would shadow Darwin's `struct rusage` in Swift, so the module keeps the target's name.
                "PRODUCT_MODULE_NAME": "RUsage",
                "SWIFT_VERSION": "6.0",
            ])
        ),
        .target(
            name: "RUsageTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.raphhgg.rusage.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "RUsage")
            ],
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
            ])
        )
    ]
)
