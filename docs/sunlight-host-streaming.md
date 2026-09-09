# Sunlight host streaming

Active direction, 2026-09-07: Sunlight receives a PC stream and presents it on the
iPhone/iPad or USB-C glasses. Local iPhone-screen hosting, imported apps, and
client-side 2D-to-3D conversion are deferred until iOS 27 verification.

The primary choices are **2D**, **Host 3D**, and **Raw SBS**. Host 3D asks a
compatible host to convert its 2D desktop. Raw SBS presents content that already
contains left/right images. It must not enable another conversion pass.

## Reference sync

Fresh upstream copies were retrieved on 2026-09-07 and updated on 2026-09-08 in the ignored
`build/upstream-references/` directory. The protected sibling checkouts were
neither fetched nor changed.

| Reference | Branch | Synced commit | Ahead of sibling checkout |
| --- | --- | --- | --- |
| [Apollo-3D](https://github.com/dcatcher9/Apollo-3D) | `master` | `a4cef55ba3ebf5fd90e74c6a7109e7b582865534` | 5 commits |
| [Moonlight Android](https://github.com/dcatcher9/moonlight-android) | `moonlight-noir` | `f038e8694f05959c47f4857b0bdf10893bd61784` | 8 commits |

These are source references, not iOS dependencies. No host/Android build or
submodule initialization was performed.

## Cleanup

Removed LiveContainer's checkout and nested Git storage, its app integration,
packaging/signing tools, bundled SideStore resources, generated app/archive/IPA
outputs, and container-only test fixtures. This recovered **6.38 GiB of allocated
storage** before subsequent streaming builds. Existing console/build logs remain
at their recorded paths; the cleanup inventory is
`build/host-streaming-cleanup/storage-cleanup.json`.

The external-display coordinator, shared video routing, and physically verified
SBS calibration remain. Historical local-hosting research is retained for the
future platform reassessment; it does not describe current features.

## Delivery order

1. Validate the host-only build after dependency cleanup and fix demonstrated
   lifecycle, queue, and browsing-performance defects.
2. Replace conversion setup complexity with a focused mode chooser and output
   readiness, keeping detailed streaming/input settings available separately.
3. Implement startup/resume negotiation and correct per-eye output for Host 3D
   and Raw SBS, preserving ordinary 2D Sunshine compatibility. Mode changes that
   alter the stream geometry must reconnect until the iOS client implements the
   host's negotiated atomic presentation protocol.
4. Validate stream launch/stop, pause/resume, glasses reconnect, packing and
   physical eye separation. Simulator checks establish software behavior;
   streaming quality and glasses acceptance require the host and device.

Every device launch must preserve a live console capture with pairing and session
secrets redacted. Do not relaunch an existing device app just to inspect it.

## Current validation and baseline status

This work started from the existing dirty `Integration` checkout at `a1de0a94`,
not a reset or a clean upstream checkout. The validated external-display work was
retained. LiveContainer was removed, then cleanup fixes and initial mode setup
were developed in the same working tree. No new commit has been made.

An active-source scan found no remaining LiveContainer, SideStore, local capture,
or background-output experiment hooks. The old Settings section named
"Experimental" contains inherited streaming/input options; it is not the removed
iPhone-hosting implementation. Historical research and small captured logs are
retained as explicitly historical records.

The full clean Debug iOS build passed with code signing disabled:
`build/host-streaming-cleanup/build-clean-debug.log`. A signed build was installed
on the iPhone 17 Pro. The latest signed build includes the common-C termination
fix, expanded phone/tablet Host 3D source-resolution validation, input-aspect
corrections, and keyframe-gated decoder recovery; it was installed and launched
on 2026-09-08 at 08:04 PDT. Its build log is
`build/host-streaming-cleanup/build-phone-tablet-recovery-final.log`; installed binary
hashes are preserved in `build/host-streaming-device/installed-build-manifest-phone-tablet.json`.
The initial in-stream UI overhaul was installed at 09:24 PDT. A revision with
Quick controls, Picture & 3D, More settings, and focused touch/quality detail
pages was installed at 15:30 PDT. The hierarchy, retained tap gestures, gamepad,
input isolation, and validation are documented in `docs/sunlight-in-stream-controls.md`.
The current binary manifest is `build/host-streaming-device/installed-build-manifest.json`.

Automated validation includes 33 external-display/Metal/queue simulator cases,
13 actual Swift app/host-card regressions, 263 stream-setup UI/persistence/layout
checks, 130 startup configuration checks, 11 production StreamManager flow tests,
16 Connection lifecycle cases (also passing under ThreadSanitizer), 12 actual
common-C termination cases (also passing ASan/UBSan), the existing 87 HTTP-response
assertions, nine production decoder-recovery state cases under ASan/UBSan, and
stereo layout geometry checks. An independent comparison of the production
resolution validator against the updated host header matched all 26,234,884
width/height pairs from 1 through 5122.
The UI was inspected in light/dark appearance and at the largest Dynamic Type
setting. Reusable runners are under `tests/`; generated captures remain under
`build/external-display-tests/`, `build/ui-card-tests/`, and
`build/stream-setup-tests/20260908-075211-49416/`.

The device and app both reported the connected glasses at **3840 × 1080, 60 Hz**.
The saved Apollo-Dev host is reachable. At 00:18 PDT on 2026-09-08, Host 3D
successfully requested a 1920 × 1080 source, negotiated HEVC, decoded a
3840 × 1080 image, and presented two eye regions to the glasses at that same
resolution. The user confirmed that **depth and alignment look good**. This
followed a failed phone-native 2622 × 1206 launch against the then-current host's
model shape allowlist; that earlier client selected a compatible 1080p fallback.
The updated host/client references support phone and tablet tensors. The current
installed client preserves supported native sizes and accepts odd Host 3D logical
dimensions using the host's chroma alignment for encoded output. At 08:26 PDT,
the native 2622 × 1206 source successfully decoded as 5244 × 1206 and presented
two eye regions at 3840 × 1080. The user confirmed this native-resolution picture
looks good. Tablet dimensions have automated coverage; no physical tablet test
is claimed.

The accepted 1080p test's redacted capture is
`build/host-streaming-device/live-console-20260908-host3d-resolution.log`, and
observations are in `build/host-streaming-device/physical-validation.json`.
The newer native-resolution build's launch capture is
`build/host-streaming-device/live-console-20260908-phone-tablet.log`.
The user confirmed Raw SBS was already verified and requested that further Raw
tests be skipped. That acceptance does not identify a separate Full/Half test in
this run. At 08:39 PDT, changing from Host 3D to 2D successfully resumed the host
session, decoded 2622 × 1206 mono video, and duplicated it to both eye regions;
the final 2D optical observation is pending.

The user also confirmed Home Screen and return resumes normally with the glasses
connected. That first transition kept the application active through its external
scene. A later full application background/foreground transition at 08:42 PDT
requested fresh IDRs and rebuilt HEVC format without subsequent decoder errors
in the capture; its optical recovery confirmation remains pending. A bounded
native Host 3D Time Profiler capture is documented in
`docs/sunlight-performance.md`; it does not establish sustained thermal or frame
rate performance.

The detached common-C termination callback now
carries a local session token, with the fix and regression coverage recorded in
`docs/sunlight-stream-lifecycle.md`. As of September 9, iOS and Android use the
same published shared core `3a235790931e8092500e215f4864e696147bf3f6`.
It includes the `100c767` race fix and microphone/authored-haptics feature ports.
Both the earlier bespoke callback API and the temporary four-file backport are
retired; the iOS submodule is clean. Integration details and qualification limits
are recorded in `docs/shared-common-core-ios-handoff.md`. App work remains
uncommitted.

Glasses output uses SDR at up to 60 FPS, one Metal decoded-frame consumer,
and the previously verified 3840 × 1080 external mode. Host 3D previews one eye on
the phone; Raw previews retain the packed desktop for input mapping. 2D repeats
the complete mono picture in both eyes while the glasses remain in SBS mode.
On an ordinary glasses display, only 2D is available. Entering the verified SBS
mode keeps a 2D stream unchanged; returning to confirmed normal mode reconnects
a Host/Raw 3D stream in 2D. Raw is now one exact-canvas passthrough choice, with
no Full/Half reshaping or virtual-display requirement. Each mode tab has its own
app-scoped quality and Apply & reconnect action; shared PC video/audio preferences
inherit from Global settings. Further device verification remains as listed above.
