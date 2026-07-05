import Foundation

@MainActor
enum MenuBarStructureExporter {
    static func makeStructure(from snapshot: MenuBarValidationSnapshot) -> UiStructureNodeArtifact {
        UiStructureNodeArtifact(
            id: "menu-root",
            role: "menu",
            label: "CodexPill",
            visible: true,
            children: snapshot.sections.map { section in
                makeSectionNode(section, menuItems: snapshot.menuItems)
            }
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

        for item in items {
            if searchableTitle(for: item.title).contains(expected) || expected.contains(searchableTitle(for: item.title)) {
                return item
            }
            if let child = findMenuItem(for: title, in: item.children) {
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
    static func makeMenuEmptyCatalogContract(
        from snapshot: MenuBarValidationSnapshot
    ) throws -> UiStructureContractArtifact {
        return UiStructureContractArtifact(
            kind: "ui_structure_contract",
            schemaVersion: "kite.ui-structure-contract.v1",
            id: "codexpill-menu-empty-catalog-structure",
            scenario: UiStructureScenarioArtifact(
                id: "menu-empty-catalog",
                featureId: "account-catalog-empty-state",
                acceptanceCriteria: ["empty-catalog-guides-to-add-account"],
                targetSurface: "CodexPill hosted menubar projection",
                proofType: "ui-structure-contract"
            ),
            root: MenuBarStructureExporter.makeStructure(from: snapshot),
            assertions: menuEmptyCatalogAssertions,
            nonClaims: menuEmptyCatalogNonClaims
        )
    }

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

    private static let menuEmptyCatalogNonClaims = [
        "Does not prove pixel rendering, typography, spacing, or screenshot visual fidelity.",
        "Does not prove native menu opening, native click routing, focus, or hittability.",
        "Does not prove Add Account sign-in workflow behavior.",
        "Does not prove live Codex auth lookup, account switching, or live macOS menu bar behavior."
    ]
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
