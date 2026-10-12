import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// zz_config.terms_required_version (YYYY-MM-DD); missing or malformed = no
// requirement.
export async function requiredTermsVersion(supabase: SupabaseClient): Promise<string | null> {
  const { data } = await supabase
    .from("zz_config")
    .select("value")
    .eq("key", "terms_required_version")
    .maybeSingle();
  const v = (data?.value ?? "").trim();
  return /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null;
}

// True when the user has accepted a Terms version at least as new as the
// required one (string comparison is correct for YYYY-MM-DD).
export async function termsAccepted(supabase: SupabaseClient, userId: string): Promise<boolean> {
  const required = await requiredTermsVersion(supabase);
  if (!required) return true;
  const { data } = await supabase.from("users").select("terms_version").eq("id", userId).maybeSingle();
  const accepted = data?.terms_version ?? "";
  return accepted >= required;
}

const MONTHS = ["january", "february", "march", "april", "may", "june", "july",
  "august", "september", "october", "november", "december"];

// Reads the "*Last updated: 12 October 2026*" line of the live Terms text in
// the public `legal` bucket and returns it as YYYY-MM-DD, or null.
export async function liveTermsVersion(supabase: SupabaseClient): Promise<string | null> {
  const { data, error } = await supabase.storage.from("legal").download("terms-of-service.md");
  if (error || !data) return null;
  const text = await data.text();
  const m = text.match(/Last updated:\s*(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})/);
  if (!m) return null;
  const month = MONTHS.indexOf(m[2].toLowerCase()) + 1;
  if (month < 1) return null;
  return `${m[3]}-${String(month).padStart(2, "0")}-${m[1].padStart(2, "0")}`;
}
