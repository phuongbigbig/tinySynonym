# Menubar Thesaurus

A lightweight macOS menu bar app that instantly shows synonyms when you select a word anywhere on your Mac. Double-click a word in any application — a browser, text editor, PDF reader, or Word — and a small dropdown appears from the menu bar with relevant synonyms. Click any synonym to copy it to your clipboard.

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (arm64) Mac
- Accessibility permission (prompted on first launch)

## Build & Install

```bash
# Build the app
cd Menubar_thesaurus
bash build.sh

# Install to Applications
cp -r build/MenubarThesaurus.app /Applications/

# Run
open /Applications/MenubarThesaurus.app
```

No Xcode project is needed — the build script compiles directly with `swiftc`.

On first launch, macOS will prompt you to grant Accessibility access in **System Settings > Privacy & Security > Accessibility**. The app needs this to read selected text from other applications.

## How It Works

1. The app lives in your menu bar (book icon) with no Dock icon.
2. It polls the macOS Accessibility API every 0.4 seconds to check for selected text.
3. When a single English word is selected, it looks up synonyms from multiple sources.
4. A floating dropdown panel appears below the menu bar icon showing the results.
5. The dropdown auto-dismisses after 10 seconds or when the word is deselected.
6. Click any synonym to copy it to your clipboard (the icon briefly shows a checkmark).

## Synonym Sources

The app queries four sources in parallel, merging results with duplicates removed. Each source is shown in a subtly different text color so you can tell where results come from:

| Source | Description | Color |
|---|---|---|
| **Offline (curated)** | ~450 common words with hand-picked, high-quality synonyms. Also includes a 26K-word WordNet-based thesaurus. | Default text color |
| **Free Dictionary** | Synonyms from the Free Dictionary API. | Teal |
| **Datamuse (synonym)** | Strict synonyms from the Datamuse `rel_syn` endpoint. | Lavender |
| **Datamuse (means like)** | Broader semantically similar words from the Datamuse `ml` endpoint. Produces Word-style results for less common words. | Amber |

Priority order: offline curated data is shown first (best quality), then strict synonyms, then dictionary results, then "means like" results to fill remaining slots.

## Word Stemming

The app handles inflected word forms automatically. Selecting "evaluating" will find synonyms for "evaluate", "running" maps to "run", "happier" to "happy", and so on. Supported inflections include: -ing, -ed, -s/-es, -er, -est, -ly, -tion, -ment, -ness.

## Settings

All settings are accessible from the menu bar icon's dropdown menu:

- **Enabled** — Toggle the app on/off without quitting. When disabled, the icon dims.
- **Launch at Login** — Start automatically when you log in to your Mac.
- **Offline Only** — Disable all network requests; use only the bundled thesaurus.
- **Max Synonyms** — Choose how many synonyms to display (3, 5, 8, 10, or 15).
- **Dropdown Opacity** — Adjust the transparency of the floating panel (30%–100%).
- **Source Colors** — Legend showing which color corresponds to which source.
- **Diagnostics** — Shows accessibility permission status, monitoring status, and any errors. Includes a quick link to open Accessibility settings.

Settings persist across app restarts via `UserDefaults`.

## Performance

The app is very lightweight:

- **CPU**: Near-zero idle usage. The only continuous work is a single Accessibility API call every 0.4 seconds, which returns immediately.
- **Memory**: ~2–3 MB (thesaurus data + UI).
- **Network**: Zero traffic until a word is selected. Each lookup makes 3 small API calls (a few KB each), then caches the result.
- **Battery**: Comparable to other menu bar utilities like Bartender or Rectangle.

## Project Structure

```
Menubar_thesaurus/
├── build.sh                              # Build script (swiftc, no Xcode needed)
├── generate_thesaurus.py                 # Script to regenerate thesaurus.json
├── MenubarThesaurus/
│   ├── Resources/
│   │   ├── Info.plist                    # App config (LSUIElement, bundle ID)
│   │   └── thesaurus.json               # 26K-word offline thesaurus
│   └── Sources/
│       ├── main.swift                    # App entry point
│       ├── AppDelegate.swift             # Menu bar setup, settings, menu actions
│       ├── SelectionMonitor.swift        # Polls Accessibility API for selected text
│       ├── SynonymProvider.swift         # Multi-source synonym lookup & caching
│       ├── SynonymPanel.swift            # Floating dropdown panel UI
│       ├── EmbeddedThesaurus.swift       # Curated synonyms for ~450 common words
│       └── WordStemmer.swift             # English word stemming (inflection → base)
└── build/
    └── MenubarThesaurus.app              # Built app bundle
```

## Key Technical Details

- **No Dock icon**: `LSUIElement` is set to `true` in Info.plist.
- **Floating panel**: Uses `NSPanel` with `.nonactivatingPanel` style so it doesn't steal focus from your current app.
- **Vibrancy**: The dropdown uses `NSVisualEffectView` with `.popover` material for a native macOS look.
- **Launch at Login**: Uses `SMAppService.mainApp` (macOS 13+) — no helper app needed.
- **Ad-hoc signing**: The build script signs with `codesign --sign -` for local use. For distribution, replace with a Developer ID.

## Uninstall

1. Quit the app from its menu bar icon (click icon → Quit).
2. Delete `/Applications/MenubarThesaurus.app`.
3. Optionally remove settings: `defaults delete com.phuong.MenubarThesaurus`

## License

Personal use. Not affiliated with any dictionary or thesaurus service.
