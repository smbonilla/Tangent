# Tangent architecture

## Directory responsibilities

- `Tangent/App/` creates the SwiftData container and injects application dependencies.
- `Tangent/DesignSystem/` owns shared semantic colours and future reusable UI tokens.
- `Tangent/Features/Onboarding/` collects the initial profile using the same profile-saving logic as Settings.
- `Tangent/Features/Record/` and `Tangent/Features/Library/` own their respective SwiftUI views and feature logic.
- `Tangent/Domain/` contains persistence-independent app models and service protocols.
- `Tangent/Data/` contains SwiftData models, domain conversions, container setup, and the `NoteStore` implementation.
- `Tangent/Services/Audio/` and `Tangent/Services/Speech/` contain concrete media service implementations.
- `Tangent/Services/Intelligence/` contains the on-device language model: loading, downloads, summaries and insights. It is the only place that imports MLX.

## Dependency direction

Features depend on domain models and protocols. `Data` and `Services` implement those protocols, and `App` composes the implementations. Domain code does not import SwiftData, and feature code must not access `ModelContext` or persistence records directly.

## Persistence

`TangentModelContainer` owns the schema for user profiles, prompts, questions, diary entries, and insights. `SwiftDataNoteStore` provides async CRUD-style operations and converts between SwiftData records and domain values. Diary questions and populated prompt text are stored as historical snapshots.

Use an in-memory container for unit tests and previews. UI tests use an isolated store and preferences suite so relaunches can verify persistence. The app uses the default local SwiftData store; no data leaves the device.

## On-device generation

`DiaryLanguageModel` and `ModelCatalog` are domain protocols. Features use
these protocols; only `Services/Intelligence` imports MLX. `App` injects
`MLXDiaryLanguageModel` on devices and `UnavailableDiaryLanguageModel` on the
simulator, wrapped by `OptionalAIService`. The wrapper gates warmup, generation, and downloads using shared `AppPreferences`, cancels active work when disabled, and rejects late results. The simulator can exercise diary workflows without model inference.

`AppPreferences` persists AI and onboarding choices in UserDefaults. New installs start with AI off; existing installs retain their enabled workflow and skip onboarding. Completing onboarding saves the profile before marking setup complete. Downloads remain explicit in Settings. AI-off diary cards use transcript previews; daily details hide summaries, and Insights disables generation.

Recording saves an entry, then `DailyTangentDetailsViewModel` transcribes the
recording and, when AI is enabled, requests one short summary. It stores the sentence and its filled
prompt, and reuses the saved summary when the entry is reopened. There is no
background second generation task. Transcripts remain available in daily details.

`InsightsViewModel` filters entries by the selected date range and converts
nonempty short summaries to `DiarySummary` values. The language-model service
receives dates, summary text, and the user's interests and concerns.
`PromptTemplate` orders the summaries by date and asks for trends in that
range. Interests and concerns are optional context for what the writer may
want to hear about; they are not required. Transcripts are not inputs.
Entries without summaries are skipped.
The From/To range is capped per selected model: Qwen2.5 0.5B looks back 3 weeks,
Qwen3 0.6B and Gemma 3 1B 4 weeks, Qwen3 1.7B 6 weeks, and MedGemma 1.5 4B
2 weeks. Official context windows are 32K–128K tokens; on-device generation
stays inside the 4,096-input-token budget, and the largest model keeps the
shortest span because of memory.

`MLXDiaryLanguageModel` holds one loaded model. `MLXModelCatalog` downloads
weights to Application Support when requested in Settings. Diary content and
inference stay on the device; network access is used to download model weights.

The diary stores one short summary per entry. `ProfileSeeder` creates a profile
and the default prompts without resetting user edits.

Settings edits the user's name, interests, and concerns. The model catalog offers Qwen3 0.6B, Qwen2.5 0.5B, Qwen3 1.7B, Gemma 3 1B,
and MedGemma 1.5 4B. Qwen3 uses its tokenizer's non-thinking mode. Model choice
is stored separately from diary data, so switching does not change diary entries.

## Adding workflows

Keep persistence models and `ModelContext` in `Data`. Inject domain protocols
through `AppDependencies`; views and view models must not import SwiftData or
MLX to implement a workflow. Add tests for persistence changes and feature
behaviour in the existing test targets.

`ModelResourceGuard` checks user-initiated downloads using Apple's volume capacity
API and declares its disk-space reason in `PrivacyInfo.xcprivacy`. Loading reserves
twice the larger of actual/estimated weight bytes plus 768 MiB. Generation reserves
768 MiB plus 160 KiB per input/output token, with a 4,096-input-token limit and
128-token prefill batches. These are conservative estimates, not measured guarantees.
A monitor checks app-available memory every 200 ms and system memory-pressure signals;
downloads check remaining storage every second. Failures cancel work, discard partial
output, release model/cache memory, and surface actionable messages through existing UI.
Capacity checks use injected readings in tests; device capacity never leaves the app.

`OptionalAIService` routes warmup, summaries, and insights through one FIFO
`ModelOperationQueue`. The lease remains held across every await until work has
finished or finished cancelling. Queued requests report waiting/running status;
turning AI off cancels both active and queued requests. Downloads are independent.
