// Rules for text a person types that becomes a QR code on the card (the front
// QR overlay, sent as frontInkMessage, and the optional back message QR, sent
// as backInkMessage). A phone camera acts on a QR: it opens links, offers to
// call, text, email, join a Wi-Fi network or add a contact. OpenAI moderation
// judges words, not where a link leads, so these fields must be plain text.
//
// send-card refuses the send when any rule matches. The app applies the same
// rules before the person can move on (CardDrop/Services/QRTextRules.swift) —
// keep the two lists identical. Not a moderation strike: nothing is recorded.
//
// All patterns run case-insensitively on the trimmed text.
const SEP = "[\\s().\\-/]";   // separators allowed between phone digits
const TLDS = [
  "com", "net", "org", "edu", "gov", "info", "biz", "io", "co", "app", "me",
  "ly", "gl", "to", "us", "uk", "ca", "de", "fr", "au", "nz", "xyz", "online",
  "site", "shop", "store", "link", "live", "tv", "fm", "ai", "dev", "page",
  "cc", "ws", "gg", "im", "ch", "nl", "se", "es", "jp", "cn", "ru", "br", "mx",
].join("|");

export const QR_TEXT_RULES: { name: string; pattern: string }[] = [
  { name: "http(s) link", pattern: "https?:\\/\\/" },
  { name: "www link", pattern: "www\\." },
  { name: "bare domain", pattern: `[a-z0-9-]+\\.(?:${TLDS})(?![a-z0-9])` },
  { name: "short-link host", pattern: "(?:bit\\.ly|tinyurl|t\\.co|goo\\.gl|youtu\\.be|ow\\.ly|is\\.gd|buff\\.ly|rebrand\\.ly)" },
  { name: "phone/sms/email scheme", pattern: "^\\s*(?:tel|sms|smsto|mailto):" },
  { name: "Wi-Fi scheme", pattern: "^\\s*wifi:" },
  { name: "map scheme", pattern: "^\\s*(?:geo|maps):" },
  { name: "contact/calendar card", pattern: "^\\s*(?:begin:v(?:card|event)|mecard:)" },
  { name: "other scheme://", pattern: "[a-z][a-z0-9+.\\-]*:\\/\\/" },
  { name: "email address", pattern: "[a-z0-9._%+\\-]+@[a-z0-9.\\-]+\\.[a-z]{2,}" },
  { name: "data/javascript", pattern: "(?:data|javascript):\\S" },
  { name: "phone number (7+ digits)", pattern: `\\d(?:${SEP}{0,2}\\d){6,}` },
  { name: "international prefix number", pattern: `(?:\\+|(?<!\\d)00)${SEP}{0,2}\\d(?:${SEP}{0,2}\\d){4,}` },
  { name: "toll-free vanity number", pattern: `(?<![a-z0-9])(?:\\+?1${SEP}?)?(?:800|833|844|855|866|877|888)[\\s.\\-]*(?:[a-z][\\s.\\-]*){7,}` },
];

// Keypad vanity number (555-CALL-NOW): three digits, a separator, then seven
// letters/digits split 3+4 or 4+3, with at least one letter somewhere.
const KEYPAD_VANITY =
  /(?<![a-z0-9])\d{3}[\s.\-]+(?:[a-z0-9]{3}[\s.\-]*[a-z0-9]{4}|[a-z0-9]{4}[\s.\-]*[a-z0-9]{3})(?![a-z0-9])/i;

const COMPILED = QR_TEXT_RULES.map((r) => ({ name: r.name, re: new RegExp(r.pattern, "i") }));

// Returns the name of the first rule the text breaks, or null when it is plain text.
export function qrTextViolation(text: string): string | null {
  const t = text.trim();
  if (t.length === 0) return null;
  for (const r of COMPILED) if (r.re.test(t)) return r.name;
  const m = KEYPAD_VANITY.exec(t);
  if (m && /[a-z]/i.test(m[0])) return "keypad vanity number";
  return null;
}
