# External-display and SBS calibration validation

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

> Historical record: on 2026-09-05 the user selected [per-app 3D integration](sunlight-per-app-3d.md), with container hosting as one candidate. The background-output probes and their source projects have been removed. Previous findings and device log paths are retained as evidence; proposed experiments below are not the active implementation plan.

Date: 2026-09-04.

## Implemented behavior

- A fullscreen external scene creates a visible Sunlight readiness screen without a PC or stream.
- The scene configuration uses the actual UIKit noninteractive role, with older iOS compatibility.
- The scene owns its window; the coordinator owns the selected content request independently of display availability.
- A pending stream stays on the phone until a usable external window is present. Disconnect restores phone presentation; stopping a stream returns the glasses to readiness.
- Metal and AVSampleBuffer route their actual video views through the same coordinator.
- Window changes reuse one Metal render worker. Failed frame submissions return their acquired frame slot.
- Existing duplicate/Stage Manager and disabled presentation preferences are preserved.
- Display connection and geometry diagnostics include the observed mode, scale, and reported refresh ceiling, without host session data.
- The phone's Glasses panel starts/stops standalone SBS calibration and swaps eye order without requiring a PC. Dismissing the panel keeps calibration running.
- Calibration requires an explicit Start and a 3840 × 1080 mode with matching window pixel dimensions. Its two eye images use identical, zero-disparity circle/grid geometry and distinct LEFT/green and RIGHT/cyan labels.
- Calibration requests and eye order survive display reconnects and 2D/3D transitions within the app session. Incompatible or disabled output suspends the pattern. A PC content request cancels calibration and takes priority.

## Automated checks

Run `tests/run_external_display_tests.sh` from the repository. It builds a small UIKit test app using the production display components, runs on a dedicated temporary simulator, captures its console, exports readiness and calibration previews, and removes only that simulator afterward.

All 14 checks passed on the iOS 26.5 simulator. Twelve cover readiness visibility, both attachment orderings, immediate cleanup, replacement protection across main-queue turns, disconnect/reconnect, disabled presentation, stale-window cleanup, idempotence, and layout before change notifications. Two use the production Metal view with a fake rendering delegate to verify that eight direct window moves and four detached intervals retain one worker with no concurrent frame consumers, and that reattachment cannot restart a terminally stopped worker.

Artifacts for that run:

- `Build/external-display-tests/20260904-081216-23907/console.log`
- `Build/external-display-tests/20260904-081216-23907/readiness-1920x1080.png`

The 1920 × 1080 readiness preview was visually inspected: centered text, intact grid and border, and no clipping.

The subsequent calibration run passed **21 checks, zero failures** on iOS 26.5, retaining the 14 foundation checks and adding seven calibration cases. These cover explicit Start, exact mode and window pixel compatibility, pending requests and eye-order retention across reconnect/2D transitions, disabled output, PC priority, idempotent Start/Stop, and per-eye geometry/swap rendering. Clearing PC content when no PC owns the output is also verified to preserve calibration. Screen-mode doubles are scoped to the production compatibility query so unrelated UIKit layout uses the real simulator screen.

Latest calibration artifacts:

- `Build/external-display-tests/20260904-085018-27663/console.log`
- `Build/external-display-tests/20260904-085018-27663/calibration-normal-3840x1080.png`
- `Build/external-display-tests/20260904-085018-27663/calibration-swapped-3840x1080.png`

The normal and swapped patterns were visually inspected. Each eye occupies exactly 1920 × 1080 with a centered, round 432 × 432 circle and intact borders. Comparing corresponding eye images after swapping found only 12 and 14 pixels with one-level channel differences on antialiased circle edges. The pixel regression check permits at most 64 such pixels per eye and a maximum channel difference of 1/255; geometry assertions remain exact. This is rendering validation, not physical glasses validation.

The subsequent ownership run also passed **21 checks, zero failures**, with additional assertions in the existing cases for pending-view identity, guarded cleanup of matching requests, protection of newer pending and visible requests, and preservation of calibration. Log: `Build/external-display-tests/20260904-100058-31588/console.log`.

Runtime inspection confirmed that both UIKit external-display constants resolve to `UIWindowSceneSessionRoleExternalDisplayNonInteractive` on iOS 26.5. This differs from the old manifest's literal key, so the modern manifest entry is necessary.

The actual Glasses controls controller was also rendered in a separate UIKit harness at iPhone 17 Pro dimensions (402 × 874 points, 1206 × 2622 pixels). Active, disconnected, and scrolled instruction states were visually inspected with no clipping. The injected coordinator supplied preview state; the controls were the production implementation. Preview artifacts are in `Build/glasses-phone-preview/20260904-084726-26950/`. Both harnesses use private temporary simulators and remove them afterward.

## Device build and launch

