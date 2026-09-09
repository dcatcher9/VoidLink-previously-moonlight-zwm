# iOS regression checks

Run from the repository root with a selected Xcode installation:

```sh
bash tests/run_ios_regression_tests.sh core
bash tests/run_ios_regression_tests.sh ui
```

`core` builds the production models, protocol/crypto and lifecycle code against
macOS frameworks. Callback tests compile unchanged production methods with
controlled dependencies so teardown, delayed delivery and malformed responses
can be reproduced. `ui` uses isolated iOS simulators for UIKit, actual Swift
browser views, Core Data storage and Metal/display routing. `all` runs both.
Each suite has an individual `run_*_tests.sh` entry point for focused iteration.
Logs go to an ignored timestamped build directory; `SUNLIGHT_TEST_LOG_DIR` can
choose another directory. Failures are collected and return a nonzero status.
Crypto checks use the macOS OpenSSL framework from the project's resolved Swift
package under `build/DerivedData/SourcePackages`. Build/resolve packages there
first, or set `SUNLIGHT_TEST_OPENSSL_FRAMEWORK` to the equivalent framework.

These tests do not contact the user's PC, send pairing requests or install on a
physical iPhone. They do not verify glasses optics, sustained GPU load, wireless
latency, microphone sound or physical controller haptics. Device launches must
follow the redacted live-console instructions in [AGENTS.md](../AGENTS.md).

The retired setup-screen suite became `settings_persistence_tests`; it retains
actual database/native-default coverage without compiling the removed setup UI.
`stream_quality_session_tests` covers staged tab changes, accepted reconnect
commit snapshots, Native/fixed choices and the exact Raw canvas.
