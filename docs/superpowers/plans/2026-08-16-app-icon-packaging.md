# Quill.app Icon and Application Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and install a real `Quill.app` with a Finder/Application icon generated from quill’s existing feather artwork, while preserving menu-bar and LaunchAgent behavior.

**Architecture:** Move the feather SVG into a tiny statically linked `QuillArtwork` target so the runtime menu-bar icon and a new `quill-icon` generator share one source of truth. A packaging script builds the release executable, invokes `quill-icon` to create `AppIcon.icns`, and assembles the app bundle from a tracked bundle plist. The LaunchAgent resolves the installed app executable first, then retains a running-executable fallback for development and existing command-line installs.

**Tech Stack:** Swift 6, Swift Package Manager, AppKit, `iconutil`, macOS 15+, shell packaging script, Finder `.app` bundle.

## Global Constraints

- Use the existing feather SVG from `Sources/quill/UI/MenuBarController.swift` as the canonical artwork.
- Preserve `LSUIElement=true`; the app appears in Applications/Finder but remains menu-bar-only.
- Preserve bundle identifier `com.digimata.quill`.
- Preserve microphone and system-audio usage descriptions.
- Do not add a runtime resource dependency; artwork stays statically linked through Swift code.
- The installed LaunchAgent must execute `Quill.app/Contents/MacOS/quill`.
- Packaging must fail on build, icon generation, bundle assembly, or installation errors.

---

### Task 1: Share the canonical feather artwork

**Files:**
- Modify: `Package.swift`
- Create: `Sources/QuillArtwork/FeatherArtwork.swift`
- Modify: `Sources/quill/UI/MenuBarController.swift:89-100`

**Interfaces:**
- Produces `public enum FeatherArtwork` with `public static let svg: String`.
- `quill` imports `QuillArtwork` and uses `FeatherArtwork.svg` for its menu-bar image.
- The later `quill-icon` target imports the same type.

- [ ] **Step 1: Add the shared target declaration**

In `Package.swift`, add a target before the existing executable target:

```swift
.target(name: "QuillArtwork"),
```

Add `"QuillArtwork"` to the `quill` executable target dependencies.

- [ ] **Step 2: Move the exact SVG literal into the shared source**

Create `Sources/QuillArtwork/FeatherArtwork.swift`:

```swift
public enum FeatherArtwork {
    public static let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" \
    viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" \
    stroke-linecap="round" stroke-linejoin="round">\
    <path d="M12.67 19a2 2 0 0 0 1.416-.588l6.154-6.172a6 6 0 0 0-8.49-8.49L5.586 9.914A2 2 0 0 0 5 11.328V18a1 1 0 0 0 1 1z"/>\
    <path d="M16 8 2 22"/>\
    <path d="M17.5 15H9"/>\
    </svg>
    """
}
```

- [ ] **Step 3: Update the menu-bar controller to consume the shared type**

Add `import QuillArtwork` to `MenuBarController.swift`, delete its private `featherSVG` declaration, and change the image loader to:

```swift
guard let data = FeatherArtwork.svg.data(using: .utf8),
      let image = NSImage(data: data)
else { return nil }
```

Keep the existing 16-point image sizing and template-image behavior unchanged.

- [ ] **Step 4: Build the existing executable**

Run: `swift build -c debug --product quill`

Expected: PASS; the executable still builds with the menu-bar artwork supplied by `QuillArtwork`.

- [ ] **Step 5: Commit the artwork extraction**

```bash
git add Package.swift Sources/QuillArtwork/FeatherArtwork.swift Sources/quill/UI/MenuBarController.swift
git commit -m "Share feather artwork with app icon tooling"
```

---

### Task 2: Add the deterministic icon generator

**Files:**
- Modify: `Package.swift`
- Create: `Sources/quill-icon/main.swift`

**Interfaces:**
- Adds executable target `quill-icon` depending on `QuillArtwork`.
- CLI contract: `quill-icon --output <path-to-AppIcon.icns>`.
- Produces a valid `.icns` by rasterizing the shared SVG at 16, 32, 128, 256, 512, and 1024 pixel sizes and invoking `/usr/bin/iconutil`.

- [ ] **Step 1: Declare the generator target**

Add this target to `Package.swift`:

```swift
.executableTarget(
    name: "quill-icon",
    dependencies: ["QuillArtwork"]
),
```

- [ ] **Step 2: Implement strict argument parsing and output setup**

