import Foundation

/// Claude's 5-hour and 7-day subscription windows, any per-model weekly limits, and paid extra usage, as Anthropic
/// reports them.
struct ClaudeUsageReport: Codable, Equatable, Sendable {
    struct Window: Codable, Equatable, Sendable {
        let usedPercent: Double
        let resetsAt: Date?
    }

    struct ModelWindow: Codable, Equatable, Sendable {
        let modelName: String
        let usedPercent: Double
        let resetsAt: Date?
    }

    /// Paid usage beyond the plan this month, in the account's currency.
    struct ExtraUsage: Codable, Equatable, Sendable {
        let spent: Decimal
        let limit: Decimal?
        let currencyCode: String
    }

    let fiveHour: Window?
    let sevenDay: Window?
    var modelWeeks: [ModelWindow] = []
    var extraUsage: ExtraUsage? = nil
}

extension ClaudeUsageReport {
    /// Usage saved before per-model limits or extra usage existed has no `modelWeeks` or `extraUsage`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try container.decodeIfPresent(Window.self, forKey: .fiveHour)
        sevenDay = try container.decodeIfPresent(Window.self, forKey: .sevenDay)
        modelWeeks = try container.decodeIfPresent([ModelWindow].self, forKey: .modelWeeks) ?? []
        extraUsage = try container.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
    }
}

protocol ClaudeUsageWebClient: Sendable {
    func usage(using token: ClaudeAccessToken) async throws(ClaudeUsageWebError) -> Data
    /// Best effort: nil on any failure.
    func profile(using token: ClaudeAccessToken) async -> ClaudeProfile?
}

/// The plan and email of the account behind a token, read once after "Sign in with Claude".
struct ClaudeProfile: Equatable, Sendable {
    /// Such as `max_20x`, in the format `ClaudeCredentials.planName` uses.
    let planName: String?
    let email: String?
}

enum ClaudeUsageWebError: Error, Equatable {
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: TimeInterval?)
    case httpStatus(Int)
    case transport
}

/// The Anthropic API endpoints rusage calls, and the pure rules around them.
enum ClaudeUsageAPI {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    static func request(using token: ClaudeAccessToken, url: URL = usageURL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return request
    }

    /// The token may follow a redirect only to the same host over HTTPS.
    static func allowsRedirect(from original: URL?, to target: URL?) -> Bool {
        guard let original, let target, let host = original.host?.lowercased() else { return false }
        return target.scheme?.lowercased() == "https" && target.host?.lowercased() == host
    }

    /// Nil for 200. `retryAfter` is the parsed `Retry-After` wait, if any.
    static func error(forStatus statusCode: Int, retryAfter: TimeInterval?) -> ClaudeUsageWebError? {
        switch statusCode {
        case 200: nil
        case 401: .unauthorized
        case 403: .forbidden
        case 429: .rateLimited(retryAfter: retryAfter)
        default: .httpStatus(statusCode)
        }
    }

    /// Reads `five_hour`, `seven_day`, and each `weekly_scoped` entry in `limits`, the per-model weekly limits
    /// that both Claude clients title by `scope.model.display_name`. Other windows, such as `seven_day_opus`, are
    /// ignored. A `limits` entry without a name or percent is skipped and never fails the read. `extra_usage` counts
    /// only while enabled, and an unreadable one is skipped.
    static func parseUsage(_ data: Data) throws -> ClaudeUsageReport {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(UsageResponseDTO.self, from: data)
        let limits = (try? decoder.decode(LimitsDTO.self, from: data))?.limits ?? []
        var modelWeeks: [ClaudeUsageReport.ModelWindow] = []
        for limit in limits where limit.kind == "weekly_scoped" {
            guard let name = limit.modelName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let percent = limit.percent,
                  !modelWeeks.contains(where: { $0.modelName == name }) else { continue }
            modelWeeks.append(.init(modelName: name, usedPercent: min(max(percent, 0), 100), resetsAt: limit.resetsAt.flatMap(date(from:))))
        }
        return ClaudeUsageReport(
            fiveHour: window(response.fiveHour),
            sevenDay: window(response.sevenDay),
            modelWeeks: modelWeeks,
            extraUsage: (try? decoder.decode(ExtraUsageResponseDTO.self, from: data))?.extraUsage.flatMap(extraUsage)
        )
    }

