# Shared common-C integration

## Adopted revisions

Synced on September 9, 2026:

| Repository | Revision |
| --- | --- |
| Sunshine 3D host | `7e7b6cc13ae5a003e781582759d2b77c40f05971` |
| Moonlight 3D Android | `445e51fd7fb0081e50cca6127df2764119222436` |
| Shared client common-C | `3a235790931e8092500e215f4864e696147bf3f6` |

The iOS submodule now uses `https://github.com/dcatcher9/moonlight-common-c.git`
at the same commit as Android, with no local core modifications. The outer iOS
`Integration` branch was already current with its remote; existing uncommitted
app work is preserved. Host and Android synchronization used only fetch,
fast-forward and pinned submodule updates. Neither reference was edited or built.
The host retains its own published common-C pin; it need not use the client pin.

Microphone forwarding and authored DualSense PCM are retained as required by the
user. The old four-file termination backport was checked against its recorded
checksum and exact modified-file set, backed up, reversed, and retired. The shared
revision already includes the `connectionTerminatedWithSession` /
`connectionSessionId` fix and releases the platform thread context before calling
an entry, including entries that exit the thread directly.

## Shared contracts

The core owns microphone negotiation, packetization, encryption, pings and teardown.
iOS keeps permissions, capture, resampling, Opus encoding and audio routing.
`redirectMic`, `sendMicrophoneOpusData()` and
`isMicrophoneEncryptionEnabled()` remain available. The Swift Opus varargs wrapper
is now an inline iOS adapter in `VoidLink/Input/SunlightOpus.h`.

Microphone stage handling follows the public stage identifiers through
`LiGetStageName()`. Capture startup and interruption recovery must be invalidated
on stop; each send must belong to the originating `ConnectionLifecycle`, so a
retired capture producer cannot send into a successor session.

Authored PCM uses `LI_DS5_HAPTICS_PCM_FRAME` and the `ds5HapticsPcm` callback. iOS
continues copying borrowed PCM into `NSData` before queuing playback. IR-v2 types
and the existing handler are retained, but callback registration remains inactive.
Ordinary rumble, trigger rumble, adaptive triggers, motion and LEDs keep their
separate callbacks.

The published core resolves the former haptics/SBS capability collision:

| Capability | Host flag | Client flag |
| --- | --- | --- |
| Authored PCM | `0x80` | `0x20` |
| Authored IR v2 | `0x04000000` | `0x40` |
| Shared haptics profile | `0x08000000` | — |
| Source-frame identity | `0x10000000` | `0x10` |
| Atomic presentation | `0x20000000` | `0x08` |
| SBS telemetry | `0x40000000` | `0x04` |

The shared core selects legacy haptics bits only for compatible legacy hosts,
without shared SBS/profile flags. iOS therefore registers its PCM callback based
on local output support instead of excluding all Sunshine 3D hosts. Per-controller
`LI_CCAP_DS5_HAPTICS_PCM` is advertised only with an eligible PlayStation output
and the session callback subscription, including player zero.

The latest host source includes optional microphone and authored-PCM backends,
with support gated on configured and available resources. This supersedes the
older shared-core migration document's statement that Sunshine 3D lacks those
backends. A published source revision does not establish that a running host has
the required microphone route, DualSense sidecar and driver configured.

## iOS platform adaptations

- Background/PiP admission is an app-owned atomic flag in `SunlightPlatform`.
- Capture converts the hardware input through a mixer tap to 48 kHz mono before
  encoding 960-frame (20 ms) Opus packets. Pending tap work and buffered audio
  are bounded, and the tap does not wait for network sends.
- Video presentation uses published `presentationTimeMs`, preserving the queue's
  90 kHz `CMTime` convention and unwrapping the RTP epoch. It does not invent
  sub-millisecond source precision; regressions and duplicate timestamps remain
  distinct from rollovers. New renderers start independent clock histories.
- The common Xcode targets compile the shared `reedsolomon/rs.c` implementation;
  the removed fork's `rswrapper` and nanors include paths are no longer used.
- Streaming UI termination hints use only error codes emitted by the shared core.
- The shared core's worker scheduling replaces the fork's internal Darwin QoS
  overrides. Existing iOS render/decode dispatch queues retain their QoS policy;
  no claim of identical hidden worker priorities is made.

## Validation and device qualification

Integration validation is recorded under
`build/host-streaming-cleanup/shared-core-20260909/`. It includes actual C
termination/thread behavior, upstream microphone/haptics protocol fixtures,
iOS lifecycle ownership, presentation timestamps and a signed iPhone build.
The signed iPhone build and strict code-signature verification passed. Native
validation passed 15 termination cases, 3,402 Darwin thread checks, 18 connection
lifecycle cases and all eight upstream feature suites, with their sanitizer runs.
Additional iOS checks passed: 16 timestamp checks, 9 decoder-recovery cases,
26 stream-manager flows, 42 display/Metal/queue cases, and 34 microphone
stage/ownership/capture lifecycle checks. The microphone fixtures execute actual
production methods with controlled audio/transport boundaries; they do not prove
physical microphone routing or audio quality. See `verification.json` and
`build-manifest.json` in the evidence directory.

The previously installed build manifest remains a record of that exact binary.
Do not label it as this new shared-core build until a new installation is verified.
Physical microphone input, authored haptics and reconnect qualification with the
updated running host remain separate from compilation/protocol tests. Raw SBS
was previously verified; no repeat physical Raw SBS test is required by this work.