In `Sources/quill-icon/main.swift`, import `AppKit`, `Foundation`, and `QuillArtwork`. Require exactly `--output <path>`, create a temporary `.iconset` directory, and exit nonzero with a stderr message for missing arguments, an invalid SVG, failed PNG encoding, failed writes, or an `iconutil` failure.

- [ ] **Step 3: Rasterize the shared SVG into iconset PNGs**

Load `FeatherArtwork.svg` with `NSImage(data:)`. For each `(pixelSize, filename)` pair below, draw the SVG into an RGBA `NSBitmapImageRep`, encode it as PNG, and write it to the temporary iconset:

```swift
[
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
```

Use `NSGraphicsContext(bitmapImageRep:)`, draw into the full square rect with transparent background, restore the graphics state, and release the temporary directory with `defer`.

- [ ] **Step 4: Convert the iconset to `.icns`**

Run `/usr/bin/iconutil -c icns -o output iconsetURL.path` with `Process`, capture stderr, and throw/exit on a nonzero status. Create the output parent directory before invoking it.

- [ ] **Step 5: Build and exercise the generator**

Run:

```sh
swift run -c debug quill-icon --output .build/debug/AppIcon.icns
file .build/debug/AppIcon.icns
```

Expected: the generator exits 0 and `file` identifies a macOS icon resource rather than a text or empty file.

- [ ] **Step 6: Commit the generator**

```bash
git add Package.swift Sources/quill-icon/main.swift
git commit -m "Add deterministic Quill app icon generator"
```

---

### Task 3: Assemble and install `Quill.app`

**Files:**
- Create: `Packaging/Info.plist`
- Create: `scripts/build-app.sh`

**Interfaces:**
- `scripts/build-app.sh` with no arguments creates `.build/Quill.app`.
- `scripts/build-app.sh --install` creates/replaces `/Applications/Quill.app` after successfully building and validating the staging bundle.
- The staged bundle contains `Contents/MacOS/quill`, `Contents/Resources/AppIcon.icns`, and `Contents/Info.plist`.

- [ ] **Step 1: Add the bundle plist**

Create `Packaging/Info.plist` with these keys and values:

```xml
<key>CFBundleDisplayName</key>
<string>Quill</string>
<key>CFBundleExecutable</key>
<string>quill</string>
<key>CFBundleIdentifier</key>
<string>com.digimata.quill</string>
<key>CFBundleIconFile</key>
<string>AppIcon</string>
<key>CFBundleName</key>
<string>Quill</string>
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>CFBundleShortVersionString</key>
<string>1.0</string>
<key>CFBundleVersion</key>
<string>1</string>
<key>LSMinimumSystemVersion</key>
<string>15.0</string>
<key>LSUIElement</key>
<true/>
```

Copy the existing `NSMicrophoneUsageDescription` and `NSAudioCaptureUsageDescription` entries verbatim from `Sources/quill/Info.plist`.

- [ ] **Step 2: Add strict packaging script argument handling**

Create an executable `scripts/build-app.sh` using `set -euo pipefail`. Accept only no arguments or `--install`; print usage and exit 64 for anything else. Resolve the repository root from the script location so it works from any current directory.

- [ ] **Step 3: Build into a staging bundle**

The script must:

```sh
swift build -c release --product quill
swift build -c release --product quill-icon
BIN_DIR="$(swift build -c release --show-bin-path)"
BUILD_ROOT="$ROOT/.build"
STAGING="$BUILD_ROOT/Quill.app.staging.$$"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN_DIR/quill" "$STAGING/Contents/MacOS/quill"
cp "$ROOT/Packaging/Info.plist" "$STAGING/Contents/Info.plist"
swift run -c release quill-icon \
  --output "$STAGING/Contents/Resources/AppIcon.icns"
chmod 755 "$STAGING/Contents/MacOS/quill"
```

Use `ditto` or `cp` only after all build steps succeed. The script must not claim success when any command fails.

- [ ] **Step 4: Validate the staged bundle before optional installation**

Add shell checks that all three required files exist, then run:

```sh
plutil -lint "$APP/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "com.digimata.quill"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")" = "true"
file "$APP/Contents/Resources/AppIcon.icns"
```

Exit nonzero if any check fails.

- [ ] **Step 5: Install only a validated bundle**

