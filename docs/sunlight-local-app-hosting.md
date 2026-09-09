# Sunlight local app hosting

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

Candidate within the user's [per-app 3D direction](sunlight-per-app-3d.md), clarified on 2026-09-05: offer compatible local apps in Sunlight's library and run them inside Sunlight while it processes and presents SBS on directly connected USB-C glasses. The cable supplies both video and power. Sunlight does not provide a publisher SDK or require target-app developer integration. The named targets are the native YouTube, Bilibili, TikTok and Telegram apps, retaining their own online playback and controls. Sunlight-player, website and emulator substitutes are outside this requirement. Hosting and 2D-to-3D conversion are not implemented or physically validated yet.

## What hosting means

The user reaffirmed container hosting on 2026-09-05 and asked for greater reliability and alternative runtimes. The [reliability and alternatives plan](sunlight-container-reliability.md) records the current recommendation and the first implementation gates. This is an accepted research direction, not a validated hosting implementation.

LiveContainer is a concrete reference for a native app launcher, rather than an emulator or remote streamer. It imports IPA packages and can run guest apps through its own runtime and extension processes, with hosted scenes shown in virtual windows. Its original uses include sideloaded app libraries, multiple versions/data profiles, and multitasking. [Project](https://github.com/LiveContainer/LiveContainer), [multitask guide](https://livecontainer.github.io/docs/guides/multitask).

This does **not** automatically adopt an app already installed from the App Store, its data, or its credentials. An imported guest is a separate copy. The current FAQ documents iOS 26.4+ support with LiveContainer 3.6.65 or later and identifies encrypted/FairPlay app packages as a loading failure. Prefer developer-provided or source-built packages. A host version's OS support is not proof that a particular guest works on our phone. [Compatibility FAQ](https://livecontainer.github.io/docs/faq/app-crashes).

The named video targets are YouTube, Bilibili, TikTok and Telegram; game titles and the acceptable package-import workflow are still to be confirmed. Online content remains fetched and played by each guest app. No imported-app coverage is being represented as support for an existing App Store installation. See the [named-app findings](sunlight-per-app-3d.md) for evidence and qualification gates.

## Proposed Sunlight behavior

The app list would have a local library alongside existing PC sources. Selecting a qualified local entry would create a guest session inside Sunlight. Phone touch/keyboard/controller input would go to that session, and Sunlight's foreground external-display coordinator would own glasses presentation. The initial prototype should run one guest at a time.

The intended image path is:

```text
Hosted app renders → capture its pixels → depth + stereo synthesis → SBS glasses output
```

Scene hosting alone does not supply readable GPU pixels. First verify that a consented capture route includes the hosted scene, including Metal/video content, while the host keeps independent glasses output. Do not assume UIView screenshots capture remote scenes or protected video. If controlled guest source is available, a direct frame-sharing experiment can be evaluated separately.

## Compatibility qualification

Track exact guest app version, host build, phone/iOS, and graphics/output configuration. Record import, launch, input, login, saves, sustained rendering, capture and glasses output separately. A successful launch is not sufficient to mark an app supported in 3D.

| Candidate | Qualification needed |
| --- | --- |
| Developer-owned UIKit/Metal fixtures | Establish native input, scene hosting, frame capture and output behavior without third-party account dependencies. |
| Source-built games and ordinary apps | Best initial real workloads; validate each build and its required services. |
| Commercial games with supplied compatible packages | Some work, but account, anti-tamper and signing requirements vary. Minecraft Bedrock 1.21.51 has a historical confirmed LiveContainer result, not Sunlight validation. [Report](https://github.com/LiveContainer/LiveContainer/issues/292#issuecomment-2568564693). |
| Video apps | Qualify actual playback and capture. Protected FairPlay video can be black during recording even when the app itself runs. [Apple capture documentation](https://developer.apple.com/library/archive/qa/qa1970/_index.html). |
| Apps depending on guest-specific entitlements, push or extensions | The documented host model does not preserve all guest entitlements and does not support guest extensions or remote push. Shared permissions and weaker separation between guest data also affect product design. [Architecture limitations](https://livecontainer.github.io/docs/development/architecture#limitations). |

Static package checks can identify architecture, encryption and declared capabilities. Runtime qualification is required for login, save/load, rendering and capture. Compatibility records should include failure reasons and dates rather than a blanket supported-app count. LiveContainer's implementation uses private hosting/loading mechanisms and is distributed through sideloading; it is not an established ordinary App Store integration. Its source is AGPL-3.0, which must be considered before incorporating it into a distributed product. [Installation](https://livecontainer.github.io/docs/installation), [license](https://github.com/LiveContainer/LiveContainer/blob/main/LICENSE).

## Measure latency instead of guessing

No reproducible official hosting-latency benchmark was identified. Native execution removes the need for phone emulation or a network round trip, but does not establish zero hosting overhead.

Use the same developer-owned animated/input fixture in four configurations:

1. Standalone on the phone: establish the original input-to-visible-response baseline.
2. Hosted, no capture or 3D: measure hosting's incremental input/render delay and frame pacing.
3. Hosted with captured 2D on glasses: isolate capture, frame transfer and external presentation.
4. Hosted with 3D: measure the extra inference/stereo work, queueing, and sustained thermal behavior.

Record median and p95 latency, frame intervals, drops, memory and thermal state. Keep launch time separate from interactive latency. Use frame IDs/timestamps for pipeline attribution; measure actual input-to-photon behavior separately because an enqueue or GPU completion timestamp is not physical display visibility. At 60 Hz, each queued frame adds about 16.7 ms, so favor the latest available frame over a growing queue. That is a design target, not a measured result.

The first acceptance gate is simultaneous interactive guest content on the phone and a moving independent pattern in the glasses with Sunlight foreground. The next gate is fresh, capturable guest pixels on the glasses. Only then integrate depth inference and evaluate app-specific latency.

## Cleanup of the retired background-output approach

At the user's request, the background AVPlayer, raised-window Metal, ReplayKit/PiP, native AVKit, and long-form routing diagnostic projects were removed, together with their media, generators, main-app launch hooks, probe-only coordinator helpers and standalone derived build directories. The iOS 26 background-GPU capability-only log was also removed.

Foreground USB-C routing, readiness, SBS calibration, PC streaming and their existing regression tests remain the foundation for this direction. Historical research documents are marked superseded; device console logs remain at their recorded paths under `Build/`. No app-hosting code was added as part of cleanup and no iPhone app was launched or uninstalled.
