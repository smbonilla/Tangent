# Tangent

Created by us, for you, for no money. This is not a business.

**Developers:** Sierra Bonilla, George Drayson, and Magnus Ross.

Tangent is a private voice diary for your interests, concerns, and everyday ideas.
Record your thoughts, read them back, and choose if AI helps you reflect or not we don't mind. up to you.

## What it does

- Records voice entries and transcribes them on your device.
- Keeps multiple recordings per day as separate cards, ordered by recording start time. Use the circled plus in Diary to add another recording today or tap a past date in the calendar to record for that day; details show the recording's start time.
- Transcribes in the background while you speak, preserving earlier speech across pauses and long recordings. If live recognition fails, the complete recording is kept for on-device recovery in short, overlapping windows.
- Optionally generates one short summary per entry.
- Finds insights across your short summaries, guided by your interests and concerns.
- Lets you choose from small Qwen, Gemma, and MedGemma models in Settings.

AI starts off. Without it, your diary contains just your transcripts. Choose and download a model during onboarding to enable **AI summaries**, or continue without AI. You can download, switch, and remove models in Settings later. AI stays off until the selected model is downloaded, and removing the active model turns AI off.

## Privacy

Your diary, transcription, and AI processing stay on your device. Model downloads
come from Hugging Face when you choose to download them.

iOS asks for Speech Recognition permission with a standard warning about sending
speech to Apple. Tangent uses on-device recognition only: it checks device support
and requires local processing for every request. If unavailable, transcription
stops instead of uploading audio.
[Apple explains this setting here](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).

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

Use an Apple Silicon Mac with Xcode and Python 3. From the repository root, run:

```sh
python3 scripts/environment.py auto --resolve --open
```

The helper selects dependencies for your Xcode version. Select the **Tangent**
scheme, configure your signing team for a physical device, and run.
The app requires iOS 18.2 or later. AI needs a supported physical device;
the simulator can run the interface but not model inference.

See [architecture](Tangent/ARCHITECTURE.md) for the code layout.

Go on then, record a few tangents!
