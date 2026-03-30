# VectCutAPI Fork for CapCut Draft Generation

This repository is a fork of the open source [VectCutAPI](https://github.com/sun-guannan/VectCutAPI). This fork is maintained as a CapCut-focused variant for creating and saving local CapCut draft projects through a Python HTTP API and shell scripts.

## Fork Scope

This fork is intentionally narrower than the upstream project.

- CapCut is the only supported desktop editor documented here.
- The documented interface is the local HTTP API exposed by `capcut_server.py`.
- The README focuses on local draft generation, subtitle import, and scripted draft assembly.

## What This Fork Does

This project lets you build CapCut drafts programmatically, then save those drafts into CapCut's local projects directory so they appear in the desktop app.

Core capabilities in this fork include:

- Create a new draft timeline
- Add video clips in sequence
- Add audio tracks
- Add subtitles from SRT
- Add text, images, stickers, effects, and keyframes
- Save the assembled project as a local CapCut draft

## Repository Layout

- `capcut_server.py`: Flask server that exposes the local HTTP API
- `config.json.example`: Example configuration for local setup
- `scripts/create_capcut_draft_from_videos.sh`: End-to-end script that assembles a CapCut draft from local video files
- `scripts/generate_srt_with_openai.py`: Optional helper that generates SRT captions with the OpenAI API
- `scripts/videos/`: Default input directory for the draft creation script

## Requirements

- Python 3.10 or newer
- `ffmpeg`
- `ffprobe`
- CapCut desktop installed on the machine where drafts will be saved

Notes:

- `ffprobe` is required because the draft creation script reads each clip's duration before adding it to the timeline.
- If you want automatic captions, you also need an OpenAI API key.

## Installation

```bash
git clone https://github.com/jamil-islam/VectCutAPI.git
cd VectCutAPI

python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt
```

## Configuration

Create a local config file:

```bash
cp config.json.example config.json
```

The example config includes:

- `is_capcut_env`: should remain `true` for this fork
- `draft_domain`: base domain used for generated draft URLs
- `port`: local Flask server port
- `preview_router`: route used when building draft preview URLs
- `openai_api_key`: optional, used by `scripts/generate_srt_with_openai.py`

If you do not want to store the OpenAI key in `config.json`, you can instead export `OPENAI_API_KEY` in your shell.

## Start The Local API Server

```bash
python3 capcut_server.py
```

By default the server runs on port `9001`.

## Basic Smoke Test

Create a draft:

```bash
curl -s -X POST http://localhost:9001/create_draft \
  -H 'Content-Type: application/json' \
  -d '{"width":1080,"height":1920}'
```

You should receive a JSON response containing a `draft_id`.

## Core HTTP Endpoints

The main endpoints exposed by `capcut_server.py` include:

- `POST /create_draft`
- `POST /add_video`
- `POST /add_audio`
- `POST /add_subtitle`
- `POST /add_text`
- `POST /add_image`
- `POST /add_sticker`
- `POST /add_effect`
- `POST /add_video_keyframe`
- `POST /save_draft`
- `POST /query_draft_status`
- `POST /query_script`
- `POST /generate_draft_url`

There are also multiple metadata endpoints for fonts, transitions, masks, text animations, audio effects, and video effects.

## Quick API Example

Create a draft:

```python
import requests

create_response = requests.post(
    "http://localhost:9001/create_draft",
    json={"width": 1080, "height": 1920},
)
create_response.raise_for_status()

draft_id = create_response.json()["output"]["draft_id"]
print(draft_id)
```

Add a video clip:

```python
import requests

response = requests.post(
    "http://localhost:9001/add_video",
    json={
        "draft_id": "your-draft-id",
        "video_url": "/absolute/path/to/clip.mp4",
        "target_start": 0,
        "duration": 5.0,
        "track_name": "video_main",
    },
)
response.raise_for_status()
print(response.json())
```

Save the draft:

```python
import requests

response = requests.post(
    "http://localhost:9001/save_draft",
    json={
        "draft_id": "your-draft-id",
        "draft_folder": "/Users/your-user/Movies/CapCut/User Data/Projects/com.lveditor.draft",
        "draft_name": "example-project",
    },
)
response.raise_for_status()
print(response.json())
```

## End-To-End Script: `scripts/create_capcut_draft_from_videos.sh`

This script is the simplest complete workflow in the repo for turning a set of local clips into a CapCut draft.

### What The Script Does

The script:

1. Scans a local video directory for supported files
2. Creates a new draft through `POST /create_draft`
3. Adds each clip sequentially through `POST /add_video`
4. Optionally adds subtitles through `POST /add_subtitle`
5. Saves the result into CapCut's local draft directory through `POST /save_draft`
6. Prints the final draft path so you can open it in Finder

Supported file extensions are:

- `mp4`
- `mov`
- `m4v`
- `mkv`
- `avi`
- `webm`

### Default Paths

By default the script uses:

- Video input directory: `scripts/videos`
- Subtitle file: `scripts/captions.srt`
- CapCut draft root: `~/Movies/CapCut/User Data/Projects/com.lveditor.draft`
- Server URL: `http://localhost:9001`

### Typical Usage

Start the API server in one terminal:

```bash
python3 capcut_server.py
```

In another terminal, activate your virtualenv if needed, place clips into `scripts/videos`, then run:

```bash
./scripts/create_capcut_draft_from_videos.sh
```

### What Happens At Runtime

- The script creates `scripts/videos` if it does not already exist.
- It fails immediately if no supported video files are found.
- It uses `ffprobe` to calculate each clip's duration.
- It appends clips in order by increasing timeline start time.
- If `scripts/captions.srt` exists, it imports that file as subtitles.
- If a custom `DRAFT_NAME` is provided, the script sanitizes it before creating the final folder name.

### Optional Automatic Captions

If you want the script to generate captions before building the draft, set:

```bash
AUTO_CAPTIONS=true ./scripts/create_capcut_draft_from_videos.sh
```

When `AUTO_CAPTIONS=true`, the script runs `scripts/generate_srt_with_openai.py` before creating the draft. That helper:

- extracts audio from each clip with `ffmpeg`
- sends audio to the OpenAI transcription API
- combines the resulting segments into one timeline-aligned SRT file
- writes the final SRT to `CAPTIONS_SRT_PATH`

You must provide an API key through either:

- `OPENAI_API_KEY`
- `openai_api_key` in `config.json`

### Useful Environment Variables

You can customize the script without editing it by setting environment variables before running it.

General workflow variables:

- `SERVER_URL`: API base URL, default `http://localhost:9001`
- `VIDEO_DIR`: input clip directory, default `scripts/videos`
- `CAPTIONS_SRT_PATH`: subtitle file path, default `scripts/captions.srt`
- `CAPCUT_DRAFT_ROOT`: destination CapCut drafts directory
- `DRAFT_NAME`: optional final draft folder name
- `TRACK_NAME`: video track name, default `video_main`
- `AUTO_CAPTIONS`: `true` or `false`
- `OPENAI_TRANSCRIBE_MODEL`: default `whisper-1`
- `OPENAI_TRANSCRIBE_LANGUAGE`: optional language hint such as `en`
- `OPENAI_TRANSCRIBE_PROMPT`: optional transcription prompt
- `SUBTITLE_TRACK_NAME`: subtitle track name, default `subtitle`
- `SUBTITLE_PRESET`: subtitle preset selector, default `circuit_electric`

Subtitle styling variables:

- `SUBTITLE_FONT`
- `SUBTITLE_FONT_SIZE`
- `SUBTITLE_BOLD`
- `SUBTITLE_ITALIC`
- `SUBTITLE_UNDERLINE`
- `SUBTITLE_FONT_COLOR`
- `SUBTITLE_ALPHA`
- `SUBTITLE_VERTICAL`
- `SUBTITLE_BORDER_COLOR`
- `SUBTITLE_BORDER_WIDTH`
- `SUBTITLE_BORDER_ALPHA`
- `SUBTITLE_BACKGROUND_COLOR`
- `SUBTITLE_BACKGROUND_STYLE`
- `SUBTITLE_BACKGROUND_ALPHA`
- `SUBTITLE_TRANSFORM_X`
- `SUBTITLE_TRANSFORM_Y`
- `SUBTITLE_SCALE_X`
- `SUBTITLE_SCALE_Y`
- `SUBTITLE_ROTATION`

### Example Custom Run

```bash
DRAFT_NAME="launch-cut" \
VIDEO_DIR="$PWD/my_clips" \
CAPTIONS_SRT_PATH="$PWD/my_captions.srt" \
SUBTITLE_FONT_SIZE="12.0" \
SUBTITLE_TRANSFORM_Y="-0.78" \
./scripts/create_capcut_draft_from_videos.sh
```

### Expected Result

On success, the script prints the final saved draft path under CapCut's local projects directory. That draft should then appear in the CapCut desktop application.

## Troubleshooting

If draft creation fails:

- confirm `python3 capcut_server.py` is running
- confirm the server is reachable at `SERVER_URL`
- confirm `ffmpeg` and `ffprobe` are installed and available on `PATH`
- confirm CapCut is installed and `CAPCUT_DRAFT_ROOT` points to the correct local drafts directory
- confirm your clip paths are valid and readable

If auto captions fail:

- confirm `OPENAI_API_KEY` is set or `config.json` contains `openai_api_key`
- confirm the transcoded audio for each clip stays under the OpenAI upload size limit enforced by `scripts/generate_srt_with_openai.py`

## Upstream

This repository is based on the open source VectCutAPI project. If you need features or documentation that are not present in this fork, check the upstream repository:

`https://github.com/sun-guannan/VectCutAPI`
