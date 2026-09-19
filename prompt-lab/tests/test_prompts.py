import re

import pytest

from prompt_lab import (
    DAILY_PROMPT,
    INSIGHTS_PROMPT,
    clean_response,
    load_prompt,
    render_daily,
    render_insights,
)


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
