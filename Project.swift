import ProjectDescription

let project = Project(
    name: "CodexPill",
    organizationName: "raphhgg",
    packages: [],
    targets: [
        .target(
            name: "CodexPill",
            destinations: .macOS,
            product: .app,
            bundleId: "com.raphhgg.codexpill",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .dictionary([
                "CFBundleDevelopmentRegion": "en",
                "CFBundleDisplayName": "CodexPill",
                "CFBundleExecutable": "$(EXECUTABLE_NAME)",
                "CFBundleIconFile": "AppIcon",
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
                "Resources/AppIcon.icns",
                "Resources/AppIcon.png",
            ],
            dependencies: [],
            settings: .settings(base: [
                "CODE_SIGN_INJECT_BASE_ENTITLEMENTS": "NO",
                "CURRENT_PROJECT_VERSION": "1",
                "ENABLE_DEBUG_DYLIB": "NO",
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
