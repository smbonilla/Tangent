"""Run Tangent's production prompts against a local Ollama model."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from .prompts import (
    DAILY_PROMPT,
    INSIGHTS_PROMPT,
    clean_response,
    load_prompt,
    render_daily,
    render_insights,
)


LAB_ROOT = Path(__file__).resolve().parents[2]
DATA = LAB_ROOT / "fake_data"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--day", help="Run one YYYY-MM-DD entry; defaults to the latest.")
    selection.add_argument("--all", action="store_true", help="Run every diary entry.")
    parser.add_argument(
        "--insights",
        action="store_true",
        help="Run all daily summaries, then generate insights from them.",
    )
    parser.add_argument("--model", default="qwen3:0.6b", help="An installed Ollama model tag.")
    parser.add_argument("--base-url", default="http://127.0.0.1:11434")
    parser.add_argument("--prompt-file", default=str(DAILY_PROMPT))
    parser.add_argument("--insights-prompt-file", default=str(INSIGHTS_PROMPT))
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--summary-max-tokens", type=int, default=120)
    parser.add_argument("--insights-max-tokens", type=int, default=400)
    parser.add_argument("--think", action="store_true")
    parser.add_argument("--show-prompt", action="store_true")
    parser.add_argument("--render-only", action="store_true", help="Show inputs without calling Ollama.")
    parser.add_argument("--output-dir", default=str(LAB_ROOT / "output"))
    return parser.parse_args()


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        sys.exit(f"Missing data file: {path}")
    except json.JSONDecodeError as error:
        sys.exit(f"Invalid JSON in {path}: {error}")


def entry_date(entry: dict) -> str:
    return entry["day"][:10]


def selected_entries(entries: list[dict], day: str | None, all_entries: bool) -> list[dict]:
    ordered = sorted(entries, key=lambda entry: entry["day"])
    if all_entries:
        return ordered
    if day:
        matches = [entry for entry in ordered if entry_date(entry) == day]
        if not matches:
            available = ", ".join(entry_date(entry) for entry in ordered)
            sys.exit(f"No entry for {day}. Available: {available}")
        return matches
    return ordered[-1:]


def read_transcript(entry: dict) -> str:
    path = DATA / entry["transcriptPath"]
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        sys.exit(f"Transcript not found: {path}")


def check_ollama(base_url: str, model: str) -> None:
    try:
        with urllib.request.urlopen(f"{base_url.rstrip('/')}/api/tags", timeout=3) as response:
            payload = json.loads(response.read())
    except (urllib.error.URLError, TimeoutError, OSError):
        sys.exit(f"Cannot reach Ollama at {base_url}. Start it with: ollama serve")

    installed = [item.get("name", "") for item in payload.get("models", [])]
    if not any(name == model or name.removesuffix(":latest") == model for name in installed):
        available = ", ".join(installed) or "none"
        sys.exit(f"Model {model} is not installed. Run: ollama pull {model}\nInstalled: {available}")


def call_ollama(
    base_url: str,
    model: str,
    prompt: str,
    temperature: float,
    max_tokens: int,
    think: bool,
) -> str:
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "stream": False,
            "think": think,
            "options": {"temperature": temperature, "num_predict": max_tokens},
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        sys.exit(f"Ollama returned HTTP {error.code}: {detail}")
    except urllib.error.URLError as error:
        sys.exit(f"Ollama request failed: {error.reason}")
    return (payload.get("message") or {}).get("content") or ""


def save_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Saved: {path}")


def generated_entry(entry: dict, prompt: str, summary: str) -> dict:
    result = deepcopy(entry)
    result["promptText"] = prompt
    result["summaryShort"] = summary
    return result


def generated_insight(first: dict, last: dict, prompt: str, text: str) -> dict:
    return {
        "id": str(uuid4()),
        "day": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "generatedFrom": first["day"],
        "generatedTo": last["day"],
        "promptText": prompt,
        "text": text,
    }


def show_input(label: str, transcript: str, prompt: str, show_prompt: bool) -> None:
    print(f"\n=== {label} ===")
    print("\nTRANSCRIPT\n")
    print(transcript)
    if show_prompt:
        print("\nFILLED PROMPT\n")
        print(prompt)


def main() -> None:
    args = parse_args()
    profile = load_json(DATA / "profile.json")
    all_entries = selected_entries(load_json(DATA / "diary.json"), None, True)
    entries = selected_entries(all_entries, args.day, args.all or args.insights)
    daily_template = load_prompt(args.prompt_file)

    if not args.render_only:
        check_ollama(args.base_url, args.model)

    generated: list[tuple[dict, str]] = []
    for entry in entries:
        transcript = read_transcript(entry)
        prompt = render_daily(daily_template, profile, transcript)
        show_input(entry_date(entry), transcript, prompt, args.show_prompt or args.render_only)
        if args.render_only:
            continue

        summary = clean_response(
            call_ollama(
                args.base_url,
                args.model,
                prompt,
                args.temperature,
                args.summary_max_tokens,
                args.think,
            )
        )
        print("\nSUMMARY\n")
        print(summary)
        output = generated_entry(entry, prompt, summary)
        save_json(Path(args.output_dir) / "daily" / f"{entry_date(entry)}.json", output)
        generated.append((entry, summary))

    if not args.insights or args.render_only:
        return

    summaries = [(entry_date(entry), summary) for entry, summary in generated if summary]
    if not summaries:
        sys.exit("No daily summaries were generated for insights.")
    prompt = render_insights(load_prompt(args.insights_prompt_file), profile, summaries)
    first, last = generated[0][0], generated[-1][0]
    print(f"\n=== INSIGHTS: {entry_date(first)} to {entry_date(last)} ===")
    if args.show_prompt:
        print("\nFILLED PROMPT\n")
        print(prompt)
    text = clean_response(
        call_ollama(
            args.base_url,
            args.model,
            prompt,
            args.temperature,
            args.insights_max_tokens,
            args.think,
        )
    )
    print("\nINSIGHTS\n")
    print(text)
    output = generated_insight(first, last, prompt, text)
    filename = f"{entry_date(first)}_to_{entry_date(last)}.json"
    save_json(Path(args.output_dir) / "insights" / filename, output)
