//
// ChatBanner.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI

/// A notice that floats over the top of a conversation, under the title
/// bar: a symbol, one or two lines of text, and a chevron when a tap opens
/// something. It is a Liquid Glass card inset from the screen's edges, so
/// it reads as chrome over the messages, as the composer does at the
/// bottom.
struct ChatBanner<Content: View>: View {
    let systemImage: String
    var symbolColor: Color = .secondary
    var showsChevron = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: ChatBannerMetrics.minHeight)
        .glassSurface(in: ChatBannerMetrics.shape)
        .contentShape(ChatBannerMetrics.shape)
        .padding(.horizontal, ChatBannerMetrics.horizontalInset)
        .padding(.top, ChatBannerMetrics.spacing)
    }
}

enum ChatBannerMetrics {
    static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    /// Lines up with the message rows' inset.
    static let horizontalInset: CGFloat = 12
    static let spacing: CGFloat = 8
    static let minHeight: CGFloat = 44
}
