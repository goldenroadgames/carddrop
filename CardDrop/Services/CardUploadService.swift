import UIKit
import Supabase

struct CardSendResult {
    let cardID: UUID
    let cardURL: URL
    let sendsRemainingMonthly: Int   // -1 = unlimited
    let sendsRemainingLifetime: Int  // -1 = unlimited
    let tier: String
}

enum CardUploadService {

    enum UploadError: LocalizedError {
        case renderFailed
        case uploadFailed(String)
        case edgeFunctionFailed(String)
        case suspended
        case monthlyLimitReached(tier: String)
        case lifetimeLimitReached(tier: String)

        var errorDescription: String? {
            switch self {
            case .renderFailed:
                return "Failed to render card images."
            case .uploadFailed(let detail):
                return "Upload failed: \(detail)"
            case .edgeFunctionFailed(let detail):
                return "Send failed: \(detail)"
            case .suspended:
                return "Your account has been suspended. Contact support at support@carddropapp.com."
            case .monthlyLimitReached(let tier):
                return monthlyLimitMessage(tier: tier)
            case .lifetimeLimitReached(let tier):
                return lifetimeLimitMessage(tier: tier)
            }
        }

        private func monthlyLimitMessage(tier: String) -> String {
            switch tier {
            case "anonymous":
                return "You've reached your monthly send limit. Create a free account to send more cards."
            case "unverified":
                return "You've reached your monthly send limit. Verify your email — it's free — to unlock unlimited sends."
            default:
                return "You've reached your monthly send limit."
            }
        }

        private func lifetimeLimitMessage(tier: String) -> String {
            switch tier {
            case "anonymous":
                return "You've used all your free sends. Create a free account to keep sending cards."
            default:
                return "You've reached your send limit."
            }
        }
    }

    static func checkSendLimits() async throws {
        guard let user = try? await supabase.auth.session.user else { return }

        struct UserRow: Decodable {
            let tier: String?
            let sends_this_month: Int?
            let sends_lifetime: Int?
        }
        struct ConfigRow: Decodable {
            let key: String
            let value: String
        }

        guard let userRow = try? await supabase
            .from("users")
            .select("tier, sends_this_month, sends_lifetime")
            .eq("id", value: user.id.uuidString)
            .single()
            .execute()
            .value as UserRow
        else { return }

        let sendsMonth    = userRow.sends_this_month ?? 0
        let sendsLifetime = userRow.sends_lifetime   ?? 0
        let dbTier        = userRow.tier             ?? "free"

        let isAnonymous = user.isAnonymous
        let isVerified  = user.userMetadata["send_unlocked"] == .bool(true)

        let tier: String
        if dbTier == "unlimited"  { tier = "unlimited" }
        else if isVerified         { tier = "verified" }
        else if !isAnonymous       { tier = "unverified" }
        else                       { tier = "anonymous" }

        guard tier == "anonymous" || tier == "unverified" else { return }

        let configKeys = ["send_limit_\(tier)_monthly", "send_limit_\(tier)_lifetime"]
        guard let configRows = try? await supabase
            .from("config")
            .select("key, value")
            .in("key", value: configKeys)
            .execute()
            .value as [ConfigRow]
        else { return }

        var configMap: [String: Int] = [:]
        for row in configRows { configMap[row.key] = Int(row.value) }

        let monthlyLimit  = configMap["send_limit_\(tier)_monthly"]  ?? -1
        let lifetimeLimit = configMap["send_limit_\(tier)_lifetime"] ?? -1

        if monthlyLimit  != -1 && sendsMonth    >= monthlyLimit  { throw UploadError.monthlyLimitReached(tier: tier) }
        if lifetimeLimit != -1 && sendsLifetime >= lifetimeLimit { throw UploadError.lifetimeLimitReached(tier: tier) }
    }

