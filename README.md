# Tangent

Created by us, for you, for no money. This is not a business.

**Developers:** Sierra Bonilla, George Drayson, and Magnus Ross.

Tangent is a private voice diary for your interests, concerns, and everyday ideas.
Record your thoughts, read them back, and choose if AI helps you reflect or not we don't mind. up to you.

## Try Tangent

[Public beta on TestFlight](https://testflight.apple.com/join/ZTfE11xN).

Read [a blog post about Tangent](https://medium.com/@smbonilla/we-didnt-win-a-hackathon-but-we-re-releasing-the-app-we-built-anyway-11caac402001).

## What it does

- Records voice entries and transcribes them on your device.
- Optionally generates one short summary per entry.
- Finds insights across your short summaries, guided by your interests and concerns.
- Current implementation uses the Qwen3 1.7B model, but we plan to let users choose from other Qwen variants, Gemma, and MedGemma models in Settings.

AI starts off. Without it, your diary contains just your transcripts. Choose and download a model during onboarding to enable **AI summaries**, or continue without AI. You can download, switch, and remove models in Settings later. AI stays off until the selected model is downloaded, and removing the active model turns AI off.

## Privacy

Your diary, transcription, and AI processing stay on your device. Model downloads
come from Hugging Face when you choose to download them.

Transcription uses Apple's on-device `SpeechAnalyzer` and `SpeechTranscriber`.
Speech language assets may download from Apple when needed; recordings are never
uploaded. Only microphone permission is requested.
[Apple documents the distinction from legacy speech recognition here](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition).

## Long recordings

Pauses do not end a recording. One speech session processes the full timeline,
and finalized segments are saved as they arrive. Microphone audio is continuously
written to a temporary 16-bit PCM CAF file, with a fixed limit on queued buffers.
CAF avoids depending on an MP4 index being finalized at Stop. The temporary audio
uses approximately 5.8 MB per minute at 48 kHz mono; it is removed only after the
complete transcript and diary entry have both been saved.

If live recognition cannot keep up or speech assets are missing, the full saved
file is transcribed using Apple's demand-driven file reader. Audio interruptions
and write failures stop capture and preserve the saved prefix. A recovery journal
makes interrupted recordings discoverable in the diary after relaunch. Recording
can continue with the screen locked through the audio background mode.

## Make it your own

You can change the interface, prompts, or model choices in the source code. The
production prompts are plain text files in
[`Tangent/Tangent/Resources/Prompts`](Tangent/Tangent/Resources/Prompts), and the
local [prompt lab](prompt-lab/README.md) can run them against Ollama.
To add a model, update [SummaryModelID](Tangent/Tangent/Domain/SummaryModelID.swift)
and [MLXModelConfigurations](Tangent/Tangent/Services/Intelligence/MLXModelConfigurations.swift)
with its Hugging Face repository, configuration, and resource estimates.
Models must use a format and architecture supported by the installed MLX version
and fit your device's storage and memory. Settings lists the models configured
in the app; it does not accept arbitrary repository names.

## Build

Use an Apple Silicon Mac with Xcode 27 (including its iOS 27 platform and Metal toolchain) and Python 3. From the repository root, run:

```sh
python3 scripts/environment.py auto --resolve --open
```

The helper checks the toolchain and uses the pinned dependencies in the shared project. Select the **Tangent**
scheme, configure your signing team for a physical device, and run.
The app requires iOS 26 or later. AI needs a supported physical device;
the simulator can run the interface but not model inference.

See [architecture](Tangent/ARCHITECTURE.md) for the code layout.

Go on then, record a few tangents!
