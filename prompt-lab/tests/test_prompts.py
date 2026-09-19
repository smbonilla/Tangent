import json
import re
from pathlib import Path

import pytest

from prompt_lab import (
    DAILY_PROMPT,
    INSIGHTS_PROMPT,
    clean_response,
    load_prompt,
    render_daily,
    render_insights,
)
from prompt_lab.cli import generated_entry, generated_insight


LAB_ROOT = Path(__file__).resolve().parents[1]
PROFILE_FIELDS = {
    "id", "name", "interests", "concerns", "email", "dailyReminder"
}
ENTRY_FIELDS = {
    "id", "profileID", "day", "questions", "promptText", "summaryShort", "transcriptPath"
}
INSIGHT_FIELDS = {"id", "day", "generatedFrom", "generatedTo", "promptText", "text"}


def test_production_prompts_load_with_the_expected_placeholders():
    placeholder = re.compile(r"\{[A-Za-z_][A-Za-z0-9_]*\}")

    daily = set(placeholder.findall(load_prompt(DAILY_PROMPT)))
    insights = set(placeholder.findall(load_prompt(INSIGHTS_PROMPT)))

    assert daily == {"{transcript}", "{user_profile}"}
    assert insights == {"{period}", "{daily_summaries}", "{user_profile}"}


def test_daily_prompt_uses_only_profile_fields_sent_by_the_app():
    prompt = render_daily(
        load_prompt(DAILY_PROMPT),
        {
            "name": " Taylor ",
            "interests": ["Drawing", "Guitar"],
            "concerns": ["Finding time"],
            "email": "not-sent@example.com",
        },
        "  I finished a sketch.  ",
    )

    assert "Name: Taylor" in prompt
    assert "Interests: Drawing; Guitar" in prompt
    assert "Concerns: Finding time" in prompt
    assert "TRANSCRIPT: I finished a sketch." in prompt
    assert "not-sent@example.com" not in prompt
    assert "{" not in prompt and "}" not in prompt


def test_insights_prompt_sorts_notes_and_does_not_include_the_name():
    prompt = render_insights(
        load_prompt(INSIGHTS_PROMPT),
        {"name": "Taylor", "interests": ["Drawing"], "concerns": []},
        [("2026-09-08", "I finished it."), ("2026-09-07", "I began it.")],
    )

    assert "NOTES (7 September to 8 September):" in prompt
    assert prompt.index("I began it.") < prompt.index("I finished it.")
    assert "Interests: Drawing" in prompt
    assert "Name: Taylor" not in prompt
    assert "{" not in prompt and "}" not in prompt


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ('Short summary: "I made progress."', "I made progress."),
        ("```\nI made progress.\n```", "I made progress."),
        ('I told them "I am fine" and left.', 'I told them "I am fine" and left.'),
    ],
)
def test_response_cleanup_matches_the_swift_cleanup(raw, expected):
    assert clean_response(raw) == expected


def test_fake_data_matches_the_app_models():
    profile = json.loads((LAB_ROOT / "fake_data/profile.json").read_text())
    entries = json.loads((LAB_ROOT / "fake_data/diary.json").read_text())

    assert set(profile) == PROFILE_FIELDS
    assert entries
    for entry in entries:
        assert set(entry) == ENTRY_FIELDS
        assert entry["profileID"] == profile["id"]
        assert all(set(question) == {"id", "text"} for question in entry["questions"])
        assert (LAB_ROOT / "fake_data" / entry["transcriptPath"]).is_file()


def test_generated_output_matches_the_app_models():
    entry = json.loads((LAB_ROOT / "fake_data/diary.json").read_text())[0]
    daily = generated_entry(entry, "Filled prompt", "Generated summary")
    insight = generated_insight(entry, entry, "Filled prompt", "Generated insight")

    assert set(daily) == ENTRY_FIELDS
    assert daily["promptText"] == "Filled prompt"
    assert daily["summaryShort"] == "Generated summary"
    assert set(insight) == INSIGHT_FIELDS
