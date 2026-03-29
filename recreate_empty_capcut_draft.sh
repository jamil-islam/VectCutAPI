#!/bin/zsh

# This script documents the exact flow used to create an empty CapCut draft
# folder from this repo and then open that folder in Finder.
#
# What happened in our session:
# 1. The local HTTP server was running on port 9001.
# 2. We called /create_draft to create an empty in-memory draft.
# 3. We called /save_draft to export that draft as a real folder on disk.
# 4. We opened the saved folder in Finder with `open ...`.
#
# Important detail:
# - draft_id values live in server memory only.
# - If you restart the server, you must call /create_draft again and use the
#   new draft_id before calling /save_draft.

set -euo pipefail

SERVER_URL="http://localhost:9001"
USER_HOME="${HOME:-$(python3 -c 'from pathlib import Path; print(Path.home())')}"

# CapCut's macOS draft root. Override locally if your installation uses
# a different location:
#   CAPCUT_DRAFT_ROOT="/custom/path" ./recreate_empty_capcut_draft.sh
CAPCUT_DRAFT_ROOT="${CAPCUT_DRAFT_ROOT:-$USER_HOME/Movies/CapCut/User Data/Projects/com.lveditor.draft}"

echo "Step 1: create an empty draft in memory"
CREATE_RESPONSE=$(curl -s -X POST "${SERVER_URL}/create_draft" \
  -H 'Content-Type: application/json' \
  -d '{"width":1080,"height":1920}')

echo "${CREATE_RESPONSE}"

NEW_DRAFT_ID=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["output"]["draft_id"])' "${CREATE_RESPONSE}")

if [[ -z "${NEW_DRAFT_ID}" ]]; then
  echo "Failed to extract draft_id from create_draft response." >&2
  exit 1
fi

TARGET_DRAFT_PATH="${CAPCUT_DRAFT_ROOT}/${NEW_DRAFT_ID}"

echo
echo "Using CapCut draft root:"
echo "${CAPCUT_DRAFT_ROOT}"
echo
echo "New draft id:"
echo "${NEW_DRAFT_ID}"
echo
echo "Target path:"
echo "${TARGET_DRAFT_PATH}"

echo
echo "Step 2: save the draft as a real folder on disk"
curl -s -X POST "${SERVER_URL}/save_draft" \
  -H 'Content-Type: application/json' \
  -d "{\"draft_id\":\"${NEW_DRAFT_ID}\",\"draft_folder\":\"${CAPCUT_DRAFT_ROOT}\"}"
echo

echo
echo "Step 3: verify the folder exists"
ls -la "${TARGET_DRAFT_PATH}"

echo
echo "Step 4: open the folder in Finder"
echo "open \"${TARGET_DRAFT_PATH}\""

echo
echo "This saves directly into CapCut's local draft directory:"
echo "${TARGET_DRAFT_PATH}"
