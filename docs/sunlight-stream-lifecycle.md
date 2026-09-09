# Streaming lifecycle cleanup

Record: 2026-09-07. This covers the host-streaming cleanup, not local iPhone
capture or a claim of physical streaming qualification.

## Implemented and verified

`StreamManager` now treats `stopStream` and `NSOperation.cancel` as the same
terminal state. It checks cancellation before startup, after key preparation,
after each synchronous HTTP response, and before creating the decoder and
connection on the main queue. Decoder/connection publication and cancellation
share a lock, and cancellation suppresses late startup error callbacks. A
published Connection is cancelled before termination is requested. Repeated
stops do not repeat termination.

An HTTP request already in progress still runs to completion because HttpManager
does not expose cancellation of that request. Its completion cannot continue
startup after the manager observes cancellation. This prevents the earlier
reproducible sequence where stopping during serverinfo still launched the host
app and later created the local connection.

`FrameQueue` now consumes pending enqueue wakeups when frames are dequeued or
evicted, and drains wakeups for frames discarded by `clear`. Long streams no
longer leave a backlog of semaphore permits that the next empty wait spins
through. Ring bounds, session ownership and cancellation-aware waits remain in
place. The queue also accepts decoder-owner identity when enqueuing, so delayed
work from an older decoder cannot enter a successor's queue.

`ConnectionLifecycle` now holds one process-wide C session owner from preparation
until C stop, decoder cleanup invocation and global teardown finish. A waiting
or unstarted connection can be cancelled without interrupting the current C
session. Repeated cancellation is idempotent, and a queued old stop first checks
that it still owns the C session. Decoder cleanup from common's `DrCleanup` and
the fallback for startup failures share a single cleanup claim.

`Connection` no longer publishes its renderer, callbacks, color options, authored
haptics option or audio observer during construction. The owned preparation step
publishes them after predecessor teardown and activates the decoder's shared
FrameQueue. `VideoDecoderRenderer` construction no longer claims that queue or
the active-renderer global; cleanup of a never-activated decoder skips the queue.
Decoder cleanup stops its owned queue immediately, synchronously drains the
display link on the main thread, and schedules the remaining main-thread resource
cleanup. The registered `DrStop` also invalidates that display link before common
destroys its video queue. Pending AVSB dequeues carry decoder ownership. Activation
is terminally disabled after cleanup.

The first C stage callback reasserts an active owner's cancellation after common
resets its interrupt flag. This closes the interval between the caller's final
cancellation check and the C reset without holding a manager lock through C
startup. Cancelled stage/start callbacks are suppressed. Delayed audio reset and
interruption work captures its Connection and performs global audio changes only
while that connection still owns an active session.

The vendored common-C termination dispatcher now supports the optional
`connectionTerminatedWithSession` callback from published shared-core commit
`100c767`, using the `connectionSessionId` field and an opaque 64-bit client-local
token. Each detached thread owns a snapshot of its callback, token and error;
it frees that snapshot before invoking the client. The iOS bridge atomically
claims a matching active token once and captures that Connection and its own
callback target before delivering outside the ownership lock. A delayed
predecessor notification cannot resolve to the successor's global callback.
Legacy callers still use the original callback, and both callback forms retain
the ability to call `LiStopConnection` synchronously.

The actual production StreamManager implementation is exercised by
`bash tests/run_stream_manager_lifecycle_tests.sh`. The harness compiles exact
temporary copies of StreamManager and HttpRequest with controlled HTTP, crypto,
decoder and connection dependencies; StreamConfiguration and HttpResponse are
also production code. It does not rewrite the manager implementation or inspect
source text as a substitute for execution. All **11 cases passed**, covering:

- Stop/cancel before startup and during crypto, serverinfo, launch and resume.
- Suppression of a cancelled request's late error and queued main continuation.
- Normal connection creation, active error reporting and idempotent stop.
- 2D glasses presentation selects Metal before connection creation while the
  transport remains mono.

`bash tests/run_connection_lifecycle_tests.sh` compiles the actual Foundation-only
coordinator used by Connection. All **16 cases passed**, covering:

- No-owner callbacks, never-queued release and cancellation before C entry.
- Cancellation during preparation and across C's interrupt reset.
- Startup failure before video setup and exactly-once common/fallback cleanup.
- Ownership after startup returns and successor blocking through complete
  predecessor teardown.
- Cancelling a waiting successor without affecting the current session.
- 64 concurrent stop requests, atomic external actions and 100 cancelled-start
  handoffs with stale queued stop work.
- Stale-token rejection, instance-owned callback capture across handoff and
  exactly-once delivery under 64 concurrent termination claims.

The same 16 cases also passed with ThreadSanitizer and no reported races:
`CONNECTION_LIFECYCLE_TSAN=1 bash tests/run_connection_lifecycle_tests.sh`.

