# Experimental iPhone windowing leads

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

> Historical record: on 2026-09-05 the user selected [per-app 3D integration](sunlight-per-app-3d.md), with container hosting as one candidate. The background-output probes and their source projects have been removed. Previous findings and device log paths are retained as evidence; proposed experiments below are not the active implementation plan.

Research date: 2026-09-05. Read-only web/source investigation; no new software was installed, no exploit was run, and no device settings or OS version were changed.

The requirement remains an iPhone with existing directly attached, phone-powered USB-C glasses, processing the real screen while arbitrary already-installed native apps are usable. A launcher limited to imported apps does not satisfy it. The user wants Sunlight invisible or small while retaining independent SBS output. The current test device is iPhone 17 Pro / iOS 26.6.1.

## Findings

The statement that iPhone cannot have multiple app windows is too broad outside the supported public app model. There are concrete implementations of system-wide scene hosting and system windowing. Their compatibility and privileges are the immediate constraints, and none establishes our complete capture-to-SBS pipeline.

| Implementation | Evidence | Limit for the current phone |
| --- | --- | --- |
| [Myrtle](https://m4fn3.github.io/repo/web/Myrtle.html) | Developer advertises movable/resizable installed-app windows. Its August 15 v1.5.0 notes add iOS 26 support and fix windowed scenes becoming white on backgrounding. | Requires a jailbreak. The broad iOS 26 claim does not establish availability on this iPhone/build. No independent glasses-output result. |
| [Cyanide Dynamic Stage Lite](https://github.com/0xjohnnydev/cyanide#supported-targets) | Open-source beta hosts another app scene alongside SpringBoard through RemoteCall. | Its iOS 26 range is 26.0–26.0.1 and explicitly excludes A19/M5. The relevant bugs were fixed in 26.1. Archived August 27; source includes unfinished features. |
| [mond](https://github.com/rooootdev/mond) / [GestaltEdit](https://github.com/frs0n/GestaltEdit) | Public implementations change system capability data to enable iPad-style UI/windowing on iPhone. GestaltEdit includes Stage Manager and iPad-app compatibility presets. | Documented for iOS 27 beta 1–4, not our 26.6.1. No claim that a current beta, an upgrade, or this specific phone is safe/compatible. |
| [Nugget](https://github.com/leminlimez/Nugget#sparserestorebookrestore-info) / [Misaka26](https://github.com/straight-tamago/misaka26) | Earlier MobileGestalt/iPadOS-mode approaches. | MobileGestalt support stops at 26.1 / 26.2 beta 1. Nugget's Stage Manager control is hidden on iPhone in current UI source; a broad version headline or visible settings toggle is insufficient proof of working iPhone windows. |

The underlying [bad_query project](https://github.com/forcequitOS/bad_query#readme) lists partial container access on iOS 26.0–26.6.1, but lists the SystemGroup access needed for MobileGestalt only on iOS 27. It does not establish a system-windowing route on 26.6.1. The mond maintainer's [26.6 support discussion](https://github.com/rooootdev/mond/issues/43#issuecomment-5264287367) does not give a release date. A positive [extended-display report](https://github.com/rooootdev/mond/issues/50) concerns an iPad mini 7 on iPadOS 27 public beta 2, not an iPhone or SBS conversion.

## Distinguish two hosting mechanisms

[LiveContainer's current implementation](https://github.com/LiveContainer/LiveContainer/blob/main/MultitaskSupport/AppSceneViewController.m#L49-L126) starts its own LiveProcess extension and obtains that extension's process identity before hosting its scene. This supports imported guest apps. It does not demonstrate attaching arbitrary installed app processes.

The related [FrontBoardAppLauncher](https://github.com/khanhduytran0/FrontBoardAppLauncher) hosts installed-app scenes but requires TrollStore and requests private FrontBoard/RunningBoard and sandbox privileges in its [entitlements](https://github.com/khanhduytran0/FrontBoardAppLauncher/blob/main/entitlements.xml). Ordinary sideloading does not establish those privileges. Merely hiding a host's controls changes neither boundary.

## Next experiments, with explicit gates

1. **Current phone, low-probability private-API capability probe:** determine whether a normally development-signed test can obtain and host the existing Settings app's scene using the newer scene-hosting API while its own phone scene remains foreground. Log unavailable APIs, permission errors, remote scene connection and touch responsiveness. Keep a synthetic moving L/R pattern in its own external window. A class being present, a launch succeeding, or a nonnil controller is insufficient: real Settings controls and the independent moving glasses image must both work. There is no positive source evidence that this unprivileged combination works on 26.6.1; this is a proposed test, not an implementation or workaround. Do not add unsigned private entitlements and represent them as granted.
2. **Already-compatible research device:** use actual system windowing, leave Sunlight small but visible, interact with native Settings beside it, and observe app/scene lifecycle plus physical independent glasses output. Only after that passes attach real ReplayKit capture and prove fresh guest pixels reach both eyes. Capture feedback, app compatibility, depth inference and thermal performance remain separate checks. Full minimization/occlusion must be tested separately from a visible small window.

Neither experiment was run during this search. The current phone's OS was not upgraded or downgraded. A system modification that can require device restoration is outside routine diagnostic installation and needs a concrete recovery plan and explicit authorization before execution.

## Other transport ideas checked

No primary source established a RayNeo USB framebuffer endpoint, independent per-eye crop of a PiP rectangle, or self-AirPlay that preserves independent wired output while the receiver app backgrounds. The current [Air 4 Pro FAQ](https://www.rayneo.com/products/rayneo-air-4-pro-ar-smart-glasses) describes companion-app conversion, so older processor-marketing language is not proof of an onboard conversion mode. The exact connected RayNeo model remains unrecorded.

Apple's [AVCaptureBroadcastVideoOutput](https://developer.apple.com/documentation/avfoundation/avcapturebroadcastvideooutput) remains a distinct iOS 27 DisplayPort capture-output lead, but the reviewed interface is tied to supported capture-device formats and offers no established public enqueue path for processed ReplayKit frames. It does not change the measured iOS 26 result.
