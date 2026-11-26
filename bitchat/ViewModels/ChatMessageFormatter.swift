import BitFoundation
import Foundation
import SwiftUI

@MainActor
final class ChatMessageFormatter {
    typealias Patterns = MessageFormattingEngine.Patterns

    private unowned let viewModel: ChatViewModel
    private let meshPalette = MinimalDistancePalette(config: .mesh)
    private let nostrPalette = MinimalDistancePalette(config: .nostr)
    /// What the Nostr palette was last built from. Colors are looked up once
    /// per people-sheet row and per formatted geochat message, so the palette
    /// is rebuilt only when the roster's membership (or our own excluded
    /// key) changes rather than recomputing the roster on every lookup.
    private var nostrPaletteKey: NostrPaletteKey?

    private struct NostrPaletteKey: Equatable {
        // periphery:ignore - read only via the synthesized Equatable
        // conformance (the rebuild check), which the indexer cannot
        // attribute.
        let membershipRevision: UInt64
        // periphery:ignore - see `membershipRevision`.
        let excludedHex: String?
    }

    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }

    func formatMessageAsText(_ message: BitchatMessage, colorScheme: ColorScheme) -> AttributedString {
        let design = Font.Design.default
        let isSelf = isSelfMessage(message)

        let isDark = colorScheme == .dark
        let isVerifiedSender = !isSelf && isVerifiedSender(of: message)
        let cacheVariant = isVerifiedSender ? "-vf" : ""
        if let cachedText = message.getCachedFormattedText(isDark: isDark, isSelf: isSelf, variant: cacheVariant) {
            return cachedText
        }

        var result = AttributedString()
        let baseColor: Color = isSelf ? .orange : peerColor(for: message, isDark: isDark)

        if message.sender != "system" {
            let (baseName, suffix) = message.sender.splitSuffix()
            var senderStyle = AttributeContainer()
            senderStyle.foregroundColor = baseColor
            let fontWeight: Font.Weight = isSelf ? .bold : .medium
            senderStyle.font = .bitchatSystem(size: 14, weight: fontWeight, design: design)
            if let spid = message.senderPeerID,
               let url = URL(string: "bitchat://user/\(spid.toPercentEncoded())") {
                senderStyle.link = url
            }

            result.append(AttributedString("<@").mergingAttributes(senderStyle))
            result.append(AttributedString(baseName).mergingAttributes(senderStyle))
            if !suffix.isEmpty {
                var suffixStyle = senderStyle
                suffixStyle.foregroundColor = baseColor.opacity(0.6)
                result.append(AttributedString(suffix).mergingAttributes(suffixStyle))
            }
            // Private rows render a filled SF Symbol seal beside the time
            // (MessageMetaView); skip the in-string ✓ there so verified DMs
            // don't show two markers.
            if isVerifiedSender, !message.isPrivate {
                appendVerifiedSeal(to: &result, baseColor: baseColor, design: design)
            }
            result.append(AttributedString("> ").mergingAttributes(senderStyle))

            appendContent(
                of: message,
                to: &result,
                style: ContentStyle(
                    textFont: isSelf
                        ? .bitchatSystem(size: 14, weight: .bold, design: design)
                        : .bitchatSystem(size: 14, design: design),
                    emphasisFont: .bitchatSystem(size: 14, weight: isSelf ? .bold : .semibold, design: design),
                    textColor: baseColor,
                    linkColor: isSelf ? .orange : .blue,
                    mentionOfMeColor: .orange
                )
            )

            let timestamp = AttributedString(" [\(message.formattedTimestamp)]")
            var timestampStyle = AttributeContainer()
            timestampStyle.foregroundColor = Color.gray.opacity(0.7)
            timestampStyle.font = .bitchatSystem(size: 10, design: design)
            result.append(timestamp.mergingAttributes(timestampStyle))
        } else {
            var contentStyle = AttributeContainer()
            contentStyle.foregroundColor = Color.gray
            let content = AttributedString("* \(message.content) *")
            contentStyle.font = .bitchatSystem(size: 12, design: design).italic()
            result.append(content.mergingAttributes(contentStyle))

            let timestamp = AttributedString(" [\(message.formattedTimestamp)]")
            var timestampStyle = AttributeContainer()
            timestampStyle.foregroundColor = Color.gray.opacity(0.5)
            timestampStyle.font = .bitchatSystem(size: 10, design: design)
            result.append(timestamp.mergingAttributes(timestampStyle))
        }

        message.setCachedFormattedText(result, isDark: isDark, isSelf: isSelf, variant: cacheVariant)
        return result
    }

    /// Prefix of the header's formatted-text cache variants. No full-text
    /// variant starts with it, so the two caches can't collide.
    static let headerCacheNamespace = "hdr:"

    func formatMessageHeader(_ message: BitchatMessage, colorScheme: ColorScheme) -> AttributedString {
        let design = Font.Design.default
        let isSelf = isSelfMessage(message)

        let isDark = colorScheme == .dark
        let isVerifiedSender = !isSelf && isVerifiedSender(of: message)
        // Same key ingredients as the full-text cache, in a namespace of its
        // own so a header and a full text never answer each other's lookups.
        let cacheVariant = Self.headerCacheNamespace + (isVerifiedSender ? "-vf" : "")
        if let cachedHeader = message.getCachedFormattedText(isDark: isDark, isSelf: isSelf, variant: cacheVariant) {
            return cachedHeader
        }

        let baseColor: Color = isSelf ? .orange : peerColor(for: message, isDark: isDark)

        if message.sender == "system" {
            var style = AttributeContainer()
            style.foregroundColor = baseColor
            style.font = .bitchatSystem(size: 14, weight: .medium, design: design)
            let header = AttributedString(message.sender).mergingAttributes(style)
            message.setCachedFormattedText(header, isDark: isDark, isSelf: isSelf, variant: cacheVariant)
            return header
        }

        var result = AttributedString()
        let (baseName, suffix) = message.sender.splitSuffix()
        var senderStyle = AttributeContainer()
        senderStyle.foregroundColor = baseColor
        senderStyle.font = .bitchatSystem(size: 14, weight: isSelf ? .bold : .medium, design: design)
        if let spid = message.senderPeerID,
           let url = URL(string: "bitchat://user/\(spid.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spid.id)") {
            senderStyle.link = url
        }

        result.append(AttributedString("<@").mergingAttributes(senderStyle))
        result.append(AttributedString(baseName).mergingAttributes(senderStyle))
        if !suffix.isEmpty {
            var suffixStyle = senderStyle
            suffixStyle.foregroundColor = baseColor.opacity(0.6)
            result.append(AttributedString(suffix).mergingAttributes(suffixStyle))
        }
        if isVerifiedSender, !message.isPrivate {
            appendVerifiedSeal(to: &result, baseColor: baseColor, design: design)
        }
        result.append(AttributedString("> ").mergingAttributes(senderStyle))
        message.setCachedFormattedText(result, isDark: isDark, isSelf: isSelf, variant: cacheVariant)
        return result
    }

    /// Prefix of the bubble body's formatted-text cache variants. No other
    /// variant starts with it, so the caches can't collide.
    static let bodyCacheNamespace = "body:"

    /// Prefix of the sender name's formatted-text cache variants.
    static let senderNameCacheNamespace = "name:"

    /// The message text alone, styled to sit inside a chat bubble: no
    /// sender and no timestamp, which the bubble row shows around it.
    /// Mentions, links, hashtags and payment tokens are picked out as in
    /// the full text. `isSelf` is the side the row put the bubble on, so the
    /// text colors always match the bubble's fill: white on my accent
    /// bubbles, the primary color on everyone else's neutral ones.
    ///
    /// A body with no visible text (a message that is only payment tokens,
    /// which render as chips) comes back empty, so the row can skip the
    /// bubble.
    func formatMessageBody(_ message: BitchatMessage, isSelf: Bool, colorScheme: ColorScheme) -> AttributedString {
        let isDark = colorScheme == .dark
        if let cachedBody = message.getCachedFormattedText(isDark: isDark, isSelf: isSelf, variant: Self.bodyCacheNamespace) {
            return cachedBody
        }

        var result = AttributedString()
        appendContent(
            of: message,
            to: &result,
            style: ContentStyle(
                textFont: .body,
                emphasisFont: .body.weight(.semibold),
                textColor: isSelf ? .white : .primary,
                linkColor: isSelf ? .white : MessageBubbleStyle.incomingLink,
                mentionOfMeColor: isSelf ? .white : MessageBubbleStyle.incomingLink
            )
        )
        if String(result.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = AttributedString()
        }
        message.setCachedFormattedText(result, isDark: isDark, isSelf: isSelf, variant: Self.bodyCacheNamespace)
        return result
    }

    /// The sender's name for the label above someone else's bubble, with
    /// the verified mark on public rows, linked to the same `bitchat://user/`
    /// action as the name in the full text.
    ///
    /// It is in the secondary label color, as in Messages, not the sender's
    /// palette color: dark hues such as purple fall short of a readable
    /// contrast on the dark backdrop.
    ///
    /// A petname the user saved for the sender replaces the announced
    /// nickname (and its "#abcd" suffix), as it already does in DMs and the
    /// people list. It is part of the cache key, so renaming someone shows
    /// at once.
    func formatSenderName(_ message: BitchatMessage, colorScheme: ColorScheme) -> AttributedString {
        let isDark = colorScheme == .dark
        let isVerifiedSender = isVerifiedSender(of: message)
        let petname = message.senderPeerID.flatMap { viewModel.localPetname(for: $0) }
        let cacheVariant = Self.senderNameCacheNamespace
            + (petname.map { "pet:\($0)|" } ?? "")
            + (isVerifiedSender ? "-vf" : "")
        if let cachedName = message.getCachedFormattedText(isDark: isDark, isSelf: false, variant: cacheVariant) {
            return cachedName
        }

        let baseColor = Color.novaSecondaryText
        let (baseName, suffix) = petname.map { ($0, "") } ?? message.sender.splitSuffix()
        var nameStyle = AttributeContainer()
        nameStyle.foregroundColor = baseColor
        nameStyle.font = .caption
        if let spid = message.senderPeerID, let url = peerURL(for: spid) {
            nameStyle.link = url
        }

        var result = AttributedString(baseName).mergingAttributes(nameStyle)
        if !suffix.isEmpty {
            var suffixStyle = nameStyle
            suffixStyle.foregroundColor = baseColor.opacity(0.6)
            result.append(AttributedString(suffix).mergingAttributes(suffixStyle))
        }
        // Private rows show the filled seal beside the bubble instead.
        if isVerifiedSender, !message.isPrivate {
            appendVerifiedSeal(to: &result, baseColor: baseColor, design: .default)
        }
        message.setCachedFormattedText(result, isDark: isDark, isSelf: false, variant: cacheVariant)
        return result
    }

    /// Formats a message ahead of display into the variant its row shows:
    /// the bubble body. A system line shows its plain text, which needs no
    /// formatting.
    func prewarmRow(_ message: BitchatMessage, colorScheme: ColorScheme) {
        guard message.sender != "system" else { return }
        _ = formatMessageBody(message, isSelf: isSelfMessage(message), colorScheme: colorScheme)
    }

    /// Whether this device wrote the row: the one rule behind every
    /// formatted variant. It is `BitchatMessage.isOwn`, the rule
    /// `ConversationUIModel.isSentByCurrentUser` applies too, so a row is
    /// styled as mine exactly when the rest of the UI treats it as mine. A
    /// name alone never makes a row mine: a namesake must not render as me.
    func isSelfMessage(_ message: BitchatMessage) -> Bool {
        message.isOwn(
            myPeerID: viewModel.meshService.myPeerID,
            myGeoChatPeerID: myGeoChatPeerID()
        )
    }

    func senderColor(for message: BitchatMessage, isDark: Bool) -> Color {
        peerColor(for: message, isDark: isDark)
    }

    func peerURL(for peerID: PeerID) -> URL? {
        URL(string: "bitchat://user/\(peerID.toPercentEncoded())")
    }

    func colorForNostrPubkey(_ pubkeyHexLowercased: String, isDark: Bool) -> Color {
        getNostrPaletteColor(for: pubkeyHexLowercased.lowercased(), isDark: isDark)
    }

    func colorForMeshPeer(id peerID: PeerID, isDark: Bool) -> Color {
        getPeerPaletteColor(for: peerID, isDark: isDark)
    }
}

