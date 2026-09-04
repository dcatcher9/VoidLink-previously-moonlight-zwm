# Project boundaries

This workspace is the writable iOS Sunlight 3D app, based on VoidLink.

The following sibling repositories are read-only references:

- `/Volumes/Data/repos/Apollo-3D` (Sunshine 3D host)
- `/Volumes/Data/repos/moonlight-android` (Moonlight 3D client)

The user maintains and fixes those projects on another machine. You may read their
source and Git history to understand protocol compatibility, but must not edit,
commit, reset, stash, fetch, build, or otherwise write into either repository.
A general request to fix a streaming problem authorizes changes to this iOS
project only. Report required host/client-reference changes to the user instead.
Apply these boundaries to delegated agents as well.

# Device debugging

For future app launches, use live console capture so logs can be inspected
directly without asking the user to copy Xcode's console. Preserve the capture
path for follow-up diagnostics, and redact session keys and pairing secrets from
captured/shared output. Do not restart a running app merely to answer a question;
restart when the user requests it or as part of an authorized build-and-test run.
