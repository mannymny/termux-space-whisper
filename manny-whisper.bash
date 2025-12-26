#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

URL="${1:-}"
T_IN="${2:-${THREADS:-}}"

if [ -z "$URL" ]; then
  echo "Usage: manny-whisper https://x.com/i/spaces/ID [threads]"
  echo "Example: manny-whisper https://x.com/i/spaces/1eaKbjdnlqaKX 6"
  echo "Or: THREADS=6 manny-whisper https://x.com/i/spaces/ID"
  exit 1
fi

DEST="$HOME/storage/downloads/yt-dlp"
mkdir -p "$DEST"

W="$HOME/whisper.cpp"
BIN="$W/build/bin/whisper-cli"
MODEL="${MODEL:-$W/models/ggml-base.bin}"

if [ ! -x "$BIN" ]; then
  echo "Error: whisper binary not found or not executable: $BIN"
  exit 1
fi

if [ ! -f "$MODEL" ]; then
  echo "Error: model file not found: $MODEL"
  exit 1
fi

# Threads
MAX_THREADS="$(nproc)"
THREADS="${T_IN:-$MAX_THREADS}"

if ! echo "$THREADS" | grep -qE '^[0-9]+$' || [ "$THREADS" -lt 1 ]; then
  echo "Error: invalid threads value: $THREADS (must be an integer >= 1)"
  exit 1
fi

if [ "$THREADS" -gt "$MAX_THREADS" ]; then
  echo "Note: this device reports $MAX_THREADS threads; using THREADS=$MAX_THREADS"
  THREADS="$MAX_THREADS"
fi

# Download
yt-dlp --no-playlist \
  -N 8 --concurrent-fragments 8 \
  -x --audio-format m4a \
  --restrict-filenames \
  -o "$DEST/%(title).200B_%(id)s.%(ext)s" \
  "$URL"

AUDIO="$(ls -t "$DEST"/*.m4a 2>/dev/null | head -n 1 || true)"
if [ -z "${AUDIO:-}" ]; then
  echo "Error: could not find downloaded audio (.m4a) in: $DEST"
  exit 1
fi

# Duration helpers
TOTAL_SEC="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO" \
  | awk '{printf("%d\n",$1+0.5)}')"
TOTAL_MIN=$(( (TOTAL_SEC + 59) / 60 ))
TOTAL_MMSS="$(awk -v s="$TOTAL_SEC" 'BEGIN{m=int(s/60); ss=s%60; printf "%d:%02d", m, ss}')"

SAFE="$(basename "$AUDIO" | sed 's/[^A-Za-z0-9._-]/_/g')"
OUT="$DEST/${SAFE%.*}_minuta_1min.txt"
LOG="$DEST/${SAFE%.*}_whisper.log"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

WAV="$TMPDIR/in.wav"

echo "Converting to 16kHz mono WAV..."
ffmpeg -loglevel error -y -i "$AUDIO" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$WAV"

# Build EXTRA flags based on what's supported by your whisper-cli
EXTRA=()
HELP="$("$BIN" -h 2>&1 || true)"

# Keep your old optional flags if present
echo "$HELP" | grep -qE '(^|[[:space:]])-bs([[:space:]]|,)' && EXTRA+=(-bs 1)
echo "$HELP" | grep -qE '(^|[[:space:]])-bo([[:space:]]|,)' && EXTRA+=(-bo 1)

# --- anti-hallucination / VAD (if supported) ---
# Tune via env vars if needed
VAD_THOLD="${VAD_THOLD:-0.7}"       # 0.6–0.8 typical: higher = more aggressive VAD
VAD_MS="${VAD_MS:-250}"             # VAD window in ms
NO_SPEECH="${NO_SPEECH:-0.6}"       # if supported
LOGPROB="${LOGPROB:--1.0}"          # if supported (more strict if higher)

echo "$HELP" | grep -qE '(^|[[:space:]])--vad-thold([[:space:]]|,)'       && EXTRA+=(--vad-thold "$VAD_THOLD")
echo "$HELP" | grep -qE '(^|[[:space:]])--vad-ms([[:space:]]|,)'          && EXTRA+=(--vad-ms "$VAD_MS")
echo "$HELP" | grep -qE '(^|[[:space:]])--no-speech-thold([[:space:]]|,)' && EXTRA+=(--no-speech-thold "$NO_SPEECH")
echo "$HELP" | grep -qE '(^|[[:space:]])--logprob-thold([[:space:]]|,)'   && EXTRA+=(--logprob-thold "$LOGPROB")

echo "Transcribing with $THREADS threads..."
echo "Progress will update as segments are produced..."
echo "Whisper log: $LOG"

# Run whisper, keep stdout for parsing, put stderr in a log
"$BIN" -m "$MODEL" -f "$WAV" -l es -t "$THREADS" "${EXTRA[@]}" 2>"$LOG" \
| awk -v total_min="$TOTAL_MIN" -v total_sec="$TOTAL_SEC" -v total_mmss="$TOTAL_MMSS" '
function hhmmss(sec,  h,m,s){
  h=int(sec/3600); m=int((sec%3600)/60); s=sec%60;
  return sprintf("%02d:%02d:%02d", h, m, s);
}
function mmss(sec,  m,s){
  m=int(sec/60); s=sec%60;
  return sprintf("%d:%02d", m, s);
}
BEGIN{
  print "Duration: " total_mmss;
  print "";
  last_pct = -1;
  last_done = 0;
  last_text = "";
  last_sec = -999999;
  print "Progress: 0% (0:00 / " total_mmss ")" > "/dev/stderr";
}
/^\[[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/{
  if (match($0, /^\[([0-9]{2}):([0-9]{2}):([0-9]{2})/, ts)) {
    sec = (ts[1]+0)*3600 + (ts[2]+0)*60 + (ts[3]+0);
    if (sec > last_done) last_done = sec;

    pct = int((last_done * 100) / total_sec);
    if (pct > last_pct) {
      if (pct > 100) pct = 100;
      print "Progress: " pct "% (" mmss(last_done) " / " total_mmss ")" > "/dev/stderr";
      last_pct = pct;
    }

    min = int(sec/60);
    text = $0;
    sub(/^\[[^]]*\][[:space:]]*/, "", text);
    gsub(/[[:space:]]+/, " ", text);

    # Anti-loop / anti-repeat:
    # 1) If identical text repeats within 2 seconds, drop it.
    # 2) If identical text already appeared in the same minute, drop it.
    key = min ":" text
    if (length(text) > 0) {
      if (text == last_text && sec <= last_sec + 2) next
      if (seen[key]++) next

      last_text = text
      last_sec  = sec

      buf[min] = (buf[min] ? buf[min] " " : "") text;
    }
  }
  next
}
END{
  print "Progress: 100% (" total_mmss " / " total_mmss ")" > "/dev/stderr";
  for (m=0; m<total_min; m++){
    a = hhmmss(m*60);
    b = hhmmss((m+1)*60);
    txt = (m in buf && length(buf[m])>0) ? buf[m] : "(no text)";
    print "[" a "] -> [" b "] " txt "\n";
  }
}
' | iconv -f UTF-8 -t ASCII//TRANSLIT > "$OUT"

echo "Done:"
echo "$OUT"
