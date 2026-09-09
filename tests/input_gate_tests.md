# Stream input isolation

Run `tests/run_input_gate_tests.sh`; add `INPUT_GATE_TSAN=1` to run the same 13 cases with Thread Sanitizer. The harness compiles the production `SunlightInputGate.m` and exercises connection admission, panel transitions, cancellation, terminal cleanup, nested delivery, and controlled concurrent delivery/cancellation. It does not simulate UIKit touch recognition or prove every input source uses the gate.

`StreamView` applies this gate to host mouse, keyboard, touch, Pencil and trackpad delivery. Delayed work captures the generation before scheduling. Opening local controls, changing touch mode, pausing touch, resigning app activity, and disconnecting invalidate pending work and release held input. Restoring the panel or app state cannot revive work from the old generation. Input remains disconnected until the controller accepts `connectionStarted`.

The collapsed trackpad retains existing gestures: one finger moves the pointer, a stationary tap clicks left, a quick two-finger tap clicks right, a second tap within 0.2 seconds followed by hold/move drags, and two fingers scroll. Configured pinch behavior remains. Right-click recognition does not cancel its own queued click or clear the multi-touch flag before finger-up.

The separate `run_relative_touch_tests.sh` fixture now checks eight actual handler/recognizer behaviors, including click types, dragging and cancellation; see `relative_touch_tests.md` for its test doubles and limits.

Physical integration checks still needed:

- Tap, double-tap, drag, two-finger right-click and scroll with the panel collapsed; verify right-click produces no extra left-click.
- Open controls during a drag, delayed click, Pencil stroke/shortcut or inertial scroll; verify release and no further PC input. Close with the original fingers still down; require a new touch before control resumes.
- Tap the pill and all expanded/local settings controls; verify no PC click, keyboard gesture or virtual gamepad action.
- Open the keyboard and trigger repeated layout/routing updates; verify it stays open. Open settings while holding keyboard modifiers; verify release.
- Pause touch; verify finger/Pencil control stops while a hardware mouse remains usable. Resume and verify a new gesture works.
- Background/foreground or disconnect during held input; verify no stuck state or delayed input in the next session.
- Enable/disable the session gamepad while a physical controller is present; verify the physical controller remains available and the saved OSC profile is unchanged.

The new controller surface must release its virtual pad before blocking local host input. Physical gamepads intentionally remain independent of the local panel gate. Legacy CALayer touch dispatch is disabled when the current OSC level is Off.

Explicit PC shortcuts intentionally use their own session owner while the panel blocks ordinary input. `run_command_execution_tests.sh` verifies cancellation and delayed-session isolation; see `command_execution_tests.md`.
