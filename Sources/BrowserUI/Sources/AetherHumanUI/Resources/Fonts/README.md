# Aether brand typeface

Drop the licensed **Scto Grotesk A** font files in this directory and Aether picks them up
automatically. No code change is required.

## Expected files

| File | Weight | Aether role |
|---|---|---|
| `SctoGroteskA-Regular.otf` | 400 | `AetherTextWeight.regular` — every chrome/body role |
| `SctoGroteskA-Medium.otf` | 500 (resolved for 450) | `AetherTextWeight.emphasis` — row titles, panel titles, emphasis |
| `SctoGroteskA-RegularItalic.otf` | 400 italic | optional |
| `SctoGroteskA-MediumItalic.otf` | 500 italic | optional |

Exact filenames do not matter; the file *names inside* the font do. `AetherFontRegistry`
enumerates the family `Scto Grotesk A` through `NSFontManager.availableMembers(ofFontFamily:)`
and reads each face's real `kCTFontWeightTrait` through CoreText.

## Weight contract

Aether's browser chrome supports **two weights only**:

* **400** — regular
* **450** — emphasis

Scto Grotesk A ships Thin/Light/Regular/Medium/Bold/Black, so `emphasis` (450) resolves to the
first registered face at or above 450 — in practice **Medium**. No synthetic emboldening is used,
and no chrome surface may request 500, 600, or 700. The `AetherType` API cannot express them.

## Where the files are found

`AetherFontRegistry.install()` scans, in order:

1. `Contents/Resources/Fonts` (bundled `.app`)
2. the executable's directory `Fonts/` and `Resources/Fonts/`
3. the `Fonts/` directory inside any `*.bundle` next to the executable (SwiftPM resource bundle)

The files are registered for the process with `CTFontManagerRegisterFontsForURL`. If no file is
present the app renders with the system face at the same numeric weights (Mac `systemFont(ofSize:weight:)`
with an interpolated weight from Apple's own `NSFont.Weight` anchors), so type stays correct
without the brand face. Licensing the font is a human decision; this repository does not ship it.