private extension ChatMessageFormatter {
    /// How the runs of a message's text are styled. The full text and the
    /// bubble body pick out the same tokens and differ only in these.
    struct ContentStyle {
        /// Plain text, hashtags, and the spacers left by payment tokens.
        let textFont: Font
        /// Mentions and links.
        let emphasisFont: Font
        let textColor: Color
        let linkColor: Color
        /// A mention of me.
        let mentionOfMeColor: Color
    }

    /// Appends the message's text with its mentions, hashtags and links
    /// picked out, and its payment tokens left as spacers (the row shows
    /// them as chips). Oversized content stays plain.
    func appendContent(of message: BitchatMessage, to result: inout AttributedString, style: ContentStyle) {
        let content = message.content
        let nsContent = content as NSString
        let nsLen = nsContent.length

        if content.isOversizedForRichFormatting() {
            var plainStyle = AttributeContainer()
            plainStyle.foregroundColor = style.textColor
            plainStyle.font = style.textFont
            result.append(AttributedString(content).mergingAttributes(plainStyle))
        } else {
            let hashtagRegex = Patterns.hashtag
            let mentionRegex = Patterns.mention
            let cashuRegex = Patterns.cashu
            let bolt11Regex = Patterns.bolt11
            let lnurlRegex = Patterns.lnurl
            let lightningSchemeRegex = Patterns.lightningScheme
            let detector = Patterns.linkDetector
            let hasMentionsHint = content.contains("@")
            let hasHashtagsHint = content.contains("#")
            let hasURLHint = content.contains("://") || content.contains("www.") || content.contains("http")
            let hasLightningHint = content.lowercased().contains("ln") || content.lowercased().contains("lightning:")
            let hasCashuHint = content.lowercased().contains("cashu")

            let hashtagMatches = hasHashtagsHint
                ? hashtagRegex.matches(in: content, options: [], range: NSRange(location: 0, length: nsLen))
                : []
            let mentionMatches = hasMentionsHint
                ? mentionRegex.matches(in: content, options: [], range: NSRange(location: 0, length: nsLen))
                : []
            let urlMatches = hasURLHint
                ? (detector?.matches(in: content, options: [], range: NSRange(location: 0, length: nsLen)) ?? [])
                : []
            let cashuMatches = hasCashuHint
                ? cashuRegex.matches(in: content, options: [], range: NSRange(location: 0, length: nsLen))
                : []
            let lightningMatches = hasLightningHint
                ? lightningSchemeRegex.matches(in: content, options: [], range: NSRange(location: 0, length: nsLen))
                : []
            let bolt11Matches = hasLightningHint
                ? bolt11Regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsLen))
                : []
            let lnurlMatches = hasLightningHint
                ? lnurlRegex.matches(in: content, options: [], range: NSRange(location: 0, length: nsLen))
                : []

