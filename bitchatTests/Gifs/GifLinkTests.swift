//
// GifLinkTests.swift
// bitchatTests
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import CoreGraphics
import Foundation
import Testing
@testable import bitchat

@Suite("GIF links")
struct GifLinkTests {
    private func parse(_ string: String) -> GifLink? {
        URL(string: string).flatMap(GifLinkParser.parse)
    }

    // MARK: Giphy

    @Test(arguments: [
        ("https://giphy.com/gifs/the-office-michael-scott-3o7btPCcdNniyf0ArS", "3o7btPCcdNniyf0ArS"),
        ("https://giphy.com/gifs/3o7btPCcdNniyf0ArS", "3o7btPCcdNniyf0ArS"),
        ("https://www.giphy.com/gifs/funny-l0MYt5jPR6QX5pnqM", "l0MYt5jPR6QX5pnqM"),
        ("https://giphy.com/gifs/cat-3o7btPCcdNniyf0ArS/fullscreen", "3o7btPCcdNniyf0ArS"),
        ("https://giphy.com/gifs/cat-3o7btPCcdNniyf0ArS?utm_source=iOS", "3o7btPCcdNniyf0ArS"),
        ("https://giphy.com/embed/3o7btPCcdNniyf0ArS", "3o7btPCcdNniyf0ArS"),
        ("https://GIPHY.com/gifs/3o7btPCcdNniyf0ArS", "3o7btPCcdNniyf0ArS")
    ])
    func giphyPageLinksNameTheID(link: String, id: String) {
        #expect(parse(link)?.source == .giphy(id: id, isSticker: false))
        #expect(parse(link)?.provider == .giphy)
    }

    @Test func giphyStickerLinksAreStickers() {
        let link = parse("https://giphy.com/stickers/wave-hello-l41lUJ1YoZB1lHVPG")
        #expect(link?.source == .giphy(id: "l41lUJ1YoZB1lHVPG", isSticker: true))
        #expect(link?.cacheKey == "giphy-sticker:l41lUJ1YoZB1lHVPG")
    }

    @Test(arguments: [
        "https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.gif",
        "https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.mp4",
        "https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.webp",
        "https://media0.giphy.com/media/3o7btPCcdNniyf0ArS/200w.gif",
        "https://media4.giphy.com/media/v1.Y2lkPTc5MGI3NjExZmY/3o7btPCcdNniyf0ArS/giphy.gif?cid=1&rid=giphy.gif",
        "https://i.giphy.com/3o7btPCcdNniyf0ArS.gif",
        "https://i.giphy.com/3o7btPCcdNniyf0ArS.mp4",
        "https://i.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.webp"
    ])
    func giphyMediaLinksNameTheID(link: String) {
        #expect(parse(link)?.source == .giphy(id: "3o7btPCcdNniyf0ArS", isSticker: false))
    }

    @Test func linksToOneGiphyGifShareACacheKey() {
        let page = parse("https://giphy.com/gifs/office-3o7btPCcdNniyf0ArS")
        let media = parse("https://media2.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.gif")
        #expect(page?.cacheKey == "giphy:3o7btPCcdNniyf0ArS")
        #expect(page?.cacheKey == media?.cacheKey)
    }

    @Test(arguments: ["https://gph.is/2QRsryK", "https://gph.is/g/E00kL5p"])
    func giphyShortLinksNeedARedirect(link: String) {
        #expect(parse(link)?.source == .giphyShortLink)
        #expect(parse(link)?.provider == .giphy)
    }

    // MARK: Tenor

    @Test(arguments: [
        "https://tenor.com/view/brick-gif-16072518840379414901",
        "https://www.tenor.com/view/brick-gif-16072518840379414901",
        "https://tenor.com/en-GB/view/brick-gif-16072518840379414901",
        "https://tenor.com/de/view/brick-gif-16072518840379414901",
        "https://tenor.com/zh-CN/view/brick-gif-16072518840379414901",
        "https://tenor.com/fil/view/brick-gif-16072518840379414901"
    ])
    func tenorPageLinksNameTheID(link: String) {
        #expect(parse(link)?.source == .tenorPage(id: "16072518840379414901"))
        #expect(parse(link)?.cacheKey == "tenor:16072518840379414901")
        #expect(parse(link)?.provider == .tenor)
    }

