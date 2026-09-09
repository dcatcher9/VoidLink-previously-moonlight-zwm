# In-stream controls

The phone remains a PC controller while the single video renderer presents on
the glasses. A persistent pill shows the current picture mode and opens App
settings directly to four picture tabs. One End session footer stays below the
tabs, inside the panel and outside the selected tab's options.

The pill uses the same mode icon and label as its tab: **2D**, **Host 3D**, or
**Raw SBS**. It reports the active stream; browsing a different tab or staging
settings leaves the pill unchanged until the mode is applied.

The ordinary touch surface retains the existing relative touch handler: slide
to move, tap to left-click, two-finger tap to right-click, two-finger movement to
scroll, and double-tap then hold to drag. There are no permanent mouse-button
bars or stream navigation gestures on the left, right, or top of the surface.

## Settings hierarchy

| Level | Destination | Contents |
| --- | --- | --- |
| Machine list | Top right: Global settings / Pad settings | One flat global defaults page; device touch and gamepad profile catalog |
| App list | Top left: Back; top right: PC settings | Return to machines; settings shared by all apps on the named PC |
| Control surface | Collapsed pill | PC touch input or gamepad; current picture mode |
| App settings | Pill opens here | Fixed 2D, Host 3D, Client 3D, and Raw SBS tabs |
| Mode tab | 2D / Host 3D / Raw SBS | Mode information, app-specific picture quality, Restore defaults, Apply & reconnect |
| Deferred tab | Client 3D | Unavailable pending iOS 27 verification; no conversion or reconnect action |
| App settings footer | End session | One common action outside the tabs; returns to the app list and leaves the PC app running |
| PC settings | Controls group | Inline trackpad, selected saved profile or gamepad choice; touch enabled state |
| PC settings | Sound and statistics groups | Inline volume slider and Off / Simplified / Detailed choice |
| PC settings | Shared connection settings | Codec, HDR, range, pacing, audio layout and host audio |
| Global settings | Defaults for all PCs | Default quality, shared video/audio and input defaults; device profile catalog |
| Mode tab | Picture quality group | Inline resolution and frame-rate menus, bitrate slider; no quality detail page |

Global settings has a gear icon and opens one scrolling page from the machine
list. Moonlight 3D icons, labels and separators distinguish its settings groups; categories
do not open additional pages. Machine settings uses the same direct-control
approach with inline choices and sliders. Compact option menus select values
without leaving the current settings page. Pad settings remains the profile
catalog. The old global sidebar and its edge gesture are retired.

The streaming panel contains picture settings only. There is no Session hub,
PC controls page, sound page, global-settings link, or per-tab End session action.
The four modes follow Moonlight 3D's mode-specific organization. A fresh PC
connection starts in 2D.

## Moonlight 3D visual reference

The iPhone app reuses the Android drawable paths from reference commit
`f58aef9a2b1b45d9e14ce4d1e994fec07d6b7d1b`. `SunlightMoonlightIcons` caches template
images from the original path data, including stroke widths and caps. The four
tabs use `ic_xr_mode_normal`, `ic_xr_mode_host_sbs`, `ic_xr_mode_client_sbs` and
`ic_xr_mode_host_sbs_raw`. Their labels are **2D**, **Host 3D**, **Client 3D** and
**Raw SBS**, in the user's requested order. Resolution, Max frame rate, Max
bitrate, FPS, Apply & reconnect, Use global defaults and End session follow the
corresponding Moonlight 3D wording where their behavior matches. App and PC
scope labels describe the iPhone's persistent ownership model.

`SunlightUITheme` mirrors `res/values/colors_xr.xml`: surface `#16181E`, raised
`#22262B`, background `#0C0F14`, dividers `#3C4043`, accent `#8AB4F8`, selected
fill `#36587F`, primary text `#FFFFFF`, secondary text `#B0B9C6`, disabled text
`#71808F`, and destructive text `#FFB4AB`. The mode tabs, primary actions,
settings forms, machine browser and phone gamepad share these roles. Existing
appearance choices are preserved on disk; the Sunlight surfaces use this dark
palette and the old theme selector is absent from the flat global page.