    /// Reads `organization.organization_type` with the `NNx` suffix of `organization.rate_limit_tier` as the plan, such
    /// as `max_20x`, and `account.email` or `account.email_address` as the email. Unknown or missing parts read as nil.
    static func parseProfile(_ data: Data) -> ClaudeProfile? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(ProfileResponseDTO.self, from: data) else { return nil }
        let plan: String? = switch response.organization?.organizationType {
        case "claude_max": "max"
        case "claude_pro": "pro"
        case "claude_team": "team"
        case "claude_enterprise": "enterprise"
        default: nil
        }
        let multiplier = response.organization?.rateLimitTier?.split(separator: "_").last
            .flatMap { $0.hasSuffix("x") && Int($0.dropLast()) != nil ? $0 : nil }
        let email = [response.account?.email, response.account?.emailAddress].compactMap(\.self).first { !$0.isEmpty }
        return ClaudeProfile(planName: plan.map { plan in multiplier.map { "\(plan)_\($0)" } ?? plan }, email: email)
    }

    /// No cookies, no cache, and redirects only to the same host over HTTPS, so a token never reaches another host.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: SameHostRedirectDelegate(), delegateQueue: nil)
    }

    /// Amounts arrive in minor units, such as cents.
    private static func extraUsage(_ dto: ExtraUsageDTO) -> ClaudeUsageReport.ExtraUsage? {
        let decimalPlaces = dto.decimalPlaces ?? 2
        guard dto.isEnabled == true, let usedCredits = dto.usedCredits, decimalPlaces >= 0 else { return nil }
        let unit = pow(Decimal(10), decimalPlaces)
        let currency = dto.currency?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ClaudeUsageReport.ExtraUsage(
            spent: usedCredits / unit,
            limit: dto.monthlyLimit.map { $0 / unit },
            currencyCode: currency.isEmpty ? "USD" : currency
        )
    }

    private static func window(_ dto: WindowDTO?) -> ClaudeUsageReport.Window? {
        guard let dto, let utilization = dto.utilization else { return nil }
        return ClaudeUsageReport.Window(
            usedPercent: min(max(utilization, 0), 100),
            resetsAt: dto.resetsAt.flatMap(date(from:))
        )
    }

    private static func date(from value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }
}

private struct ProfileResponseDTO: Decodable {
    struct Account: Decodable {
        let email: String?
        let emailAddress: String?
    }

    struct Organization: Decodable {
        let organizationType: String?
        let rateLimitTier: String?
    }

    let account: Account?
    let organization: Organization?
}

private struct UsageResponseDTO: Decodable {
    let fiveHour: WindowDTO?
    let sevenDay: WindowDTO?
}

private struct WindowDTO: Decodable {
    let utilization: Double?
    let resetsAt: String?
}

private struct ExtraUsageResponseDTO: Decodable {
    let extraUsage: ExtraUsageDTO?
}

private struct ExtraUsageDTO: Decodable {
    let isEnabled: Bool?
    let usedCredits: Decimal?
    let monthlyLimit: Decimal?
    let currency: String?
    let decimalPlaces: Int?
}

private struct LimitsDTO: Decodable {
    let limits: [LimitDTO]
}

/// Every field is optional and a field of the wrong type reads as missing, so one odd entry never fails the others.
private struct LimitDTO: Decodable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?
    let modelName: String?

    private enum CodingKeys: String, CodingKey {
        case kind, percent, resetsAt, scope
    }

    private struct Scope: Decodable {
        struct Model: Decodable {
            let displayName: String?
        }

        let model: Model?
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        kind = try? container?.decode(String.self, forKey: .kind)
        percent = try? container?.decode(Double.self, forKey: .percent)
        resetsAt = try? container?.decode(String.self, forKey: .resetsAt)
        modelName = (try? container?.decode(Scope.self, forKey: .scope))?.model?.displayName
    }
}

final class URLSessionClaudeUsageWebClient: ClaudeUsageWebClient {
    private let session = ClaudeUsageAPI.makeSession()

    deinit {
        session.finishTasksAndInvalidate()
    }

    func usage(using token: ClaudeAccessToken) async throws(ClaudeUsageWebError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: ClaudeUsageAPI.request(using: token))
        } catch {
            throw ClaudeUsageWebError.transport
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeUsageWebError.transport
        }
        if let error = ClaudeUsageAPI.error(
            forStatus: httpResponse.statusCode,
            retryAfter: RetryAfter.delay(httpResponse.value(forHTTPHeaderField: "Retry-After"), now: Date())
        ) {
            throw error
        }
        return data
    }

    func profile(using token: ClaudeAccessToken) async -> ClaudeProfile? {
        guard
            let (data, response) = try? await session.data(for: ClaudeUsageAPI.request(using: token, url: ClaudeUsageAPI.profileURL)),
            (response as? HTTPURLResponse)?.statusCode == 200
        else {
            return nil
        }
        return ClaudeUsageAPI.parseProfile(data)
    }
}

private final class SameHostRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        ClaudeUsageAPI.allowsRedirect(from: task.originalRequest?.url, to: request.url) ? request : nil
    }
}