    @Test(arguments: ["https://tenor.com/bEb8s.gif", "https://tenor.com/beb8s.gif"])
    func tenorShortLinksNeedARedirect(link: String) {
        #expect(parse(link)?.source == .tenorShortLink)
    }

    @Test(arguments: [
        "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4",
        "https://media.tenor.com/3w0Our6WmXUAAAAC/brick.gif",
        "https://media1.tenor.com/m/3w0Our6WmXUAAAAC/brick.gif",
        "https://c.tenor.com/3w0Our6WmXUAAAAC/brick.gif",
        "https://media.tenor.com/3w0Our6WmXUAAAPs/brick.webm"
    ])
    func tenorMediaLinksAreMedia(link: String) {
        #expect(parse(link)?.source == .tenorMedia)
    }

    // MARK: nostr.build

    @Test(arguments: [
        ("https://image.nostr.build/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif", GifMediaFormat.gif),
        ("https://image.nostr.build/thumb/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif", .gif),
        ("https://i.nostr.build/AbCd1234.webp", .webp),
        ("https://nostr.build/i/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif", .gif)
    ])
    func nostrBuildFilesAreUsedAsTheyAre(link: String, format: GifMediaFormat) {
        let parsed = parse(link)
        #expect(parsed?.source == .nostrBuildMedia(format))
        #expect(parsed?.provider == .nostrBuild)
        #expect(parsed?.provider.displayHost == "nostr.build")
        #expect(parsed?.cacheKey == "url:\(link)")
    }

    @Test(arguments: [
        "http://image.nostr.build/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif",
        "https://video.nostr.build/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.mp4",
        "https://image.nostr.build/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.mp4",
        "https://image.nostr.build/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.png",
        "https://image.nostr.build.evil.example/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif",
        "https://image.nostr.build/a/b/c/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif",
        "https://image.nostr.build/x.gif",
        "https://image.nostr.build/"
    ])
    func otherNostrBuildLinksAreNotGifs(link: String) {
        #expect(parse(link) == nil)
    }

    @Test func nostrBuildLinksInMessagesAreDetected() {
        let content = GifMessageDetector.detect(in: "https://image.nostr.build/0fe0c6b6c16262c07f7ff487a309bc070bf6edee91163e429b50b83002028afd.gif")
        #expect(content?.isLinkOnly == true)
        #expect(content?.link.provider == .nostrBuild)
    }

    // MARK: Rejected

    @Test(arguments: [
        // Not HTTPS.
        "http://giphy.com/gifs/3o7btPCcdNniyf0ArS",
        "http://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4",
        // Hosts off the allowlist, including look-alikes.
        "https://giphy.com.evil.example/gifs/3o7btPCcdNniyf0ArS",
        "https://evilgiphy.com/gifs/3o7btPCcdNniyf0ArS",
        "https://media.giphy.com.evil.example/media/3o7btPCcdNniyf0ArS/giphy.gif",
        "https://mediax.tenor.com/3w0Our6WmXUAAAPo/brick.mp4",
        "https://media12.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.gif",
        "https://tenor.co/view/brick-gif-16072518840379414901",
        // Credentials and odd ports.
        "https://user:pass@giphy.com/gifs/3o7btPCcdNniyf0ArS",
        "https://giphy.com:8443/gifs/3o7btPCcdNniyf0ArS",
        // Pages that are not one GIF.
        "https://giphy.com/",
        "https://giphy.com/search/cats",
        "https://giphy.com/gifs/happy-birthday",
        "https://giphy.com/clips/funny-3o7btPCcdNniyf0ArS",
        "https://tenor.com/",
        "https://tenor.com/search/cat-gifs",
        "https://tenor.com/view/no-id-here",
        "https://tenor.com/a/b/view/brick-gif-16072518840379414901",
        "https://tenor.com/bEb8s.png",
        "https://gph.is/",
        "https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.png",
        "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.png"
    ])
    func otherLinksAreNotGifs(link: String) {
        #expect(parse(link) == nil)
    }

    // MARK: Host policy

