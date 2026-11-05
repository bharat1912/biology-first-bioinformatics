#!/usr/bin/env bash
# Biology-First workstation path setup.
# Usage: bash setup_biology_first.sh [--reset]
# Configure exactly two user-selected roots: PROJECTS and DATABASES.
# Never moves or deletes biological data or reference databases.

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  printf 'Run this script, do not source it: bash setup_biology_first.sh [--reset]\n' >&2
  return 1
fi
set -euo pipefail

usage() { printf 'Usage: bash %s [--reset]\n' "${0##*/}"; }
RESET=0
case "${1:-}" in
  '') ;;
  --reset) RESET=1 ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
if (( $# > 1 )); then usage >&2; exit 2; fi

BASHRC="$HOME/.bashrc"
NEW_START='# >>> Biology-First paths (setup_biology_first.sh) >>>'
NEW_END='# <<< Biology-First paths (setup_biology_first.sh) <<<'
OLD_START='# --- Biology-First — set once by setup_biology_first.sh ---'
OLD_END='# --- end Biology-First block ---'

# Only manage blocks from this script, never edit unrelated shell configuration.
if [[ -e "$BASHRC" && ! -f "$BASHRC" ]]; then
  echo "~/.bashrc exists but is not a regular file. No changes made." >&2
  exit 1
fi
[[ -e "$BASHRC" ]] || : > "$BASHRC"
count_start=$(grep -Fxc "$NEW_START" "$BASHRC" || true)
count_end=$(grep -Fxc "$NEW_END" "$BASHRC" || true)
old_start=$(grep -Fxc "$OLD_START" "$BASHRC" || true)
old_end=$(grep -Fxc "$OLD_END" "$BASHRC" || true)
if (( count_start > 1 || count_end > 1 || old_start > 1 || old_end > 1 )) || \
   (( count_start != count_end || old_start != old_end )) || \
   (( count_start && old_start )); then
  printf 'Ambiguous or incomplete Biology-First settings in %s. No changes made.\n' "$BASHRC" >&2
  exit 1
fi
HAS_BLOCK=0
if (( count_start == 1 || old_start == 1 )); then HAS_BLOCK=1; fi
if (( HAS_BLOCK && ! RESET )); then
  echo "Biology-First paths are already configured in $BASHRC."
  echo 'To change them, use: bash setup_biology_first.sh --reset'
  exit 0
fi
# Check for assignments outside BOTH current and legacy managed blocks.
# This applies to initial setup and --reset: a later external assignment could shadow our settings.
EXTERNAL_ASSIGNMENTS=$(awk -v ns="$NEW_START" -v ne="$NEW_END" -v os="$OLD_START" -v oe="$OLD_END" '
  $0 == ns || $0 == os { inside = 1; next }
  $0 == ne || $0 == oe { inside = 0; next }
  !inside && /^[[:space:]]*(export[[:space:]]+)?(BIOLOGY_FIRST_BASE|BIOLOGY_FIRST_PROJECT_ROOT|BIOLOGY_FIRST_DB_ROOT|BIOLOGY_FIRST_PROJECTS_ROOT|PROJECT_ROOT|EXTERNAL_VAULT|VAULT_ROOT)=/ { print NR ": " $0 }
' "$BASHRC")
if [[ -n "$EXTERNAL_ASSIGNMENTS" ]]; then
  printf 'Conflicting path assignments exist OUTSIDE the managed Biology-First block in %s:\n%s\n' "$BASHRC" "$EXTERNAL_ASSIGNMENTS" >&2
  printf 'Please review these lines before setup/reset. Nothing has been changed.\n' >&2
  exit 1
fi

normalise_path() {
  local val="$1"
  if [[ "$val" == '~/'* ]]; then val="$HOME/${val:2}"; fi
  if [[ "$val" != /* || "$val" == '/' || "$val" == *$'\n'* ]]; then return 1; fi
  realpath -m -- "$val"
}

get_root() {
  local answer norm
  while :; do
    read -r -p "$1" answer || { echo 'Input cancelled.' >&2; exit 1; }
    if [[ -z "$answer" ]]; then echo 'Please enter a full absolute path (or ~/...).'; continue; fi
    if ! norm=$(normalise_path "$answer"); then
      echo 'Enter an absolute directory path, not a relative path.'; continue
    fi
    printf '%s' "$norm"
    return 0
  done
}

# Prevent accidentally creating paths beneath an unmounted /media/<user>/<drive>.
check_media_mount() {
  local p="$1" expected
  if [[ "$p" =~ ^/media/[^/]+/([^/]+)(/|$) ]]; then
    expected="/media/$(cut -d/ -f3-4 <<< "$p")"
    # The exact media mount directory must be mounted, not merely its parent.
    if ! command -v mountpoint >/dev/null 2>&1 || ! mountpoint -q "$expected"; then
      printf 'Storage location %s is not mounted. No changes made.\n' "$expected" >&2
      return 1
    fi
  fi
}

printf '\nBiology-First workstation setup: choose TWO storage locations.\n'
printf 'Existing data are never moved or deleted.\n\n'
if (( RESET )); then
  echo 'RESET will replace only the managed Biology-First settings in ~/.bashrc.'
  echo 'It will not modify any existing project or reference-database files.'
  echo ''
fi
PROJECTS=$(get_root 'PROJECTS directory (e.g. /media/yourname/volume2/projects): ')
DATABASES=$(get_root 'DATABASES directory (e.g. /media/yourname/volume1/databases): ')
if [[ "$PROJECTS" == "$DATABASES" || "$PROJECTS" == "$DATABASES/"* || "$DATABASES" == "$PROJECTS/"* ]]; then
  echo 'Projects and databases must be separate, non-nested directories. No changes made.' >&2
  exit 1
fi
check_media_mount "$PROJECTS"
check_media_mount "$DATABASES"
printf '\nPROJECTS:  %s\nDATABASES: %s\n' "$PROJECTS" "$DATABASES"
read -r -p 'Save these paths to ~/.bashrc? [y/N]: ' CONFIRM || exit 1
case "$CONFIRM" in y|Y|yes|YES) ;; *) echo 'Cancelled. No changes made.'; exit 0 ;; esac

# Validate/create directories BEFORE editing ~/.bashrc.
# mkdir -p does not overwrite data in an existing directory.
mkdir -p -- "$PROJECTS" "$DATABASES"
[[ -d "$PROJECTS" && -w "$PROJECTS" ]] || { echo 'Projects directory is not writable.' >&2; exit 1; }
[[ -d "$DATABASES" && -w "$DATABASES" ]] || { echo 'Databases directory is not writable.' >&2; exit 1; }

umask 077
TMP=$(mktemp "${BASHRC}.biology-first.XXXXXX")
trap 'rm -f -- "$TMP"' EXIT
# Preserve all unrelated .bashrc content, removing only a recognised old/new block.
awk -v ns="$NEW_START" -v ne="$NEW_END" -v os="$OLD_START" -v oe="$OLD_END" '
  $0 == ns || $0 == os { hiding = 1; next }
  $0 == ne || $0 == oe { hiding = 0; next }
  !hiding { print }
' "$BASHRC" > "$TMP"
{
  echo ''
  echo "$NEW_START"
  printf 'export BIOLOGY_FIRST_PROJECT_ROOT=%q\n' "$PROJECTS"
  printf 'export BIOLOGY_FIRST_DB_ROOT=%q\n' "$DATABASES"
  echo '# Legacy aliases for existing ecosystem scripts:'
  echo 'export BIOLOGY_FIRST_PROJECTS_ROOT="$BIOLOGY_FIRST_PROJECT_ROOT"'
  echo 'export PROJECT_ROOT="$BIOLOGY_FIRST_PROJECT_ROOT"'
  echo 'export EXTERNAL_VAULT="$BIOLOGY_FIRST_DB_ROOT"'
  echo "$NEW_END"
} >> "$TMP"
# Keep .bashrc permissions and make a dated backup before replacing.
chmod --reference="$BASHRC" "$TMP"
BACKUP=$(mktemp "${BASHRC}.biology-first-backup.$(date +%Y%m%d_%H%M%S).XXXXXX")
cp -p -- "$BASHRC" "$BACKUP"
mv -f -- "$TMP" "$BASHRC"
trap - EXIT
printf '\nSaved. Previous ~/.bashrc backed up to %s\n' "$BACKUP"
echo 'Open a new terminal, or run: source ~/.bashrc'
echo 'Verify with: echo "$BIOLOGY_FIRST_PROJECT_ROOT" "$BIOLOGY_FIRST_DB_ROOT"'
echo 'If another shell startup file changes these variables later, inspect that file separately.'
echo 'To change the chosen paths later: bash setup_biology_first.sh --reset'
echo 'Reset does NOT move projects, databases, or repair existing db_link symlinks.'
echo 'Historical results-vault scripts may require their own configuration; this script configures only the two storage roots.'