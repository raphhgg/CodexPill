import AppKit
import SwiftUI
import Testing

@testable import CodexPill

@MainActor
struct MenuBarHostedDebugRendererTests {
    @Test
    func hostedDebugRendererWritesNonEmptyPNG() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarHostedDebugRendererTests-\(UUID().uuidString)", isDirectory: true)
        let screenshotURL = temporaryDirectory.appendingPathComponent("hosted-menu-default.png")
        let now = Date(timeIntervalSince1970: 1_744_195_200)
        let state = MenuBarValidationScenarioFixtures.makeState(
            for: "hosted-menu-default",
            now: now
        )

        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        try MenuBarHostedDebugRendererTestSupport.renderPNG(
            MenuBarHostedDebugRenderer.makeView(state: state, now: now),
            to: screenshotURL
        )

        let data = try Data(contentsOf: screenshotURL)
        #expect(data.count > 0)
    }
}

@MainActor
enum MenuBarHostedDebugRendererTestSupport {
    static func renderPNG<V: View>(_ view: V, to url: URL) throws {
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize
        let frame = NSRect(origin: .zero, size: NSSize(width: max(360, size.width), height: max(1, size.height)))
        hostingView.frame = frame
        hostingView.layoutSubtreeIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: frame) else {
            throw HostedDebugRendererError.failedToCreateBitmap
        }

        hostingView.cacheDisplay(in: frame, to: representation)

        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            throw HostedDebugRendererError.failedToEncodePNG
        }

        try pngData.write(to: url, options: .atomic)
    }
}

private enum HostedDebugRendererError: Error {
    case failedToCreateBitmap
    case failedToEncodePNG
}
