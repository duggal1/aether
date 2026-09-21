# Aether brand typeface

Drop the **Instrument Sans variable font** in this directory and Aether picks it up
automatically. No code change is required.

## Expected files

| File | Axis | Aether role |
|---|---|---|
| `InstrumentSans-Variable.ttf` | wght 400–700 | exact 400 / 450 / 500 instances via the variation axis |

`AetherFontRegistry` enumerates the family `Instrument Sans` through
`NSFontManager.availableMembers(ofFontFamily:)`, resolves the `Weight` variation
axis identifier at runtime, and instantiates exact `wght` values with
`CTFontCreateCopyWithAttributes`. No synthetic emboldening is used.

## Weight contract

Aether's browser chrome supports **three weights only**:

* **400** — regular: body copy, list rows, URLs, placeholders, labels
* **450** — emphasis: row titles, tab titles (interpolated variable instance)
* **500** — medium: panel headings, active states, primary buttons

No chrome surface may request 600 or 700. The `AetherType` API cannot express them.
Symbols always render in SF Symbols, never in this face.

## Where the files are found

`AetherFontRegistry.install()` scans, in order:

1. `Contents/Resources/Fonts` (bundled `.app`)
2. the executable's directory `Fonts/` and `Resources/Fonts/`
3. the `Fonts/` directory inside any `*.bundle` next to the executable (SwiftPM resource bundle)

The files are registered for the process with `CTFontManagerRegisterFontsForURL`. If no file is
present the app renders with the system face at the same numeric weights (Mac `systemFont(ofSize:weight:)`
with an interpolated weight from Apple's own `NSFont.Weight` anchors), so type stays correct
without the brand face. Instrument Sans is OFL-licensed and ships in this repository.
