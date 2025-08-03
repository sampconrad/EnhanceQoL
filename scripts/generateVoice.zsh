#!/bin/zsh
###############################################################################
#  tts2ogg.zsh – liest wordlist.txt im selben Ordner ein; jede Zeile ist
#  Text;speed;pitch;filename;icon  (speed, pitch, filename, icon optional; # startet Kommentar)
#  Skript konvertiert jede Zeile direkt zu OGG via ffmpeg, überspringt vorhandene Dateien und hängt das optionale Icon an die LSM‑Registrierung an.
###############################################################################

VOICE="Karen (Premium)"
DEFAULT_RATE=150                       # Wörter pro Minute
DEFAULT_PITCH="[[pbas -30]]"           # –30 Cent Grundton­absenkung
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIST="$SCRIPT_DIR/wordlist.txt"
DEST="/Volumes/T7 Shield/Git/WoWAddons/Raizor/EnhanceQoLSharedMedia/Sounds/Voiceovers"
PATHW='voiceoverPath'
VOLUME_GAIN_DB=5            # Lautstärkeanhebung in dB (positiv = lauter, negativ = leiser)
mkdir -p "$DEST"
# ---------- 1) Text-to-Speech -------------------------------------------------
while IFS=';' read -r WORD SPEED PITCH FNAME ICON PNAME || [[ -n "$WORD" ]]; do
  [[ -z "$WORD" ]] && continue          # leere Zeilen überspringen
  [[ "$WORD" == \#* ]] && continue      # Kommentarzeilen überspringen

  RATE_LOCAL="${SPEED:-$DEFAULT_RATE}"
  PITCH_LOCAL="${PITCH:-$DEFAULT_PITCH}"
  BASENAME="${FNAME:-${WORD// /_}}"
  ICON_SUFFIX="${ICON:-}"
  NAME_PREFIX="${PNAME:-}"

  OUT="$DEST/${BASENAME}.aiff"
  OGG="$DEST/${BASENAME}.ogg"

  # Falls die .ogg bereits existiert → überspringen
  if [[ -e "$OGG" ]]; then
    #printf 'Skipping existing file: %s\n' "$OGG"
    continue
  fi

  # Quotes im Pitch-Tag entfernen, falls vorhanden
  PITCH_CLEAN="${PITCH_LOCAL//\"/}"

  # 1) AIFF mit say erzeugen
  say -v "$VOICE" -r "$RATE_LOCAL" -o "$OUT" "${PITCH_CLEAN}${WORD}"

  # 2) AIFF -> OGG konvertieren
  ffmpeg -loglevel error -y -i "$OUT" -af "volume=${VOLUME_GAIN_DB}dB" -c:a libvorbis -q:a 4 "$OGG"

  KEY_NAME="${WORD//\"/\\\"}"
  LABEL_NAME="$NAME_PREFIX$BASENAME"
  if [[ -n "$ICON_SUFFIX" ]]; then
    LABEL_NAME="|cFF000000|r${LABEL_NAME} ${ICON_SUFFIX}"
  fi
  LABEL_ESCAPED="${LABEL_NAME//\"/\\\"}"

  printf '{ key = "%s", label = "EQOL: %s", path = %s .. "%s.ogg" },\n' "$KEY_NAME" "$LABEL_ESCAPED" "$PATHW" "$BASENAME"
  # Optional: AIFF löschen, damit nur OGG übrig bleibt
  rm "$OUT"
done < "$LIST"