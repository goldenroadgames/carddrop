// Word blocklist (profanity). The word list lives in zz_config
// (moderation_blocklist, comma separated) and is read by moderation.ts.
//
// Matching rules:
//  - Whole words only ("pussycat", "class" are fine). A word is a run of letters
//    and digits; punctuation, spaces and the edges of the text end it.
//  - Case-insensitive. Swaps: @ a, $ s, 1 ! i, 0 o, 3 e, 5 s, 4 a.
//  - Any symbol inside a word (@ $ # % & + ^ ~ = ? ! *) can also stand for one
//    letter: "f@ck", "f#ck", "sh!t". Each word is tried with the swaps and
//    with every symbol as a wildcard.
//  - Stretched letters match: "fuuuck". A doubled letter in the list word
//    ("ass") needs at least two in the text, so "as" is not "ass".
//  - A wildcard stands for exactly one letter: "f*ck", "f**k", "sh*t". At least
//    two real letters must remain.
//  - Dots, dashes and underscores inside a word are ignored: "f-ck", "f.u.c.k".
//  - Single letters separated by spaces, dots or dashes ("f u c k", "a s s")
//    match.
//  - 2 or 3 neighbouring pieces separated by spaces, dots, dashes or underscores,
//    at least one of them 1-2 characters long, are joined and must then equal
//    a list word exactly: "fu ck", "fuc k",
//    "f u ck". "as special" joins to "asspecial", which is not a list word.
//  - An apostrophe ends a word and never joins ("who're" is not "whore").
//  - Missing-vowel spellings ("fck", "sht") are NOT derived: list them.

const SWAPS: Record<string, string> = { "@": "a", "$": "s", "1": "i", "!": "i", "0": "o", "3": "e", "5": "s", "4": "a" };

type Entry = { word: string; re: RegExp };
export type Blocklist = Entry[];

export function compileBlocklist(raw: string): Blocklist {
  const words = Array.from(
    new Set(raw.toLowerCase().split(/[,\n]+/).map((w) => w.trim()).filter((w) => /^[a-z]{2,}$/.test(w))),
  );
  return words.map((word) => ({
    word,
    re: new RegExp(
      "^" + word.replace(/(.)\1*/g, (run, c) => (run.length === 1 ? `${c}+` : `${c}{${run.length},}`)) + "$",
    ),
  }));
}

// Symbols that can stand for a letter inside a word.
const SYMBOL_RE = /[@$*#%&+^~=?!]/g;
const DIGIT_SWAPS = /[10354]/g;

// Swaps first (@ a, $ s, ! i, digits), every other symbol becomes a wildcard.
function viaSwaps(s: string): string {
  return s.replace(/[@$1!0354]/g, (c) => SWAPS[c]).replace(SYMBOL_RE, "*");
}

// Every symbol is a wildcard; digits still swap.
function viaWildcards(s: string): string {
  return s.replace(SYMBOL_RE, "*").replace(DIGIT_SWAPS, (c) => SWAPS[c]);
}

function matchesList(candidate: string, list: Blocklist): boolean {
  const a = viaSwaps(candidate);
  return matchesNormalized(a, list) || (candidate !== a && matchesNormalized(viaWildcards(candidate), list));
}

function matchesNormalized(c: string, list: Blocklist): boolean {
  if (c.length < 2) return false;
  if (!c.includes("*")) return list.some((e) => e.re.test(c));
  if (c.replace(/\*/g, "").length < 2) return false;
  return list.some(
    (e) => e.word.length === c.length && [...c].every((ch, i) => ch === "*" || ch === e.word[i]),
  );
}

function matchesEither(candidate: string, list: Blocklist): boolean {
  if (matchesList(candidate, list)) return true;
  const stripped = candidate.replace(/^[@$*#%&+^~=?!]+|[@$*#%&+^~=?!]+$/g, "");
  return stripped !== candidate && stripped.length > 0 && matchesList(stripped, list);
}

export function hasBlockedWord(text: string, list: Blocklist): boolean {
  if (list.length === 0) return false;
  const lower = text.toLowerCase();

  // Whole words, with separators inside a word (. - _ / etc.) ignored or
  // splitting it. An apostrophe only splits.
  for (const chunk of lower.split(/\s+/)) {
    for (const sub of chunk.split(/['\u2019]/)) {
      const core = sub.replace(/^[^a-z0-9@$*#%&+^~=]+|[^a-z0-9@$*#%&+^~=]+$/g, "");
      if (!core) continue;
      const parts = core.split(/[^a-z0-9@$*#%&+^~=?!]+/).filter(Boolean);
      const candidates = new Set<string>(parts);
      candidates.add(parts.join(""));
      for (const c of candidates) if (matchesEither(c, list)) return true;
    }
  }

  // 2 or 3 neighbouring pieces joined: "fu ck", "fuc k", "f u ck". Interior
  // pieces must be plain; only the outer edges may carry punctuation.
  const clean = /^[a-z0-9@$*#%&+^~=?!]+$/;
  const tokens = lower.split(/[\s.\-_]+/).filter(Boolean);
  for (let i = 0; i < tokens.length - 1; i++) {
    for (let len = 2; len <= 3 && i + len <= tokens.length; len++) {
      const pieces = tokens.slice(i, i + len);
      pieces[0] = pieces[0].replace(/^[^a-z0-9@$*#%&+^~=]+/, "");
      pieces[len - 1] = pieces[len - 1].replace(/[^a-z0-9@$*#%&+^~=]+$/, "");
      if (!pieces.some((p) => p.length <= 2)) continue; // at least one 1-2 character piece
      if (pieces.every((p) => clean.test(p)) && matchesEither(pieces.join(""), list)) return true;
    }
  }

  // Single letters spaced out: "f u c k", "f.u.c.k".
  const runRe = /(?<![a-z0-9@$*#%&+^~=])[a-z0-9@$*#%&+^~=](?:[\s.\-_]+[a-z0-9@$*#%&+^~=])+(?![a-z0-9@$*#%&+^~=])/g;
  for (const m of lower.matchAll(runRe)) {
    const chars = [...m[0].replace(/[\s.\-_]+/g, "")].slice(0, 200);
    for (let i = 0; i < chars.length - 1; i++) {
      for (let j = i + 2; j <= Math.min(chars.length, i + 12); j++) {
        if (matchesEither(chars.slice(i, j).join(""), list)) return true;
      }
    }
  }
  return false;
}