The mode icons and copy are visual reuse. iPhone Raw keeps its verified exact
SBS passthrough contract and Client 3D remains deferred pending iOS 27.

## Persistence and apply behavior

Picture quality is keyed by stable host UUID, app ID and mode. Each app on each
PC owns independent resolution, frame rate and bitrate for each usable mode.
Raw resolution is read-only and follows the complete glasses canvas. Editing
an inline picture control stages that tab's value. Apply & reconnect commits
the selected tab. Other tabs' drafts survive the same-session
reconnect; closing App settings or ending the session discards unsubmitted edits.

The default resolution is **Native**, using the control device's full landscape
pixel dimensions (2622 × 1206 on the tested iPhone). It excludes neither the safe
area nor the camera cutout and does not take the glasses' scanout dimensions.
2D and Host 3D offer Native alongside fixed resolutions. Native stays exact when
interpolation is enabled; stream dimension scaling remains available for fixed
or custom resolutions. Raw keeps its exact glasses canvas.

The September 9 update selects Native for the global default once and migrates
legacy 720p, 1080p, 1440p and 2160p 2D/Host 3D profiles to Native while preserving
their frame rate and bitrate. Custom profile dimensions remain fixed. Subsequent
manual fixed-resolution choices are explicitly recorded and are not migrated.

Existing PC/mode and older global/mode quality records are read as fallbacks so
upgrading preserves current settings. New edits write only the app/mode record.
Restore defaults in a tab stages an app/mode inheritance marker, committed by
Apply & reconnect. It bypasses the older PC/mode override and follows global
quality defaults, including future global changes. Resetting one app does not
change another app's profile.

PC connection, input, volume and statistics settings use the host UUID and are
shared across all apps and modes on that machine. Missing fields inherit global
defaults; saves store only differences. All PC groups edit a detached draft on the same page. Save settings commits
the PC draft for future connections; Cancel saves nothing. Restore defaults stages removal of both PC
connection and control overrides without changing any app's picture profiles.
The selected saved touch profile is the existing device-wide catalog selection;
the choice to use it, a trackpad or gamepad is saved for this PC.

The global Control defaults group chooses inherited control mode and touch
availability. Audio and General include the global volume and statistics
defaults. Done closes the page and saves edited fields for future connections;
opening and leaving without edits does not rewrite unrelated preferences. Active stream transport and
presentation consume a resolved snapshot. Legacy statistics and touch-pause
shortcuts update the same PC-scoped control record.

## Streaming and input

The display coordinator distinguishes confirmed normal output, confirmed
3840×1080 SBS output and unknown/unsettled output. Normal output permits only
2D. Entering SBS enables Host 3D and Raw SBS while retaining the 2D stream.
Returning to confirmed normal output reconnects a 3D stream in 2D and discards
pending edits. A transient disconnect or mismatched window canvas does not
trigger reconnect. Readiness and display mode are rechecked before reconnect
and at startup. The existing landscape lock is unchanged.

Opening App settings cancels held local input and excludes panel and pill
touches from remote input. Inline controls and value menus keep the panel
expanded through editing and reconnect validation. Closing the panel restores the PC's
selected input mode. The external phone surface shows noninteractive gesture
guidance while retaining its touch area; paused input is labelled first.

Saved profiles may use relative mouse, direct mouse, native touchscreen or no
touch input. The UI describes their actual behavior. Gamepad provides two
sticks, directional buttons, ABXY, shoulders, digital triggers, Back and Menu,
using the existing controller support and merging. Opening settings,
backgrounding or disconnecting releases held controls. Existing command
execution remains tied to its original stream owner, preventing delayed keys
from reaching a later connection.

Reconnect preserves the selected app and captured host session, waits for the
old connection to finish and does not quit or start a different PC app. Raw
assumes the host supplies a prepared SBS picture matching the glasses; it does
not request a virtual display, reshape eyes or convert depth. Mismatched Raw
frames are not drawn. The old Full/Half preference resolves to one Raw mode.
3D strength remains a host control. Client conversion remains deferred.

