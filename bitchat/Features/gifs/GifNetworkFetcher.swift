//
// GifNetworkFetcher.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import Tor

/// Sends GIF requests over the network.
///
/// Each request gets its own ephemeral session: no cookies, no URL cache,
/// no credential store, and generic headers that name neither the app nor
/// the device's language. Redirects are never followed here; `GifResolver`
/// checks every target against the allowlist first.
///
/// With Tor switched on, requests go through Tor's SOCKS proxy, the route
/// the Nostr relays use. When Tor is on but not connected, nothing is sent
/// (fail closed): a GIF is never worth the IP address Tor protects.
final class GifNetworkFetcher: GifHTTPFetching {
    static let live = GifNetworkFetcher()

    func fetch(_ url: URL, maxBytes: Int, stopMarker: Data?) async throws -> GifHTTPResponse {
        guard GifHostPolicy.isAllowed(url) else { throw GifLoadError.notAllowed }
        let proxy = try await Self.torProxyIfEnabled()
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let task = GifFetchTask(maxBytes: maxBytes, stopMarker: stopMarker)
        return try await task.run(request, configuration: Self.configuration(proxy: proxy))
    }

    /// Tor's SOCKS proxy settings when Tor is switched on, nil when it is off.
    /// Throws `torUnavailable` when Tor is on but cannot carry the request.
    private static func torProxyIfEnabled() async throws -> [AnyHashable: Any]? {
        guard NetworkActivationService.persistedTorPreference() else { return nil }
        // Tor that is stopped and not allowed to start (no network
        // activation yet) would hold the tap for the whole bootstrap
        // timeout. Say so at once instead.
        let canBecomeReady = await MainActor.run {
            TorManager.shared.isReady || TorManager.shared.isAutoStartAllowed()
        }
        guard canBecomeReady, await TorManager.shared.awaitReady() else {
            throw GifLoadError.torUnavailable
        }
        // The relays' session carries the proxy settings while Tor is the
        // active route; without them the request would go direct.
        guard let proxy = TorURLSession.shared.session.configuration.connectionProxyDictionary,
              !proxy.isEmpty
        else { throw GifLoadError.torUnavailable }
        return proxy
    }

    private static func configuration(proxy: [AnyHashable: Any]?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = proxy == nil ? 20 : 45
        configuration.timeoutIntervalForResource = proxy == nil ? 60 : 120
        configuration.connectionProxyDictionary = proxy
        return configuration
    }
}

/// One request on its own session, read through the data delegate so the
/// byte cap holds while the body streams in, not after it has arrived.
/// Every callback and state change runs on one serial queue.
private final class GifFetchTask: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let stopMarker: Data?
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "chat.bitchat.gif-fetch"
        return queue
    }()

    private var continuation: CheckedContinuation<GifHTTPResponse, Error>?
    private var session: URLSession?
    private var requestURL: URL?
    private var response: HTTPURLResponse?
    private var body = Data()
    private var isCancelled = false
    private var isFinished = false

    init(maxBytes: Int, stopMarker: Data?) {
        self.maxBytes = maxBytes
        self.stopMarker = stopMarker
    }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> GifHTTPResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.addOperation {
                    self.continuation = continuation
                    guard !self.isCancelled else {
                        self.finish(.failure(CancellationError()))
                        return
                    }
                    self.requestURL = request.url
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: self.queue)
                    self.session = session
                    session.dataTask(with: request).resume()
                }
            }
        } onCancel: {
            queue.addOperation {
                self.isCancelled = true
                self.finish(.failure(CancellationError()))
            }
        }
    }

    /// Resumes the caller once and tears the session down, which also
    /// releases this delegate.
    private func finish(_ result: Result<GifHTTPResponse, Error>) {
        guard !isFinished, let continuation else { return }
        isFinished = true
        self.continuation = nil
        session?.invalidateAndCancel()
        session = nil
        continuation.resume(with: result)
    }

    private func completedResponse() -> Result<GifHTTPResponse, Error> {
        guard let response, let url = response.url ?? requestURL else {
            return .failure(GifLoadError.badStatus(0))
        }
        return .success(GifHTTPResponse(
            url: url,
            statusCode: response.statusCode,
            mimeType: response.mimeType?.lowercased(),
            location: response.value(forHTTPHeaderField: "Location"),
            body: body
        ))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Deliver the redirect itself; the resolver checks its target.
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(GifLoadError.badStatus(0)))
            return
        }
        self.response = http
        if http.expectedContentLength > Int64(maxBytes) {
            completionHandler(.cancel)
            finish(.failure(GifLoadError.tooLarge))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isFinished else { return }
        let searchStart = max(0, body.count - (stopMarker?.count ?? 0))
        body.append(data)
        if body.count > maxBytes {
            finish(.failure(GifLoadError.tooLarge))
            return
        }
        if let stopMarker, body.range(of: stopMarker, in: searchStart..<body.count) != nil {
            finish(completedResponse())
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            finish(completedResponse())
        }
    }
}
