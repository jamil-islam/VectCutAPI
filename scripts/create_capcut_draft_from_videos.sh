#!/bin/zsh

set -euo pipefail

SERVER_URL="${SERVER_URL:-http://localhost:9001}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
VIDEO_DIR="${VIDEO_DIR:-$SCRIPT_DIR/videos}"
CAPTIONS_SRT_PATH="${CAPTIONS_SRT_PATH:-$SCRIPT_DIR/captions.srt}"
USER_HOME="${HOME:-$(python3 -c 'from pathlib import Path; print(Path.home())')}"
CAPCUT_DRAFT_ROOT="${CAPCUT_DRAFT_ROOT:-$USER_HOME/Movies/CapCut/User Data/Projects/com.lveditor.draft}"
DRAFT_NAME="${DRAFT_NAME:-${1:-}}"
TRACK_NAME="${TRACK_NAME:-video_main}"
AUTO_CAPTIONS="${AUTO_CAPTIONS:-false}"
OPENAI_TRANSCRIBE_MODEL="${OPENAI_TRANSCRIBE_MODEL:-whisper-1}"
OPENAI_TRANSCRIBE_LANGUAGE="${OPENAI_TRANSCRIBE_LANGUAGE:-}"
OPENAI_TRANSCRIBE_PROMPT="${OPENAI_TRANSCRIBE_PROMPT:-}"
SUBTITLE_TRACK_NAME="${SUBTITLE_TRACK_NAME:-subtitle}"
SUBTITLE_PRESET="${SUBTITLE_PRESET:-circuit_electric}"

SUBTITLE_FONT="${SUBTITLE_FONT:-}"
SUBTITLE_FONT_SIZE="${SUBTITLE_FONT_SIZE:-10.0}"
SUBTITLE_BOLD="${SUBTITLE_BOLD:-false}"
SUBTITLE_ITALIC="${SUBTITLE_ITALIC:-false}"
SUBTITLE_UNDERLINE="${SUBTITLE_UNDERLINE:-false}"
SUBTITLE_FONT_COLOR="${SUBTITLE_FONT_COLOR:-#FFFFFF}"
SUBTITLE_ALPHA="${SUBTITLE_ALPHA:-1.0}"
SUBTITLE_VERTICAL="${SUBTITLE_VERTICAL:-false}"
SUBTITLE_BORDER_COLOR="${SUBTITLE_BORDER_COLOR:-#000000}"
SUBTITLE_BORDER_WIDTH="${SUBTITLE_BORDER_WIDTH:-0.08}"
SUBTITLE_BORDER_ALPHA="${SUBTITLE_BORDER_ALPHA:-1.0}"
SUBTITLE_BACKGROUND_COLOR="${SUBTITLE_BACKGROUND_COLOR:-#000000}"
SUBTITLE_BACKGROUND_STYLE="${SUBTITLE_BACKGROUND_STYLE:-1}"
SUBTITLE_BACKGROUND_ALPHA="${SUBTITLE_BACKGROUND_ALPHA:-1.0}"
SUBTITLE_TRANSFORM_X="${SUBTITLE_TRANSFORM_X:-0.0}"
SUBTITLE_TRANSFORM_Y="${SUBTITLE_TRANSFORM_Y:--0.82}"
SUBTITLE_SCALE_X="${SUBTITLE_SCALE_X:-1.0}"
SUBTITLE_SCALE_Y="${SUBTITLE_SCALE_Y:-1.0}"
SUBTITLE_ROTATION="${SUBTITLE_ROTATION:-0.0}"