## Validation

The flat settings and Moonlight visual pass completed 523 overlay checks, 58
final native PC-form checks, 503 actual Global-page checks, 103 actual-app
scope/staging checks and 30 actual browser checks. Global verification covered
no-op saves at 500 Kbps and 300 Mbps, exact custom-resolution display, a matching
1080p preset, independent FPS/bitrate/volume/codec/control edits, and large-text
scrolling. The browser fixture used only synthetic in-memory hosts and verified
that clearing controller focus restores the ordinary card border. No host actions
were invoked. All 20 cached icon path definitions matched the Android XML exactly.

Final visual/runtime artifacts:

- `Build/stream-controls-tests/20260908-212127-13149/` (four tabs and inline quality)
- `Build/stream-controls-tests/20260908-212302-13701/` (flat PC settings)
- `build/flat-global-runtime/verified-results-20260908-214351/` (flat Global settings)
- `build/settings-category-runtime/machine-staging-results/` (scope and staged changes)
- `build/settings-category-runtime/browser-theme-results/` (machine browser and app navigation;
  `apps-navigation-settled-214040.png` is the final settled app-view capture)
- `build/host-streaming-cleanup/moonlight-ui-reference-verification.json` (reference provenance)

The signed iPhone and simulator builds passed. The final update was installed
on the iPhone 17 Pro at `2026-09-08T21:45:41-07:00`. iOS rejected the single
live-console launch because the phone was locked. The installed binary hashes,
source hashes and final checks are recorded in
`build/host-streaming-device/installed-build-manifest.json`; the redacted launch
log is `build/host-streaming-device/live-console-20260908-moonlight-shared-ui.log`.
Physical UI review remains pending.

Foundation checks also passed: 119 picture profiles, 76 shared settings, 80
machine controls, 36 field-specific Global quality edits and 50 legacy Global
quality migration checks. The runtime fixture does not establish physical
streaming acceptance; prior verified Raw behavior was not retested.

`tests/run_stream_controls_tests.sh` exercises the actual UIKit overlay and
forms: hit testing, hierarchy navigation, staged changes, callbacks, safe-area
layout, and Dynamic Type. The fixture captures screenshots for visual review.
`tests/run_command_execution_tests.sh` passes ten production-command cases,
including cancellation, releasing held input, and suppressing delayed events
after a successor session starts.

Previously verified unchanged behavior: 1,050 gamepad checks; 13 input-gate
cases including Thread Sanitizer; eight production click/drag/cancellation cases;
21 reconnect manager-flow cases; and 18 connection lifecycle cases including
Thread Sanitizer. These counts describe prior runs, not a new physical input
acceptance of the settings hierarchy.

The initial controls build was installed at 09:24 PDT on 2026-09-08 and connected
at 09:28:58, decoding a 2622×1206 2D stream into two eye regions on the 3840×1080
glasses output. Capture:
`build/host-streaming-device/live-console-20260908-in-stream-controls.log`.
The hierarchy revision passed 335 native UIKit checks and a signed iOS build:
`build/host-streaming-cleanup/build-in-stream-hierarchy-final.log`.
Screenshots and fixture output:
`Build/stream-controls-tests/20260908-152830-79648/`.
The app was installed on the iPhone 17 Pro at 15:30 PDT on 2026-09-08.
Launch diagnostics (redacted):
`build/host-streaming-device/live-console-20260908-settings-hierarchy.log`.
The first launch attempt was rejected because the iPhone was locked; installation
succeeded. `installed-build-manifest-settings-hierarchy.json` preserves this build's record.
Physical usability feedback on this hierarchy remains pending. Raw SBS physical
testing remains skipped at the user's request.

The Picture-first revision passed 373 native UIKit checks with no compiler or
Auto Layout warnings. Portrait, landscape, iPad, collapsed hints, and maximum
Dynamic Type captures were reviewed in
`Build/stream-controls-tests/20260908-155019-82184/`.
The signed build passed:
`build/host-streaming-cleanup/build-picture-first-controls.log`.
It was installed on the iPhone 17 Pro at 15:54 PDT on 2026-09-08. iOS rejected
the launch because the phone was still locked; on-device usability is pending.
Redacted diagnostics:
`build/host-streaming-device/live-console-20260908-picture-first.log`.
`installed-build-manifest-picture-first.json` preserves this revision and its artifacts.

