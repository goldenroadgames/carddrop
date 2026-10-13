import Foundation

// Rules for text a person types that becomes a QR code on the card (the front
// QR overlay and the optional back message QR). A phone camera acts on a QR:
// it opens links, offers to call, text, email, join a Wi-Fi network or add a
// contact, and OpenAI moderation only judges words, not where a link leads.
// So these fields must be plain text.
//
// The send-card server applies the same rules (supabase/functions/_shared/
// qrText.ts) — keep the two lists identical. Not a moderation strike.
enum QRTextRules {

    static let message = "It looks like your Invisible Ink QR message might contain links, phone numbers or email addresses, which aren't permitted. Please type your message as plain text."

    private static let sep = #"[\s().\-/]"#
    private static let tlds = [
        "com", "net", "org", "edu", "gov", "info", "biz", "io", "co", "app", "me",
        "ly", "gl", "to", "us", "uk", "ca", "de", "fr", "au", "nz", "xyz", "online",
        "site", "shop", "store", "link", "live", "tv", "fm", "ai", "dev", "page",
        "cc", "ws", "gg", "im", "ch", "nl", "se", "es", "jp", "cn", "ru", "br", "mx",
    ].joined(separator: "|")

    private static let patterns: [String] = [
        #"https?:\/\/"#,
        #"www\."#,
        "[a-z0-9-]+\\.(?:\(tlds))(?![a-z0-9])",
        #"(?:bit\.ly|tinyurl|t\.co|goo\.gl|youtu\.be|ow\.ly|is\.gd|buff\.ly|rebrand\.ly)"#,
        #"^\s*(?:tel|sms|smsto|mailto):"#,
        #"^\s*wifi:"#,
        #"^\s*(?:geo|maps):"#,
        #"^\s*(?:begin:v(?:card|event)|mecard:)"#,
        #"[a-z][a-z0-9+.\-]*:\/\/"#,
        #"[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}"#,
        #"(?:data|javascript):\S"#,
        "\\d(?:\(sep){0,2}\\d){6,}",
        "(?:\\+|(?<!\\d)00)\(sep){0,2}\\d(?:\(sep){0,2}\\d){4,}",
        "(?<![a-z0-9])(?:\\+?1\(sep)?)?(?:800|833|844|855|866|877|888)[\\s.\\-]*(?:[a-z][\\s.\\-]*){7,}",
    ]

    // Keypad vanity number (555-CALL-NOW): three digits, a separator, then
    // seven letters/digits split 3+4 or 4+3, with at least one letter somewhere.
    private static let keypadVanity =
        #"(?<![a-z0-9])\d{3}[\s.\-]+(?:[a-z0-9]{3}[\s.\-]*[a-z0-9]{4}|[a-z0-9]{4}[\s.\-]*[a-z0-9]{3})(?![a-z0-9])"#

    private static let compiled: [NSRegularExpression] = patterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }
    private static let keypadRegex = try? NSRegularExpression(pattern: keypadVanity, options: [.caseInsensitive])

    /// True when the text breaks any rule (a link, phone number, email address
    /// or other QR action). Empty text is fine.
    static func isNotPlainText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let range = NSRange(t.startIndex..., in: t)
        for re in compiled where re.firstMatch(in: t, options: [], range: range) != nil { return true }
        if let m = keypadRegex?.firstMatch(in: t, options: [], range: range),
           let r = Range(m.range, in: t),
           t[r].rangeOfCharacter(from: .letters) != nil {
            return true
        }
        return false
    }
}