            let mentionRanges = mentionMatches.map { $0.range(at: 0) }
            func overlapsMention(_ range: NSRange) -> Bool {
                for mentionRange in mentionRanges where NSIntersectionRange(range, mentionRange).length > 0 {
                    return true
                }
                return false
            }

            func attachedToMention(_ range: NSRange) -> Bool {
                if let swiftRange = Range(range, in: content), swiftRange.lowerBound > content.startIndex {
                    var index = content.index(before: swiftRange.lowerBound)
                    while true {
                        let character = content[index]
                        if character.isWhitespace || character.isNewline { break }
                        if character == "@" { return true }
                        if index == content.startIndex { break }
                        index = content.index(before: index)
                    }
                }
                return false
            }

            func isStandaloneHashtag(_ range: NSRange) -> Bool {
                guard let swiftRange = Range(range, in: content) else { return false }
                if swiftRange.lowerBound == content.startIndex { return true }
                let previous = content.index(before: swiftRange.lowerBound)
                return content[previous].isWhitespace || content[previous].isNewline
            }

            var allMatches: [(range: NSRange, type: String)] = []
            for match in hashtagMatches
            where !overlapsMention(match.range(at: 0))
                && !attachedToMention(match.range(at: 0))
                && isStandaloneHashtag(match.range(at: 0)) {
                allMatches.append((match.range(at: 0), "hashtag"))
            }
            for match in mentionMatches {
                allMatches.append((match.range(at: 0), "mention"))
            }
            for match in urlMatches where !overlapsMention(match.range) {
                allMatches.append((match.range, "url"))
            }
            for match in cashuMatches where !overlapsMention(match.range(at: 0)) {
                allMatches.append((match.range(at: 0), "cashu"))
            }
            for match in lightningMatches where !overlapsMention(match.range(at: 0)) {
                allMatches.append((match.range(at: 0), "lightning"))
            }