    /// Full send pipeline:
    /// 1. Upload front image to teaser-images/{cardID}.jpg  (serves as teaser + HTML front)
    /// 2. Upload back image to teaser-images/{cardID}_back.jpg
    /// 3. Generate lightweight URL-based HTML and upload to card-html/{cardID}.html
    /// 4. Call send-card Edge Function → get cardURL + sendsRemaining
    static func send(
        cardID: UUID,
        frontData: Data,
        backData: Data,
        frontIsPortrait: Bool,
        frontInkMessage: String? = nil,
        backInkMessage: String? = nil,
        senderNickname: String?,
        recipientNickname: String?,
        recipientName: String?,
        recipientPhone: String?,
        recipientEmail: String?,
        messagePreview: String?
    ) async throws -> CardSendResult {

        let idStr = cardID.uuidString.lowercased()
        guard let sender = try? await supabase.auth.session.user else {
            throw UploadError.renderFailed
        }
        let senderID = sender.id.uuidString.lowercased()

        // 1. Upload front image (also serves as teaser for email/SMS previews)
        try await supabase.storage
            .from("teaser-images")
            .upload(
                "\(senderID)/\(idStr).jpg",
                data: frontData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        // 2. Upload back image
        try await supabase.storage
            .from("teaser-images")
            .upload(
                "\(senderID)/\(idStr)_back.jpg",
                data: backData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        // 3. Call send-card Edge Function
        return try await callSendCardFunction(
            cardID: cardID,
            isPortrait: frontIsPortrait,
            frontInkMessage: frontInkMessage,
            backInkMessage: backInkMessage,
            senderNickname: senderNickname,
            recipientNickname: recipientNickname,
            recipientName: recipientName,
            recipientPhone: recipientPhone,
            recipientEmail: recipientEmail,
            messagePreview: messagePreview
        )
    }

    // MARK: - Edge Function

    private static func callSendCardFunction(
        cardID: UUID,
        isPortrait: Bool,
        frontInkMessage: String?,
        backInkMessage: String?,
        senderNickname: String?,
        recipientNickname: String?,
        recipientName: String?,
        recipientPhone: String?,
        recipientEmail: String?,
        messagePreview: String?
    ) async throws -> CardSendResult {

        struct RequestBody: Encodable {
            let cardID: String
            let deviceUUID: String
            let senderNickname: String?
            let recipientNickname: String?
            let recipientName: String?
            let recipientPhone: String?
            let recipientEmail: String?
            let messagePreview: String?
            let isPortrait: Bool
            let frontInkMessage: String?
            let backInkMessage: String?
        }

        struct ResponseBody: Decodable {
            let cardURL: String?
            let sendsRemainingMonthly: Int?
            let sendsRemainingLifetime: Int?
            let tier: String?
            let error: String?
        }

        let body = RequestBody(
            cardID: cardID.uuidString,
            deviceUUID: UserService.deviceUUID.uuidString,
            senderNickname: senderNickname,
            recipientNickname: recipientNickname,
            recipientName: recipientName,
            recipientPhone: recipientPhone,
            recipientEmail: recipientEmail,
            messagePreview: messagePreview,
            isPortrait: isPortrait,
            frontInkMessage: frontInkMessage,
            backInkMessage: backInkMessage
        )

        do {
            let response: ResponseBody = try await supabase.functions
                .invoke("send-card", options: FunctionInvokeOptions(body: body))

            // Edge function returned 2xx — check for embedded error field
            if let errorCode = response.error {
                throw mapEdgeError(errorCode, tier: response.tier ?? "anonymous")
            }

            guard let urlString = response.cardURL, let url = URL(string: urlString) else {
                throw UploadError.edgeFunctionFailed("Invalid card URL in response")
            }

            return CardSendResult(
                cardID: cardID,
                cardURL: url,
                sendsRemainingMonthly:  response.sendsRemainingMonthly  ?? -1,
                sendsRemainingLifetime: response.sendsRemainingLifetime ?? -1,
                tier: response.tier ?? "anonymous"
            )

        } catch let error as UploadError {
            throw error
        } catch let fnError as FunctionsError {
            if case .httpError(_, let data) = fnError,
               let body = try? JSONDecoder().decode(ResponseBody.self, from: data),
               let errorCode = body.error {
                throw mapEdgeError(errorCode, tier: body.tier ?? "anonymous")
            }
            throw UploadError.edgeFunctionFailed(fnError.localizedDescription)
        } catch {
            throw UploadError.edgeFunctionFailed(error.localizedDescription)
        }
    }

    private static func mapEdgeError(_ code: String, tier: String) -> UploadError {
        switch code {
        case "suspended":              return .suspended
        case "monthly_limit_reached":  return .monthlyLimitReached(tier: tier)
        case "lifetime_limit_reached": return .lifetimeLimitReached(tier: tier)
        default:                       return .edgeFunctionFailed(code)
        }
    }
}
