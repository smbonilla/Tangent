# Tangent prompt lab

This small development harness runs Tangent's production prompts against a local
Ollama model. The app and the harness read the same prompt files from
`Tangent/Tangent/Resources/Prompts/`.

Start Ollama and install a model, then run from the repository root:

```bash
ollama serve
ollama pull qwen3:0.6b

uv run --project prompt-lab run-prompts --day 2026-09-07
uv run --project prompt-lab run-prompts --all
uv run --project prompt-lab run-prompts --insights
```

Useful options:

```bash
# Inspect a filled prompt without calling a model.
uv run --project prompt-lab run-prompts --day 2026-09-07 --render-only

# Try a copied prompt without changing the app's production prompt.
uv run --project prompt-lab run-prompts \
  --prompt-file /path/to/daily-variant.txt --all

# Try another installed model.
uv run --project prompt-lab run-prompts \
  --model gemma3:1b --day 2026-09-07
```

Defaults mirror the app: temperature `0.2`, 120 output tokens for daily
summaries, 400 for insights, a single user message, and plain-text output.
Daily results are stored under `prompt-lab/output/daily/` as complete
`DiaryEntry` records with `promptText` and `summaryShort` updated, just as the
app saves them. Insight results are complete `Insight` records. The fake profile
uses the prompt-relevant `UserProfile` fields plus current settings fields,
while diary entries use the complete `DiaryEntry` schema. Legacy profile fields
that are not used by prompts are deliberately omitted.

Ollama and MLX may tokenize or quantize a model differently. Use this harness
for quick prompt comparisons, then confirm a chosen prompt in the iOS app.

## Tests

Run the deterministic tests from the repository root:

```bash
uv run --project prompt-lab pytest
```

The single test file covers the shared production prompt files, their exact
placeholder contracts, Swift-compatible profile and date rendering, ordering
of insight notes, privacy-sensitive field omission, response cleanup, and the
app-model schemas used by fixtures and generated output. The tests never start
or call a model.