            let occupied = urlMatches.map(\.range) + lightningMatches.map { $0.range(at: 0) }
            func overlapsOccupied(_ range: NSRange) -> Bool {
                for occupiedRange in occupied where NSIntersectionRange(range, occupiedRange).length > 0 {
                    return true
                }
                return false
            }

            for match in bolt11Matches
            where !overlapsMention(match.range(at: 0)) && !overlapsOccupied(match.range(at: 0)) {
                allMatches.append((match.range(at: 0), "bolt11"))
            }
            for match in lnurlMatches
            where !overlapsMention(match.range(at: 0)) && !overlapsOccupied(match.range(at: 0)) {
                allMatches.append((match.range(at: 0), "lnurl"))
            }
            allMatches.sort { $0.range.location < $1.range.location }

            var lastEnd = content.startIndex
            let myNickname = viewModel.nickname.normalizedNickname
            let isMentioned = message.mentions?.contains { $0.normalizedNickname == myNickname } ?? false

            for (range, type) in allMatches {
                guard let swiftRange = Range(range, in: content) else { continue }

                if lastEnd < swiftRange.lowerBound {
                    let beforeText = String(content[lastEnd..<swiftRange.lowerBound])
                    if !beforeText.isEmpty {
                        var beforeStyle = AttributeContainer()
                        beforeStyle.foregroundColor = style.textColor
                        beforeStyle.font = style.textFont
                        if isMentioned {
                            beforeStyle.font = beforeStyle.font?.bold()
                        }
                        result.append(AttributedString(beforeText).mergingAttributes(beforeStyle))
                    }
                }

                let matchText = String(content[swiftRange])
                if type == "mention" {
                    let (mentionBase, mentionSuffix) = matchText.splitSuffix()
                    let mySuffix: String? = {
                        if case .location(let channel) = viewModel.activeChannel,
                           let identity = try? viewModel.idBridge.deriveIdentity(forGeohash: channel.geohash) {
                            return String(identity.publicKeyHex.suffix(4))
                        }
                        return String(viewModel.meshService.myPeerID.id.prefix(4))
                    }()
                    let isMentionToMe: Bool = {
                        if mentionBase == viewModel.nickname {
                            if let mySuffix, !mentionSuffix.isEmpty {
                                return mentionSuffix == "#\(mySuffix)"
                            }
                            return mentionSuffix.isEmpty
                        }
                        return false
                    }()

                    var mentionStyle = AttributeContainer()
                    mentionStyle.font = style.emphasisFont
                    let mentionColor: Color = isMentionToMe ? style.mentionOfMeColor : style.textColor
                    mentionStyle.foregroundColor = mentionColor
                    let at = "@"
                    result.append(AttributedString("\(at)").mergingAttributes(mentionStyle))
                    result.append(AttributedString(mentionBase).mergingAttributes(mentionStyle))
                    if !mentionSuffix.isEmpty {
                        var lightStyle = mentionStyle
                        lightStyle.foregroundColor = mentionColor.opacity(0.6)
                        result.append(AttributedString(mentionSuffix).mergingAttributes(lightStyle))
                    }
                } else if type == "hashtag" {
                    let token = String(matchText.dropFirst()).lowercased()
                    let allowed = Set("0123456789bcdefghjkmnpqrstuvwxyz")
                    let isGeohash = (2...12).contains(token.count) && token.allSatisfy { allowed.contains($0) }
                    let attachedToMentionToken: Bool = {
                        if swiftRange.lowerBound > content.startIndex {
                            var index = content.index(before: swiftRange.lowerBound)
                            while true {
                                let character = content[index]
                                if character.isWhitespace || character.isNewline { break }
                                if character == "@" { return true }
                                if index == content.startIndex { break }
                                index = content.index(before: index)
                            }
                        }
                        return false
                    }()
                    let standalone: Bool = {
                        if swiftRange.lowerBound == content.startIndex { return true }
                        let previous = content.index(before: swiftRange.lowerBound)
                        return content[previous].isWhitespace || content[previous].isNewline
                    }()

                    var tagStyle = AttributeContainer()
                    tagStyle.font = style.textFont
                    tagStyle.foregroundColor = style.textColor
                    if isGeohash && !attachedToMentionToken && standalone,
                       let url = URL(string: "bitchat://geohash/\(token)") {
                        tagStyle.link = url
                        tagStyle.underlineStyle = .single
                    }
                    result.append(AttributedString(matchText).mergingAttributes(tagStyle))
                } else if type == "cashu" || type == "lightning" || type == "bolt11" || type == "lnurl" {
                    var spacer = AttributeContainer()
                    spacer.foregroundColor = style.textColor
                    spacer.font = style.textFont
                    result.append(AttributedString(" ").mergingAttributes(spacer))
                } else {
                    var matchStyle = AttributeContainer()
                    matchStyle.font = style.emphasisFont
                    if type == "url" {
                        matchStyle.foregroundColor = style.linkColor
                        matchStyle.underlineStyle = .single
                        if let url = URL(string: matchText) {
                            matchStyle.link = url
                        }
                    }
                    result.append(AttributedString(matchText).mergingAttributes(matchStyle))
                }

                if lastEnd < swiftRange.upperBound {
                    lastEnd = swiftRange.upperBound
                }
            }