- Xcode 26.6, iPhoneOS SDK 26.5.
- iPhone 17 Pro running iOS 26.6.1.
- Scheme `VoidLink`, Debug configuration; existing development signing identity and bundle identifier.
- A signed build succeeded and was installed and launched on the phone.
- Live console output is captured through a redaction filter that removes pairing/session-secret diagnostics and PEM blocks before writing the log.
- Initial device build log: `Build/external-display-device/build.log`.
- Initial live console: `Build/external-display-device/console.log`.
- Final build, including the Metal frame-slot fix, succeeded: `Build/external-display-device/build-final.log`.
- Final build installed and launched with ongoing live capture: `Build/external-display-device/console-final.log`.
- The subsequent SBS calibration build succeeded and was installed and launched on the phone: `Build/sbs-calibration-device/build.log`.
- Current calibration-build live console, using the same redaction filter: `Build/sbs-calibration-device/console.log`.
- A later reinstall confirmed `transportType: wired`, installed the same calibration build, and launched **Sunlight 3D**. Its connection, install, and redacted console records are in `Build/sbs-calibration-device/reinstall-usb/`.
- The USB reinstall's console capture ended when that app instance exited. A read-only process query found the user had reopened the same installed app as a new process; it was not restarted for diagnosis. The reopened process's calibration activation is confirmed by the user below, not by the earlier launch capture.

## Confirmed physical connection

The user connected the RayNeo glasses to the iPhone by USB-C and confirmed seeing the readiness screen. The ongoing final-build console recorded the external scene connecting and becoming active at 08:20:29, followed by disconnection at 08:21:18 (console timestamps). The app was not restarted for this check.

- Scene role: `UIWindowSceneSessionRoleExternalDisplayNonInteractive`.
- Active mode and native size: 1920 × 1080 pixels.
- Scale and native scale: 1.0.
- Reported maximum refresh rate: 60 Hz; actual presentation cadence was not measured.
- Advertised modes: 640 × 480, 800 × 600, 1024 × 768, 1280 × 720, 1280 × 768, 1280 × 1024, 1400 × 1050, 1680 × 1050, 1600 × 1200, 1920 × 1080, 1920 × 1200, 2048 × 1536, 2560 × 1440, and 2560 × 1600.

This passes the first physical acceptance check: automatic display detection and a dedicated visible Sunlight screen without starting a PC stream. The initial 2D-mode list did not include 3840 × 1080; the subsequent 3D-mode check below exposed it.

## Confirmed 3D-mode negotiation and reconnect

The user reconnected the glasses and enabled their 3D mode. The same running app process recorded the following sequence, without an app restart:

- 08:27:48: external scene connected at 1920 × 1080.
- 08:27:58: external scene disconnected during the hardware-mode transition.
- 08:27:59: external scene reconnected and became active at **3840 × 1080**, with scale/native scale 1.0 and a reported maximum of **60 Hz**. The available-mode list now included 3840 × 1080.
- 08:28:13: a later external-scene disconnection was recorded. A subsequent device query reported only the built-in LCD.

This confirms that the phone/glasses connection can negotiate the full-SBS output dimensions, with space for two 1920 × 1080 eye images, and that Sunlight receives the replacement scene automatically. Actual refresh cadence and physical eye separation were not measured. That readiness test used one 2D canvas; the subsequent calibration build provides a proper left/right test pattern for the next physical check.

## Physical calibration procedure

1. Connect the glasses, enable their hardware 3D mode, and open **Glasses → Start SBS test** on the phone.
2. Close the right eye: the left eye should see LEFT and a green circle/grid.
3. Close the left eye: the right eye should see RIGHT and a cyan circle/grid. Use **Swap eyes** if these are reversed.
4. With both eyes open, check that the circles look round, the targets align, and all four border corners remain visible. The pattern has zero disparity; this is an eye-order and geometry check, not a depth demonstration.
5. Reconnect and switch 2D/3D modes while the test is requested. USB power loss resets the tested glasses to normal 2D mode, so manually re-enable 3D after reconnecting. The test should pause in 2D and resume in compatible 3D mode with the selected eye order. **Stop SBS test** returns to readiness.

The user confirmed the physical calibration display was correct after tapping **Start SBS test**. Their initial report of no different colors was resolved by starting the test; no rendering change was necessary. A read-only device display query immediately before that confirmation reported 3840 × 1080 output at scale 1.

The user then reported that all seven guided checks passed: connection/start, left-eye LEFT/green, right-eye RIGHT/cyan, round aligned circles with visible borders, swapping labels/colors between eyes and switching back, reconnect recovery, and Stop returning to readiness. They observed that unplugging USB removes glasses power and resets their hardware mode to normal 2D. Re-enabling 3D after reconnecting restored correct output. This is a user-reported physical pass with manual hardware-mode selection; no automatic mode switching or measured presentation cadence is claimed.

## Remaining physical acceptance

Connect-before-launch, extended reconnect/mode-switch stress testing beyond the successful guided check, background/foreground recovery, and actual streamed video on both backends remain to be verified. The exact RayNeo model and the control used to enable its 3D mode still need recording.

