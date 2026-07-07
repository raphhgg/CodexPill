import Foundation

@MainActor
enum MenuBarStructureExporter {
    static func makeStructure(from snapshot: MenuBarValidationSnapshot) -> UiStructureNodeArtifact {
        var children = snapshot.sections.map { section in
            makeSectionNode(section, menuItems: snapshot.menuItems)
        }
        if let statusMessage = snapshot.statusMessage {
            children.append(UiStructureNodeArtifact(
                id: "status-message",
                role: "status",
                text: statusMessage,
                visible: true,
                semanticTags: ["menu-status-message"]
            ))
        }

        return UiStructureNodeArtifact(
            id: "menu-root",
            role: "menu",
            label: "CodexPill",
            visible: true,
            children: children
        )
    }

    private static func makeSectionNode(
        _ section: MenuBarValidationSnapshot.Section,
        menuItems: [MenuBarValidationSnapshot.MenuItem]
    ) -> UiStructureNodeArtifact {
        UiStructureNodeArtifact(
            id: sectionID(for: section.title),
            role: "section",
            label: section.title,
            visible: true,
            children: section.items.map { item in
                makeItemNode(item, menuItems: menuItems)
            }
        )
    }

    private static func makeItemNode(
        _ title: String,
        menuItems: [MenuBarValidationSnapshot.MenuItem]
    ) -> UiStructureNodeArtifact {
        let menuItem = findMenuItem(for: title, in: menuItems)
        let label = menuItem?.title ?? title
        let observedActionID = menuItem.flatMap(actionID(for:))
        let observedNodeID = menuItem.flatMap(nodeID(for:))
        let actions = menuItem?.hasAction == true ? [
            UiStructureActionArtifact(
                id: observedActionID ?? stableID(for: displayLabel(for: label)),
                label: label,
                enabled: menuItem?.isEnabled
            )
        ] : nil

        return UiStructureNodeArtifact(
            id: observedNodeID ?? itemID(for: title),
            role: actions == nil ? "text" : "menu-item",
            label: displayLabel(for: label),
            visible: true,
            enabled: menuItem?.isEnabled,
            semanticTags: semanticTags(for: title),
            actions: actions
        )
    }

    private static func findMenuItem(
        for title: String,
        in items: [MenuBarValidationSnapshot.MenuItem]
    ) -> MenuBarValidationSnapshot.MenuItem? {
        let expected = searchableTitle(for: title)
        if let exactMatch = findExactMenuItem(matching: expected, in: items) {
            return exactMatch
        }
        return findFuzzyMenuItem(matching: expected, in: items)
    }

    private static func findExactMenuItem(
        matching expected: String,
        in items: [MenuBarValidationSnapshot.MenuItem]
    ) -> MenuBarValidationSnapshot.MenuItem? {
        for item in items {
            if searchableTitle(for: item.title) == expected {
                return item
            }
            if let child = findExactMenuItem(matching: expected, in: item.children) {
                return child
            }
        }

        return nil
    }

    private static func findFuzzyMenuItem(
        matching expected: String,
        in items: [MenuBarValidationSnapshot.MenuItem]
    ) -> MenuBarValidationSnapshot.MenuItem? {
        for item in items {
            if searchableTitle(for: item.title).contains(expected) || expected.contains(searchableTitle(for: item.title)) {
                return item
            }
            if let child = findFuzzyMenuItem(matching: expected, in: item.children) {
                return child
            }
        }

        return nil
    }

    private static func sectionID(for title: String) -> String {
        "\(stableID(for: title))-section"
    }

    private static func itemID(for title: String) -> String {
        switch title {
        case "No active saved account":
            return "empty-active-account-row"
        default:
            return stableID(for: displayLabel(for: title))
        }
    }

    private static func actionID(for item: MenuBarValidationSnapshot.MenuItem) -> String? {
        item.actionSelector.map { "selector:\(selectorSlug(for: $0))" }
    }

    private static func nodeID(for item: MenuBarValidationSnapshot.MenuItem) -> String? {
        item.actionSelector.map(selectorSlug(for:))
    }

