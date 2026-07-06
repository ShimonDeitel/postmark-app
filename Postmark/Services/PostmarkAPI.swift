import Foundation
import UIKit

// MARK: - Configuration

/// Endpoint / model / key resolution.
///
/// Order:
/// 1. Info.plist keys POSTMARK_API_ENDPOINT / POSTMARK_MODEL /
///    POSTMARK_API_KEY, injected at build time from Secrets.xcconfig
///    (never committed).
/// 2. DEBUG ONLY: if the key is empty (simulator dev), fall back to reading
///    ~/.cache/neverend/openrouter.key off the host Mac.
///
/// Production builds ship with a thin proxy endpoint before submission; the
/// key never lives in a release binary.
struct PostmarkAPIConfiguration {
    var endpoint: URL
    var model: String
    var apiKey: String

    static let defaultEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    /// Production model (multimodal input, text out). Served via the thin
    /// proxy with a funded key before submission.
    static let defaultModel = "google/gemini-2.5-flash"
    #if DEBUG
    /// Free-tier vision model so dev works on an uncredited OpenRouter key.
    /// Rate-limited; production still moves to a funded key behind the proxy.
    static let debugFreeModel = "nvidia/nemotron-nano-12b-v2-vl:free"
    #endif

    static func load(bundle: Bundle = .main) -> PostmarkAPIConfiguration? {
        let info = bundle.infoDictionary ?? [:]
        let endpointString = nonEmpty(info["POSTMARK_API_ENDPOINT"] as? String) ?? defaultEndpoint
        var model = nonEmpty(info["POSTMARK_MODEL"] as? String) ?? defaultModel
        #if DEBUG
        if nonEmpty(info["POSTMARK_MODEL"] as? String) == nil {
            model = debugFreeModel
        }
        #endif
        var apiKey = nonEmpty(info["POSTMARK_API_KEY"] as? String) ?? ""

        #if DEBUG
        if apiKey.isEmpty, let hostKey = debugHostKey() {
            apiKey = hostKey
        }
        #endif

        guard !apiKey.isEmpty, let endpoint = URL(string: endpointString) else { return nil }
        return PostmarkAPIConfiguration(endpoint: endpoint, model: model, apiKey: apiKey)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    #if DEBUG
    /// Simulator-only convenience: the simulator process can read host-Mac
    /// files, so pick up the owner's OpenRouter key without any xcconfig.
    /// Never compiled into Release.
    private static func debugHostKey() -> String? {
        var candidates: [String] = []
        if let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            candidates.append(hostHome + "/.cache/neverend/openrouter.key")
        }
        candidates.append(NSHomeDirectory() + "/.cache/neverend/openrouter.key")
        for path in candidates {
            if let raw = try? String(contentsOfFile: path, encoding: .utf8) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
    #endif
}

// MARK: - API client

/// Async client for an OpenRouter-compatible /chat/completions endpoint.
/// Posts JPEG-compressed base64 images, expects a strict JSON object back,
/// and performs exactly one repair round-trip if decoding fails.
final class PostmarkAPI {

    enum APIError: LocalizedError {
        case notConfigured
        case badStatus(Int, String)
        case emptyResponse
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "The identification service is not configured. Add an API key to Secrets.xcconfig."
            case .badStatus(let code, _):
                return "The identification service returned an error (HTTP \(code))."
            case .emptyResponse:
                return "The identification service returned an empty response."
            case .decodingFailed:
                return "Could not understand the identification result."
            }
        }
    }

    private let configuration: PostmarkAPIConfiguration
    private let urlSession: URLSession

    /// Max long-edge pixels / JPEG quality applied before upload.
    private static let maxImageDimension: CGFloat = 1280
    private static let jpegQuality: CGFloat = 0.6