    @Test func redirectsMustStayOnTheAllowlist() throws {
        let base = try #require(URL(string: "https://tenor.com/bEb8s.gif"))
        #expect(GifHostPolicy.redirectTarget(location: "https://tenor.com/view/a-gif-123456", from: base) != nil)
        #expect(GifHostPolicy.redirectTarget(location: "/view/a-gif-123456", from: base)?.absoluteString
            == "https://tenor.com/view/a-gif-123456")
        #expect(GifHostPolicy.redirectTarget(location: "http://tenor.com/view/a-gif-123456", from: base) == nil)
        #expect(GifHostPolicy.redirectTarget(location: "https://example.com/a.gif", from: base) == nil)
        #expect(GifHostPolicy.redirectTarget(location: "//example.com/a.gif", from: base) == nil)
    }

    // MARK: Message detection

    @Test func aLinkAloneIsLinkOnly() {
        let content = GifMessageDetector.detect(in: "  https://giphy.com/gifs/3o7btPCcdNniyf0ArS \n")
        #expect(content?.isLinkOnly == true)
        #expect(content?.link.source == .giphy(id: "3o7btPCcdNniyf0ArS", isSticker: false))
    }

    @Test func aLinkWithTextIsNotLinkOnly() {
        let content = GifMessageDetector.detect(in: "lol (https://tenor.com/view/brick-gif-16072518840379414901).")
        #expect(content?.isLinkOnly == false)
        #expect(content?.link.source == .tenorPage(id: "16072518840379414901"))
    }

    @Test func theFirstGifLinkWins() {
        let content = GifMessageDetector.detect(in: """
        https://example.com/x https://tenor.com/bEb8s.gif https://giphy.com/gifs/3o7btPCcdNniyf0ArS
        """)
        #expect(content?.link.source == .tenorShortLink)
    }

    @Test(arguments: [
        "hello",
        "giphy.com/gifs/3o7btPCcdNniyf0ArS",
        "http://giphy.com/gifs/3o7btPCcdNniyf0ArS",
        "I love tenor.com",
        "https://example.com/giphy.com/gifs/3o7btPCcdNniyf0ArS"
    ])
    func textWithoutAGifLinkHasNoGif(text: String) {
        #expect(GifMessageDetector.detect(in: text) == nil)
    }

    @Test func oversizedMessagesAreNotScanned() {
        let text = "https://giphy.com/gifs/3o7btPCcdNniyf0ArS " + String(repeating: "a", count: GifMessageDetector.maxScannedLength)
        #expect(GifMessageDetector.detect(in: text) == nil)
    }

    @Test func cachedDetectionMatchesDetection() {
        let text = "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4"
        #expect(GifMessageDetector.content(in: text) == GifMessageDetector.detect(in: text))
        #expect(GifMessageDetector.content(in: text)?.isLinkOnly == true)
    }
}

