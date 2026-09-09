# Sunlight performance evidence

Status: 2026-09-08. One native Host 3D CPU sample identifies avoidable software
crypto work. An accelerated OpenSSL candidate builds but is **not integrated**;
no device performance benefit has been measured.

## Baseline capture

Signed Debug build, PID **9660**, iPhone 17 Pro, **iOS 26.6.1 (23G83)**.
Connection started **08:26:53.672 PDT**: Host 3D source **2622 × 1206**, HEVC
SBS decoded **5244 × 1206**, SDR, two Metal eye regions on **3840 × 1080** USB-C
glasses reporting a 60 Hz limit. Content/motion, bitrate, and achieved FPS were
not controlled measurements.

Time Profiler attached once for a requested 25 seconds, recording
**08:29:48.802–08:30:15.393 PDT**, **26.590884 seconds** including profiler
boundaries. No app restart, stop, settings change, or console interruption.

```sh
xcrun xctrace record --template 'Time Profiler' \
  --device 00008150-000170EC2E40401C --attach 9660 --time-limit 25s \
  --output build/host-streaming-device/native-performance/native-host3d-pid9660.trace
```

Evidence: `build/host-streaming-device/native-performance/` contains the ~22 MB
trace, `toc.xml`, `time-profile.xml`, `hangs.xml`, and `summary.json`. Live console:
`build/host-streaming-device/live-console-20260908-phone-tablet.log`. These are
ignored local artifacts. Redact keys/pairing secrets before sharing console
excerpts; use a fresh PID/output path for any later capture.

## Findings and limits

**11,066 running-thread samples**, weighted 1 ms each. One-core estimates divide
sampled CPU seconds by the complete 26.590884-second wall interval.

| Work | Sampled CPU | App sample share | Approx. one-core demand |
| --- | ---: | ---: | ---: |
| All app threads | 11.066 s | 100% | 41.6% |
| VideoRecv thread | 7.766 s | 70.18% | 29.2% |
| Decryption, inclusive | 4.970 s | 44.91% | 18.7% |
| AES/GHASH, leaf | 4.765 s | 43.06% | 17.9% |
| `submitDecodeBuffer`, leaf | 1.149 s | 10.38% | 4.3% |
| MetalVideoRenderer thread | 0.270 s | 2.44% | 1.0% |

Rows overlap. Decryption dominates identified CPU work; queue methods each
accounted for at most 0.2%, with no dominant queue/spin path. No >=250 ms hang
events were recorded. This does **not** prove a throughput bottleneck or measure
FPS, GPU time, whole-device utilization, battery, or thermal stability. Waiting
threads were excluded; sampling, profiler overhead, Debug code, and uncontrolled
content limit comparisons. Small Metal CPU weight does not measure GPU waiting.

## Isolated OpenSSL candidate

Baseline SPM **OpenSSL-Package 3.3.2000 / OpenSSL 3.3.2** explicitly defines
`OPENSSL_NO_ASM`; framework UUID **D691956E-6EBA-3507-A212-864B489C655F** matches
the trace. The [vendor recipe](https://github.com/krzyzanowskim/OpenSSL/blob/3.3.2000/scripts/build.sh#L99)
passes `no-asm`. Existing production EVP calls can use accelerated OpenSSL
without a new crypto implementation.

Candidate root: `build/host-streaming-cleanup/openssl-accelerated/`.
`build-ios-arm64.sh` uses official **3.3.2**, tag `openssl-3.3.2`, commit
`fb7fab9fa6f4869eaa8fbb97e0d593159f03ffe4`, with published archive SHA256:

```
2e8a40b01979afe8be0bbfb3de5dc1c6709fedb46d6c89c10da114ab5fc3d281
```

Flags: `ios64-xcrun enable-asm no-shared no-tests no-engine
-mios-version-min=12.0`; SDK 26.5; no crypto source patches.
`ios-arm64-install/lib/` contains both ARM64 archives. Generated headers omit
`OPENSSL_NO_ASM`; AESv8/GHASH symbols and `aese`/`pmull` instructions are present.
All **67 current app imports** are available; this is an ABI surface check.

`crypto-kat.c` calls production `PlatformCrypto.c` for **23** known-answer,
authentication-rejection, and context/IV-reuse checks. `build-kat-ios-arm64.sh`
compiled/linked successfully; **the checks have not run on a device**. No app,
SPM, project, cache, or device integration occurred. Candidate `README.md`,
`provenance.txt`, configuration, digest, and symbol reports preserve reproduction
details. Scripts/artifacts remain ignored and must be preserved when transferred.

## Remaining steps

1. Run device crypto checks and validate pairing/certificate/stream compatibility.
2. Package the required framework/module/header/API and platform slices before
   consistently replacing both package consumers. This static device slice
   cannot directly replace the full XCFramework; do not patch DerivedData.
3. Compare controlled content, bitrate, geometry, codec, display, and build
   settings with a fresh bounded sample. Measure frame delivery and sustained
   behavior separately before claiming FPS, CPU, or battery improvements.
