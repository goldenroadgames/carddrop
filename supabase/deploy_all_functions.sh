#!/bin/bash
# Redeploy every edge function. sweep-deleted-cards is the only one that
# uses --no-verify-jwt (it authenticates with the cron secret instead).
# The CLI must run from the folder that CONTAINS supabase/ (the CardDrop repo root).
REF=wtclulqlwtdlecdriwsi
cd "$(dirname "$0")/.."
for f in $(ls -d supabase/functions/*/ | xargs -n1 basename | grep -v '^_shared$'); do
  [ -f "supabase/functions/$f/index.ts" ] || continue
  flags=""
  [ "$f" = "sweep-deleted-cards" ] && flags="--no-verify-jwt"
  echo "== $f"
  supabase functions deploy "$f" $flags --project-ref $REF || echo "FAILED: $f"
done