No PC app was launched for streaming. The standalone SBS pattern is implemented and physically validated. The user clarified that the next standalone source is live iPhone-screen mirroring across app switches, with future 2D-to-3D processing; an in-app local video player is out of scope. Background capture plus custom external output, automatic glasses mode switching, HDR, and head tracking are not demonstrated by the calibration checks.

## Background-output diagnostic preparation

A Debug-only, explicitly launched AVPlayer external-output probe was built successfully and installed over Wi-Fi at 10:06. It is excluded from Release and inert during normal launches. It displays marked moving SBS content for up to three minutes solely to measure whether system-managed external output can remain visible when another app is frontmost. It does not capture or mirror the iPhone. See the historical probe findings in this document and `docs/sunlight-iphone-screen-feasibility.md`.

The device initially reported only its built-in LCD after installation. Preparation artifacts: `Build/background-output-probe-device/build-final.log`, `install.log`, and `displays-after-build.txt`.

After the user connected the glasses and enabled 3D, a device query confirmed 3840 × 1080. The first launch was rejected because the phone was locked. After unlocking, the retry launched at 10:11:08, with redacted live capture in `Build/background-output-probe-device/console-20260904-retry.log`. Foreground logs show playback advancing on the requested 3840 × 1080 view. Both scenes subsequently entered background and AVPlayerLayer readiness changed from 1 to 0; AVPlayer system external playback remained inactive while the media clock advanced. The user confirmed that the glasses switched to mirroring the phone. This app-owned-window route therefore failed the required background-output behavior.

The system-only control was built, installed, and launched at 10:17:03. It left external-window ownership to iOS and displayed the player layer on the phone. Logs confirmed no app-owned external window, `mirroredScreen=phone`, and `externalPlayback=0`. The user saw the phone-controls panel in the glasses and confirmed that they followed the phone again on Home/app switch. This control also failed the independent/background-output requirement. Artifacts: `Build/background-output-probe-device/build-system-control.log`, `install-system-control.log`, and `console-system-control.log`. No iPhone-screen capture has been implemented or started; background processed output remains an unresolved feasibility gate.

After completing the comparison, Sunlight was relaunched normally without either diagnostic flag at 10:19:18. The normal external scene connected and became active at 3840 × 1080, and no probe was started. The restored app's live redacted capture is `Build/background-output-probe-device/console-restored-normal.log`. Readiness and calibration behavior use the normal app path again.

## Direct GPU / raised-window experiment

After reviewing the Windows host's virtual-source and topmost-presenter implementation, the user asked to try that approach. A separate Debug-only probe now creates a 1920 × 1080 offscreen Metal texture, draws a moving synthetic pattern and numeric source-frame identifier, and packs it into a 3840 × 1080 external drawable. A separate, non-key external window at `UIWindowLevelAlert + 1` presents it above Sunlight's normal window in the same system-provided scene. The source remains an app-owned texture, not an OS virtual monitor; there is no capture, media file, AVPlayer, depth conversion, or background permission request.

The direct probe pauses new GPU submissions on app or relevant scene deactivation, ensures already submitted work has been scheduled, and retains the last frame for the physical visibility check. Stop, timeout, incompatible output, and display changes detach only its own window and release its resources; a new coordinator render request stops the test. Normal launch and Release remain unaffected.

The signed device build succeeded and installed over Wi-Fi at 10:34. `Build/direct-output-probe-device/build-final.log` contains the final successful build, and `install.log` records installation. The first launch was rejected because the device had locked again; `console.log` records that attempt. See the historical probe findings in this document for the observation procedure.

The unlocked retry launched at 10:36:06. Runtime Metal shader compilation succeeded and the counters reached 87 submitted/completed commands and 86 drawable presentation callbacks at 6.2 seconds, without missing drawables or reported errors. The source/drawable dimensions are 1920 × 1080 / 3840 × 1080, and the window level is 2001. Redacted log: `Build/direct-output-probe-device/console-retry.log`. The user reported that the glasses followed the phone to the desktop on Home. This is a failed retained-frame visibility result for the raised-window/direct-render approach. Foreground GPU execution is validated; a new system virtual monitor, background capture, or depth conversion has not been implemented.

The diagnostic's source was adjusted afterward to resume when the phone is active and the external scene is foregroundInactive, an actual return state observed in the log. It still pauses for background or unattached scenes. Timeout text now correctly states that suspended-process cleanup waits until execution resumes. These are recovery and wording fixes; the original Home-transition result is unchanged.

The adjusted build succeeded (`Build/direct-output-probe-device/build-restoration.log`) and was installed at 10:39:40 (`install-restoration.log`). The normal app launch path remains inert for all probes unless a diagnostic argument is explicitly supplied. A subsequent device lock-state query returned a CoreDevice resource-allocation error; installation had already completed successfully.

The normal launch attempt was rejected because the phone had locked (`Build/direct-output-probe-device/console-restored-normal.log`). No normal running app or ongoing console capture is claimed after that attempt. Opening Sunlight normally uses the installed app without any diagnostic flag.
