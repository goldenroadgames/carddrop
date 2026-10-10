// Normalizes a street + zip into a stable key, then hashes it, so the same
// physical address typed slightly differently ("123 Main Street Apt 2" vs
// "123 main st #2") matches. Unit/apartment is deliberately ignored: the
// block is on the building address. Returns null if there is not enough to
// match on (e.g. a scrubbed order).

const SUFFIX: Record<string, string> = {
  street: "st", st: "st", avenue: "ave", ave: "ave", av: "ave", road: "rd", rd: "rd",
  drive: "dr", dr: "dr", lane: "ln", ln: "ln", boulevard: "blvd", blvd: "blvd",
  court: "ct", ct: "ct", circle: "cir", cir: "cir", place: "pl", pl: "pl",
  terrace: "ter", ter: "ter", parkway: "pkwy", pkwy: "pkwy", highway: "hwy", hwy: "hwy",
  trail: "trl", trl: "trl",
};

const DIRECTION: Record<string, string> = {
  north: "n", n: "n", south: "s", s: "s", east: "e", e: "e", west: "w", w: "w",
  northeast: "ne", ne: "ne", northwest: "nw", nw: "nw", southeast: "se", se: "se",
  southwest: "sw", sw: "sw",
};

const UNIT_WORDS = new Set([
  "apt", "apartment", "unit", "ste", "suite", "fl", "floor", "bldg", "building", "rm", "room",
]);

export function addressKey(street?: string | null, zip?: string | null): string | null {
  if (!street || !zip) return null;
  const zip5 = zip.replace(/\D/g, "").slice(0, 5);
  if (zip5.length < 5) return null;

  const tokens = street
    .toLowerCase()
    .replace(/#/g, " # ")
    .replace(/[.,]/g, " ")
    .split(/\s+/)
    .filter(Boolean);

  const kept: string[] = [];
  for (const t of tokens) {
    if (t === "#" || UNIT_WORDS.has(t)) break; // everything after a unit marker is the unit
    kept.push(DIRECTION[t] ?? SUFFIX[t] ?? t);
  }
  if (kept.length < 2) return null;
  return `${kept.join(" ")}|${zip5}`;
}

export async function addressHash(street?: string | null, zip?: string | null): Promise<string | null> {
  const key = addressKey(street, zip);
  if (!key) return null;
  const bytes = new TextEncoder().encode(key);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
