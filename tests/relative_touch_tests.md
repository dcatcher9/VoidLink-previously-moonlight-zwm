# Relative touch regression fixture

Run `tests/run_relative_touch_tests.sh`. It builds a small app for one dedicated iOS simulator, preserves build/live console logs under `build/relative-touch-tests/`, then shuts down and deletes that simulator. `RELATIVE_TOUCH_COMPILE_ONLY=1` builds without creating a simulator.

The runner copies and byte-compares the actual `RelativeTouchHandler`, `CustomTapGestureRecognizer`, `SunlightInputDispatch` and `SunlightInputGate` sources. It does not rewrite their code. Small doubles supply touch coordinates, event membership, settings, the StreamView-to-gate bridge, and a recorded host event sink. The separate Swift scroll component is a no-op here.

Eight cases passed on 2026-09-08 (`build/relative-touch-tests/20260908-092235-72800/console.log`):

- A stationary tap emits exactly one left press/release.
- Staggered two-finger taps emit only right press/release with the recognizer action before finger-up.
- The same tap emits only right press/release with the action after finger-up.
- Simultaneous two-finger input also emits only right press/release.
- A second tap within the existing interval holds the left button through movement, then releases without an extra click.
- Opening controls before a queued tap can enter the real gate rejects it, including after controls close.
- Cancelling a held finger prevents its later move/up from reactivating input after closing; a fresh tap works.
- The real ancestor recognizer delegate rejects pill touches and blocked StreamView touches.

The pending-tap case holds the real gate while cancelling, so the result does not depend on winning a scheduler race. Recognition itself uses the real touch/state methods; the harness deliberately dispatches the recognized action in both orders relative to handler finger-up. It does not simulate UIKit's full event arbitration, physical timing, StreamView's complete view hierarchy, Pencil, hardware input, or inertial scrolling. Those remain app/device checks listed in `input_gate_tests.md`.
