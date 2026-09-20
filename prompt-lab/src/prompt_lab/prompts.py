"""Load and render the prompt templates shared with the Tangent app."""

from datetime import date
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
DAILY_PROMPT = REPO_ROOT / "Tangent/Tangent/Resources/Prompts/daily_short_summary.txt"
INSIGHTS_PROMPT = REPO_ROOT / "Tangent/Tangent/Resources/Prompts/weekly_insights.txt"


def load_prompt(path: str | Path) -> str:
    return Path(path).read_text(encoding="utf-8").replace("\r\n", "\n").strip("\n")


def _cleaned_list(values) -> list[str]:
    return [str(value).strip() for value in values or [] if str(value).strip()]


def focus_description(profile: dict) -> str:
    lines: list[str] = []
    interests = _cleaned_list(profile.get("interests"))
    concerns = _cleaned_list(profile.get("concerns"))
    if interests:
        lines.append(f"Interests: {'; '.join(interests)}")
    if concerns:
        lines.append(f"Concerns: {'; '.join(concerns)}")
    return "\n".join(lines) if lines else "No interests or concerns specified."


def profile_description(profile: dict) -> str:
    name = str(profile.get("name") or "").strip()
    parts = ([f"Name: {name}"] if name else []) + [focus_description(profile)]
    return "\n".join(parts)


def render_daily(template: str, profile: dict, transcript: str) -> str:
    return template.replace("{user_profile}", profile_description(profile)).replace(
        "{transcript}", transcript.strip()
    )


def _prompt_day(day_text: str) -> str:
    parsed = date.fromisoformat(day_text)
    return f"{parsed.strftime('%a')} {parsed.day} {parsed.strftime('%b')}"


def _period_description(first: str, last: str) -> str:
    start = date.fromisoformat(first)
    end = date.fromisoformat(last)
    start_text = f"{start.day} {start.strftime('%B')}"
    end_text = f"{end.day} {end.strftime('%B')}"
    return start_text if start == end else f"{start_text} to {end_text}"


def render_insights(template: str, profile: dict, summaries: list[tuple[str, str]]) -> str:
    if not summaries:
        raise ValueError("Insights require at least one daily summary.")
    ordered = sorted(summaries)
    period = _period_description(ordered[0][0], ordered[-1][0])
    notes = "\n".join(f"{_prompt_day(day)}: {summary.strip()}" for day, summary in ordered)
    return (
        template.replace("{period}", period)
        .replace("{user_profile}", focus_description(profile))
        .replace("{daily_summaries}", notes)
    )


def clean_response(raw: str) -> str:
    text = raw.strip()
    if text.startswith("```"):
        lines = text.splitlines()[1:]
        if lines and lines[-1].strip() == "```":
            lines.pop()
        text = "\n".join(lines).strip()

    for label in ("short_summary:", "short summary:", "summary:", "notes:"):
        if text.lower().startswith(label):
            text = text[len(label) :].strip()
            break

    if text.startswith('"'):
        text = text[1:]
        if text.endswith('"'):
            text = text[:-1]
    return text.strip()
