import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarStructureContractExporterTests {
    @Test
    func menuEmptyCatalogStructureContractComesFromProductExporter() throws {
        let contract = try MenuBarStructureContractExporter.makeMenuEmptyCatalogContract(
            from: emptyCatalogSnapshot()
        )

        #expect(contract.kind == "ui_structure_contract")
        #expect(contract.schemaVersion == "kite.ui-structure-contract.v1")
        #expect(contract.scenario.id == "menu-empty-catalog")
        #expect(contract.scenario.featureId == "account-catalog-empty-state")
        #expect(contract.scenario.acceptanceCriteria == ["empty-catalog-guides-to-add-account"])
        #expect(contract.root.children?.map(\.id) == [
            "active-account-section",
            "manage-accounts-section",
            "preferences-section"
        ])
        #expect(contract.assertions.map(\.id).contains("add-account-action-available"))
        #expect(contract.nonClaims.contains("Does not prove native menu opening, native click routing, focus, or hittability."))
    }

    @Test
    func menuStructureExporterDerivesObservedTreeFromSnapshot() throws {
        let root = MenuBarStructureExporter.makeStructure(from: emptyCatalogSnapshot())
        let manageSection = try #require(root.children?.first { $0.id == "manage-accounts-section" })
        let addAccount = try #require(manageSection.children?.first { $0.id == "add-account" })

        #expect(root.children?.map(\.id) == [
            "active-account-section",
            "manage-accounts-section",
            "preferences-section"
        ])
        #expect(addAccount.label == "Add Account…")
        #expect(addAccount.enabled == true)
        #expect(addAccount.actions == [
            UiStructureActionArtifact(
                id: "selector:add-account",
                label: "Add Account…",
                enabled: true
            )
        ])
    }

    @Test
    func menuStructureExporterUsesActionSelectorsForStableActionIDs() throws {
        let snapshot = MenuBarValidationSnapshot(
            sections: [
                .init(title: "Manage Accounts", items: ["Create Account…"])
            ],
            statusMessage: nil,
            currentAccount: nil,
            remoteHosts: [],
            hasStatusItemContentData: false,
            effectiveStatusBarDisplayMode: "iconOnly",
            statusItem: nil,
            actionTrace: nil,
            menuItems: [
                .init(
                    title: "Create Account…",
                    isEnabled: true,
                    state: "off",
                    hasAction: true,
                    actionSelector: "addAccount",
                    isSeparator: false,
                    viewFrameWidth: nil,
                    children: []
                )
            ]
        )

        let root = MenuBarStructureExporter.makeStructure(from: snapshot)
        let manageSection = try #require(root.children?.first { $0.id == "manage-accounts-section" })
        let item = try #require(manageSection.children?.first)

        #expect(item.id == "add-account")
        #expect(item.label == "Create Account…")
        #expect(item.actions == [
            UiStructureActionArtifact(
                id: "selector:add-account",
                label: "Create Account…",
                enabled: true
            )
        ])
    }

    @Test
    func menuStructureExporterPrefersExactSubmenuActionOverFuzzyParentMatch() throws {
        let snapshot = MenuBarValidationSnapshot(
            sections: [
                .init(title: "Manage Accounts", items: ["Add Account… (disabled)"])
            ],
            statusMessage: nil,
            currentAccount: nil,
            remoteHosts: [],
            hasStatusItemContentData: false,
            effectiveStatusBarDisplayMode: "iconOnly",
            statusItem: nil,
            actionTrace: nil,
            menuItems: [
                .init(
                    title: "Account",
                    isEnabled: true,
                    state: "off",
                    hasAction: false,
                    actionSelector: nil,
                    isSeparator: false,
                    viewFrameWidth: nil,
                    children: [
                        .init(
                            title: "Add Account…",
                            isEnabled: false,
                            state: "off",
                            hasAction: true,
                            actionSelector: "addAccount:",
                            isSeparator: false,
                            viewFrameWidth: nil,
                            children: []
                        )
                    ]
                )
            ]
        )

        let root = MenuBarStructureExporter.makeStructure(from: snapshot)
        let manageSection = try #require(root.children?.first { $0.id == "manage-accounts-section" })
        let addAccount = try #require(manageSection.children?.first)

        #expect(addAccount.id == "add-account")
        #expect(addAccount.role == "menu-item")
        #expect(addAccount.label == "Add Account…")
        #expect(addAccount.enabled == false)
        #expect(addAccount.actions == [
            UiStructureActionArtifact(
                id: "selector:add-account",
                label: "Add Account…",
                enabled: false
            )
        ])
    }

    private func emptyCatalogSnapshot() -> MenuBarValidationSnapshot {
        MenuBarValidationSnapshot(
            sections: [
                .init(title: "Active Account", items: ["No active saved account"]),
                .init(title: "Manage Accounts", items: ["Add Account…"]),
                .init(title: "Preferences", items: ["Refresh Time: 5 minutes"])
            ],
            statusMessage: nil,
            currentAccount: nil,
            remoteHosts: [],
            hasStatusItemContentData: false,
            effectiveStatusBarDisplayMode: "iconOnly",
            statusItem: nil,
            actionTrace: nil,
            menuItems: [
                .init(
                    title: "Add Account…",
                    isEnabled: true,
                    state: "off",
                    hasAction: true,
                    actionSelector: "addAccount:",
                    isSeparator: false,
                    viewFrameWidth: nil,
                    children: []
                )
            ]
        )
    }
}
