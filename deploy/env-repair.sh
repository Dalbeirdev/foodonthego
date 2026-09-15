#!/usr/bin/env bash
#
# Repair a .env that has stopped parsing, without losing what is in it.
#
# WHY THIS IS A SCRIPT. It has happened twice: a key or token printed in one
# command, a `>> .env` append in the next, and the paste lands in the wrong one.
# The pasted lines are not `NAME=value`, so compose stops on the first of them
# and every command fails at once — including the ones that would say why.
#
# The temptation then is to delete the file and start again. That is how a
# review deployment loses its database: DB_PASSWORD is what makes the existing
# MySQL volume readable, and a fresh one does not open an old volume.
#
# So this keeps comments, blank lines and proper assignments, drops everything
# else, and refuses to leave you with a file that is missing something it needs.

set -uo pipefail
cd "$(dirname "$0")"

REQUIRED=(APP_ENV APP_KEY DB_PASSWORD DB_ROOT_PASSWORD DB_DATABASE DB_USERNAME)

[ -f .env ] || { echo "No .env here. Nothing to repair — copy .env.example and fill it in."; exit 1; }

BACKUP=".env.broken.$(date +%Y%m%d-%H%M%S).bak"
cp .env "$BACKUP"

awk '/^[[:space:]]*#/ || /^[[:space:]]*$/ || /^[A-Za-z_][A-Za-z0-9_]*=/' "$BACKUP" > .env.repaired

# Checked BEFORE the repaired file is put in place. A repair that quietly
# dropped DB_PASSWORD would be worse than the breakage it fixed, and finding
# that out after the move means restoring from a backup under pressure.
missing=()
for k in "${REQUIRED[@]}"; do
  grep -q "^${k}=" .env.repaired || missing+=("$k")
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "REFUSING TO REPAIR — these would be lost: ${missing[*]}"
  echo "Your .env is untouched. The candidate is in .env.repaired; the backup is $BACKUP."
  echo "Most likely the assignment itself was mangled, not just appended to."
  exit 1
fi

mv .env.repaired .env

echo "Repaired. Kept:"
for k in "${REQUIRED[@]}"; do printf '  %-18s ok\n' "$k"; done

leaked=$(grep -c 'PRIVATE KEY' .env || true)
echo "  lines mentioning PRIVATE KEY: $leaked (want 0)"

if docker compose config >/dev/null 2>&1; then
  echo "  compose parses it: yes"
else
  echo "  compose parses it: NO — something else is wrong; run: docker compose config"
fi

# The backup holds whatever was pasted, which is the whole reason it broke.
if command -v shred >/dev/null 2>&1; then shred -u "$BACKUP"; else rm -f "$BACKUP"; fi
echo "  backup shredded (it held whatever was pasted in)"

cat <<'NOTE'

If what leaked was an SSH key, check it is not also authorising logins:

  grep -c 'github-actions deploy' ~/.ssh/authorized_keys    # want 0
NOTE
