import SwiftUI

struct PanelValueBox: View {
    let value: String
    var font: Font = .system(size: 24, weight: .semibold, design: .monospaced)
    var height: CGFloat = 64
    var textColor: Color = .primary
    var allowsTextSelection = true

    var body: some View {
        if allowsTextSelection {
            content
                .textSelection(.enabled)
        } else {
            content
                .textSelection(.disabled)
        }
    }

    private var content: some View {
        Text(value)
            .font(font)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            )
    }
}
