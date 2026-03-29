#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path

import json5
from openai import OpenAI


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=True, text=True, capture_output=True)


def get_duration_seconds(media_path: Path) -> float:
    result = run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(media_path),
        ]
    )
    return float(result.stdout.strip())


def format_srt_timestamp(seconds: float) -> str:
    total_ms = max(0, int(round(seconds * 1000)))
    hours = total_ms // 3_600_000
    total_ms %= 3_600_000
    minutes = total_ms // 60_000
    total_ms %= 60_000
    secs = total_ms // 1_000
    millis = total_ms % 1_000
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"


def transcode_audio(input_path: Path, output_path: Path) -> None:
    run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(input_path),
            "-vn",
            "-ac",
            "1",
            "-ar",
            "16000",
            "-b:a",
            "64k",
            str(output_path),
        ]
    )


def get_segments(response) -> list[dict]:
    if hasattr(response, "segments") and response.segments is not None:
        segments = response.segments
    else:
        dumped = response.model_dump() if hasattr(response, "model_dump") else json.loads(response.json())
        segments = dumped.get("segments", [])

    normalized = []
    for segment in segments:
        if hasattr(segment, "model_dump"):
            segment = segment.model_dump()
        normalized.append(segment)
    return normalized


def load_openai_api_key() -> str:
    env_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if env_key:
        return env_key

    repo_root = Path(__file__).resolve().parent.parent
    config_path = repo_root / "config.json"
    if config_path.is_file():
        with config_path.open("r", encoding="utf-8") as f:
            config = json5.load(f)
        config_key = str(config.get("openai_api_key", "")).strip()
        if config_key:
            return config_key

    raise SystemExit("OPENAI_API_KEY is required, either as an environment variable or as openai_api_key in config.json.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a combined SRT from ordered video clips using the OpenAI SDK.")
    parser.add_argument("--output", required=True, help="Output SRT path.")
    parser.add_argument("--model", default="whisper-1", help="OpenAI transcription model.")
    parser.add_argument("--language", default="", help="Optional language hint, for example 'en'.")
    parser.add_argument("--prompt", default="", help="Optional transcription prompt.")
    parser.add_argument("inputs", nargs="+", help="Ordered media files to transcribe.")
    args = parser.parse_args()

    client = OpenAI(api_key=load_openai_api_key())
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    srt_lines: list[str] = []
    index = 1
    offset_seconds = 0.0
    previous_end_seconds = 0.0

    for input_name in args.inputs:
        input_path = Path(input_name)
        if not input_path.is_file():
            raise SystemExit(f"Input file not found: {input_path}")

        clip_duration = get_duration_seconds(input_path)

        with tempfile.TemporaryDirectory(prefix="vectcut-whisper-") as temp_dir:
            temp_audio_path = Path(temp_dir) / f"{input_path.stem}.mp3"
            transcode_audio(input_path, temp_audio_path)

            if temp_audio_path.stat().st_size > 25 * 1024 * 1024:
                raise SystemExit(
                    f"Transcoded audio exceeds 25MB for {input_path.name}. "
                    "Split the clip or lower bitrate before transcription."
                )

            request_kwargs = {
                "model": args.model,
                "file": temp_audio_path.open("rb"),
                "response_format": "verbose_json",
                "timestamp_granularities": ["segment"],
            }
            if args.language:
                request_kwargs["language"] = args.language
            if args.prompt:
                request_kwargs["prompt"] = args.prompt

            with request_kwargs["file"] as audio_file:
                request_kwargs["file"] = audio_file
                response = client.audio.transcriptions.create(**request_kwargs)

        segments = get_segments(response)
        clip_start_seconds = offset_seconds
        clip_end_seconds = offset_seconds + clip_duration

        for segment in segments:
            text = (segment.get("text") or "").strip()
            if not text:
                continue

            start_seconds = max(clip_start_seconds, offset_seconds + float(segment["start"]))
            end_seconds = min(clip_end_seconds, offset_seconds + float(segment["end"]))

            if start_seconds < previous_end_seconds:
                start_seconds = previous_end_seconds

            if end_seconds <= start_seconds:
                end_seconds = min(clip_end_seconds, start_seconds + 0.2)

            if end_seconds <= start_seconds:
                continue

            srt_lines.extend(
                [
                    str(index),
                    f"{format_srt_timestamp(start_seconds)} --> {format_srt_timestamp(end_seconds)}",
                    text,
                    "",
                ]
            )
            index += 1
            previous_end_seconds = end_seconds

        offset_seconds += clip_duration

    output_path.write_text("\n".join(srt_lines), encoding="utf-8")
    print(str(output_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
