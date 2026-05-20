import AppKit
import SwiftUI

@main
struct TokenUsagePrototypeScreenshotRenderer {
    static func main() throws {
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/verification/RGR-360-token-usage")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for card in TokenUsagePrototype.fixtureCards {
            let view = TokenUsagePrototypeMenuScreenshot(card: card)
                .frame(width: 372)
                .background(Color(nsColor: .windowBackgroundColor))
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: 372, height: 214)
            hostingView.layoutSubtreeIfNeeded()

            let targetSize = hostingView.fittingSize
            hostingView.frame = NSRect(x: 0, y: 0, width: 372, height: targetSize.height)
            hostingView.layoutSubtreeIfNeeded()

            guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
                throw RendererError.bitmapUnavailable
            }
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw RendererError.pngEncodingFailed
            }

            let filename = "token-usage-\(card.variant.rawValue).png"
            try pngData.write(to: outputDirectory.appendingPathComponent(filename))
        }
    }
}

private enum RendererError: Error {
    case bitmapUnavailable
    case pngEncodingFailed
}

private struct TokenUsagePrototypeMenuScreenshot: View {
    let card: TokenUsagePrototypeCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Active Account")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Personal")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("Pro")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                Text("This Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 9)

            Divider()
                .padding(.horizontal, 14)
                .opacity(0.55)

            TokenUsagePrototypeMenuContent(card: card)

            Divider()
                .padding(.horizontal, 14)
                .opacity(0.55)

            Text("Other Accounts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
    }
}
