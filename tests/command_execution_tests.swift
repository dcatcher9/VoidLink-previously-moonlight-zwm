import Foundation

// CommandManager imports UIKit but uses none of its types. Its two unrelated
// app dependencies are doubled so the complete, unchanged source runs on macOS.
public class ToolboxViewController: NSObject { public func reloadTableView() {} }
class PublicUtils { static let isGUIWidgetPickerAvailable = true }

private final class SessionState { var current = 1 }
@main struct CommandExecutionTests {
    static var cases = 0
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fputs("FAIL \(message)\n", stderr); exit(1) }
    }
    static func pass(_ message: String) { cases += 1; print("PASS \(message)") }
    static func pump(_ seconds: TimeInterval) {
        let end = Date(timeIntervalSinceNow: seconds)
        while end.timeIntervalSinceNow > 0 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: min(0.002, end.timeIntervalSinceNow)))
        }
    }
    static func events() -> [String] { CommandTestEvents() }
    static func send(_ commands: [String], owner: CommandExecutionOwner, delay: TimeInterval = 0.01) {
        CommandManager.shared.sendOwnedAutoReleaseComboCommand(cmdStrings: commands, delay: delay, owner: owner)
    }
    static func main() {
        require(Thread.isMainThread, "test must run on main")
        CommandTestReset()
        var owner = CommandExecutionOwner(canSend: { true })
        send(["CTRL", "C"], owner: owner)
        pump(0.05)
        require(events() == ["old:K17:down", "old:K67:down", "old:K67:up", "old:K17:up"], "normal shortcut changed press/reverse-release order")
        pass("owned keyboard shortcut completes and releases in reverse order")

        CommandTestReset()
        owner = CommandExecutionOwner(canSend: { true })
        send(["M_LEFT", "M_RIGHT"], owner: owner)
        pump(0.05)
        require(events() == ["old:M1:down", "old:M3:down", "old:M3:up", "old:M1:up"], "mouse shortcut left held buttons")
        pass("owned mouse shortcut completes and releases")

        CommandTestReset()
        owner = CommandExecutionOwner(canSend: { false })
        send(["CTRL", "C"], owner: owner)
        pump(0.03)
        require(events().isEmpty, "retired owner admitted its first command")
        pass("inactive owner rejects explicit execution")

        CommandTestReset()
        let state = SessionState()
        let oldToken = state.current
        owner = CommandExecutionOwner(canSend: { state.current == oldToken })
        send(["CTRL", "C"], owner: owner, delay: 0.04)
        require(events() == ["old:K17:down"], "first step must run synchronously")
        owner.cancelPendingCommands()
        require(events() == ["old:K17:down", "old:K17:up"], "pre-teardown cancellation failed to release only the held key")
        state.current = 2; CommandTestSetSession("new")
        let nextToken = state.current
        let successor = CommandExecutionOwner(canSend: { state.current == nextToken })
        send(["B"], owner: successor)
        pump(0.09)
        require(events() == ["old:K17:down", "old:K17:up", "new:K66:down", "new:K66:up"], "cancelled old down/up entered successor session")
        pass("cancellation releases before teardown and delayed old steps cannot reach successor")

        CommandTestReset()
        state.current = 1
        owner = CommandExecutionOwner(canSend: { state.current == 1 })
        send(["ALT", "F4"], owner: owner, delay: 0.04)
        state.current = 2; CommandTestSetSession("new")
        pump(0.06)
        owner.cancelPendingCommands()
        require(events() == ["old:K18:down"], "ownership loss sent an old release to successor")
        pass("already-lost ownership suppresses both delayed press and delayed cleanup")

        CommandTestReset()
        owner = CommandExecutionOwner(canSend: { true })
        send(["CTRL", "C"], owner: owner, delay: 0.04)
        send(["M_LEFT", "M_RIGHT"], owner: owner, delay: 0.04)
        owner.cancelPendingCommands()
        owner.cancelPendingCommands()
        pump(0.06)
        require(events().count == 4 && events().filter { $0 == "old:K17:up" }.count == 1 &&
            events().filter { $0 == "old:M1:up" }.count == 1, "one owner did not cancel every active sequence exactly once")
        pass("one session owner cancels sequences from repeated toolbox presentations")

        CommandTestReset()
        owner = CommandExecutionOwner(canSend: { true })
        owner.cancelPendingCommands()
        send(["A"], owner: owner)
        pump(0.03)
        require(events().isEmpty, "terminal owner reactivated")
        pass("cancelled owner stays retired even when its predicate remains true")

        CommandTestReset()
        owner = CommandExecutionOwner(canSend: { true })
        send(["CTRL", "CTRL", "A"], owner: owner)
        pump(0.012)
        owner.cancelPendingCommands()
        pump(0.05)
        require(events().filter { $0 == "old:K17:down" }.count == 2 &&
            events().filter { $0 == "old:K17:up" }.count == 1 &&
            !events().contains("old:K65:down"), "cleanup did not track only actually held keys")
        pass("duplicate presses have one held-key release on cancellation")

        CommandTestReset()
        owner = CommandExecutionOwner(canSend: { true })
        send([], owner: owner)
        owner.cancelPendingCommands()
        require(events().isEmpty, "empty shortcut generated input")
        pass("empty shortcut finishes without input")

        CommandTestReset()
        CommandManager.shared.sendAutoReleaseComboCommand(cmdStrings: ["CTRL", "C"], delay: 0.01)
        pump(0.05)
        require(events() == ["old:K17:down", "old:K67:down", "old:K67:up", "old:K17:up"], "ownerless legacy path changed")
        pass("ownerless legacy shortcut retains existing behavior")
        print("PASS \(cases) command execution cases")
    }
}
