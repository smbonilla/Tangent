#!/usr/bin/env python3
"""Run Tangent's production prompts against a local Ollama model."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

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
    selection.add_argument("--day", help="Generate one YYYY-MM-DD entry; defaults to the latest.")
    selection.add_argument("--all", action="store_true", help="Generate every daily summary.")
    parser.add_argument(
        "--insights",
        action="store_true",
        help="Generate every missing daily summary, then generate insights from them.",
    )
    parser.add_argument("--model", default="qwen3:0.6b", help="An installed Ollama model tag.")
    parser.add_argument("--base-url", default="http://127.0.0.1:11434")
    parser.add_argument("--prompt-file", default=str(DAILY_PROMPT))
    parser.add_argument("--insights-prompt-file", default=str(INSIGHTS_PROMPT))
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--summary-max-tokens", type=int, default=120)
    parser.add_argument("--insights-max-tokens", type=int, default=400)
    parser.add_argument("--think", action="store_true", help="Allow thinking output when the model supports it.")
    parser.add_argument("--show-prompt", action="store_true", help="Print each filled prompt.")
    parser.add_argument("--render-only", action="store_true", help="Fill prompts without calling Ollama.")
    parser.add_argument("--refresh", action="store_true", help="Ignore matching cached responses.")
    parser.add_argument("--no-output", action="store_true", help="Do not read or write cached responses.")
    parser.add_argument("--output-dir", default=str(LAB_ROOT / "output"))
    return parser.parse_args()


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        sys.exit(f"Missing data file: {path}")
    except json.JSONDecodeError as error:
        sys.exit(f"Invalid JSON in {path}: {error}")


def sentence_count(text: str) -> int:
    """Count sentence endings well enough to enforce this prompt's short output."""
    return len(re.findall(r"[.!?]+(?=(?:[\"']?\s)|$)", text.strip()))


def validate_daily(text: str, forbidden_claims: list[str] | None = None) -> dict:
    issues: list[str] = []
    if not text:
        issues.append("The response is empty.")
    if text and not re.search(r"\b(?:I|I'm|I've|I'll|I'd|me|my)\b", text):
        issues.append("The response is not written in the first person.")
    count = sentence_count(text)
    if count > 1:
        issues.append(f"Expected one sentence but found {count}.")
    for claim in forbidden_claims or []:
        if claim.casefold() in text.casefold():
            issues.append(f"Contains fixture-forbidden claim: {claim!r}.")
    return {"passed": not issues, "issues": issues}


def insight_items(text: str) -> list[str]:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    bulleted = [
        re.sub(r"^(?:[-*•]|\d+[.)])\s+", "", line)
        for line in lines
        if re.match(r"^(?:[-*•]|\d+[.)])\s+", line)
    ]
    if bulleted:
        return bulleted
    return [item.strip() for item in re.split(r"(?<=[.!?])\s+", text.strip()) if item.strip()]


def validate_insights(text: str) -> dict:
    issues: list[str] = []
    if not text:
        issues.append("The response is empty.")
    items = insight_items(text)
    if len(items) > 5:
        issues.append(f"Expected at most five insights but found {len(items)}.")
    if text and not re.search(r"\b(?:you|your|you're|you've|you'll|you'd)\b", text, re.IGNORECASE):
        issues.append('The response does not address the writer as "you".')
    return {"passed": not issues, "issues": issues}


def validate_response(stage: str, text: str, forbidden_claims: list[str] | None = None) -> dict:
    if stage == "daily":
        return validate_daily(text, forbidden_claims)
    if stage == "insights":
        return validate_insights(text)
    raise ValueError(f"Unknown generation stage: {stage}")


def show_checks(checks: dict) -> None:
    for issue in checks["issues"]:
        print(f"\033[33mcheck: {issue}\033[0m")


def check_ollama(base_url: str, model: str) -> None:
    try:
        with urllib.request.urlopen(f"{base_url.rstrip('/')}/api/tags", timeout=3) as response:
            payload = json.loads(response.read())
    except (urllib.error.URLError, TimeoutError, OSError):
        sys.exit(f"Cannot reach Ollama at {base_url}. Start it with: ollama serve")

    installed = [item.get("name", "") for item in payload.get("models", [])]
    accepted = {model, f"{model}:latest"}
    if not any(name in accepted or name.removesuffix(":latest") == model for name in installed):
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
    payload = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "stream": True,
            "think": think,
            "options": {"temperature": temperature, "num_predict": max_tokens},
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/api/chat",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    chunks: list[str] = []
    try:
        with urllib.request.urlopen(request) as response:
            for line in response:
                event = json.loads(line)
                if event.get("error"):
                    raise RuntimeError(event["error"])
                piece = (event.get("message") or {}).get("content") or ""
                if piece:
                    chunks.append(piece)
                    print(piece, end="", flush=True)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        sys.exit(f"Ollama returned HTTP {error.code}: {detail}")
    except urllib.error.URLError as error:
        sys.exit(f"Ollama request failed: {error.reason}")
    print()
    return "".join(chunks)


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def cache_key(model: str, prompt: str, temperature: float, max_tokens: int, think: bool) -> str:
    identity = json.dumps(
        {
            "model": model,
            "prompt": prompt,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "think": think,
        },
        sort_keys=True,
        ensure_ascii=False,
    )
    return digest(identity)


