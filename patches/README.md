# Shared common-C dependency

There are no active local common-C patches. Both iOS and Moonlight 3D Android
consume `dcatcher9/moonlight-common-c` revision
`3a235790931e8092500e215f4864e696147bf3f6`.

The former four-file `100c767` termination compatibility backport was verified,
backed up, and removed before switching from the VoidLink fork. Its implementation
and the microphone/authored-haptics feature ports are now published in the shared
core. Do not reapply either the old `WithContext` patch or the `100c767` backport.

For a fresh iOS checkout, initialize the pinned dependency normally:

```sh
git submodule update --init --recursive moonlight-common/moonlight-common-c
```

The current core must have a clean working tree. Make shared-core changes on the
other machine and publish them before updating this client's pin. Platform capture,
rendering, lifecycle policy and Swift adapters stay in the iOS app.

See [the integration record](../docs/shared-common-core-ios-handoff.md) for the
adopted contracts and validation. Historical migration evidence is retained in the
ignored `build/host-streaming-cleanup/shared-core-20260909/` directory.
