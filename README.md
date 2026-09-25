# Ultra Look

A Quick Look extension for macOS that gives developer files a better preview in Finder:

- **Markdown**: rendered headings, lists, task lists, tables, quotes and highlighted code blocks, with a Preview / Raw toggle.
- **Source code**: syntax highlighting for 70+ languages, line numbers, a wrap toggle, and find (⌘F).
- **Archives**: browse zip, tar and tar.gz contents (folders, sizes, kinds) without extracting.

Everything runs locally. Previews never touch the network.

## Build

```bash
brew install xcodegen
xcodegen generate
open UltraLook.xcodeproj
```

Run the `UltraLook` scheme once, then enable **Ultra Look Preview** in System Settings › General › Login Items & Extensions › Quick Look. For the extension to register reliably, sign with your own team (set `DEVELOPMENT_TEAM` in `project.yml`) and run the app from `/Applications`.

Opening a file with Ultra Look (Open With, Dock drop, `open -a "Ultra Look" file`) shows it in the app's preview pane.

## Layout

| Path                | What |
| ------------------- | ---- |
| `UltraLookKit/`     | Shared framework: file loading, highlighter, markdown parser, archive readers, SwiftUI views |
| `PreviewExtension/` | The Quick Look preview extension (`QLPreviewingController`) |
| `App/`              | Host app with onboarding, sample files and imported UTI declarations |
| `Tests/`            | Unit tests for `UltraLookKit` |

## Notes

- `.ts` files are typed by macOS as MPEG-2 video, so Ultra Look doesn't claim them (`.tsx`, `.mts`, `.cts` work).
- Files without an extension (e.g. `Makefile`) have no specific type, so Quick Look won't route them to Ultra Look.
