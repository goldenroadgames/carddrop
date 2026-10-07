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
        let isVerified  = user.isSendVerified

        let tier: String
        if dbTier == "unlimited"  { tier = "unlimited" }
        else if isVerified         { tier = "verified" }
        else if !isAnonymous       { tier = "unverified" }
        else                       { tier = "anonymous" }

        guard tier == "anonymous" || tier == "unverified" else { return }

        let configKeys = ["send_limit_\(tier)_monthly", "send_limit_\(tier)_lifetime"]
        guard let configRows = try? await supabase
            .from("zz_config")
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
    /// 1. Upload front image to card-images/{cardID}.jpg  (serves as teaser + HTML front)
    /// 2. Upload back image to card-images/{cardID}_back.jpg
    /// 2b. Upload 6x9 alt back image to card-images/{cardID}_back6x9.jpg, when available
    /// 3. Call send-card Edge Function → get cardURL + sendsRemaining
    static func send(
        cardID: UUID,
        frontData: Data,
        backData: Data,
        back6x9Data: Data? = nil,
        frontIsPortrait: Bool,
        frontInkMessage: String? = nil,
        backInkMessage: String? = nil,
        senderNickname: String?,
        recipientNickname: String?,
        recipientName: String?,
        recipientPhone: String?,
        recipientEmail: String?,
        messagePreview: String?,
        designFeatures: String? = nil,
        beforeImage: UIImage? = nil
    ) async throws -> CardSendResult {

        try await uploadDigitalCardImages(cardID: cardID, frontData: frontData, backData: backData, back6x9Data: back6x9Data, beforeImage: beforeImage)

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
            messagePreview: messagePreview,
            designFeatures: designFeatures
        )
    }

    // MARK: - Digital card images

    /// Uploads the digital-resolution front/back(+6x9) images to
    /// card-images/{senderID}/{cardID}.jpg / _back.jpg / _back6x9.jpg — the
    /// exact paths the webapp's /card/[id] page reads (see
    /// web/app/card/[id]/page.tsx). Every card needs these, not just
    /// digitally-sent ones: a physical postcard's back-of-card QR code links
    /// to /card/{cardID} too, so without this upload that link 404s even
    /// though the card was successfully mailed.
    static func uploadDigitalCardImages(cardID: UUID, frontData: Data, backData: Data, back6x9Data: Data? = nil, beforeImage: UIImage? = nil) async throws {
        let idStr = cardID.uuidString.lowercased()
        guard let sender = try? await supabase.auth.session.user else {
            throw UploadError.renderFailed
        }
        let senderID = sender.id.uuidString.lowercased()

        try await supabase.storage
            .from("card-images")
            .upload(
                "\(senderID)/\(idStr).jpg",
                data: frontData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        try await supabase.storage
            .from("card-images")
            .upload(
                "\(senderID)/\(idStr)_back.jpg",
                data: backData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        if let thumbData = scaledDownThumbnail(fromFrontData: frontData) {
            try await supabase.storage
                .from("card-images")
                .upload(
                    "\(senderID)/\(idStr)_thumb.jpg",
                    data: thumbData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
        }

        if let back6x9Data {
            try await supabase.storage
                .from("card-images")
                .upload(
                    "\(senderID)/\(idStr)_back6x9.jpg",
                    data: back6x9Data,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
        }

        // "Before" photo — the original, pre-edit photo, downscaled for the
        // Inspire gallery's before/after toggle. Display-only, never
        // reconstructed/printed from. Optional: older sends / drafts without
        // an original image on disk simply don't get one. Plus a small
        // thumbnail of it for the Inspire grid tiles — same idea as the
        // front's own _thumb.jpg, so the grid isn't loading full-res images.
        if let beforeImage {
            if let beforeData = resizedJPEG(from: beforeImage, maxDimension: 1500, quality: 0.75) {
                try await supabase.storage
                    .from("card-images")
                    .upload(
                        "\(senderID)/\(idStr)_before.jpg",
                        data: beforeData,
                        options: FileOptions(contentType: "image/jpeg", upsert: true)
                    )
            }
            if let beforeThumbData = resizedJPEG(from: beforeImage, maxDimension: 600, quality: 0.6) {
                try await supabase.storage
                    .from("card-images")
                    .upload(
                        "\(senderID)/\(idStr)_before_thumb.jpg",
                        data: beforeThumbData,
                        options: FileOptions(contentType: "image/jpeg", upsert: true)
                    )
            }
        }
    }

    // MARK: - Admin thumbnail / before-photo scaling

    /// Downscales `image` to `maxDimension` on its long edge and re-encodes
    /// as JPEG at `quality`. Shared by the admin thumbnail and the "before"
    /// (original, pre-edit) photo upload — both are display-only, never
    /// reconstructed/printed from.
    private static func resizedJPEG(from image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1, maxDimension / longEdge)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// A small (max 600pt on the long edge), lower-quality JPEG of the front
    /// image — for fast-loading admin/moderation lists later, not the
    /// full-resolution card display. Returns nil if frontData can't decode.
    private static func scaledDownThumbnail(fromFrontData frontData: Data, maxDimension: CGFloat = 600) -> Data? {
        guard let image = UIImage(data: frontData) else { return nil }
        return resizedJPEG(from: image, maxDimension: maxDimension, quality: 0.6)
    }

    // MARK: - LOB export upload

    /// Uploads a front/back pair produced by `CardRenderer.renderLOBTestExport`
    /// to the public card-images bucket. Used both by the DEBUG-only manual
    /// LOB test buttons and by the real physical-mail send flow (after
    /// payment succeeds, before calling submit-to-lob) — `sizeLabel` (e.g.
    /// "4x6"/"6x9") just disambiguates the filenames so repeated
    /// renders/orders at different sizes don't collide.
    /// Returns the public URLs for a LOB export pair already uploaded for
    /// this exact card+size, or nil if either file is missing. A card's
    /// content is immutable once created (editing produces a new cardID via
    /// cloneExact — see [[feedback_sent_card_cardid_not_clone]]), so a prior
    /// render for this cardID+size is always byte-identical to a fresh one;
    /// callers should check this before re-rendering/re-uploading so
    /// ordering a second physical copy of the same card doesn't redundantly
    /// overwrite the file that's already there.
    static func existingLOBExportURLs(cardID: UUID, sizeLabel: String) async throws -> (frontURL: URL, backURL: URL)? {
        guard let sender = try? await supabase.auth.session.user else {
            throw UploadError.renderFailed
        }
        let senderID = sender.id.uuidString.lowercased()
        let idStr = cardID.uuidString.lowercased()
        let frontName = "\(idStr)_front_forLOB_\(sizeLabel).jpg"
        let backName  = "\(idStr)_back_forLOB_\(sizeLabel).jpg"

        let files = try await supabase.storage.from("card-images").list(
            path: senderID,
            options: SearchOptions(search: idStr)
        )
        let names = Set(files.map { $0.name })
        guard names.contains(frontName), names.contains(backName) else { return nil }

        let frontURL = SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/card-images/\(senderID)/\(frontName)")
        let backURL  = SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/card-images/\(senderID)/\(backName)")
        return (frontURL, backURL)
    }

    static func uploadLOBTestExport(cardID: UUID, frontData: Data, backData: Data, sizeLabel: String) async throws -> (frontURL: URL, backURL: URL) {
        guard let sender = try? await supabase.auth.session.user else {
            throw UploadError.renderFailed
        }
        let senderID = sender.id.uuidString.lowercased()
        let idStr = cardID.uuidString.lowercased()

        let frontPath = "\(senderID)/\(idStr)_front_forLOB_\(sizeLabel).jpg"
        let backPath  = "\(senderID)/\(idStr)_back_forLOB_\(sizeLabel).jpg"

        try await supabase.storage.from("card-images").upload(
            frontPath, data: frontData, options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
        try await supabase.storage.from("card-images").upload(
            backPath, data: backData, options: FileOptions(contentType: "image/jpeg", upsert: true)
        )

        let frontURL = SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/card-images/\(frontPath)")
        let backURL  = SupabaseConfig.projectURL.appendingPathComponent("storage/v1/object/public/card-images/\(backPath)")
        return (frontURL, backURL)
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
        messagePreview: String?,
        designFeatures: String? = nil
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
            let designFeatures: String?
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
            backInkMessage: backInkMessage,
            designFeatures: designFeatures
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
