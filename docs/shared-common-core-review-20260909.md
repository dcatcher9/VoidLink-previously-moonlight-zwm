# Shared common-C analyzer follow-up — 2026-09-09

Reviewed revision: `3a235790931e8092500e215f4864e696147bf3f6` of
`dcatcher9/moonlight-common-c`, as checked out by the iOS project. This is a
bounded triage of four reported areas, not verification of all shared-core or
vendor code. No core or sibling-reference files were changed. Shared-core fixes
remain work for the other machine and should arrive in a published revision.

## Confirmed: duplicate RTSP headers leak an option node

`src/RtspParser.c:157–166` allocates an `OPTION_ITEM` for each parsed header and
passes ownership to `insertOption`. At `src/RtspParser.c:294–299`, a matching
option name replaces `current->content` and returns without attaching or freeing
the incoming node. `freeOptionList` (`309–320`) only visits attached nodes, so
`freeMessage` cannot reclaim the duplicate allocation. The analyzer reports the
leak at line 175, after this ownership loss.

For example, parsing and freeing this response leaks one `OPTION_ITEM`:

```text
RTSP/1.0 200 OK\r\nCSeq: 1\r\nCSeq: 2\r\n\r\n
```

An isolated probe compiled the unchanged production `RtspParser.c` with counting
malloc/free wrappers and ASan/UBSan. Parsing, validating the last header value,
and calling `freeMessage` produced:

```text
distinct headers: 0 unreachable allocation(s) after freeMessage
duplicate CSeq: 1 unreachable allocation(s) after freeMessage
```

The probe frees its recorded orphan after checking the count; this demonstrates
the parser's ownership leak without deliberately leaking the test process.
Source and output are in the iOS checkout's ignored directory
`build/ios-review-20260909/shared-core-analyzer-triage/`, named
`rtsp_duplicate_header_probe.c` and `rtsp_duplicate_header_probe.log`.

Suggested fix: make `insertOption` consistently consume the incoming node on
both insertion and replacement. Replacing the entire existing list node while
retaining its list position, then freeing the replaced node according to
`FLAG_ALLOCATED_OPTION_FIELDS`, is one small approach that keeps ownership clear.
Do not merely free the incoming node and all its fields after copying its
content pointer: `RtspConnection.c:33–68` also supplies nodes with independently
allocated option/content strings. Preserve the current last-value-wins behavior.

Suggested regression: count allocations through parse/free for duplicate first,
middle, and last headers, repeated duplicates, malformed-message cleanup, and
the allocated-field path used by `addOption`. Verify the final value remains
correct and all allocations are reclaimed. Exercise those cases under a leak
detector or explicit allocation accounting, plus ASan/UBSan.

## Other reported paths

| Report | Assessment and follow-up |
| --- | --- |
| `reedsolomon/rs.c:355`, uninitialized read | The trace skips the matrix initialization loop at line 415 while taking positive data/parity counts. With valid counts and a positive sum no greater than `DATA_SHARDS_MAX` (255), every cell read by `sub_matrix` is initialized. The public constructor computes signed `data_shards + parity_shards` at line 398 before validating inputs, so extreme API arguments warrant an overflow-safe validation follow-up. Current audio uses constants 4+2; video derives bounded 10-bit data count and 8-bit percentage (`RtpVideoQueue.c:703–705`). No reachable uninitialized read from those callers was demonstrated. |
| `src/RtpVideoQueue.c:356`, null list head | Likely an invariant-related false positive. The trace assumes a sufficient positive list count at line 208 but a null head at line 290. `queuePacket` appends an entry before `reconstructFrame` is called, and insert/remove/purge maintain count and head together. Reconstruction does not remove the list head before this access. No valid queue state reaching the reported null access was found; a count/head invariant regression would make that assumption explicit. |
| `src/VideoDepacketizer.c:322` and `:540`, freeing stack `qduDS` | Likely false positives under the existing single-session lifecycle. Both traces assume `CAPABILITY_DIRECT_SUBMIT` changes between allocation choice at line 490 and freeing at lines 321/527. The capability is copied at connection startup and remains stable during a frame; video threads are joined during stop before the next session starts. The analyzer does not preserve that global invariant across calls/callbacks. A local allocation-kind snapshot could clarify ownership, but these traces do not establish an actual stack free. |

The original diagnostics and path events are retained in
`build/ios-review-20260909/analyze-iphoneos-final.log` and the corresponding
Xcode analyzer plist outputs. The duplicate-header leak is reproduced; the
other entries above are source/path-based triage, not equivalent runtime proof.
