#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 [path-to-payloads]" >&2
  echo "Default payload path: scripts/locale_payloads" >&2
  echo "Env: CF_API_KEY (required), CURSEFORGE_PROJECT_ID (default 1076354)," >&2
  echo "     MISSING_PHRASE_HANDLING (default DeletePhrase)" >&2
  exit 1
}

payload_dir="${1:-scripts/locale_payloads}"
project_id="${CURSEFORGE_PROJECT_ID:-1076354}"
missing_handling="${MISSING_PHRASE_HANDLING:-DeletePhrase}"

[ -z "${1:-}" ] || [ "$1" != "-h" ] || usage
[ -d "$payload_dir" ] || { echo "Payload directory not found: $payload_dir" >&2; exit 1; }

cf_token=${CF_API_KEY:-}
if [ -z "$cf_token" ] && [ -f ".env" ]; then
  # shellcheck disable=SC1091
  . ".env"
  cf_token=${CF_API_KEY:-$cf_token}
fi

if [ -z "$cf_token" ]; then
  echo "CF_API_KEY is required (set it directly or via .env with op read)." >&2
  exit 1
fi

import_locale() {
  local lang="$1"
  local namespace="$2"
  local file="$3"

  local cf_namespace="$namespace"
  case "$cf_namespace" in
    ""|"base"|"core"|"EnhanceQoL")
      cf_namespace=""
      ;;
  esac

  local metadata
  metadata=$(printf '{ language: "%s", namespace: "%s", }' "$lang" "$cf_namespace")

  local tempfile cleanfile
  tempfile=$(mktemp)
  cleanfile=$(mktemp)
  sed -n '/L\["/,$p' "$file" > "$cleanfile"

  printf "Uploading %-5s %-12s ... " "$lang" "${namespace:-root}"
  local result
  result=$(curl -sS -0 -X POST -w "%{http_code}" -o "$tempfile" \
    -H "X-Api-Token: $cf_token" \
    -F "metadata=$metadata" \
    -F "localizations=<$cleanfile" \
    "https://legacy.curseforge.com/api/projects/$project_id/localization/import" \
  ) || { echo "curl failed"; rm -f "$tempfile" "$cleanfile"; exit 1; }

  case "$result" in
    200) echo "done." ;;
    *)
      echo "error ($result)"
      if [ -s "$tempfile" ]; then
        if command -v jq >/dev/null 2>&1; then
          jq -r '.errorMessage // .message // empty' "$tempfile"
        else
          cat "$tempfile"
        fi
      fi
      rm -f "$tempfile" "$cleanfile"
      exit 1
      ;;
  esac

  rm -f "$tempfile" "$cleanfile"
}

shopt -s nullglob
found=0
for lang_dir in "$payload_dir"/*; do
  [ -d "$lang_dir" ] || continue
  lang=$(basename "$lang_dir")

  files=( "$lang_dir"/* )
  if [ "${#files[@]}" -eq 0 ]; then
    echo "No locale files in $lang_dir, skipping." >&2
    continue
  fi

  for file in "${files[@]}"; do
    [ -f "$file" ] || continue
    namespace=$(basename "$file")
    namespace="${namespace%.*}"
    import_locale "$lang" "$namespace" "$file"
    found=1
  done
done

if [ "$found" -eq 0 ]; then
  echo "No locale files found under $payload_dir" >&2
  exit 1
fi