def output_path(output_dir: Path, stage: str, label: str, key: str) -> Path:
    safe_label = re.sub(r"[^A-Za-z0-9_.-]", "-", label)
    return output_dir / stage / f"{safe_label}-{key[:12]}.json"


def generate(
    *,
    args: argparse.Namespace,
    stage: str,
    label: str,
    prompt: str,
    prompt_file: str,
    max_tokens: int,
    forbidden_claims: list[str] | None = None,
) -> dict:
    key = cache_key(args.model, prompt, args.temperature, max_tokens, args.think)
    path = output_path(Path(args.output_dir), stage, label, key)
    if not args.no_output and not args.refresh and path.exists():
        cached = load_json(path)
        cached["checks"] = validate_response(
            stage,
            cached["cleaned_response"],
            forbidden_claims,
        )
        print(f"\033[2mreusing {path}\033[0m")
        print(cached["cleaned_response"])
        show_checks(cached["checks"])
        return cached

    raw = call_ollama(
        args.base_url,
        args.model,
        prompt,
        args.temperature,
        max_tokens,
        args.think,
    )
    cleaned = clean_response(raw)
    checks = validate_response(stage, cleaned, forbidden_claims)
    result = {
        "stage": stage,
        "label": label,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "model": args.model,
        "temperature": args.temperature,
        "max_tokens": max_tokens,
        "thinking": args.think,
        "prompt_file": str(Path(prompt_file).resolve()),
        "prompt_sha256": digest(prompt),
        "prompt": prompt,
        "raw_response": raw,
        "cleaned_response": cleaned,
        "checks": checks,
        "cache_key": key,
    }
    show_checks(checks)
    if not args.no_output:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"\033[2msaved: {path}\033[0m")
    return result


def selected_entries(entries: list[dict], day: str | None, all_entries: bool) -> list[dict]:
    ordered = sorted(entries, key=lambda entry: entry["day"])
    if all_entries:
        return ordered
    if day:
        matches = [entry for entry in ordered if entry["day"] == day]
        if not matches:
            available = ", ".join(entry["day"] for entry in ordered)
            sys.exit(f"No entry for {day}. Available: {available}")
        return matches
    return ordered[-1:]


def read_transcript(entry: dict) -> str:
    path = DATA / entry["transcript_path"]
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        sys.exit(f"Transcript not found: {path}")


def show_prompt(prompt: str) -> None:
    print(f"\033[2m--- filled prompt ---\n{prompt}\n---------------------\033[0m")


def main() -> None:
    args = parse_args()
    profile = load_json(DATA / "profile.json")
    all_entries = selected_entries(load_json(DATA / "diary.json"), None, True)
    entries = selected_entries(all_entries, args.day, args.all or args.insights)
    daily_template = load_prompt(args.prompt_file)

    if not args.render_only:
        check_ollama(args.base_url, args.model)

    summaries: list[tuple[str, str]] = []
    for entry in entries:
        prompt = render_daily(daily_template, profile, read_transcript(entry))
        print(f"\n\033[1m{entry['day']}\033[0m  ({args.model})")
        if args.show_prompt or args.render_only:
            show_prompt(prompt)
        if args.render_only:
            continue
        result = generate(
            args=args,
            stage="daily",
            label=entry["day"],
            prompt=prompt,
            prompt_file=args.prompt_file,
            max_tokens=args.summary_max_tokens,
            forbidden_claims=entry.get("forbidden_claims"),
        )
        summary = result["cleaned_response"].strip()
        if summary:
            summaries.append((entry["day"], summary))

    if not args.insights or args.render_only:
        return
    if not summaries:
        sys.exit("No daily summaries were generated for insights.")

    insights_template = load_prompt(args.insights_prompt_file)
    prompt = render_insights(insights_template, profile, summaries)
    first, last = summaries[0][0], summaries[-1][0]
    print(f"\n\033[1minsights\033[0m  ({first} to {last}, {args.model})")
    if args.show_prompt:
        show_prompt(prompt)
    generate(
        args=args,
        stage="insights",
        label=f"{first}_to_{last}",
        prompt=prompt,
        prompt_file=args.insights_prompt_file,
        max_tokens=args.insights_max_tokens,
    )


if __name__ == "__main__":
    main()