if [[ "$SUBTITLE_PRESET" == "circuit_electric" ]]; then
  SUBTITLE_FONT_SIZE="${SUBTITLE_FONT_SIZE:-10.0}"
  SUBTITLE_FONT_COLOR="${SUBTITLE_FONT_COLOR:-#FFFFFF}"
  SUBTITLE_BORDER_COLOR="${SUBTITLE_BORDER_COLOR:-#000000}"
  SUBTITLE_BORDER_WIDTH="${SUBTITLE_BORDER_WIDTH:-0.08}"
  SUBTITLE_BORDER_ALPHA="${SUBTITLE_BORDER_ALPHA:-1.0}"
  SUBTITLE_BACKGROUND_COLOR="${SUBTITLE_BACKGROUND_COLOR:-#000000}"
  SUBTITLE_BACKGROUND_STYLE="${SUBTITLE_BACKGROUND_STYLE:-1}"
  SUBTITLE_BACKGROUND_ALPHA="${SUBTITLE_BACKGROUND_ALPHA:-1.0}"
  SUBTITLE_TRANSFORM_Y="${SUBTITLE_TRANSFORM_Y:--0.82}"
  SUBTITLE_VERTICAL="${SUBTITLE_VERTICAL:-false}"
fi

mkdir -p "$VIDEO_DIR"

