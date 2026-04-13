struct StatusItemTitleVisibilityPolicy {
    let displayMode: StatusBarDisplayMode
    let isStatusItemHovered: Bool
    let isMenuOpen: Bool
    let keepsStatusTitleWhileMenuOpen: Bool

    var shouldShowTitle: Bool {
        switch displayMode {
        case .iconOnly:
            false
        case .iconAndText:
            true
        case .textOnHover:
            isStatusItemHovered || (isMenuOpen && keepsStatusTitleWhileMenuOpen)
        }
    }
}
