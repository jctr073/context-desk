# WritingBuddy

A macOS writing assistant. Paste in text, pick the transformations you want
(Rephrase / Expand / Shorten / Clean up) and the output formats you'd like
(Paragraphs / Bullets / Tables), then hit **Improve**.

Built in **SwiftUI** for macOS 13+. OpenAI models use the Responses API,
Claude models use Anthropic's Messages API, API keys are read from shell
profiles, and the app defaults to GPT-5.5 Medium. Providers without a live
client still use deterministic mock output for now.

## Features

- macOS-style window with custom titlebar, traffic lights, and a model
  picker tucked in the top-right.
- OpenAI GPT-5.5 and Anthropic Claude model picker options, including Opus
  4.7 effort levels.
- Multi-select operation chips with keyboard shortcuts (⌘1 – ⌘4).
- Multi-select output format chips (Paragraphs, Bullets, Tables).
- Input and context image attachments via picker, paste, or drag and drop.
- Attached images are previewed inline, can be opened in a lightbox, and are
  included in live OpenAI / Anthropic requests.
- System-wide Control-A / Control-Q import: copies selected text from any app
  into the input or context editor while WritingBuddy is running.
- Collapsible history sidebar with saved text, context, images, and outputs.
- Stacked or side-by-side layout (toggle via the floating Tweaks panel).
- Light & dark themes (toggle via Tweaks).
- History sidebar "+" starts a new session (⌘N).
- Diff view that highlights additions / deletions vs. the original input.
- Streaming-style skeleton placeholder while a run is in progress.

## Setup

Requires **Xcode 15+** and **macOS 13+**.

```sh
git clone https://github.com/jctr073/writing-buddy.git
cd writing-buddy
xcode-select --install
```

`xcode-select --install` is only needed if the Xcode command-line tools are
not already installed.

Live OpenAI and Anthropic requests need API keys. The app checks shell-profile
assignments in `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `~/.profile`,
`~/.bash_profile`, and `~/.bashrc`, plus the inherited process environment:

```sh
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
# Optional for future Google/Gemini support:
export GOOGLE_API_KEY="AIza..."
```

Google/Gemini appears in the picker for future support, but still uses mock
output until a live Google client is added.

## Run From Xcode

```sh
open WritingBuddy.xcodeproj
```

Press ⌘R in Xcode. The app launches with an empty editor; completed runs
are saved into the history sidebar.

## Build From Scripts

Build a release app bundle:

```sh
./scripts/build-app.sh
```

The packaged app is written to `.build/app/WritingBuddy.app`. The script also
generates the app icon, copies it into the bundle, and ad-hoc signs the app
when `codesign` is available.

Build a debug app bundle with the same script:

```sh
CONFIGURATION=Debug ./scripts/build-app.sh
```

Build and install into `/Applications`:

```sh
./scripts/install-system.sh
```

`install-system.sh` runs `build-app.sh`, copies the app to
`/Applications/WritingBuddy.app`, fixes permissions, and removes quarantine
metadata when possible. It uses `sudo` only when `/Applications` is not
writable by the current user.

Regenerate just the iconset, if you are iterating on the icon script:

```sh
./scripts/create-icon.swift .build/app-icon.iconset
iconutil -c icns .build/app-icon.iconset -o .build/WritingBuddy.icns
```

## Direct Xcode Build

For CI-style local verification without packaging:

```sh
xcodebuild \
  -project WritingBuddy.xcodeproj \
  -scheme WritingBuddy \
  -configuration Debug \
  -derivedDataPath .build/xcode-debug \
  build
```

There is no separate test target in the repo yet, so the main verification
step is a successful Xcode build.

## Project layout

```
WritingBuddy/
  WritingBuddyApp.swift     — @main entry, hidden-titlebar window
  AppState.swift            — single source of truth (input, ops, output…)
  Theme/
    Palette.swift           — light/dark color tokens (mirrors design)
    Layout.swift            — stacked vs side-by-side enum
  Models/
    Operation.swift         — Rephrase / Expand / Shorten / Clean up
    OutputFormat.swift      — Paragraphs / Bullets / Tables
    OutputBlock.swift       — paragraph | heading | bulletList | table
    RecentItem.swift        — persisted history items
    AIModel.swift           — model list
    AttachedImage.swift     — image loading, metadata, and base64 payloads
    OpenAIService.swift     — provider-dispatched AI writing clients
    GlobalSelectionShortcut.swift — system-wide selected-text import
    MockGenerator.swift     — deterministic fallback generator
    DiffEngine.swift        — LCS-based word diff
  Views/
    ContentView.swift       — top-level layout
    Titlebar.swift          — gradient titlebar
    ModelPicker.swift       — dropdown menu
    HistorySidebar.swift    — left sidebar with recents
    InputPane.swift         — toolbar + editor + footer (Improve button)
    OutputPane.swift        — toolbar + content (output / diff / streaming)
    OutputBody.swift        — renders [OutputBlock]
    DiffView.swift          — renders diff segments
    StreamingPlaceholder.swift — pulsing skeleton bars
    TweaksPanel.swift       — floating theme/layout toggles
    Components/
      ImageLightbox.swift   — attached-image preview modal
      Chip.swift            — multi-select toolbar chip
      IconButton.swift      — square icon-only toolbar button
      Kbd.swift             — keyboard-key visual
      Spinner.swift         — animated loading spinner
      TrafficLightsArea.swift — left-padding spacer for AppKit traffic lights
```

## Model routing

Live models call `AIWritingService.improve(input:context:customInstructions:operation:formats:model:apiKey:)`.
The UI passes one provider-neutral request: input text, reference context,
custom instructions, input/context images, selected operation, selected output
formats, and model.
`AIWritingService` then maps that request to the selected provider's API:
OpenAI receives `instructions` plus a text or multimodal `input` through the
Responses API, while Anthropic receives the same instructions as the Messages
API `system` value and sends text/images as user content blocks. Claude Opus
4.7 effort variants are sent as Anthropic `output_config.effort` with
adaptive thinking enabled. Provider key lookup checks the provider's
environment variable names in shell profiles and the inherited process
environment. It does not store or read keys from Mac Keychain.