@Suite("GIF media sources")
struct GifMediaSourceTests {
    @Test func giphyPrefersMP4ThenGIF() {
        let candidates = GiphyMedia.candidates(id: "3o7btPCcdNniyf0ArS", isSticker: false)
        #expect(candidates.map(\.url.absoluteString) == [
            "https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.mp4",
            "https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.gif"
        ])
        #expect(candidates.map(\.format) == [.mp4, .gif])
    }

    @Test func giphyStickersKeepTransparency() {
        let candidates = GiphyMedia.candidates(id: "l41lUJ1YoZB1lHVPG", isSticker: true)
        #expect(candidates.map(\.format) == [.webp, .gif])
    }

    @Test func tenorGifLinksTryTheMP4Rendition() throws {
        let url = try #require(URL(string: "https://media1.tenor.com/m/3w0Our6WmXUAAAAC/brick.gif"))
        let candidates = TenorMedia.candidates(forMediaLink: url)
        #expect(candidates.map(\.url.absoluteString) == [
            "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4",
            "https://media1.tenor.com/m/3w0Our6WmXUAAAAC/brick.gif"
        ])
        #expect(candidates.map(\.format) == [.mp4, .gif])
    }

    @Test func tenorMP4LinksAreUsedAsIs() throws {
        let url = try #require(URL(string: "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4"))
        #expect(TenorMedia.candidates(forMediaLink: url) == [GifMediaCandidate(url: url, format: .mp4)])
    }

    @Test func tenorWebMLinksOnlyNameTheGif() throws {
        let url = try #require(URL(string: "https://media.tenor.com/3w0Our6WmXUAAAPs/brick.webm"))
        #expect(TenorMedia.candidates(forMediaLink: url).map(\.format) == [.mp4])
    }

    @Test func sniffingReadsTheMagicBytes() {
        #expect(GifMediaFormat.sniff(Data("GIF89a\u{0}\u{0}\u{0}\u{0}\u{0}\u{0}".utf8)) == .gif)
        #expect(GifMediaFormat.sniff(Data("RIFF\u{0}\u{0}\u{0}\u{0}WEBPVP8 ".utf8)) == .webp)
        #expect(GifMediaFormat.sniff(Data("\u{0}\u{0}\u{0}\u{18}ftypmp42".utf8)) == .mp4)
        #expect(GifMediaFormat.sniff(Data("<!doctype html>".utf8)) == nil)
        #expect(GifMediaFormat.sniff(Data("GIF".utf8)) == nil)
    }

    // MARK: Tenor page

    /// The head of a real Tenor page, trimmed to the tags that matter.
    static let tenorHead = """
    <html><head>
    <meta class="dynamic" property="og:site_name" content="Tenor">
    <meta class="dynamic" name="twitter:player:stream" content="https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4">
    <meta class="dynamic" name="twitter:player:stream:content_type" content="video/mp4">
    <meta class="dynamic" property="og:url" content="https://media1.tenor.com/m/3w0Our6WmXUAAAAC/brick.gif">
    <meta class="dynamic" property="og:image" content="https://media1.tenor.com/m/3w0Our6WmXUAAAAC/brick.gif">
    <meta class="dynamic" property="og:image:type" content="image/gif">
    <meta class="dynamic" property="og:image:width" content="498">
    <meta class="dynamic" property="og:image:height" content="492">
    <meta class="dynamic" property="og:video" content="https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4">
    <meta class="dynamic" property="og:video:secure_url" content="https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4">
    <meta class="dynamic" property="og:video:type" content="video/mp4">
    <meta class="dynamic" property="og:video:width" content="498">
    <meta class="dynamic" property="og:video:height" content="494">
    <meta class="dynamic" property="og:video" content="https://media.tenor.com/3w0Our6WmXUAAAPs/brick.webm">
    <meta class="dynamic" property="og:video:type" content="video/webm">
    <meta class="dynamic" property="og:video:width" content="498">
    <meta class="dynamic" property="og:video:height" content="492">
    </head><body></body></html>
    """

    @Test func tenorPagesNameTheMP4FirstWithItsSize() {
        let candidates = TenorPageParser.candidates(fromHTML: Self.tenorHead)
        #expect(candidates == [
            GifMediaCandidate(
                url: URL(string: "https://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4")!,
                format: .mp4,
                pixelSize: CGSize(width: 498, height: 494)
            ),
            GifMediaCandidate(
                url: URL(string: "https://media1.tenor.com/m/3w0Our6WmXUAAAAC/brick.gif")!,
                format: .gif,
                pixelSize: CGSize(width: 498, height: 492)
            )
        ])
    }

    @Test func tenorPagesIgnoreMediaOffTheAllowlist() {
        let html = """
        <meta property='og:video' content='https://evil.example/brick.mp4'>
        <meta property='og:video:type' content='video/mp4'>
        <meta content="http://media.tenor.com/3w0Our6WmXUAAAPo/brick.mp4" property="og:video">
        <meta property="og:image" content="https://tenor.com/assets/img/tenor-app-icon.png">
        <meta property="og:image" content="https://media.tenor.com/3w0Our6WmXUAAAAC/a.gif?x=1&amp;y=2">
        """
        #expect(TenorPageParser.candidates(fromHTML: html).map(\.url.absoluteString) == [
            "https://media.tenor.com/3w0Our6WmXUAAAAC/a.gif?x=1&y=2"
        ])
    }

    @Test func pagesWithoutMediaNameNothing() {
        #expect(TenorPageParser.candidates(fromHTML: "<html><head><title>x</title></head></html>").isEmpty)
    }
}
