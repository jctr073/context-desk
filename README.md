# WritingBuddy

A macOS writing assistant. Paste in text, pick the transformations you want
(Rephrase / Expand / Shorten / Clean up) and the output formats you'd like
(Paragraphs / Bullets / Tables), then hit **Improve**.

Built in **SwiftUI** for macOS 13+. The "AI" output is a deterministic mock
(no API key required) — wire in a real model when you're ready.

## Features

- macOS-style window with custom titlebar, traffic lights, and a model
  picker tucked in the top-right.
- Multi-select operation chips with keyboard shortcuts (⌘1 – ⌘4).
- Multi-select output format chips (Paragraphs, Bullets, Tables).
- Stacked or side-by-side layout (toggle via the floating Tweaks panel).
- Light & dark themes (toggle via Tweaks).
- History sidebar with sample recents and a "+" to start a new session
  (⌘N).
- Diff view that highlights additions / deletions vs. the original input.
- Streaming-style skeleton placeholder while a run is in progress.

## Build & run

Requires **Xcode 15+** and **macOS 13+**.

```sh
open WritingBuddy.xcodeproj
```

Press ⌘R in Xcode. The app launches with sample input pre-loaded and an
initial mocked output already rendered, so you can see the design "alive"
on first paint.

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
    RecentItem.swift        — sample sidebar items
    AIModel.swift           — mocked model list
    MockGenerator.swift     — deterministic output generator
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

## Wiring a real LLM

`MockGenerator.generate(input:ops:fmts:model:)` is the single seam. Replace
its body with a call into the Anthropic SDK (or whatever provider you
prefer) and return `[OutputBlock]`. The 650 ms `Task.sleep` in
`AppState.run()` simulates network latency — drop or shorten it.
