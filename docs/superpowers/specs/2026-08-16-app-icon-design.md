# Quill.app Icon and Application Packaging Design

## Goal

Package quill as a discoverable macOS application with a Dock/Finder icon while preserving its menu-bar-only behavior and LaunchAgent startup path.

## Design

Use the existing embedded feather SVG in `Sources/quill/UI/MenuBarController.swift` as the canonical artwork. Add a deterministic packaging step that rasterizes that SVG at the standard macOS icon sizes, builds `AppIcon.icns`, and assembles `Quill.app`.

The bundle layout is:

```text
Quill.app/
  Contents/
    Info.plist
    MacOS/quill
    Resources/AppIcon.icns
```

The bundle plist will declare the existing bundle identifier `com.digimata.quill`, a user-facing display name, `LSUIElement=true` so the app remains an accessory/menu-bar app without a Dock icon while still appearing in Applications, and `CFBundleIconFile=AppIcon`.

The existing source `Info.plist` remains embedded in the executable for TCC attribution. The app-bundle plist is packaging metadata and carries the same microphone and system-audio usage descriptions so permissions remain correctly explained when launched from the bundle.

## Packaging and installation

Add a repository build/package command or script that:

1. Builds the release executable with Swift Package Manager.
2. Generates the icon resources from the canonical feather SVG.
3. Creates `Quill.app` with the executable, icon, and bundle plist.
4. Installs the resulting bundle at `/Applications/Quill.app` when requested.

Update README installation instructions to use this app packaging path. Keep the `quill install --launch-at-login` command, but have its LaunchAgent execute `Contents/MacOS/quill` inside the installed app bundle. This avoids a second binary copy and keeps login startup behavior unchanged.

## Error handling

The packaging command fails immediately if the release build, SVG rasterization, icon conversion, bundle assembly, or copy into `/Applications` fails. It must not leave a partially assembled app presented as successful. Existing runtime permission and recording behavior is outside this change.

## Verification

Verify the observable contract by:

- building the release app from a clean checkout;
- checking that `Quill.app` contains the executable, plist, and `AppIcon.icns`;
- inspecting the plist for the bundle identifier, icon declaration, and accessory setting;
- confirming the icon file is a valid macOS icon resource;
- launching the bundled executable and confirming the existing menu-bar behavior still starts;
- installing the app and confirming Finder recognizes it as an application.

No new runtime feature or menu-bar behavior is introduced.
