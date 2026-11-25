//
// GlassButtonStyle.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

extension View {
    /// Native button chrome: Liquid Glass on OS 26+, bordered below.
    /// `prominent` gives the tinted variant for the primary action.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            borderedButtonStyle(prominent: prominent)
        }
        #else
        borderedButtonStyle(prominent: prominent)
        #endif
    }

    /// Circular button outline for icon-only buttons. iOS 16 / macOS 13 have
    /// no circle shape and keep the default outline.
    @ViewBuilder
    func circularButtonShape() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            buttonBorderShape(.circle)
        } else {
            self
        }
    }

    @ViewBuilder
    private func borderedButtonStyle(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
