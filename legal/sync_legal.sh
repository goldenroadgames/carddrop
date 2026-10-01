#!/bin/bash
# Re-uploads the local Terms of Service and Privacy Policy to the Supabase
# "legal" storage bucket, overwriting whatever's live there.
#
# `supabase storage cp` refuses to overwrite an existing object (409
# KeyAlreadyExists), so each file is removed first, then re-uploaded.
#
# Run this from anywhere — it cd's into the project root (the folder holding
# supabase/, one level above the CardDrop git repo) itself.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

FILES=(
  "CardDrop/legal/TERMS_OF_SERVICE.md:terms-of-service.md"
  "CardDrop/legal/PRIVACY_POLICY.md:privacy-policy.md"
)

for entry in "${FILES[@]}"; do
  local_path="${entry%%:*}"
  bucket_name="${entry##*:}"

  echo "Syncing ${local_path} -> legal/${bucket_name}"
  supabase storage rm "ss:///legal/${bucket_name}" --experimental --yes >/dev/null 2>&1 || true
  supabase storage cp "${local_path}" "ss:///legal/${bucket_name}" --experimental
done

echo "Done. Verifying..."
curl -sI "https://wtclulqlwtdlecdriwsi.supabase.co/storage/v1/object/public/legal/terms-of-service.md" | grep -i last-modified
curl -sI "https://wtclulqlwtdlecdriwsi.supabase.co/storage/v1/object/public/legal/privacy-policy.md" | grep -i last-modified
