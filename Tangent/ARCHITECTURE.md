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

## Recording and transcription (iOS 27)

`AVAudioRecorderService` owns one microphone engine. Its iOS 27 throwing tap supplies immutable Sendable buffers to a bounded
writer queue (64 buffers; each at most 16,384 frames and 8 channels). A serial
worker writes 16-bit PCM CAF before feeding speech. Queued buffers are released
after processing, so retained raw audio does not grow with recording length.
A full queue is a recording failure, never a silent dropped frame. Stop removes
the tap, drains accepted buffers, and closes the file off the main thread.
The audio background mode supports screen locking; interruptions, route-driven
engine changes, and media-service resets stop capture and preserve saved audio.

`OnDeviceTranscriber` uses `SpeechTranscriber` and one `SpeechAnalyzer` per
recording. There is no silence timeout, request rotation, overlap, or word-based
deduplication. Only finalized segments are requested, retaining Apple's spacing
and punctuation. `AnalyzerInputConverter` handles sample conversion and flushes
held-over samples at Stop. Live input retains at most 32 analyzer inputs; overflow
invalidates the live transcript and uses the complete disk recording for recovery.
`AssetInputSequenceProvider` supplies file audio on demand using the same engine.
Locale support and model installation use `AssetInventory`. Missing models do not
block recording: file transcription installs them later. No legacy Speech
Recognition authorization or server transcription is used.

`TranscriptCheckpoint` appends finalized text and synchronizes it to disk, with
atomic replacement for revisions. `PendingRecording` writes a JSON recovery
intent before capture, including the entry id, profile, day, and audio reference.
Launch snapshots pending intents and idempotently restores interrupted recordings
as audio-backed diary entries. Interrupted replacements recover as new entries so
the previous diary is preserved. The journal is removed only after the entry saves;
audio is removed only after a complete transcript and entry are both durable.
A process termination can lose samples still in the bounded in-memory queues;
this is not a guarantee against power loss or storage failure.

`DailyTangentDetailsViewModel` retries saved audio when required, then optionally
requests one short AI summary. It stores the sentence and filled prompt and reuses
the saved summary on reopening. Transcripts remain available with AI disabled.

Apple references:
- [SpeechAnalyzer lifecycle and input](https://developer.apple.com/documentation/speech/speechanalyzer)
- [AnalyzerInputConverter](https://developer.apple.com/documentation/speech/analyzerinputconverter)
- [CAF streaming format](https://developer.apple.com/library/archive/documentation/MusicAudio/Reference/CAFSpec/CAF_spec/CAF_spec.html)
- [Background audio session configuration](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record)

Device validation still requires a supported physical iPhone and installed speech
assets: record speech before and after several minutes of silence; repeat a phrase;
lock/unlock; change audio routes; interrupt with a call; force-quit and relaunch;
and check the full transcript after a long recording. Simulator tests exercise
conversion, persistence, queue overflow, and recovery without speech model downloads.

`InsightsViewModel` filters entries by the selected date range and converts
nonempty short summaries to `DiarySummary` values. The language-model service
receives dates, summary text, and the user's interests and concerns.
`PromptTemplate` loads the canonical text templates from bundled resources,
orders the summaries by date, and asks for trends in that
range. Interests and concerns are optional context for what the writer may
want to hear about; they are not required. Transcripts are not inputs.
Entries without summaries are skipped.
The From/To range is capped per selected model: Qwen3 0.6B and Gemma 3 1B
look back 4 weeks, Qwen3 1.7B 6 weeks, and Gemma 3n E2B and MedGemma 1.5 4B
2 weeks. Official context windows are 32K–128K tokens; on-device generation
stays inside the 4,096-input-token budget, and the largest models keep the
shortest span because of memory.

`MLXDiaryLanguageModel` holds one loaded model. `MLXModelCatalog` downloads
weights to Application Support when requested in Settings. Diary content and
inference stay on the device; network access is used to download model weights.

The diary stores one short summary per entry. `ProfileSeeder` creates a profile
and the default prompts without resetting user edits.

Settings edits the user's name, interests, and concerns. The model catalog offers Qwen3 1.7B (first and default), Qwen3 0.6B, Gemma 3n E2B, Gemma 3 1B,
and MedGemma 1.5 4B. For the first beta, onboarding and Settings grey out and disable
all controls for models other than Qwen3 1.7B; their backend support remains intact.
Qwen3 uses its tokenizer's non-thinking mode. Model choice
is stored separately from diary data, so switching does not change diary entries.
Gemma 3n E2B uses the text-only `mlx-community/gemma-3n-E2B-it-lm-4bit`
weights (about 2.55 GB) through the LLM factory. Saved selections of the removed
Qwen2.5 0.5B model fall back to the default Qwen3 1.7B.

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
