#!/bin/zsh

set -euo pipefail

SERVER_URL="${SERVER_URL:-http://localhost:9001}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
VIDEO_DIR="${VIDEO_DIR:-$SCRIPT_DIR/videos}"
USER_HOME="${HOME:-$(python3 -c 'from pathlib import Path; print(Path.home())')}"
CAPCUT_DRAFT_ROOT="${CAPCUT_DRAFT_ROOT:-$USER_HOME/Movies/CapCut/User Data/Projects/com.lveditor.draft}"
TRACK_NAME="${TRACK_NAME:-video_main}"

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

echo "Step 3: save the draft into CapCut's local drafts directory"
save_response=$(curl -s -X POST "${SERVER_URL}/save_draft" \
  -H 'Content-Type: application/json' \
  -d "$(python3 -c '
import json, sys
print(json.dumps({
    "draft_id": sys.argv[1],
    "draft_folder": sys.argv[2],
}))
' "$draft_id" "$CAPCUT_DRAFT_ROOT")")

echo "$save_response"
echo

target_draft_path="$CAPCUT_DRAFT_ROOT/$draft_id"

echo "Step 4: verify the folder exists"
ls -la "$target_draft_path"
echo

echo "Step 5: open the folder in Finder"
echo "open \"$target_draft_path\""
echo
echo "Saved draft path:"
echo "$target_draft_path"
