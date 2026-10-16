// Word blocklist (profanity). The word list lives in zz_config
// (moderation_blocklist, comma separated) and is read by moderation.ts.
//
// Matching rules:
//  - Whole words only ("pussycat", "class" are fine). A word is a run of letters
//    and digits; punctuation, spaces and the edges of the text end it.
//  - Case-insensitive. Swaps: @ a, $ s, 1 ! i, 0 o, 3 e, 5 s, 4 a.
//  - Stretched letters match: "fuuuck". A doubled letter in the list word
//    ("ass") needs at least two in the text, so "as" is not "ass".
//  - A "*" inside a word stands for exactly one letter: "f*ck", "f**k", "sh*t".
//    At least two real letters must remain.
//  - Dots, dashes and underscores inside a word are ignored: "f-ck", "f.u.c.k".
//  - Single letters separated by spaces, dots or dashes ("f u c k", "a s s")
//    match; whole words next to each other ("as special") never join.
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

function normalize(s: string): string {
  return s.replace(/[@$1!0354]/g, (c) => SWAPS[c]);
}

function matchesList(candidate: string, list: Blocklist): boolean {
  const c = normalize(candidate);
  if (c.length < 2) return false;
  if (!c.includes("*")) return list.some((e) => e.re.test(c));
  if (c.replace(/\*/g, "").length < 2) return false;
  return list.some(
    (e) => e.word.length === c.length && [...c].every((ch, i) => ch === "*" || ch === e.word[i]),
  );
}

function matchesEither(candidate: string, list: Blocklist): boolean {
  if (matchesList(candidate, list)) return true;
  const stripped = candidate.replace(/^\*+|\*+$/g, "");
  return stripped !== candidate && stripped.length > 0 && matchesList(stripped, list);
}

export function hasBlockedWord(text: string, list: Blocklist): boolean {
  if (list.length === 0) return false;
  const lower = text.toLowerCase();

  // Whole words, with separators inside a word (. - _ ') ignored or splitting it.
  for (const chunk of lower.split(/\s+/)) {
    const core = chunk.replace(/^[^a-z0-9@$*]+|[^a-z0-9@$*]+$/g, "");
    if (!core) continue;
    const parts = core.split(/[^a-z0-9@$*!]+/).filter(Boolean);
    const candidates = new Set<string>(parts);
    candidates.add(parts.join(""));
    for (const c of candidates) if (matchesEither(c, list)) return true;
  }

  // Single letters spaced out: "f u c k", "f.u.c.k".
  const runRe = /(?<![a-z0-9@$*])[a-z0-9@$*](?:[\s.\-_]+[a-z0-9@$*])+(?![a-z0-9@$*])/g;
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
