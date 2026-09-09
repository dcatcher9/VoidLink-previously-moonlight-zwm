# Sunlight per-app 3D: native apps and online video

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

Active scope, clarified by the user on 2026-09-05: selected native games and video apps on iPhone, with directly connected USB-C glasses receiving power and SBS video. The named video targets are **YouTube, Bilibili, TikTok and Telegram**. Users should keep each app's familiar feed, account, search, comments and playback controls. Sunlight does not provide an SDK or require app developers to integrate code.

Whole-phone mirroring is retired. A Sunlight video player, extracted media URLs, downloaded-movie workflow, web replacements and emulator catalogs do not satisfy these named native-app requirements. The user has now selected container hosting for further investigation, with reliability as the priority, and requested comparison with other third-party containers. This does not resolve the earlier concerns about imported copies, login and updates. Glasses must remain unmodified, connected directly for power and video; all 3D conversion stays on the iPhone. Game titles are not yet specified. See the [container reliability and alternatives plan](sunlight-container-reliability.md).

## Intended native-app experience

The user selects a supported native app in Sunlight. A compatible guest runs its own interface and online playback while Sunlight remains the foreground host and owns the separate glasses output. The guest app retains responsibility for requesting its online content; the proposed Sunlight component obtains rendered frames and produces SBS. It does not replace the guest's player or require the user to download videos first.

“Local” describes running the app and 3D processing on the phone. The online app can still use its service normally, subject to account and guest compatibility. No PC or remote 3D processor is required by this design. Compatibility must validate networking and account behavior, not assume that every service works after re-signing.