The four-tab revision passed 546 native UIKit checks. The landscape captures
show each mode's quality and Apply & reconnect controls, PC and Global settings,
and the persistent End session action. Large text was also checked. The app's
existing orientation lock was not changed. Artifacts:
`Build/stream-controls-tests/20260908-164626-91089/`.
A settled native capture additionally confirms Global settings' Cancel button;
the blank label in its hierarchy render was a capture artifact:
`Build/stream-controls-tests/native-global-20260908-165329/`.

Logic verification passed 85 quality-profile checks, 76 shared-settings checks,
136 stream-configuration checks, 42 external-display/mode-policy checks,
26 stream-manager lifecycle/presentation checks, nine decoder recovery sanitizer
cases, and the stereo-layout suite. These cover settings inheritance and commit
boundaries, confirmed glasses transitions, snapshot propagation, and Raw geometry.
They do not constitute physical streaming acceptance of this revision.

The final signed build passed:
`build/host-streaming-cleanup/build-scoped-mode-tabs-installed.log`.
It was installed on the iPhone 17 Pro at 16:51 PDT on 2026-09-08. iOS rejected the
16:54 launch because the phone was locked. Redacted launch diagnostics:
`build/host-streaming-device/live-console-20260908-scoped-mode-tabs.log`.
`build/host-streaming-device/installed-build-manifest-scoped-mode-tabs.json` records this installed
binary, hashes, and verification artifacts. Physical usability remains pending;
no additional Raw physical test was performed, as requested.

The settings ownership revision replaces the duplicated global editors with a
single machine-list index and moves shared PC settings to the app list. The real
simulator app passed 74 runtime checks, including machine → app → machine
navigation and all nine storyboard-backed category pages. Opening and leaving
every category preserved all global attributes and 24 profile fields. A Local
audio edit changed only volume; seeded Auto codec, 90 fps, 54321 Kbps, 2622×1206
and the existing orientation preference were preserved. Category header contrast
was corrected and checked in the final landscape captures:
`build/settings-category-runtime/final-results/`.
Redacted runtime console:
`build/settings-category-runtime/live-console-final.log`.

The profile regression suite now passes 89 checks, preserving the legacy
500–800000 Kbps range. Fifty migration checks verify that explicit global quality
changes remove only the three old unscoped quality records and retain PC-specific
profiles. The final signed build passes:
`build/host-streaming-cleanup/build-settings-session-hub-final.log`.

The final Session/Picture overlay passed 582 UIKit checks without compiler,
layout or appearance warnings in that run. The Session hub keeps Picture,
PC controls and Sound & statistics separate; Picture contains only mode options,
quality, Restore defaults and Apply & reconnect. Landscape and large-text
captures are preserved in `Build/stream-controls-tests/20260908-193136-1680/`.
The updated app was installed at 19:33 PDT on 2026-09-08. Launch was rejected
because the iPhone was locked, so physical usability review is still pending.
Redacted launch diagnostics:
`build/host-streaming-device/live-console-20260908-settings-session-hub.log`.
`build/host-streaming-device/installed-build-manifest-settings-session-hub.json`
records that installed binary and its checks. No additional physical Raw test was run.

The following app/PC ownership correction passed 312 overlay checks and 77
actual-app startup checks. Picture preferences use app+PC+mode identity; input,
volume and statistics remain shared by PC. Foundation suites passed 119 picture
profile, 76 shared-settings and 80 machine-controls cases. Both iPhone and
simulator builds passed. The iPhone install completed while the user requested
further flattening of settings, so that build was not launched. Its artifacts
are `Build/stream-controls-tests/20260908-205308-5947/` and
`build/settings-category-runtime/machine-scope-results/`. These runs precede
the subsequent flat-settings revision.