video_files=()
for ext in mp4 mov m4v mkv avi webm; do
  for file in "$VIDEO_DIR"/*."$ext"(N); do
    video_files+=("$file")
  done
  for file in "$VIDEO_DIR"/*."${(U)ext}"(N); do
    video_files+=("$file")
  done
done

if (( ${#video_files[@]} == 0 )); then
  echo "No video files found in: $VIDEO_DIR" >&2
  echo "Put clips into scripts/videos and rerun." >&2
  exit 1
fi

echo "Using video directory:"
echo "$VIDEO_DIR"
echo
echo "Using CapCut draft root:"
echo "$CAPCUT_DRAFT_ROOT"
echo
if [[ -n "$DRAFT_NAME" ]]; then
  echo "Using draft folder name:"
  echo "$DRAFT_NAME"
  echo
fi
echo "Using captions file:"
echo "$CAPTIONS_SRT_PATH"
echo

if [[ "$AUTO_CAPTIONS" == "true" ]]; then
  echo "Step 0: generate captions with the OpenAI SDK"
  transcribe_cmd=(
    python3
    "$SCRIPT_DIR/generate_srt_with_openai.py"
    --output
    "$CAPTIONS_SRT_PATH"
    --model
    "$OPENAI_TRANSCRIBE_MODEL"
  )

  if [[ -n "$OPENAI_TRANSCRIBE_LANGUAGE" ]]; then
    transcribe_cmd+=(--language "$OPENAI_TRANSCRIBE_LANGUAGE")
  fi

  if [[ -n "$OPENAI_TRANSCRIBE_PROMPT" ]]; then
    transcribe_cmd+=(--prompt "$OPENAI_TRANSCRIBE_PROMPT")
  fi

  transcribe_cmd+=("${video_files[@]}")
  "${transcribe_cmd[@]}"
  echo
fi

echo "Step 1: create a new draft"
create_response=$(curl -s -X POST "${SERVER_URL}/create_draft" \
  -H 'Content-Type: application/json' \
  -d '{"width":1080,"height":1920}')

echo "$create_response"

draft_id=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["output"]["draft_id"])' "$create_response")
if [[ -z "$draft_id" ]]; then
  echo "Failed to extract draft_id from create_draft response." >&2
  exit 1
fi

echo
echo "Draft ID:"
echo "$draft_id"
echo

current_start="0.0"
index=1

for video_path in "${video_files[@]}"; do
  duration=$(ffprobe -v error \
    -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 \
    "$video_path")

  if [[ -z "$duration" ]]; then
    echo "Failed to read duration for: $video_path" >&2
    exit 1
  fi

  echo "Step 2.$index: add video"
  echo "  file: $video_path"
  echo "  start: $current_start"
  echo "  duration: $duration"

  add_response=$(curl -s -X POST "${SERVER_URL}/add_video" \
    -H 'Content-Type: application/json' \
    -d "$(python3 -c '
import json, sys
print(json.dumps({
    "draft_id": sys.argv[1],
    "draft_folder": sys.argv[2],
    "video_url": sys.argv[3],
    "target_start": float(sys.argv[4]),
    "duration": float(sys.argv[5]),
    "track_name": sys.argv[6],
}))
' "$draft_id" "$CAPCUT_DRAFT_ROOT" "$video_path" "$current_start" "$duration" "$TRACK_NAME")")

  echo "$add_response"

  current_start=$(python3 -c 'import sys; print(float(sys.argv[1]) + float(sys.argv[2]))' "$current_start" "$duration")
  index=$((index + 1))
  echo
done

if [[ -f "$CAPTIONS_SRT_PATH" ]]; then
  echo "Step 3: add subtitles from SRT"
  subtitle_response=$(curl -s -X POST "${SERVER_URL}/add_subtitle" \
    -H 'Content-Type: application/json' \
    -d "$(python3 -c '
import json, sys
payload = {
    "draft_id": sys.argv[1],
    "srt": sys.argv[2],
    "track_name": sys.argv[3],
    "font_size": float(sys.argv[4]),
    "bold": sys.argv[5].lower() == "true",
    "italic": sys.argv[6].lower() == "true",
    "underline": sys.argv[7].lower() == "true",
    "font_color": sys.argv[8],
    "alpha": float(sys.argv[9]),
    "vertical": sys.argv[10].lower() == "true",
    "border_color": sys.argv[11],
    "border_width": float(sys.argv[12]),
    "border_alpha": float(sys.argv[13]),
    "background_color": sys.argv[14],
    "background_style": int(sys.argv[15]),
    "background_alpha": float(sys.argv[16]),
    "transform_x": float(sys.argv[17]),
    "transform_y": float(sys.argv[18]),
    "scale_x": float(sys.argv[19]),
    "scale_y": float(sys.argv[20]),
    "rotation": float(sys.argv[21]),
    "width": 1080,
    "height": 1920,
}
if sys.argv[22]:
    payload["font"] = sys.argv[22]
print(json.dumps(payload))
' "$draft_id" "$CAPTIONS_SRT_PATH" "$SUBTITLE_TRACK_NAME" "$SUBTITLE_FONT_SIZE" "$SUBTITLE_BOLD" "$SUBTITLE_ITALIC" "$SUBTITLE_UNDERLINE" "$SUBTITLE_FONT_COLOR" "$SUBTITLE_ALPHA" "$SUBTITLE_VERTICAL" "$SUBTITLE_BORDER_COLOR" "$SUBTITLE_BORDER_WIDTH" "$SUBTITLE_BORDER_ALPHA" "$SUBTITLE_BACKGROUND_COLOR" "$SUBTITLE_BACKGROUND_STYLE" "$SUBTITLE_BACKGROUND_ALPHA" "$SUBTITLE_TRANSFORM_X" "$SUBTITLE_TRANSFORM_Y" "$SUBTITLE_SCALE_X" "$SUBTITLE_SCALE_Y" "$SUBTITLE_ROTATION" "$SUBTITLE_FONT")")

  echo "$subtitle_response"
  echo
else
  echo "Step 3: skip subtitles"
  echo "No SRT found at: $CAPTIONS_SRT_PATH"
  echo
fi

echo "Step 4: save the draft into CapCut's local drafts directory"
save_response=$(curl -s -X POST "${SERVER_URL}/save_draft" \
  -H 'Content-Type: application/json' \
  -d "$(python3 -c '
import json, sys
print(json.dumps({
    "draft_id": sys.argv[1],
    "draft_folder": sys.argv[2],
    "draft_name": sys.argv[3] or None,
}))
' "$draft_id" "$CAPCUT_DRAFT_ROOT" "$DRAFT_NAME")")

echo "$save_response"
echo

target_draft_dir_name="$draft_id"
if [[ -n "$DRAFT_NAME" ]]; then
  target_draft_dir_name="$(python3 -c '
import re, sys
name = sys.argv[1].strip()
name = re.sub(r"[\\\\/]+", "_", name)
name = re.sub(r"[\x00-\x1f]+", "", name)
name = name.rstrip(" .")
print(name)
' "$DRAFT_NAME")"
  if [[ -z "$target_draft_dir_name" ]]; then
    target_draft_dir_name="$draft_id"
  fi
fi

target_draft_path="$CAPCUT_DRAFT_ROOT/$target_draft_dir_name"

echo "Step 5: verify the folder exists"
ls -la "$target_draft_path"
echo

echo "Step 6: open the folder in Finder"
echo "open \"$target_draft_path\""
echo
echo "Saved draft path:"
echo "$target_draft_path"