            if lastEnd < content.endIndex {
                let remainingText = String(content[lastEnd...])
                var remainingStyle = AttributeContainer()
                remainingStyle.foregroundColor = style.textColor
                remainingStyle.font = style.textFont
                if isMentioned {
                    remainingStyle.font = remainingStyle.font?.bold()
                }
                result.append(AttributedString(remainingText).mergingAttributes(remainingStyle))
            }
        }
    }

    /// My geochat sender ID in the location channel on screen (nil on
    /// #mesh), from the identity slot the view model caches.
    func myGeoChatPeerID() -> PeerID? {
        guard case .location(let channel) = viewModel.activeChannel,
              let identity = viewModel.geohashIdentity(for: channel.geohash)
        else { return nil }
        return PeerID(nostr: identity.publicKeyHex)
    }

    /// Whether the message sender has a fingerprint the user has verified.
    /// Used for the in-chat seal next to `<@name>` so verification is visible
    /// without opening the fingerprint sheet (#1439).
    func isVerifiedSender(of message: BitchatMessage) -> Bool {
        guard let peerID = message.senderPeerID,
              let fingerprint = viewModel.getFingerprint(for: peerID) else {
            return false
        }
        return viewModel.peerIdentityStore.isVerified(fingerprint)
    }

    func appendVerifiedSeal(
        to result: inout AttributedString,
        baseColor: Color,
        design: Font.Design
    ) {
        var sealStyle = AttributeContainer()
        // Match the peer-list verified seal: filled checkmark in the sender tint.
        sealStyle.foregroundColor = baseColor
        sealStyle.font = .bitchatSystem(size: 11, weight: .semibold, design: design)
        result.append(AttributedString(" ✓").mergingAttributes(sealStyle))
    }

    func peerColor(for message: BitchatMessage, isDark: Bool) -> Color {
        if let spid = message.senderPeerID {
            if spid.isGeoChat || spid.isGeoDM {
                let full = viewModel.nostrKeyMapping[spid]?.lowercased() ?? spid.bare.lowercased()
                return getNostrPaletteColor(for: full, isDark: isDark)
            } else if spid.id.count == 16 {
                return getPeerPaletteColor(for: spid, isDark: isDark)
            } else {
                return getPeerPaletteColor(for: PeerID(str: spid.id.lowercased()), isDark: isDark)
            }
        }
        return Color(peerSeed: message.sender.lowercased(), isDark: isDark)
    }

    func meshSeed(for peerID: PeerID) -> String {
        if let full = viewModel.cachedStablePeerID(for: peerID)?.id.lowercased() {
            return "noise:" + full
        }
        return peerID.id.lowercased()
    }

    func getPeerPaletteColor(for peerID: PeerID, isDark: Bool) -> Color {
        if peerID == viewModel.meshService.myPeerID {
            return .orange
        }

        meshPalette.ensurePalette(for: currentMeshPaletteSeeds())
        if let color = meshPalette.color(for: peerID.id, isDark: isDark) {
            return color
        }
        return Color(peerSeed: meshSeed(for: peerID), isDark: isDark)
    }

    func currentMeshPaletteSeeds() -> [String: String] {
        let myID = viewModel.meshService.myPeerID
        var seeds: [String: String] = [:]
        for peer in viewModel.allPeers where peer.peerID != myID {
            seeds[peer.peerID.id] = meshSeed(for: peer.peerID)
        }
        return seeds
    }

    func getNostrPaletteColor(for pubkeyHexLowercased: String, isDark: Bool) -> Color {
        let myHex = currentGeohashIdentityHex()
        if let myHex, pubkeyHexLowercased == myHex {
            return .orange
        }

        ensureNostrPalette(excluding: myHex)
        if let color = nostrPalette.color(for: pubkeyHexLowercased, isDark: isDark) {
            return color
        }
        return Color(peerSeed: "nostr:" + pubkeyHexLowercased, isDark: isDark)
    }

    /// Seeds the palette from the tracker's published roster, and only when
    /// its membership changed. Rebuilding it from a fresh roster scan per
    /// lookup made every people-sheet render O(N²) in the participant count.
    func ensureNostrPalette(excluding myHex: String?) {
        let tracker = viewModel.participantTracker
        let key = NostrPaletteKey(
            membershipRevision: tracker.visibleMembershipRevision,
            excludedHex: myHex
        )
        guard key != nostrPaletteKey else { return }
        nostrPaletteKey = key

        var seeds: [String: String] = [:]
        let excluded = myHex ?? ""
        for person in tracker.visiblePeople where person.id != excluded {
            seeds[person.id] = "nostr:" + person.id
        }
        nostrPalette.ensurePalette(for: seeds)
    }

    func currentGeohashIdentityHex() -> String? {
        if case .location(let channel) = viewModel.activeChannel,
           let identity = try? viewModel.idBridge.deriveIdentity(forGeohash: channel.geohash) {
            return identity.publicKeyHex.lowercased()
        }
        return nil
    }
}
