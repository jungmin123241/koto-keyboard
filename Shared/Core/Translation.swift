import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TranslationResult: Equatable, Sendable {
    public let originalText: String
    public let translatedText: String
    public let detectedSourceLanguage: String?
    public let provider: String

    public init(originalText: String, translatedText: String, detectedSourceLanguage: String?, provider: String) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.detectedSourceLanguage = detectedSourceLanguage
        self.provider = provider
    }
}

public protocol TranslationService: Sendable {
    func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> TranslationResult
}

public enum TranslationError: String, Error, Sendable {
    case unsupported, offline, timeout, permission, configuration, unauthorized, rateLimited, server, invalidResponse

    public var message: String {
        switch self {
        case .unsupported: return "이 번역 방식에서 지원하지 않는 문장 또는 언어입니다."
        case .offline: return "네트워크 연결을 확인하세요. 기본 입력은 계속 사용할 수 있습니다."
        case .timeout: return "번역 시간이 초과되었습니다. 다시 시도하세요."
        case .permission: return "네트워크 번역에는 전체 접근 허용이 필요합니다."
        case .configuration: return "메인 앱에서 번역 서버와 접근 토큰을 설정하세요."
        case .unauthorized: return "접근 토큰을 확인하세요."
        case .rateLimited: return "요청이 많습니다. 잠시 후 다시 시도하세요."
        case .server: return "번역 서비스에 연결할 수 없습니다."
        case .invalidResponse: return "번역 응답을 확인할 수 없습니다."
        }
    }
}

public enum TranslationState: Equatable, Sendable {
    case idle, translating, empty
    case translated(TranslationResult)
    case failed(TranslationError)
}

public struct MockTranslationService: TranslationService {
    public init() {}
    public func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> TranslationResult {
        try await Task.sleep(nanoseconds: 180_000_000)
        try Task.checkCancellation()
        let phrases = ["안녕하세요": "こんにちは", "감사합니다": "ありがとうございます", "hello": "こんにちは", "thank you": "ありがとうございます"]
        guard targetLanguage == "ja", let result = phrases[text.lowercased()] else {
            throw TranslationError.unsupported
        }
        return TranslationResult(originalText: text, translatedText: result, detectedSourceLanguage: nil, provider: "Mock · 개발 예제")
    }
}

/// Small, truthful offline phrasebook. This is not a general translation model.
public struct LocalTranslationService: TranslationService {
    public init() {}
    public func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> TranslationResult {
        try Task.checkCancellation()
        let groups: [[String: String]] = [
            ["ko": "안녕하세요", "en": "hello", "ja": "こんにちは", "zh": "你好"],
            ["ko": "감사합니다", "en": "thank you", "ja": "ありがとうございます", "zh": "谢谢"],
            ["ko": "죄송합니다", "en": "sorry", "ja": "すみません", "zh": "对不起"],
            ["ko": "안녕히 가세요", "en": "goodbye", "ja": "さようなら", "zh": "再见"]
        ]
        for group in groups {
            if let source = group.first(where: { $0.value.lowercased() == text.lowercased() }), let result = group[targetLanguage] {
                return TranslationResult(originalText: text, translatedText: result, detectedSourceLanguage: source.key, provider: "오프라인 예문")
            }
        }
        throw TranslationError.unsupported
    }
}

public struct RemoteTranslationService: TranslationService {
    public let endpoint: URL
    public let accessToken: String
    public let wifiOnly: Bool

    public init(endpoint: URL, accessToken: String, wifiOnly: Bool) {
        self.endpoint = endpoint
        self.accessToken = accessToken
        self.wifiOnly = wifiOnly
    }

    public func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> TranslationResult {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
              endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              !accessToken.isEmpty else { throw TranslationError.configuration }
        struct Body: Encodable { let text: String; let sourceLanguage: String?; let targetLanguage: String }
        struct Reply: Decodable { let translatedText: String; let detectedSourceLanguage: String?; let provider: String }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.allowsCellularAccess = !wifiOnly
        #if os(iOS) || os(macOS)
        config.allowsExpensiveNetworkAccess = !wifiOnly
        config.waitsForConnectivity = false
        #endif
        let session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Body(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage))
        do {
            #if os(iOS) || os(macOS)
            let (bytes, response) = try await session.bytes(for: request)
            var data = Data()
            for try await byte in bytes {
                guard data.count < 65_536 else { throw TranslationError.invalidResponse }
                data.append(byte)
            }
            #else
            let (data, response) = try await session.data(for: request)
            #endif
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
            switch http.statusCode {
            case 200: break
            case 401, 403: throw TranslationError.unauthorized
            case 429: throw TranslationError.rateLimited
            case 408, 504: throw TranslationError.timeout
            default: throw TranslationError.server
            }
            guard data.count <= 65_536, let reply = try? JSONDecoder().decode(Reply.self, from: data),
                  !reply.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  reply.translatedText.count <= 8_000 else { throw TranslationError.invalidResponse }
            return TranslationResult(originalText: text, translatedText: reply.translatedText,
                                     detectedSourceLanguage: reply.detectedSourceLanguage, provider: reply.provider)
        } catch is CancellationError { throw CancellationError() }
        catch let error as TranslationError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? TranslationError.timeout : TranslationError.offline
        } catch { throw TranslationError.invalidResponse }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward a user's token/text to a redirect destination.
        completionHandler(nil)
    }
}