`bash tests/run_common_termination_tests.sh` passed **12 cases** using the exact
production Connection.c dispatcher and Misc.c callback initializer with controlled
thread delivery and allocation. Cases cover delayed predecessor/successor delivery
in both orders, callback/token/error snapshot identity, legacy behavior,
synchronous stop inside both callback forms, allocation failure, thread-creation
failure, interruption suppression and repeated termination. The same cases pass
AddressSanitizer and UndefinedBehaviorSanitizer:
`COMMON_TERMINATION_ASAN=1 bash tests/run_common_termination_tests.sh`.

The simulator harness passed **33 display/Metal/queue cases**, including new
checks that empty waits sleep after direct dequeue/clear and that a fresh enqueue
still wakes the consumer, and that delayed producers and consumers cannot modify
a successor's queue. Captured console:
`Build/external-display-tests/20260907-231429-38951/console.log`.

## Published fix adoption (2026-09-08)

The migration to the shared `100c767` implementation passed 15 production C
termination cases normally and under AddressSanitizer/UndefinedBehaviorSanitizer.
They include the original delayed-delivery coverage plus immutable start
snapshots and callbacks that synchronously stop/reconnect before detached-thread
creation returns. The 18 iOS lifecycle cases passed normally and under
ThreadSanitizer.

The new Darwin fixture executes production `Platform.c` with real pthreads. It
passed 3,140 checks normally and under AddressSanitizer/UndefinedBehaviorSanitizer,
including 256 forced immediate completions, native detach, payload ownership,
allocation/create failure, existing join/interrupt/detach behavior and the fork's
QoS API. The signed iPhone build passed. The compatibility patch reproduces all
four production files byte-for-byte from the recorded pristine iOS base.

Evidence is recorded in
`build/host-streaming-cleanup/published-termination-fix/verification.json` and
`reproducibility.json` in that directory. Earlier counts above describe initial
cleanup runs. No new physical Raw or reconnect acceptance is implied by this
migration's native regression checks.

## Clean shared-core adoption (2026-09-09)

The earlier Connection-owned startup/reset, missing-cleanup and detached
termination identity gaps are addressed by the coordinator and optional common-C
API with controlled regression coverage. These tests do not claim physical-host
reconnect qualification, nor binary compatibility with a library/client built
against mismatched callback-struct versions.

The iOS submodule now consumes published `dcatcher9/moonlight-common-c` revision
`3a235790931e8092500e215f4864e696147bf3f6`, identical to Android's pin, without
local source modifications. The temporary four-file backport was verified,
backed up and removed. Microphone and authored haptics remain available in the
shared core; the iOS bridge continues using the published `WithSession` API.

The 15 termination cases and 18 lifecycle cases pass on this revision, including
ASan/UBSan and TSan respectively. The Darwin thread fixture now passes 3,402
checks, including releasing trampoline context before entry and direct
`pthread_exit`. Its old fork-only QoS assertion was removed because the shared
core uses its own worker scheduling. All eight upstream feature suites also
pass normally and under ASan/UBSan. Logs are in
`build/host-streaming-cleanup/shared-core-20260909/`.

Host and Android references were fetched and fast-forwarded under the user's
explicit sync request. No source edits or builds were made in either reference.
See `docs/shared-common-core-ios-handoff.md` for platform adapters and remaining
physical-device qualification.

## Decoder recovery after backgrounding

The physical Host 3D capture on 2026-09-08 showed error -17694 after returning to
the app. The installed SDK defines it as `kVTVideoDecoderReferenceMissingErr`:
the reset decoder was accepting predicted frames before receiving fresh
references. The old path also ignored synchronous VT decode failures, whose
output handler is not invoked, and could re-enter the decoder lock from a VT
worker callback while the caller waited for that callback.

`SunlightDecoderRecovery.h` now owns the production admission/retry state.
Invalidation requires a successfully decoded IDR before inter frames resume;
pending recovery asks at most twice per second. Non-PiP background pause drops
incoming pictures and parameter sets before decoder/format recreation. The
controller supplies its completed PiP decision to avoid notification-order
ambiguity. Foreground callbacks arm recovery; compressed-frame submission
requests refresh through common's `DR_NEED_IDR` return path.

Direct VT return errors and synchronous output-callback errors feed the same
recovery path. The output callback records its result without acquiring the
decoder lock, and the caller handles invalidation after the VT call returns.
Legacy AVSampleBuffer layer/PiP paths retain their existing behavior.

`bash tests/run_decoder_recovery_tests.sh` passes nine production state-machine
cases under AddressSanitizer/UndefinedBehaviorSanitizer. The complete signed iOS
build also passed. On the installed 08:04 build, the user confirmed that Home
Screen and return resumes normally with the glasses connected. That transition
left the application active through the external scene, so it did not exercise
the decoder-reset path. A later 08:42 PDT transition did reach application
background state, requested fresh IDRs, and rebuilt HEVC format on return without
subsequent decoder errors in the capture. Optical confirmation of that later
recovery remains pending. These observations are preserved in
`build/host-streaming-device/physical-validation.json` and
`build/host-streaming-device/live-console-20260908-phone-tablet.log`.
