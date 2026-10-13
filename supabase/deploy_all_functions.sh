#!/bin/bash
# Redeploy every edge function (every folder in supabase/functions with an
# index.ts, so new functions are picked up automatically).
# NO_JWT_FUNCTIONS: functions deployed with --no-verify-jwt because their
# callers send no login token. Add a name here for any new function like that.
# sweep-deleted-cards authenticates with the cron secret instead.
# The CLI must run from the folder that CONTAINS supabase/ (the CardDrop repo root).
REF=wtclulqlwtdlecdriwsi
NO_JWT_FUNCTIONS="sweep-deleted-cards"
cd "$(dirname "$0")/.."
failed=()
for f in $(ls -d supabase/functions/*/ | xargs -n1 basename | grep -v '^_shared$'); do
  [ -f "supabase/functions/$f/index.ts" ] || continue
  flags=""
  case " $NO_JWT_FUNCTIONS " in *" $f "*) flags="--no-verify-jwt" ;; esac
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