LiveContainer is the concrete open-source hosting reference. It uses imported IPA guests and its own runtime/extension processes. This does not attach an arbitrary existing App Store app or automatically reuse its data and credentials. A hosted copy may need a new sign-in. [Architecture](https://livecontainer.github.io/docs/development/architecture), [container details](sunlight-local-app-hosting.md).

## What the named-app evidence actually establishes

Research date: 2026-09-05. None of these is a Sunlight/device compatibility pass.

| App | Primary evidence | Qualification status |
| --- | --- | --- |
| YouTube | A user reports routine use in LiveContainer 3.8.2 on iOS 26.5.2, followed by an exit/re-entry termination regression. A maintainer reported a fix on July 30. [Report](https://github.com/LiveContainer/LiveContainer/issues/1491), [fix](https://github.com/LiveContainer/LiveContainer/issues/1491#issuecomment-5130262371). | Strong first candidate. App version and full playback/login/capture coverage are not specified. |
| TikTok | A maintainer reports TikTok 39.7.0 working, while another reporter still failed. [Report](https://github.com/LiveContainer/LiveContainer/issues/505#issuecomment-2878371604). LiveContainer 3.6.63 has a concrete For You layout problem when a small guest window is maximized. [Layout report](https://github.com/LiveContainer/LiveContainer/issues/1139). | Candidate with a fixed-size guest layout. These reports do not certify the current phone/OS/app version. |
| Bilibili | A reporter on the iOS 26.5 beta 3 / LiveContainer April 25 nightly thread says Bilibili, including a tweaked build, did not show the launch crashes seen with their other apps. No Bilibili version or complete test is given. [Firsthand comment](https://github.com/LiveContainer/LiveContainer/issues/1310#issuecomment-4326042036). | Limited launch evidence only. Reports for PiliPala/PiliPlus are third-party clients and must not stand in for official Bilibili compatibility. |
| Telegram | Telegram 11.7.0 / LiveContainer 3.2.57 has a CloudKit-related crash; the maintainer identifies unavailable iCloud capability under the free-account setup and closes it as not planned. A Telegram 10.0.3 / LiveContainer 3.6.1 / iOS 26.0.1 / iPhone 17 Pro report is closed as a duplicate. [Maintainer diagnosis](https://github.com/LiveContainer/LiveContainer/issues/343#issuecomment-2649698218), [later report](https://github.com/LiveContainer/LiveContainer/issues/876). | Known historical account/capability obstacle. Neither permanently unsupported nor fixed on our configuration is established. A third-party Telegram client is not an equivalent acceptance result. |

Some reports involve modified packages. Do not turn those into a promise that an untouched App Store package works. No reviewed source proves fresh guest-video capture, independent USB-C SBS and acceptable latency together.

## Proposed implementation

### 1. One native guest, normal phone geometry

Launch one guest at the phone's normal content size from its first scene. Keep Sunlight's external scene separate. Do not begin with a tiny floating window and enlarge it: TikTok reportedly retains the initial feed geometry. Qualify orientation changes, keyboard, touch and fullscreen playback explicitly. Fixed initial geometry avoids the reported trigger; it is an untested mitigation, not a promised fix. [TikTok resizing explanation](https://github.com/LiveContainer/LiveContainer/issues/721#issuecomment-3145141052).

First demonstrate live interaction in the native guest while an independent moving pattern remains visible in the glasses. A live guest window or advancing media clock alone is insufficient.

### 2. Obtain guest frames without replacing its player

Start with consented capture of the hosted scene and prove it includes actual video/Metal pixels. This is a different ownership configuration from the retired background-mirroring probes: Sunlight stays foreground and the source is its hosted guest. Hosting by itself does not supply readable remote-layer pixels, so this remains an explicit gate.

For selected apps, a later **internal guest-player adapter** could obtain frames closer to the player's output to reduce compositing/capture delay. LiveContainer's architecture includes guest instrumentation through TweakLoader, which supplies a place to investigate such adapters without a publisher SDK. [Guest runtime](https://livecontainer.github.io/docs/development/architecture).

This is a hypothesis to inspect and test per app, not a universal video hook. AVPlayer, sample-buffer renderers and custom graphics pipelines differ; some buffers are compressed and may require another decode. Protected frames may remain inaccessible. No DRM bypass, automatic access to every video surface, or existing working adapter is claimed. The original app continues owning feed selection, playback, audio and controls.

### 3. Process and present

Pass timestamped captured frames to Sunlight's internal depth/stereo engine and existing foreground USB-C renderer. Establish synchronized 2D output before enabling depth inference. Determine whether the useful output is the whole guest view or its video region without replacing the native app's phone UI.

Bound the processing queue and use current frames rather than accumulating stale ones. Measure the guest's native presentation, hosted presentation without capture, 2D glasses output, and 3D output separately. Collect frame age, A/V sync, dropped frames and sustained thermals; for games also measure input-to-photon delay. No hosting-latency number is yet measured.

## Hosted app updates

Hosted apps are separate imported copies. Updating the normal App Store installation does not update the guest. LiveContainer can replace a guest with a newer IPA of the same bundle identifier; its replacement code carries forward container metadata, data UUID and app-specific settings. This is designed to retain data, not a guarantee that every login or application data migration succeeds. [Replacement implementation](https://github.com/LiveContainer/LiveContainer/blob/fe4c0ea7607322f7a2c7aa3111d7082054b14c8b/LiveContainerSwiftUI/Views/AppList/LCAppListView.swift#L630-L748).

Its Sources feature can refresh a source feed and install from an app's latest-version download URL. That is a source-based package workflow, not automatic App Store synchronization. [Sources guide](https://livecontainer.github.io/docs/guides/sources).

A proposed Sunlight updater would detect a new available package, qualify that exact version for hosting/capture/3D, and replace the guest while preserving its data container. Installation must stop the running guest. Stage and verify a replacement before removing the working bundle; retain recoverable data where possible. A binary-only rollback may not work after a new version migrates its data. Package availability and continued compatibility remain ongoing maintenance requirements. An online service can also stop accepting an older app version, so keeping an old known-good build is not an unlimited fallback. No updater is implemented yet.

## First qualification run

Begin with YouTube because the source evidence includes recent iOS 26 use. Use a specific compatible package/host version and record provenance and configuration. Proceed through import/launch, sign-in if needed, feed/search, ordinary online playback, Shorts/fullscreen, capture of fresh frames and independent glasses output. Account actions should be performed by the user; do not log credentials or private feed content.

Then test TikTok and Bilibili with the same gates plus rapid feed switching, comments, seeking, autoplay and service-specific layouts. Investigate Telegram's capability failure before treating it as ready. Protected content, notifications, login and app-version updates require distinct compatibility records.

The first success is **the actual native app playing online content, usable on the phone, with independently updating output in the glasses while Sunlight remains foreground**. Then insert 3D processing and measure its cost. No new host implementation, device install, or physical test was performed during this research update.

## Repository cleanup verification

The retired five diagnostic projects, launch hooks, probe-only helpers and standalone derived builds have been removed. Historical logs remain at their recorded paths. No iPhone apps were launched or uninstalled during cleanup.

- Existing foreground-display regression suite: **21 tests passed, zero failures**, including routing, reconnect, calibration and Metal lifecycle. Log: `Build/external-display-tests/20260905-194024-64416/console.log`.
- Unsigned Debug and Release builds: **passed**. Logs: `Build/hosting-cleanup/build-debug.log` and `Build/hosting-cleanup/build-release.log`.
- Project/plist validation, stale diagnostic reference checks and local documentation link checks: **passed**.