    private static func selectorSlug(for selector: String) -> String {
        let normalized = selector.replacingOccurrences(of: ":", with: "")
        var words: [String] = []
        var current = ""

        for scalar in normalized.unicodeScalars {
            if CharacterSet.uppercaseLetters.contains(scalar) {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                current.append(String(scalar).lowercased())
            } else if CharacterSet.alphanumerics.contains(scalar) {
                current.append(String(scalar).lowercased())
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            words.append(current)
        }

        let id = words.joined(separator: "-")
        return id.isEmpty ? "action" : id
    }

    private static func semanticTags(for title: String) -> [String]? {
        if title == "No active saved account" {
            return ["empty-active-account-row"]
        }
        if title.contains(" • S ") || title.contains(" • Session:") {
            return ["saved-account-row"]
        }
        return nil
    }

    private static func displayLabel(for title: String) -> String {
        title.replacingOccurrences(of: " (disabled)", with: "")
    }

    private static func searchableTitle(for title: String) -> String {
        displayLabel(for: title)
            .lowercased()
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stableID(for title: String) -> String {
        let scalars = title.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let raw = String(scalars)
        let collapsed = raw
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "item" : collapsed
    }
}

@MainActor
enum MenuBarStructureContractExporter {
    static func makeContract(
        for scenario: String,
        from snapshot: MenuBarValidationSnapshot
    ) throws -> UiStructureContractArtifact {
        guard let spec = scenarioSpecs[scenario] else {
            throw MenuBarStructureContractExporterError.unsupportedScenario(scenario)
        }
        return makeContract(spec: spec, from: snapshot)
    }

    static func makeMenuEmptyCatalogContract(
        from snapshot: MenuBarValidationSnapshot
    ) throws -> UiStructureContractArtifact {
        try makeContract(for: "menu-empty-catalog", from: snapshot)
    }

    private static func makeContract(
        spec: UiStructureContractSpec,
        from snapshot: MenuBarValidationSnapshot
    ) -> UiStructureContractArtifact {
        UiStructureContractArtifact(
            kind: "ui_structure_contract",
            schemaVersion: "kite.ui-structure-contract.v1",
            id: "codexpill-\(spec.scenario)-structure",
            scenario: UiStructureScenarioArtifact(
                id: spec.scenario,
                featureId: spec.featureId,
                acceptanceCriteria: spec.acceptanceCriteria,
                targetSurface: "CodexPill hosted menubar projection",
                proofType: "ui-structure-contract"
            ),
            root: MenuBarStructureExporter.makeStructure(from: snapshot),
            assertions: spec.assertions,
            nonClaims: spec.nonClaims
        )
    }

    private static let scenarioSpecs: [String: UiStructureContractSpec] = [
        "hosted-menu-default": UiStructureContractSpec(
            scenario: "hosted-menu-default",
            featureId: "menubar-default-read-state",
            acceptanceCriteria: ["default-menu-shape-does-not-claim-live-state"],
            assertions: [
                sectionVisible("active-account-section", "Active Account"),
                sectionVisible("other-accounts-section", "Other Accounts"),
                sectionVisible("more-accounts-section", "More Accounts…"),
                sectionVisible("manage-accounts-section", "Manage Accounts"),
                sectionVisible("preferences-section", "Preferences"),
                topLevelOrder([
                    "active-account-section",
                    "other-accounts-section",
                    "more-accounts-section",
                    "manage-accounts-section",
                    "preferences-section"
                ])
            ],
            nonClaims: menuStructureNonClaims + [
                "Does not prove SwiftUI preview rendering.",
                "Does not prove live Codex account or app-server state."
            ]
        ),
        "menu-busy-status": UiStructureContractSpec(
            scenario: "menu-busy-status",
            featureId: "menubar-busy-status",
            acceptanceCriteria: ["busy-status-visible-and-conflicting-actions-disabled"],
            assertions: [
                nodeExists(
                    id: "busy-status-message-visible",
                    match: UiStructureMatchArtifact(
                        id: "status-message",
                        role: "status",
                        text: "Refreshing account data...",
                        visible: true
                    )
                ),
                nodeExists(
                    id: "add-account-visible-and-disabled",
                    match: UiStructureMatchArtifact(
                        id: "add-account",
                        role: "menu-item",
                        label: "Add Account…",
                        visible: true,
                        enabled: false
                    )
                ),
                UiStructureAssertionArtifact(
                    id: "add-account-action-disabled",
                    type: "action-available",
                    match: UiStructureMatchArtifact(id: "add-account"),
                    action: UiStructureActionMatchArtifact(
                        id: "selector:add-account",
                        label: "Add Account…",
                        enabled: false
                    )
                ),
                topLevelOrder([
                    "active-account-section",
                    "manage-accounts-section",
                    "preferences-section",
                    "status-message"
                ])
            ],
            nonClaims: menuStructureNonClaims + [
                "Does not prove workflow action dispatch or event-log ordering.",
                "Does not prove busy actions route through confirmation paths.",
                "Does not prove live Codex workflow state."
            ]
        ),
        "menu-empty-catalog": UiStructureContractSpec(
            scenario: "menu-empty-catalog",
            featureId: "account-catalog-empty-state",
            acceptanceCriteria: ["empty-catalog-guides-to-add-account"],
            assertions: menuEmptyCatalogAssertions,
            nonClaims: menuStructureNonClaims + [
                "Does not prove Add Account sign-in workflow behavior.",
                "Does not prove live Codex auth lookup or account switching."
            ]
        ),
        "menu-account-overflow": UiStructureContractSpec(
            scenario: "menu-account-overflow",
            featureId: "account-catalog-overflow",
            acceptanceCriteria: ["overflow-keeps-hidden-accounts-discoverable"],
            assertions: [
                sectionVisible("other-accounts-section", "Other Accounts"),
                sectionVisible("more-accounts-section", "More Accounts…"),
                nodeExists(
                    id: "saved-account-rows-present",
                    match: UiStructureMatchArtifact(semanticTag: "saved-account-row")
                ),
                topLevelOrder([
                    "active-account-section",
                    "other-accounts-section",
                    "more-accounts-section",
                    "manage-accounts-section",
                    "preferences-section"
                ])
            ],
            nonClaims: menuStructureNonClaims + [
                "Does not prove live Codex auth lookup.",
                "Does not prove account switching.",
                "Does not prove runtime menu opening or pointer interaction."
            ]
        ),
        "menu-unmatched-active-account": UiStructureContractSpec(
            scenario: "menu-unmatched-active-account",
            featureId: "active-account-truth",
            acceptanceCriteria: ["active-account-unmatched-does-not-lie"],
            assertions: [
                sectionVisible("active-account-section", "Active Account"),
                nodeExists(
                    id: "empty-active-account-row-visible",
                    match: UiStructureMatchArtifact(
                        id: "empty-active-account-row",
                        role: "text",
                        label: "No active saved account",
                        visible: true
                    )
                ),
                sectionVisible("other-accounts-section", "Other Accounts"),
                sectionVisible("more-accounts-section", "More Accounts…"),
                topLevelOrder([
                    "active-account-section",
                    "other-accounts-section",
                    "more-accounts-section",
                    "manage-accounts-section",
                    "preferences-section"
                ])
            ],
            nonClaims: menuStructureNonClaims + [
                "Does not prove live Codex auth lookup.",
                "Does not prove account switching."
            ]
        )
    ]

    private static let menuEmptyCatalogAssertions: [UiStructureAssertionArtifact] = [
        UiStructureAssertionArtifact(
            id: "active-account-section-visible",
            type: "node-exists",
            match: UiStructureMatchArtifact(
                id: "active-account-section",
                role: "section",
                label: "Active Account",
                visible: true
            )
        ),
        UiStructureAssertionArtifact(
            id: "empty-active-account-row-visible",
            type: "node-exists",
            match: UiStructureMatchArtifact(
                id: "empty-active-account-row",
                role: "text",
                label: "No active saved account",
                visible: true
            )
        ),
        UiStructureAssertionArtifact(
            id: "add-account-visible-and-enabled",
            type: "node-exists",
            match: UiStructureMatchArtifact(
                id: "add-account",
                role: "menu-item",
                label: "Add Account…",
                visible: true,
                enabled: true
        )
    ),
    UiStructureAssertionArtifact(
        id: "add-account-action-available",
        type: "action-available",
        match: UiStructureMatchArtifact(id: "add-account"),
        action: UiStructureActionMatchArtifact(
            id: "selector:add-account",
            label: "Add Account…",
            enabled: true
        )
    ),
        UiStructureAssertionArtifact(
            id: "no-saved-account-row",
            type: "node-absent",
            match: UiStructureMatchArtifact(semanticTag: "saved-account-row")
        ),
        UiStructureAssertionArtifact(
            id: "no-more-accounts-section",
            type: "node-absent",
            match: UiStructureMatchArtifact(id: "more-accounts-section")
        ),
    UiStructureAssertionArtifact(
        id: "no-switch-action",
        type: "action-absent",
        action: UiStructureActionMatchArtifact(id: "selector:switch-account")
    ),
    UiStructureAssertionArtifact(
        id: "no-remote-switch-action",
        type: "action-absent",
        action: UiStructureActionMatchArtifact(id: "selector:switch-account-on-host")
    ),
        UiStructureAssertionArtifact(
            id: "top-level-menu-order",
            type: "child-order",
            parent: UiStructureMatchArtifact(id: "menu-root"),
            orderedChildIds: [
                "active-account-section",
                "manage-accounts-section",
                "preferences-section"
            ]
        )
    ]

    private static let menuStructureNonClaims = [
        "Does not prove pixel rendering, typography, spacing, or screenshot visual fidelity.",
        "Does not prove native menu opening, native click routing, focus, or hittability.",
        "Does not prove the live macOS menu bar surface."
    ]

    private static func sectionVisible(
        _ id: String,
        _ label: String
    ) -> UiStructureAssertionArtifact {
        nodeExists(
            id: "\(id.replacingOccurrences(of: "-section", with: ""))-section-visible",
            match: UiStructureMatchArtifact(
                id: id,
                role: "section",
                label: label,
                visible: true
            )
        )
    }

    private static func nodeExists(
        id: String,
        match: UiStructureMatchArtifact
    ) -> UiStructureAssertionArtifact {
        UiStructureAssertionArtifact(
            id: id,
            type: "node-exists",
            match: match
        )
    }

    private static func topLevelOrder(_ ids: [String]) -> UiStructureAssertionArtifact {
        UiStructureAssertionArtifact(
            id: "top-level-menu-order",
            type: "child-order",
            parent: UiStructureMatchArtifact(id: "menu-root"),
            orderedChildIds: ids
        )
    }
}

private enum MenuBarStructureContractExporterError: Error {
    case unsupportedScenario(String)
}

private struct UiStructureContractSpec {
    let scenario: String
    let featureId: String
    let acceptanceCriteria: [String]
    let assertions: [UiStructureAssertionArtifact]
    let nonClaims: [String]
}
// Product-side payload structs for emitting Kite ui-structure-contract JSON.
// Kite owns validation semantics; CodexPill only maps menu state into the schema.
struct UiStructureContractArtifact: Codable, Equatable {
    let kind: String
    let schemaVersion: String
    let id: String
    let scenario: UiStructureScenarioArtifact
    let root: UiStructureNodeArtifact
    let assertions: [UiStructureAssertionArtifact]
    let nonClaims: [String]
}

struct UiStructureScenarioArtifact: Codable, Equatable {
    let id: String
    let featureId: String
    let acceptanceCriteria: [String]
    let targetSurface: String
    let proofType: String
}

struct UiStructureNodeArtifact: Codable, Equatable {
    let id: String
    let role: String
    let label: String?
    let text: String?
    let visible: Bool?
    let enabled: Bool?
    let selected: Bool?
    let semanticTags: [String]?
    let actions: [UiStructureActionArtifact]?
    let children: [UiStructureNodeArtifact]?

    init(
        id: String,
        role: String,
        label: String? = nil,
        text: String? = nil,
        visible: Bool? = nil,
        enabled: Bool? = nil,
        selected: Bool? = nil,
        semanticTags: [String]? = nil,
        actions: [UiStructureActionArtifact]? = nil,
        children: [UiStructureNodeArtifact]? = nil
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.text = text
        self.visible = visible
        self.enabled = enabled
        self.selected = selected
        self.semanticTags = semanticTags
        self.actions = actions
        self.children = children
    }
}

struct UiStructureActionArtifact: Codable, Equatable {
    let id: String
    let label: String?
    let enabled: Bool?

    init(id: String, label: String? = nil, enabled: Bool? = nil) {
        self.id = id
        self.label = label
        self.enabled = enabled
    }
}

struct UiStructureMatchArtifact: Codable, Equatable {
    let id: String?
    let role: String?
    let label: String?
    let text: String?
    let semanticTag: String?
    let visible: Bool?
    let enabled: Bool?
    let selected: Bool?

    init(
        id: String? = nil,
        role: String? = nil,
        label: String? = nil,
        text: String? = nil,
        semanticTag: String? = nil,
        visible: Bool? = nil,
        enabled: Bool? = nil,
        selected: Bool? = nil
    ) {
        self.id = id
        self.role = role
        self.label = label
        self.text = text
        self.semanticTag = semanticTag
        self.visible = visible
        self.enabled = enabled
        self.selected = selected
    }
}

struct UiStructureActionMatchArtifact: Codable, Equatable {
    let id: String?
    let label: String?
    let enabled: Bool?

    init(id: String? = nil, label: String? = nil, enabled: Bool? = nil) {
        self.id = id
        self.label = label
        self.enabled = enabled
    }
}

struct UiStructureAssertionArtifact: Codable, Equatable {
    let id: String
    let type: String
    let match: UiStructureMatchArtifact?
    let action: UiStructureActionMatchArtifact?
    let parent: UiStructureMatchArtifact?
    let orderedChildIds: [String]?

    init(
        id: String,
        type: String,
        match: UiStructureMatchArtifact? = nil,
        action: UiStructureActionMatchArtifact? = nil,
        parent: UiStructureMatchArtifact? = nil,
        orderedChildIds: [String]? = nil
    ) {
        self.id = id
        self.type = type
        self.match = match
        self.action = action
        self.parent = parent
        self.orderedChildIds = orderedChildIds
    }
}
