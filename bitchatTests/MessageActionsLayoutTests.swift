//
// MessageActionsLayoutTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import SwiftUI
import Testing
@testable import bitchat

struct MessageActionsLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let safeArea = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
    private let bar = CGSize(width: 330, height: 56)
    private let card = CGSize(width: 252, height: 260)

    private func layout(_ message: CGRect, isSelf: Bool, bar: CGSize? = nil) -> MessageActionsLayout {
        MessageActionsLayout(screen: screen, safeArea: safeArea, messageFrame: message, isSelf: isSelf, barSize: bar ?? self.bar, cardSize: card)
    }

    private func isOnScreen(_ rect: CGRect) -> Bool {
        rect.minY >= safeArea.top && rect.maxY <= screen.height - safeArea.bottom
            && rect.minX >= 0 && rect.maxX <= screen.width
    }

    @Test func aMessageWithRoomStaysInPlaceWithTheBarAboveAndTheCardBelow() {
        let message = CGRect(x: 12, y: 300, width: 220, height: 44)
        let result = layout(message, isSelf: false)
        #expect(result.message == message)
        #expect(result.bar.maxY + MessageActionsLayout.spacing == message.minY)
        #expect(result.card.minY == message.maxY + MessageActionsLayout.spacing)
        // Lined up with the message's side: leading for theirs.
        #expect(result.bar.minX == message.minX)
        #expect(result.card.minX == message.minX)
        #expect(!result.isMessageClipped)
    }

    @Test func myMessageLinesUpOnTheTrailingSide() {
        let message = CGRect(x: 160, y: 300, width: 218, height: 44)
        let result = layout(message, isSelf: true)
        #expect(result.bar.maxX == message.maxX)
        #expect(result.card.maxX == message.maxX)
    }

    @Test func nearTheTopTheStackSlidesDownToKeepTheBarOnScreen() {
        let message = CGRect(x: 12, y: 70, width: 220, height: 44)
        let result = layout(message, isSelf: false)
        #expect(isOnScreen(result.bar) && isOnScreen(result.message) && isOnScreen(result.card))
        #expect(result.message.minY > message.minY)
    }

    @Test func nearTheBottomTheStackSlidesUpToKeepTheCardOnScreen() {
        let message = CGRect(x: 12, y: 740, width: 220, height: 44)
        let result = layout(message, isSelf: false)
        #expect(isOnScreen(result.bar) && isOnScreen(result.message) && isOnScreen(result.card))
        #expect(result.message.minY < message.minY)
    }

    @Test func aVeryTallMessageIsCutSoTheBarAndCardStillFit() {
        let message = CGRect(x: 12, y: 40, width: 280, height: 1_400)
        let result = layout(message, isSelf: false)
        #expect(result.isMessageClipped)
        #expect(result.message.height < message.height)
        #expect(isOnScreen(result.bar) && isOnScreen(result.message) && isOnScreen(result.card))
    }

    @Test func withoutTheBarTheMessageNeedsNoRoomAboveIt() {
        let message = CGRect(x: 12, y: 300, width: 220, height: 44)
        let result = layout(message, isSelf: false, bar: .zero)
        #expect(result.message == message)
        #expect(result.card.minY == message.maxY + MessageActionsLayout.spacing)
    }

    @Test func aWideBarStaysWithinTheScreenEdges() {
        let message = CGRect(x: 330, y: 300, width: 48, height: 44)
        let result = layout(message, isSelf: false)
        #expect(result.bar.maxX <= screen.width - MessageActionsLayout.margin)
        #expect(result.card.maxX <= screen.width - MessageActionsLayout.margin)
    }
}
