# ContextDesk

A macOS AI chat workspace with a persistent conversation rail, a multi-turn
chat thread, a dedicated output canvas, and a focused writing mode. Send text
or images, add reusable conversation context, choose a chat or writing
operation, and pin rendered assistant replies for copying, comparing, or
revising.

Built in **SwiftUI** for macOS 13+. OpenAI models use the Responses API,
Claude models use Anthropic's Messages API, live provider responses stream into
structured output blocks, API keys are read from shell profiles or the
inherited process environment, and the app defaults to GPT-5.5 Medium.
Google/Gemini is present in the picker for future support and still uses
deterministic mock output for now.

## Features

- macOS-style window with a custom titlebar, traffic lights, and a model
  picker in the top-right.
- Grouped model picker with GPT-5.5 effort levels, Claude Opus 4.7 effort
  levels, Claude Sonnet 4.6, Claude Haiku 4.5, and a Gemini 2.5 Pro
  placeholder.
- Three-pane workspace with a collapsible conversation sidebar, a multi-turn
  chat thread, and a resizable/hideable output canvas.
- Chat mode operations for Ask / Plan / Summarize / Compare / Translate, plus
  writing mode operations for Rephrase / Expand / Shorten / Clean up.
- Output format toolbar with Auto / Paragraphs / Bullets / Tables chips, plus
  Markdown and Slack mrkdwn raw-output views.
- Conversation-wide custom instructions that are applied alongside the selected
  operation.
- Conversation-wide context text and images that are sent with each live
  request in that conversation.
- Per-conversation Web toggle for hosted provider web search/fetch. It defaults
  off and adds safety guidance when enabled.
- Input and context image attachments via picker, paste, or drag and drop.
- Attached images are previewed inline, can be opened in a lightbox, and are
  included in live OpenAI / Anthropic requests.
- System-wide Control-A import: copies selected text from the frontmost app
  into the composer while ContextDesk is running. macOS Accessibility
  permission is required the first time this is used.
- Conversation sidebar with persisted threads, per-thread mode/operation,
  context, images, and outputs. The sidebar "+" starts a new conversation
  (⌘N), and saved conversations are capped to the most recent 50.
- Light and dark themes via the floating Tweaks panel.
- Output canvas with Rendered / Raw modes, reply tabs, copy, regenerate, and
  writing-mode diff view that highlights additions / deletions vs. the original
  input.
- Rendered output supports paragraphs, headings, bullet lists, tables, and
  syntax-highlighted code blocks.
- Tool activity renders inline as compact cards: web search shows a smart
  summary of result titles + favicons + domains, web fetch shows the fetched
  URL with an expandable preview, and consecutive code-execution steps roll
  up into one collapsible session. `<cite>` tags in the prose are replaced
  with inline favicon pills linking to the cited source.
- Live OpenAI / Anthropic responses stream incrementally through Server-Sent
  Events; Gemini uses the deterministic mock stream until live support is wired
  up.

## Setup

Requires **Xcode 15+** and **macOS 13+**. Xcode resolves the pinned SwiftPM
dependency for syntax highlighting automatically.

```sh
git clone https://github.com/jctr073/context-desk.git
cd context-desk
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
ContextDesk opens an in-app setup sheet with the exact export line to add; it
does not save API keys itself.

## Run From Xcode

```sh
open ContextDesk.xcodeproj
```

Press ⌘R in Xcode. The app launches into the chat workspace; completed runs
are saved into the conversation sidebar.

## Build From Scripts

Build a release app bundle:

```sh
./scripts/build-app.sh
```

The packaged app is written to `.build/app/ContextDesk.app`. The script also
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
`/Applications/ContextDesk.app`, fixes permissions, and removes quarantine
metadata when possible. It uses `sudo` only when `/Applications` is not
writable by the current user.

Regenerate just the iconset, if you are iterating on the icon script:

```sh
./scripts/create-icon.swift .build/app-icon.iconset
iconutil -c icns .build/app-icon.iconset -o .build/ContextDesk.icns
```

## Direct Xcode Build

For CI-style local verification without packaging:

```sh
xcodebuild \
  -project ContextDesk.xcodeproj \
  -scheme ContextDesk \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath .build/xcode-debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The repo includes an XCTest target for request encoding/decoding, streaming
