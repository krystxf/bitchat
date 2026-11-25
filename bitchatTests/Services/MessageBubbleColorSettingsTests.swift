import Foundation
import Testing
@testable import bitchat

struct MessageBubbleColorSettingsTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: UUID().uuidString)!
    }

    @Test func defaultsToBlueAndRoundTripsSelection() {
        let defaults = makeDefaults()
        #expect(MessageBubbleColorSettings.selected(in: defaults) == .blue)
        MessageBubbleColorSettings.set(.teal, in: defaults)
        #expect(MessageBubbleColorSettings.selected(in: defaults) == .teal)
    }

    @Test func unknownSelectionFallsBackToBlueAndResetRemovesChoice() {
        let defaults = makeDefaults()
        defaults.set("future-color", forKey: MessageBubbleColorSettings.key)
        #expect(MessageBubbleColorSettings.selected(in: defaults) == .blue)
        MessageBubbleColorSettings.set(.purple, in: defaults)
        MessageBubbleColorSettings.reset(in: defaults)
        #expect(MessageBubbleColorSettings.selected(in: defaults) == .blue)
    }

    @Test func everyPaletteColorMeetsWhiteTextContrast() {
        for color in MessageBubbleColor.allCases {
            #expect(color.whiteContrastRatio >= 4.5, "\(color.rawValue) contrast was \(color.whiteContrastRatio)")
        }
    }
}
