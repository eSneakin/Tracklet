<img src="Resources/images/Tracklet%20Logo%20Light.png" width="88" alt="Tracklet icon">

# Tracklet

[English](README.md) · [Español](README.es.md)

**Your music, within reach.** A small, native macOS companion for Spotify, with desktop widgets in three sizes.

Connect Spotify, choose your style, and keep your music close without opening a full player.

New here? Start with **Download and first steps** below. You do not need to understand the code to use Tracklet. If you want to build or contribute, follow **Build it yourself**, then the [developer guide](DEVELOPMENT.md#english).

## What you can do

- See the song, artist, album, artwork, progress, and playback device.
- Pause, resume, skip, and go back from the app; use controls and track repeat in the large widget.
- Choose small, medium, or large widgets, appearance presets, and full-color, blurred, or monochrome artwork.
- Keep the last song visible when Spotify stops reporting playback, marked **Last played**.
- Use a compact, resizable window with blue accents and light/dark app icons.

Built with Swift, SwiftUI, WidgetKit, and native Apple APIs. No third-party runtime frameworks.

## Before you start

| Requirement | Details |
| --- | --- |
| macOS | The app declares macOS 13 as its minimum; desktop widgets require macOS 14. |
| Mac | The download contains Apple Silicon and Intel binaries. Local testing used Apple Silicon on macOS 27; other systems still need testing. |
| Spotify | Premium and an available playback device are required for controls. Tracklet does not play audio itself. |
| Developer access | If the Spotify application is in development mode, your account must be on its allowlist. See [Spotify's access rules](https://developer.spotify.com/documentation/web-api/concepts/quota-modes). |

## Download and first steps

Visit [Releases](https://github.com/eSneakin/Tracklet/releases) for available builds and [release notes](RELEASE_NOTES.md) for changes.

> **Development build:** version 1.0 is signed with Apple Development, not Developer ID, and is not notarized. Its integrity check passes, but the local Gatekeeper assessment rejects it. It is not yet a general-distribution installer. If macOS blocks it, use your own locally signed build or wait for a notarized release; do not disable Gatekeeper.

For an authorized development installation:

1. Unzip the download. Close any older Tracklet instance and copy `Tracklet.app` to **Applications**.
2. Open Tracklet and choose **Connect** to authorize Spotify.
3. Play a song in Spotify. Tracklet will pick it up and save its first playback snapshot.
4. Open macOS's widget gallery, find **Tracklet**, and choose a size.
5. Adjust artwork in **Widget** and the style in **Appearance**.

Keep Tracklet running for periodic synchronization. Closing a window is not the same as quitting: quitting stops the app's polling. Widget controls can ask macOS to launch the host app for an action.

If no download is visible, there may not be a published build available to your account yet. A draft release is not a public download; an open-source license and a published installer are separate things.

## How playback behaves

- **Playing:** progress advances locally; the app checks Spotify about every 30 seconds and after actions.
- **Paused:** artwork and metadata stay visible; progress stops.
- **Last played:** Spotify returned no playback, so Tracklet keeps the last confirmed song and position without pretending it is still playing.
- **Play:** first checks the current session. If Spotify confirms an active device but no item, Tracklet can restore a saved track with a valid URI. It cannot rebuild a lost queue or wake an unavailable device.
- **Previous:** at three seconds or more, restarts the current item. Before three seconds, requests the previous item.
- **Disconnect:** removes credentials and clears the account's playback snapshot.

WidgetKit schedules widget refreshes. An animated progress bar is a local timer, not a Spotify request every second.

**Why does the song stay visible while updating?** Tracklet keeps the last confirmed information on screen while it asks Spotify for new data. A slow connection should not make the card disappear. A temporary error is not the same as Spotify confirming that nothing is playing.

**Does Repeat do the same thing as Previous?** No. Previous restarts or goes back using the three-second rule. Repeat in the large widget turns repetition of the current track on or off.

## Technical terms, in plain language

You will encounter these names in setup instructions and bug reports. Here is what they mean for Tracklet:

| Term | What it means |
| --- | --- |
| OAuth + PKCE | The sign-in process that lets you authorize Tracklet through Spotify. PKCE helps tie the authorization to the app that started it, without embedding a client secret. |
| Scope | A specific permission, such as reading the current song or pausing playback. New permissions require a new authorization. |
| Access / refresh token | Credentials used to call Spotify and renew access. Treat both as secrets; never paste them into an issue. |
| Keychain | macOS's secure credential storage, where Tracklet keeps tokens. |
| Snapshot | A saved picture of playback data—not a screenshot—including the song, position and time it was checked. |
| App Group | A shared storage container that lets the app pass snapshots and artwork to its widget. It does not contain Spotify tokens. |
| Polling | Checking Spotify periodically for changes. Progress between checks is calculated locally. |
| Bundle | The complete `Tracklet.app` package, including the executable, widget and icons. Copy the whole package when installing. |

You do not need to configure these individually to use an already configured installation.

## Build it yourself

### 1. Get the source

```sh
git clone https://github.com/eSneakin/Tracklet.git
cd Tracklet
open Tracklet.xcodeproj
```

Xcode 27 was used to validate this version and compile its Icon Composer asset. Set your team and signing identity in [Configuration/Tracklet.xcconfig](Configuration/Tracklet.xcconfig). App and extension must use the same team and a compatible App Group.

### 2. Configure Spotify

Create your own app in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and register `tracklet://callback` as its redirect URI.

Configuration lives in [SpotifyConfiguration.swift](Sources/Tracklet/Configuration/SpotifyConfiguration.swift). For your build, set `SpotifyClientID` and `SpotifyRedirectURI` in [Tracklet-Info.plist](Configuration/Tracklet-Info.plist), or use `SPOTIFY_CLIENT_ID` and `SPOTIFY_REDIRECT_URI` in your development launch environment. The bundled Client ID is public but does not grant your account API access. Never add a client secret.

The **Client ID** identifies your application; it is not your Spotify password. The **redirect URI** is the address Spotify returns to after authorization. Keep `tracklet://callback` for the existing setup. If you change its scheme (`tracklet`), also update `CFBundleURLTypes` in the app's plist so macOS can route the callback correctly.

Configuration priority is **plist → launch environment → bundled defaults**. A plist value takes precedence over an environment variable. When testing through Xcode, launch variables belong in **Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables**; they are not automatically saved in an installed app.

### 3. Build and check

```sh
xcodebuild -project Tracklet.xcodeproj -scheme Tracklet \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .build/release ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build

swift test
ruby Scripts/check-app-icon.rb .build/release/Build/Products/Release/Tracklet.app
```

Your app is at `.build/release/Build/Products/Release/Tracklet.app`, including its extension and icons. Install this bundle; `swift run` alone does not install a widget.

Here, `xcodebuild` builds the complete app, `swift test` runs automated checks, and the Ruby script checks packaged icons. **Release** is a build configuration, not proof that an app is ready for public distribution. Signing and notarization still need to be handled separately.

The Xcode project is committed. Regeneration is optional: `Scripts/generate-xcode-project.rb` requires the `xcodeproj` Ruby gem and replaces the project when run.

## Finding your way around

See the bilingual [developer guide](DEVELOPMENT.md) for data flow, ownership and regression checks.

| Location | Responsibility |
| --- | --- |
| `Sources/Tracklet/Features` | Screens and observable playback/settings state |
| `Sources/Tracklet/Services/Spotify` | Authentication, API requests, playback actions |
| `Sources/Tracklet/Models` | Typed account and playback data |
| `Sources/Tracklet/Storage` | Credentials and app preferences |
| `Sources/Tracklet/Shared` | Snapshot storage and intents shared with the widget |
| `TrackletWidgetExtension` | Widget layouts and timeline provider |
| `Configuration`, `Resources`, `Tests` | Signing/version settings, icons, automated checks |

## Troubleshooting

| What you see | What to try |
| --- | --- |
| “Open Spotify to continue” | Open Spotify and start playback on the device you want to control. |
| Permission error / 403 | Check Premium, the developer allowlist, and permissions. After a scope change, Disconnect and Connect again. |
| Stale widget | Open Tracklet, check connectivity, and allow time for WidgetKit. After an update, removing and re-adding the widget may help. |
| Older app version | Quit Tracklet and launch the copy in Applications. Avoid running a second development copy. |
| Startup fails without internet | Credentials are retained. Restore connectivity and reopen Tracklet to retry. Fully offline profile restoration is not implemented. |
| Dark icon in Light mode | macOS controls icons separately: System Settings → Appearance → Icon & widget style → Default for the light icon. Install the complete updated app bundle. |
| Missing widget gallery icon | Install the complete app, not just its executable. If its icon appears in Applications but not the gallery, see the [developer diagnostics](DEVELOPMENT.md#english); packaging and system icon lookup are separate checks. Do not delete system-wide caches. |

## Privacy and security

Tokens stay in macOS Keychain. Preferences use UserDefaults (Apple's local settings storage); playback snapshots and cached artwork use an App Group container. Widget snapshots contain no access or refresh tokens. Actions run through the host app's Spotify service.

Archives do not include the developer's session or playback cache. Tracklet contacts Spotify for authentication, profile, playback, and images. It is an independent project, not an official Spotify app.

## Help make Tracklet better

Ideas, bug reports, documentation fixes, and accessibility feedback are welcome in [Issues](https://github.com/eSneakin/Tracklet/issues).

Include your macOS version, Mac architecture, Tracklet version, reproduction steps, and expected/actual behavior. Redact personal information from screenshots. Never post tokens, authorization codes, Keychain exports, or private signing keys.

For code changes, discuss larger ideas first, keep PRs focused, reuse existing services, and run the checks above. Update both language guides when behavior changes. Review the licensing status below before contributing code.

## License and publication status

Tracklet's original code and documentation are available under the [MIT License](LICENSE), copyright 2026 Enmanuel Lopez (eSneakin). You may use, modify, and redistribute them, including commercially, while retaining the copyright and license notices. The software is provided without warranty, as set out in the license.

Third-party reference material, content, and branding are not relicensed by this grant; see [third-party notices](THIRD_PARTY_NOTICES.md).

Before a general release: review third-party reference material and branding, decide repository visibility, configure Developer ID signing, and [notarize the app](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
