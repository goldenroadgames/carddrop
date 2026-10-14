#!/bin/bash
# Redeploy every edge function (every folder in supabase/functions with an
# index.ts, so new functions are picked up automatically).
# --no-verify-jwt is added automatically to any function whose index.ts checks
# the cron secret header (x-cron-secret): the scheduled call carries no JWT.
# That covers sweep-deleted-cards and expire-cards, and any future cron-called
# function written the same way. NO_JWT_FUNCTIONS is for any other function that
# must be callable without a token (add its name by hand).
# The CLI must run from the folder that CONTAINS supabase/ (the CardDrop repo root).
REF=wtclulqlwtdlecdriwsi
NO_JWT_FUNCTIONS=""
cd "$(dirname "$0")/.."
failed=()
for f in $(ls -d supabase/functions/*/ | xargs -n1 basename | grep -v '^_shared$'); do
  [ -f "supabase/functions/$f/index.ts" ] || continue
  flags=""
  case " $NO_JWT_FUNCTIONS " in *" $f "*) flags="--no-verify-jwt" ;; esac
  if grep -q "x-cron-secret" "supabase/functions/$f/index.ts"; then flags="--no-verify-jwt"; fi
  echo ""
  echo "##############################################################"
  echo "#  DEPLOYING: $f"
  echo "##############################################################"
  if supabase functions deploy "$f" $flags --project-ref $REF; then
    echo "----- OK: $f -----"
  else
    echo "!!!!! FAILED: $f !!!!!"
    failed+=("$f")
  fi
done

echo ""
echo "=============================================================="
if [ ${#failed[@]} -eq 0 ]; then
  echo "  ALL FUNCTIONS DEPLOYED"
else
  echo "  FAILED (${#failed[@]}): ${failed[*]}"
  echo "  Redeploy one with:"
  echo "    supabase functions deploy <name> --project-ref $REF"
fi
echo "=============================================================="
