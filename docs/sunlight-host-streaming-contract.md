# Sunlight host streaming contract

This implementation targets host streaming only. Local iPhone desktop capture and client-side
2D-to-3D conversion are deferred pending iOS 27 verification. A presentation change takes effect
on the next connection; this client does not send proprietary live conversion controls.

## Reference baseline

Read-only audit of the separately synced reference clones under `build/upstream-references`:

- Apollo-3D `master`: `a4cef55ba3ebf5fd90e74c6a7109e7b582865534`.
- Moonlight Android `moonlight-noir`: `f038e8694f05959c47f4857b0bdf10893bd61784`.

No `AGENTS.md` files were present inside these clones during this audit. The sibling host and
Android workspaces remain read-only; this work does not update their sources or Git state.

Primary implementation references:

- [Android presentation architecture](https://github.com/dcatcher9/moonlight-android/blob/f038e8694f05959c47f4857b0bdf10893bd61784/docs/android-xr-sbs.md)
- [Android quality geometry](https://github.com/dcatcher9/moonlight-android/blob/f038e8694f05959c47f4857b0bdf10893bd61784/app/src/main/java/com/limelight/preferences/PreferenceConfiguration.java)
- [Android launch and session identity](https://github.com/dcatcher9/moonlight-android/blob/f038e8694f05959c47f4857b0bdf10893bd61784/app/src/main/java/com/limelight/nvstream/http/NvHTTP.java)
- [Host HTTP contract](https://github.com/dcatcher9/Apollo-3D/blob/a4cef55ba3ebf5fd90e74c6a7109e7b582865534/src/nvhttp.cpp)
- [Host RTSP negotiation](https://github.com/dcatcher9/Apollo-3D/blob/a4cef55ba3ebf5fd90e74c6a7109e7b582865534/src/rtsp.cpp)
- [Host control packet definitions](https://github.com/dcatcher9/Apollo-3D/blob/a4cef55ba3ebf5fd90e74c6a7109e7b582865534/src/stream.h)

## Presentation and geometry

For 2D and Host 3D, `W × H` means the logical source quality selected by the user. For Raw,
`G × J` is the glasses' complete packed output in pixels, currently 3840 × 1080 in SBS mode.
The HTTP `mode` and RTSP dimensions describe the host source desktop. Raw content is already
rendered side by side by its host app; the client does not create depth or ask the host to convert it.

| Mode | HTTP/RTSP source | Encoded image | Host `sbsMode` | Host desktop input geometry |
| --- | --- | --- | --- | --- |
| 2D | `W × H` | `W × H` | `0`, only on capable hosts | `W × H` |
| Host 3D | `W × H` | Fitted `2W × H` | `1`, capable hosts only | `W × H` |
| Raw SBS | `G × J` | Must be exactly `G × J` | `0`, only on capable hosts | `G × J` |

Raw is one exact passthrough mode. Its persisted enum is `SunlightStreamModeRawFullSBS` (`2`);
legacy `SunlightStreamModeRawHalfSBS` (`3`) normalizes to that mode during preflight. Both
`logicalWidth/Height` and HTTP/RTSP `width/height` describe the complete packed frame, never
per-eye dimensions; preflight does not double the width. The quality form shows this glasses-supplied
resolution as read-only while frame rate and bitrate remain editable. Raw input addresses the
complete packed host desktop, while Host 3D input addresses its mono source desktop.

On the SBS glasses route, Raw renders one full-output quad with texture coordinates `[0,1]` on
both axes. The actual decoded dimensions must exactly equal the acquired Metal drawable's texture
dimensions. A mismatch is withheld instead of fitted, cropped, or stretched; equal aspect alone
is insufficient. There are no eye splits or texel insets in this path. Host 3D still fits its eyes
independently, and 2D repeats its complete mono image into both eyes on SBS output. The phone's
Raw preview can fit the complete packed image to its screen for input mapping.

Raw does not require virtual-display capabilities, request `virtualDisplay=1`, or restrict
resume to the generated Virtual Display app. A physical or virtual desktop can be resumed when
the app and session identities match. The premise is that the PC already supplies correctly
packed content at the glasses' exact resolution. Merely requesting a wide encoded frame does
not establish this: the host can fit physical capture into the requested frame without changing
the physical desktop. The dimension check cannot detect incorrectly arranged source content.
This differs from Android's configurable Full/Half desktop policy, which chooses `2W × H` or
`W × H` and requires virtual backing.

Raw must preserve both packed axes exactly. iOS rejects requests beyond 8192 pixels on either
axis, or 4096 when no common HEVC/AV1 codec is advertised. Host 3D instead permits host encoder
fitting: conservatively 4096 per axis
for H.264 or 8192 for HEVC/AV1, scaling both packed axes together, then aligning packed width
to a multiple of four and height to an even value. This gives each eye whole 4:2:0 chroma cells.
Host 3D may request odd logical source dimensions (for example, 1919 × 1081 becomes
3836 × 1080 encoded SBS). Raw retains its even-dimension requirements and exact packed geometry.
Actual decoded format dimensions remain authoritative; these limits are startup layout hints,
not a substitute for hardware validation.

Host 3D also has a separate **source model** limit: longest side at most 5120, at most
5120 × 2160 source pixels, and one of the 24 calibrated depth tensors. The short side is 434;
the long side is one of 574, 616, 630, 658, 700, 770, 868, 938, 966, 980, 1022, or 1036.
Both orientations are supported. iOS mirrors the pinned host's float32 14-pixel patch fitter.
Phone-native 2622 × 1206 now fits the supported 938 × 434 tensor and stays at its native
source size, producing 5244 × 1206 encoded SBS when codec/runtime limits allow it. Tablet
dimensions such as 2732 × 2048 also remain unchanged. This expanded membership requires the
updated host and its model artifacts; the wire protocol does not advertise the shape set.
When creating a Host 3D session from inherited stream settings, iOS preserves compatible sizes
and substitutes 1920 × 1080 for an unsupported saved size, before selecting codecs or freezing
logical/input dimensions. Stream setup shows the effective source and explains this fallback.
The saved 2D preference is unchanged. Unsupported custom ratios such as 1920 × 1536 still
use the visible 1080p fallback. Preflight independently rejects unsupported Host 3D
sources before HTTP launch; Raw SBS is not subject to the host depth model's source limits.

## Capability and startup requests

The current Android implementation uses the *presence* of `<hostsessionid>` in `serverinfo` as
the Apollo-3D session/control extension indicator. Its idle value is `0`; absence means a legacy
host. Do not require a nonzero idle token to detect support. A malformed present token is an error.
`ServerCodecModeSupport` provides ordinary advertised codec support.

Authenticated Windows Apollo responses additionally contain:

```xml
<VirtualDisplayCapable>true</VirtualDisplayCapable>
<VirtualDisplayDriverReady>true</VirtualDisplayDriverReady>
```

These tags describe virtual-display capability and driver readiness; iOS Raw passthrough does
not require them. The pinned host's `nvhttp.cpp` physical resume branch probes capture/encoders
before resuming (`1796–1805`), and `process.cpp` rejects only a request to convert a retained
physical app into virtual backing (`1305–1310`). Omitting that request preserves its backing.
Physical capture may still be fitted by the host when source and requested dimensions differ
(`platform/windows/display_vram.cpp`, physical capture conversion around `5899–5931`).

Exact startup extension names are case-sensitive:

- `sbsMode=0|1`: off or Host AI; omitted entirely when `hostsessionid` support is absent.
- `virtualDisplay=1`: optional host backing request. iOS mode preflight clears this request for
  all modes; Raw uses already packed physical or virtual content without changing backing.
- `scaleFactor`: optional, host default `100`, accepted range `20..200`. iOS uses the default.
- `appuuid`: optional stable app identity. The current iOS app model has only numeric app ID,
  so this is sent only if a caller actually supplies a UUID; no UUID is inferred from a name.
- `hostSessionId`: nonzero retained session token on `resume`, omitted on fresh `launch` and
  on legacy hosts.

The host accepts omitted display extensions with defaults of no virtual-display request,
100% scale, and SBS off. Raw on ordinary Sunshine or legacy Apollo therefore uses ordinary
streaming without proprietary display/conversion extensions.

A busy host must report the selected app's identity before iOS resumes it. UUID takes precedence
when both sides provide it, with numeric ID as the fallback. When the caller already has a bound
session token, the fresh server response must match it. Otherwise, a freshly selected matching app
binds the current token before sending `resume`. Successful launch and resume responses must return
a valid `hostsessionid` on capable hosts, and a resume response must match the bound token.

## Virtual display only

The September 9 integration uses separately refreshed reference checkouts:
Apollo-3D `ad99d5a6cca9db848d5dc6b35d754d54d0619c0d` and Moonlight Android
`5d56dfe93631848bf9ebd800421fb4ce49a64ee6`. The original sibling workspaces remain
untouched. Android still pins shared common-C `3a235790931e8092500e215f4864e696147bf3f6`,
matching this iOS app; this policy needs no shared-core change.

**Use virtual display only while streaming** is a global preference, enabled by
default for new and existing iOS installs. It is stored separately from per-PC
and per-app picture settings and captured at each connection start. An explicit
off value is preserved. The global settings screen saves only user edits on leave;
a change applies on the next connection, including a mode reconnect.

Only exact `VirtualDisplayOnlySupported=1` from successful, pinned HTTPS
`serverinfo` enables the request. HTTP fallback and responses redirected to an
insecure or different endpoint cannot grant this capability. Supporting hosts receive
`virtualDisplayOnly=1` or `virtualDisplayOnly=0` on both `/launch` and `/resume`.
Older hosts receive neither. This is independent of `hostsessionid`, app name,
picture mode and `virtualDisplay`: the host classifies virtual backing, including
its generated Virtual Display tile. Existing iOS source and Raw geometry are
unchanged, and physical-display streams remain physical.

For virtual-backed sessions, the host temporarily disables ordinary physical
displays, makes the virtual desktop primary, and automatically manages the shared
Windows cursor. Approved AR outputs can remain active when needed for scanout;
the host confines the cursor to the virtual desktop in that case. Disconnect,
reconnect grace and teardown restore the previous topology according to the host's
recovery policy. A retained session owner or a client with launch permission may
change the preference on resume; another view-only client inherits its existing
choice. These are host responsibilities, not client-side monitor manipulation.

The temporary iOS first-frame cursor centering, extra readiness gate and associated
handoff/tests were removed. Input uses the original connection/lifetime gate and
normal relative/absolute protocol, without cursor warping or confinement flags.
See the host's [virtual desktop contract](https://github.com/dcatcher9/Apollo-3D/blob/ad99d5a6cca9db848d5dc6b35d754d54d0619c0d/docs/virtual-desktop.md).

## Runtime controls intentionally deferred

Latest Apollo accepts only the atomic presentation V2 control body for live mode changes. The
old independent SBS toggle and legacy live mode payloads must not be used:

- RTSP host capability: `a=x-ss-general.featureFlags` bit `0x20000000`.
- Client advertisement: `x-ml-general.featureFlags` bit `0x08`, alongside required session V1.
- Request `0x3007`: exactly 20 bytes, little-endian. Byte 0 version `2`; byte 1 SBS `0|1`;
  bytes 2–3 zero flags; 4–7 request ID; 8–9 source width; 10–11 source height; 12–15 FPS × 100;
  16–19 total wire bitrate in Kbps.
- ACK `0x3008`: exactly 28 bytes. Version/status/mode/reserved in bytes 0–3; request ID 4–7;
  generation 8–11; source width/height 12–15; encoded width/height 16–19; FPS × 100 20–23;
  applied bitrate 24–27. Status `0` applied, `1` invalid, `2` reconnect needed, `3` failed.
  All statuses report the mode that actually remains active.

The shared core at `3a235790931e8092500e215f4864e696147bf3f6` publishes
`LiSendSetVideoModeV2`, its acknowledgement callback and host SBS telemetry APIs.
The iOS app currently uses startup mode plus reconnect. Adopting live changes
still requires an app-side decoder/presentation transaction that commits only
after matching fresh video proves the change. No local common-C patch is needed
to access the published transport API. Raw remains the verified exact-canvas
path in this app.

Host 3D uses the host's pinned Depth Coordinate V2 pipeline, with no supported host model selector.
`sbs_3d_pop_strength` is host configuration (`0.25..2.0`); this audit found no streaming-protocol
setter for host strength/convergence. Do not show an iOS slider that pretends to control it.
Telemetry requires its separate `0x40000000` capability and 0x3009/0x300A V2 contract; it is also
deferred.

## iOS integration and verification

`StreamConfiguration` owns the startup contract. UI supplies `streamMode` and logical quality
for 2D/Host 3D, or complete glasses output dimensions for Raw;
`prepareSunlightStreamWithHostSessionSupport:virtualDisplayCapable:virtualDisplayReady:` validates
fresh capabilities and produces source `width/height` idempotently. `expectedPackedWidth/Height`
are conservative renderer hints. `StreamManager` validates before launch/resume and binds session
responses; `HttpManager` adds only permitted query items. A new session starts in 2D.
Host 3D and Raw require a confirmed SBS glasses output and an explicit tab apply.

Inline quality controls stage their choices in the current app mode tab; each usable tab owns
its Apply & reconnect action. The Raw label is now “Raw SBS”, matching Moonlight 3D;
its transport contract is unchanged.
Raw's glasses-supplied dimensions are not saved over the user's general resolution preference.
`SunlightStreamQualityProfile` loads detached drafts for each host UUID, app ID and mode.
New scoped keys encode host and app identity independently to avoid separator collisions.
Legacy Half shares the Raw mode. Reads resolve an explicit app/mode profile, then an old
PC/mode record, then the old global/mode record and supplied global quality fallback.
A committed Restore defaults marker skips the old PC/mode layer for that app and mode,
so it follows global defaults now and after future global changes. Loads never persist
fallbacks; new saves never fan out into another app or the legacy PC records. Blank host
or app identities cannot save/reset. Unsupported modes cannot save. A record must contain
all four valid integer fields: width/height `1..16384`, frame rate `1..240`, and bitrate
`500..800000` Kbps. Invalid records fall through to the next complete profile without mixing
fields. Input, local volume and statistics are resolved separately by host UUID, shared by
all of that PC's apps, and copied into the startup configuration/presentation snapshot.
Mode-specific source and codec validation still runs later during stream preflight.

`bash tests/run_stream_configuration_tests.sh` exercises the Foundation-only geometry, capability,
query, and session identity rules. These tests do not verify hardware decoding, host capture,
external-display layout, per-eye aspect, or actual glasses output. Those still require the app
build and device/host stream qualification. No host/Android build was performed as part of this
read-only contract audit.

`bash tests/run_stereo_layout_tests.sh` additionally checks the production Raw region helper's
full-frame UVs, one-to-one pixel-center mapping, refusal of mismatched/invalid dimensions, and
the unchanged mono duplication and Host 3D per-eye fitting helpers. These are geometry checks,
not physical scanout or decoded-content verification.

`bash tests/run_stream_quality_profile_tests.sh` covers isolated drafts, separate mode keys,
legacy Raw aliases, explicit commits, malformed defaults, inclusive bounds, and invalid-save refusal.