parsers, structured output, and persistence. Run it from Xcode or with the same
project/scheme via `xcodebuild test` when you need more than a packaging build.

## Project layout

```
ContextDesk/
  ContextDeskApp.swift     — @main entry, hidden-titlebar window
  AppState.swift            — single source of truth (conversations, draft, canvas…)
  Theme/
    Palette.swift           — light/dark color tokens (mirrors design)
    Layout.swift            — legacy pane-layout enum
  Models/
    Operation.swift         — chat and writing mode operations
    OutputFormat.swift      — Auto / Paragraphs / Bullets / Tables chip state
    OutputContainerFormat.swift — Markdown / Slack raw-output options
    OutputBlock.swift       — paragraph | heading | bulletList | table | codeBlock
    OutputBlock+Markdown.swift — Markdown export for rendered output blocks
    RenderMode.swift        — Rendered vs Raw output toggle
    Conversation.swift      — persisted chat threads
    RecentItem.swift        — legacy persisted history items
    AIModel.swift           — model list
    AttachedImage.swift     — image loading, metadata, and base64 payloads
    APIKeyStore.swift       — shell-profile and environment API-key lookup
    OpenAIService.swift     — provider-dispatched streaming clients
    SSEEventStream.swift    — Server-Sent Events parser
    StructuredOutputSchema.swift — shared output block JSON schema
    StreamingOutputParser.swift — incremental structured-output parser
    GlobalSelectionShortcut.swift — system-wide selected-text import
    MockGenerator.swift     — deterministic fallback generator
    DiffEngine.swift        — LCS-based word diff
  Views/
    ContentView.swift       — top-level layout
    Titlebar.swift          — gradient titlebar
    ModelPicker.swift       — dropdown menu
    HistorySidebar.swift    — conversation sidebar
    InputPane.swift         — chat thread + composer + operation controls
    OutputPane.swift        — output canvas (reply tabs / diff / streaming)
    OutputBody.swift        — renders [OutputBlock] including tables and code
    DiffView.swift          — renders diff segments
    StreamingPlaceholder.swift — pulsing skeleton bars
    TweaksPanel.swift       — floating theme toggle
    Components/
      ImageLightbox.swift   — attached-image preview modal
      APIKeySetupSheet.swift — provider API-key setup help
      CustomInstructionsSheet.swift — conversation instructions editor
      ContextSheet.swift    — conversation context editor
      Chip.swift            — toolbar chip
      FormatDropdown.swift  — output container dropdown
      IconButton.swift      — square icon-only toolbar button
      Kbd.swift             — keyboard-key visual
      SegmentedToggle.swift — Rendered / Raw segmented control
      Spinner.swift         — animated loading spinner
      TrafficLightsArea.swift — left-padding spacer for AppKit traffic lights
```

## Model routing

The chat UI appends a user `ChatMessage`, creates an empty assistant placeholder,
and calls `AIWritingService.submitChatStream(turns:operation:customInstructions:model:apiKey:)`.
The active conversation's context text and images are folded into the first user
turn for the request, so the model sees the reusable reference material without
duplicating it into every saved message.

`AIWritingService` builds one provider-neutral `ChatSubmitPrompt`: transcript
turns, operation instructions, conversation-wide custom instructions, attached
images, the per-conversation Web toggle, and the selected model. OpenAI receives
`instructions` plus a multi-turn Responses API `input`, a forced `emit_output`
function tool, `stream: true`, and `reasoning.effort` for GPT-5.5 effort
variants. Anthropic receives the same system guidance through Messages API
`system`, image/text content blocks, `stream: true`, and the same
structured-output tool. Claude Opus 4.7 effort variants are sent as Anthropic
`output_config.effort` with adaptive thinking enabled.

Hosted OpenAI `web_search` and Anthropic `web_search` / `web_fetch` tools are
registered only when the conversation Web toggle is enabled. Tool telemetry
rendered in the UI comes from provider tool events; the final-answer schema does
not allow the model to invent tool cards.

Both live providers stream Server-Sent Events into `StreamingOutputParser`, which
turns partial JSON-schema/tool-output deltas into `[OutputBlock]` snapshots for
the thread and output canvas. Google/Gemini currently routes to mock output.
Provider key lookup checks the provider's environment variable names in shell
profiles and the inherited process environment. ContextDesk does not store or
read keys from Mac Keychain.
