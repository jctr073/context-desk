# WritingBuddy

A macOS writing assistant. Paste in text or attach images, choose a rewrite
operation (Rephrase / Expand / Shorten / Clean up), pick an output shape
(Automatic / Paragraphs / Bullets / Tables), then hit **Submit**.

Built in **SwiftUI** for macOS 13+. OpenAI models use the Responses API,
Claude models use Anthropic's Messages API, API keys are read from shell
profiles or the inherited process environment, and the app defaults to GPT-5.5
Medium. Google/Gemini is present in the picker for future support and still
uses deterministic mock output for now.

## Features

- macOS-style window with custom titlebar, traffic lights, and a model
  picker tucked in the top-right.
- Grouped model picker with GPT-5.5 effort levels, Claude Opus 4.7 effort
  levels, Claude Sonnet 4.6, Claude Haiku 4.5, and a Gemini 2.5 Pro placeholder.
- Single operation selector with keyboard shortcuts (⌘1 – ⌘4).
- Automatic output mode plus optional multi-select format chips (Paragraphs,
  Bullets, Tables), with Markdown and Slack mrkdwn container options.
- Session-scoped custom instructions that are applied alongside the selected
  operation.
- Input and context image attachments via picker, paste, or drag and drop.
- Attached images are previewed inline, can be opened in a lightbox, and are
  included in live OpenAI / Anthropic requests.
- System-wide Control-A / Control-Q import: copies selected text from any app
  into the input or context editor while WritingBuddy is running. macOS
  Accessibility permission is required the first time this is used.
- Collapsible history sidebar with saved text, context, images, and outputs.
- Stacked or side-by-side layout (toggle via the floating Tweaks panel).
- Light & dark themes (toggle via Tweaks).
- History sidebar "+" starts a new session (⌘N).
- Output toolbar with Rendered / Raw modes, copy, regenerate, and diff view
  that highlights additions / deletions vs. the original input.
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
# or:
export GEMINI_API_KEY="AIza..."
```

Google/Gemini appears in the picker for future support, but still uses mock
output until a live Google client is added. If a live provider key is missing,
WritingBuddy opens an in-app setup sheet with the exact export line to add; it
does not save API keys itself.

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
  -destination "generic/platform=macOS" \
  -derivedDataPath .build/xcode-debug \
  CODE_SIGNING_ALLOWED=NO \
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
    OutputFormat.swift      — Automatic guidance + Paragraphs / Bullets / Tables
    OutputContainerFormat.swift — Markdown / Slack output container guidance
    OutputBlock.swift       — paragraph | heading | bulletList | table | codeBlock
    OutputBlock+Markdown.swift — Markdown export for rendered output blocks
    RenderMode.swift        — Rendered vs Raw output toggle
    RecentItem.swift        — persisted history items
    AIModel.swift           — model list
    AttachedImage.swift     — image loading, metadata, and base64 payloads
    APIKeyStore.swift       — shell-profile and environment API-key lookup
    OpenAIService.swift     — provider-dispatched AI writing clients
    GlobalSelectionShortcut.swift — system-wide selected-text import
    MockGenerator.swift     — deterministic fallback generator
    DiffEngine.swift        — LCS-based word diff
  Views/
    ContentView.swift       — top-level layout
    Titlebar.swift          — gradient titlebar
    ModelPicker.swift       — dropdown menu
    HistorySidebar.swift    — left sidebar with recents
    InputPane.swift         — toolbar + editor + footer (Submit button)
    OutputPane.swift        — toolbar + content (output / diff / streaming)
    OutputBody.swift        — renders [OutputBlock]
    DiffView.swift          — renders diff segments
    StreamingPlaceholder.swift — pulsing skeleton bars
    TweaksPanel.swift       — floating theme/layout toggles
    Components/
      ImageLightbox.swift   — attached-image preview modal
      APIKeySetupSheet.swift — provider API-key setup help
      CustomInstructionsSheet.swift — session instructions editor
      Chip.swift            — toolbar chip
      IconButton.swift      — square icon-only toolbar button
      Kbd.swift             — keyboard-key visual
      SegmentedToggle.swift — Rendered / Raw segmented control
      Spinner.swift         — animated loading spinner
      TrafficLightsArea.swift — left-padding spacer for AppKit traffic lights
```

## Model routing

Live models call `AIWritingService.submit(input:context:customInstructions:inputImages:contextImages:operation:formats:containerFormat:model:apiKey:)`.
The UI passes one provider-neutral request: input text, reference context,
custom instructions, input/context images, the selected operation, selected
output formats, selected output container, and model.
`AIWritingService` then maps that request to the selected provider's API:
OpenAI receives `instructions` plus a text or multimodal `input` through the
Responses API, including `reasoning.effort` for GPT-5.5 effort variants, while
Anthropic receives the same instructions as the Messages API `system` value and
sends text/images as user content blocks. Claude Opus 4.7 effort variants are
sent as Anthropic `output_config.effort` with adaptive thinking enabled.
Provider key lookup checks the provider's environment variable names in shell
profiles and the inherited process environment. It does not store or read keys
from Mac Keychain.