    init(configuration: PostmarkAPIConfiguration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    /// Returns a client from Info.plist/xcconfig (+ DEBUG host-key fallback),
    /// or nil when no key is available.
    static func makeDefault() -> PostmarkAPI? {
        guard let configuration = PostmarkAPIConfiguration.load() else { return nil }
        return PostmarkAPI(configuration: configuration)
    }

    private static let systemPrompt = """
    You are an expert philatelist. The user sends a photo containing one or \
    more postage stamps. Identify the stamp(s) in the photo; if several are \
    visible, describe the single most prominent or most valuable one. \
    Estimate realistic SOLD-price ranges in USD, for used condition and for \
    mint condition, based on what comparable stamps actually sell for, not \
    catalog or asking prices.

    Respond with ONLY a JSON object, no markdown fences, no commentary, with \
    exactly these keys:
    {
      "country": string, issuing country or territory,
      "issue": string, issue or series name (e.g. "Penny Black", "Columbian Exposition"),
      "year": number, integer year of issue (0 if unknown),
      "denomination": string, face value as printed (e.g. "2c", "1d"),
      "variety": string, color/perforation/error variety if identifiable, otherwise "",
      "value_low_used": number, low end of sold-price range in USD, used condition,
      "value_high_used": number, high end of sold-price range in USD, used condition,
      "value_low_mint": number, low end of sold-price range in USD, mint condition,
      "value_high_mint": number, high end of sold-price range in USD, mint condition,
      "confidence": number between 0 and 1,
      "search_term": string, the best eBay search phrase for this exact stamp
    }
    """

    /// Identifies a stamp from 1-3 photos. `hint` is optional user context
    /// (e.g. "the second photo is the back showing the watermark").
    func identify(images: [Data], hint: String? = nil) async throws -> StampResult {
        precondition(!images.isEmpty, "identify(images:) requires at least one image")

        var userParts: [ChatRequest.ContentPart] = [
            .text("Identify this stamp and estimate its sold-price value ranges." + (hint.map { " Context: \($0)" } ?? ""))
        ]
        for imageData in images.prefix(3) {
            let jpeg = Self.preparedJPEG(from: imageData)
            userParts.append(.imageDataURI(jpeg))
        }

        let content = try await send(messages: [
            .system(Self.systemPrompt),
            .user(userParts),
        ])

        // Strict decode; on failure, exactly one repair round-trip.
        do {
            return try Self.decodeStrict(content)
        } catch {
            let repaired = try await send(messages: [
                .system(Self.systemPrompt),
                .user([.text("""
                The following was supposed to be a single valid JSON object with keys \
                country, issue, year, denomination, variety, value_low_used, \
                value_high_used, value_low_mint, value_high_mint, confidence, search_term \
                (year must be an integer number) but it failed to parse. \
                Return ONLY the corrected JSON object, nothing else.

                \(content)
                """)]),
            ])
            do {
                return try Self.decodeStrict(repaired)
            } catch {
                throw APIError.decodingFailed(repaired)
            }
        }
    }

    // MARK: Transport

    private func send(messages: [ChatRequest.Message]) async throws -> String {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        let body = ChatRequest(model: configuration.model, messages: messages, temperature: 0.2)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw APIError.emptyResponse
        }
        return content
    }

    // MARK: Parsing

    /// Strict StampResult decode. Tolerates only markdown fences / surrounding
    /// prose by extracting the outermost {...} span; the JSON itself must
    /// match the schema exactly.
    static func decodeStrict(_ content: String) throws -> StampResult {
        let jsonString = extractJSONObject(from: content)
        guard let data = jsonString.data(using: .utf8) else {
            throw APIError.decodingFailed(content)
        }
        return try JSONDecoder().decode(StampResult.self, from: data)
    }

    static func extractJSONObject(from content: String) -> String {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              start < end
        else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(content[start...end])
    }

    // MARK: Image prep

    /// Re-encodes to a bounded JPEG so uploads stay small. Falls back to the
    /// raw data if UIImage can't read it.
    static func preparedJPEG(from data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let longEdge = max(image.size.width, image.size.height)
        var output = image
        if longEdge > maxImageDimension, longEdge > 0 {
            let scale = maxImageDimension / longEdge
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            output = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        return output.jpegData(compressionQuality: jpegQuality) ?? data
    }
}

// MARK: - Wire types (OpenRouter-compatible chat completions)

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: Content

        static func system(_ text: String) -> Message {
            Message(role: "system", content: .text(text))
        }
        static func user(_ parts: [ContentPart]) -> Message {
            Message(role: "user", content: .parts(parts))
        }
    }

    enum Content: Encodable {
        case text(String)
        case parts([ContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string): try container.encode(string)
            case .parts(let parts): try container.encode(parts)
            }
        }
    }

    struct ContentPart: Encodable {
        let type: String
        var text: String?
        var imageURL: ImageURL?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        static func text(_ text: String) -> ContentPart {
            ContentPart(type: "text", text: text, imageURL: nil)
        }
        static func imageDataURI(_ jpeg: Data) -> ContentPart {
            ContentPart(
                type: "image_url",
                text: nil,
                imageURL: ImageURL(url: "data:image/jpeg;base64,\(jpeg.base64EncodedString())")
            )
        }
    }

    struct ImageURL: Encodable {
        let url: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}
