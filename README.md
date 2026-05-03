# WritingBuddy

A macOS writing assistant. Paste in text, pick the transformations you want
(Rephrase / Expand / Shorten / Clean up) and the output formats you'd like
(Paragraphs / Bullets / Tables), then hit **Improve**.

Built in **SwiftUI** for macOS 13+. OpenAI models use the Responses API,
Claude models use Anthropic's Messages API, API keys are read from
`~/.zshrc` before falling back to Mac Keychain, and the app defaults to
GPT-5.5 Medium. Providers without a live client still use deterministic mock
output for now.

## Features

- macOS-style window with custom titlebar, traffic lights, and a model
  picker tucked in the top-right.
- OpenAI GPT-5.5 and Anthropic Claude model picker options.
- Multi-select operation chips with keyboard shortcuts (⌘1 – ⌘4).
- Multi-select output format chips (Paragraphs, Bullets, Tables).
- System-wide Control-A import: copies selected text from any app into the
  input editor while WritingBuddy is running.
- Stacked or side-by-side layout (toggle via the floating Tweaks panel).
- Light & dark themes (toggle via Tweaks).
- History sidebar with saved runs and a "+" to start a new session
  (⌘N).
- Diff view that highlights additions / deletions vs. the original input.
- Streaming-style skeleton placeholder while a run is in progress.

## Build & run

Requires **Xcode 15+** and **macOS 13+**.

```sh
open WritingBuddy.xcodeproj
```

Press ⌘R in Xcode. The app launches with an empty editor; completed runs
are saved into the history sidebar.

For a command-line release build:

```sh
scripts/build-app.sh
```

The packaged app is written to `.build/app/WritingBuddy.app`. To build and
copy it into `/Applications`:

```sh
scripts/install-system.sh
```

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
      Chip.swift            — multi-select toolbar chip
      IconButton.swift      — square icon-only toolbar button
      Kbd.swift             — keyboard-key visual
      Spinner.swift         — animated loading spinner
      TrafficLightsArea.swift — left-padding spacer for AppKit traffic lights
```

## Model routing

Live models call `AIWritingService.improve(input:context:customInstructions:operation:formats:model:apiKey:)`.
The UI passes one provider-neutral request: input text, reference context,
custom instructions, selected operation, selected output formats, and model.
`AIWritingService` then maps that request to the selected provider's API:
OpenAI receives `instructions` + `input` through the Responses API, while
Anthropic receives the same instructions as the Messages API `system` value
and the input as the user message. Provider key lookup checks the provider's
environment variable names in `~/.zshrc` first, then falls back to the
Keychain-saved key.