For `--install`, copy the fully validated staging bundle to `/Applications/Quill.app`, replacing an existing app bundle only at that explicit flag. Print the final app path and the executable path used for CLI commands. With no flag, print the staging path and an `open` command.

- [ ] **Step 6: Mark the script executable and smoke-test packaging**

Run:

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
find .build/Quill.app/Contents -maxdepth 2 -type f -print
```

Expected: release executable, bundle plist, and `.icns` are present; plist and icon validation pass.

- [ ] **Step 7: Commit packaging**

```bash
git add Packaging/Info.plist scripts/build-app.sh
git commit -m "Package quill as a macOS application"
```

---

### Task 4: Point LaunchAgent installation at the app bundle

**Files:**
- Modify: `Sources/quill/Install.swift:97-115`

**Interfaces:**
- `resolveBinaryPath()` returns `/Applications/Quill.app/Contents/MacOS/quill` when installed.
- If the app is not installed, it returns the current absolute executable path for development and existing command-line installs.
- `writeAgent()` continues to emit `ProgramArguments: [binary, "run"]`; no LaunchAgent schema changes are needed.

- [ ] **Step 1: Prefer the installed app executable**

Replace the `/usr/local/bin/quill`-first resolution with this order:

```swift
let appBinary = "/Applications/Quill.app/Contents/MacOS/quill"
if FileManager.default.isExecutableFile(atPath: appBinary) {
    return appBinary
}
```

- [ ] **Step 2: Preserve the absolute running-executable fallback**

Keep the existing `CommandLine.arguments.first` absolute-path fallback and its note, but update the final error text to say the user should run `scripts/build-app.sh --install` or provide an installed executable. Do not change plist writing, launchctl bootstrapping, labels, or log paths.

- [ ] **Step 3: Build and inspect the command path**

Run: `swift build -c debug --product quill`

Expected: PASS. After Task 3’s install smoke test, run `quill install --launch-at-login` through the bundled executable and inspect the generated plist’s `ProgramArguments[0]`; it must equal `/Applications/Quill.app/Contents/MacOS/quill`.

- [ ] **Step 4: Commit LaunchAgent migration**

```bash
git add Sources/quill/Install.swift
git commit -m "Launch quill from the installed app bundle"
```

---

### Task 5: Update user-facing installation documentation

**Files:**
- Modify: `README.md:11-18,24-33,97-105,132-133`

**Interfaces:**
- README’s primary installation path builds and installs `Quill.app`.
- README explains that `LSUIElement` keeps Quill in the menu bar even though Finder recognizes it as an application.
- LaunchAgent documentation names the app-bundle executable as its target.

- [ ] **Step 1: Replace the binary-only install commands**

Use:

```sh
cd quill
./scripts/build-app.sh --install
open /Applications/Quill.app
```

Keep `quill install --launch-at-login` as the optional startup command, but show it as:

```sh
/Applications/Quill.app/Contents/MacOS/quill install --launch-at-login
```

- [ ] **Step 2: Update usage and CLI examples**

Explain that Quill appears in `/Applications` and Finder with a feather icon, but `LSUIElement` intentionally keeps it out of the Dock. Update CLI examples to use `/Applications/Quill.app/Contents/MacOS/quill` where a standalone command is required.

- [ ] **Step 3: Update architecture notes**

Replace the “single binary, no app bundle” sibling note with the actual app-bundle packaging model. Retain the statement that the executable embeds `Info.plist` for TCC attribution, and state that the app bundle also carries the user-facing plist metadata.

- [ ] **Step 4: Review documentation commands**

Run each new command against the built bundle, correcting only paths that do not work on macOS 15. Confirm no README section still instructs users to install only `/usr/local/bin/quill`.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md
git commit -m "Document Quill app bundle installation"
```

---

## Final Verification

Run from the repository root:

```sh
swift build -c release --product quill
scripts/build-app.sh
plutil -lint .build/Quill.app/Contents/Info.plist
file .build/Quill.app/Contents/Resources/AppIcon.icns
open .build/Quill.app
```

Expected:

- release build succeeds;
- `Quill.app` is recognized as an application;
- `AppIcon.icns` is a valid macOS icon resource;
- Finder shows the feather icon;
- launching the bundle starts the existing menu-bar app without a Dock icon;
- installing with `scripts/build-app.sh --install` places the app at `/Applications/Quill.app`;
- `install --launch-at-login` writes a LaunchAgent whose executable is inside the installed app bundle.
