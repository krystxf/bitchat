//
// MessageBubbleColorSettings.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
//

import Foundation
import SwiftUI

enum MessageBubbleColor: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, green, teal, graphite, indigo, gold

    var id: String { rawValue }

    /// Dark saturated fills keep white message text readable in both color schemes.
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .blue: (0.00, 0.38, 0.78)
        case .purple: (0.39, 0.20, 0.70)
        case .pink: (0.72, 0.09, 0.32)
        case .red: (0.72, 0.12, 0.12)
        case .orange: (0.65, 0.25, 0.00)
        case .green: (0.09, 0.43, 0.20)
        case .teal: (0.00, 0.40, 0.36)
        case .graphite: (0.29, 0.33, 0.39)
        case .indigo: (0.25, 0.32, 0.71)
        case .gold: (0.51, 0.36, 0.00)
        }
    }

    var color: Color {
        let value = rgb
        return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: 1)
    }

    /// WCAG 2.1 contrast ratio against white.
    var whiteContrastRatio: Double {
        let value = rgb
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(value.red) + 0.7152 * linear(value.green) + 0.0722 * linear(value.blue)
        return 1.05 / (luminance + 0.05)
    }
}

enum MessageBubbleColorSettings {
    static let key = "appearance.messageBubbleColor"

    static var selected: MessageBubbleColor {
        get { selected(in: .standard) }
        set { set(newValue, in: .standard) }
    }

    static func selected(in defaults: UserDefaults) -> MessageBubbleColor {
        guard let rawValue = defaults.string(forKey: key),
              let value = MessageBubbleColor(rawValue: rawValue) else { return .blue }
        return value
    }

    static func set(_ color: MessageBubbleColor, in defaults: UserDefaults) {
        defaults.set(color.rawValue, forKey: key)
    }

    static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
