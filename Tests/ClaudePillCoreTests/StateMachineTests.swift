import XCTest
@testable import ClaudePillCore

final class StateMachineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let cwd = "/Users/dev/projects/my-app"

    private func event(_ name: String, session: String = "s1", tool: String? = nil, command: String? = nil) -> HookEvent {
        HookEvent(
            eventName: name,
            sessionId: session,
            cwd: cwd,
            toolName: tool,
            toolInput: command.map { .object(["command": .string($0)]) }
        )
    }

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testUserPromptSubmitStartsWorking() {
        var machine = StateMachine(config: .init(useApprovalTimer: true))
        let transitions = machine.handle(event("UserPromptSubmit"), now: t0)
        XCTAssertEqual(transitions.map(\.to), [.working])
        XCTAssertEqual(machine.sessions["s1"]?.state, .working)
        XCTAssertEqual(machine.sessions["s1"]?.projectName, "my-app")
        XCTAssertEqual(machine.aggregateState, .working)
    }

    func testPreThenPostReturnsToWorkingWithoutApproval() {
        var machine = StateMachine(config: .init(useApprovalTimer: true))
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "run_in_terminal", command: "ls"), now: at(1))
        XCTAssertEqual(machine.sessions["s1"]?.state, .toolPending)
        XCTAssertEqual(machine.aggregateState, .working, "toolPending is displayed as working")

        XCTAssertEqual(machine.tick(now: at(2)), [])
        machine.handle(event("PostToolUse", tool: "run_in_terminal"), now: at(2.5))
        XCTAssertEqual(machine.sessions["s1"]?.state, .working)
        XCTAssertNil(machine.sessions["s1"]?.pendingTool)
        XCTAssertEqual(machine.tick(now: at(10)), [])
    }

    func testApprovalTimerEscalatesToNeedsApproval() {
        var machine = StateMachine(config: .init(approvalDelay: 3, useApprovalTimer: true))
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "run_in_terminal", command: "npm run build"), now: at(1))

        XCTAssertEqual(machine.tick(now: at(3.9)), [])
        let transitions = machine.tick(now: at(4))
        XCTAssertEqual(transitions.map(\.to), [.needsApproval])
        let session = machine.sessions["s1"]!
        XCTAssertEqual(session.state, .needsApproval)
        XCTAssertEqual(session.stateSince, at(1), "waiting time counts from PreToolUse")
        XCTAssertEqual(session.pendingTool?.displayText, "Vill köra `npm run build`")
        XCTAssertEqual(machine.aggregateState, .needsApproval)

        // Approved → tool runs → PostToolUse
        let back = machine.handle(event("PostToolUse", tool: "run_in_terminal"), now: at(20))
        XCTAssertEqual(back.map(\.to), [.working])
    }

    func testAutoApprovedToolsNeverEscalate() {
        var machine = StateMachine(config: .init(approvalDelay: 3, autoApprovedTools: ["read_file"], useApprovalTimer: true))
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "read_file"), now: at(1))
        XCTAssertEqual(machine.tick(now: at(60)), [])
        XCTAssertEqual(machine.sessions["s1"]?.state, .toolPending)
    }

    func testParallelToolsWaitForAllPostToolUse() {
        var machine = StateMachine(config: .init(approvalDelay: 3, autoApprovedTools: ["read_file"], useApprovalTimer: true))
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "read_file"), now: at(1))
        machine.handle(event("PreToolUse", tool: "run_in_terminal", command: "rm -rf dist"), now: at(1.1))
        machine.handle(event("PostToolUse", tool: "read_file"), now: at(1.2))
        XCTAssertEqual(machine.sessions["s1"]?.state, .toolPending)
        XCTAssertEqual(machine.tick(now: at(5)).map(\.to), [.needsApproval])
        XCTAssertEqual(machine.sessions["s1"]?.pendingTool?.detail, "rm -rf dist")
        machine.handle(event("PostToolUse", tool: "run_in_terminal"), now: at(9))
        XCTAssertEqual(machine.sessions["s1"]?.state, .working)
    }

    func testStopGivesYourTurnFromAnyState() {
        for setup in [["UserPromptSubmit"], ["UserPromptSubmit", "PreToolUse"], []] {
            var machine = StateMachine(config: .init(useApprovalTimer: true))
            for name in setup { machine.handle(event(name, tool: "x"), now: t0) }
            let transitions = machine.handle(event("Stop"), now: at(5))
            XCTAssertEqual(transitions.last?.to, .yourTurn)
            XCTAssertEqual(machine.sessions["s1"]?.stateSince, at(5))
        }
    }

    func testUserPromptSubmitFromYourTurnAndNeedsApproval() {
        var machine = StateMachine(config: .init(useApprovalTimer: true))
        machine.handle(event("Stop"), now: t0)
        XCTAssertEqual(machine.handle(event("UserPromptSubmit"), now: at(1)).map(\.to), [.working])

        machine.handle(event("PreToolUse", tool: "t"), now: at(2))
        machine.tick(now: at(10))
        XCTAssertEqual(machine.sessions["s1"]?.state, .needsApproval)
        XCTAssertEqual(machine.handle(event("UserPromptSubmit"), now: at(11)).map(\.to), [.working])
    }

    func testYourTurnStaysByDefault() {
        var machine = StateMachine()
        machine.handle(event("Stop"), now: t0)
        machine.handle(event("PreToolUse", session: "s2", tool: "Bash"), now: t0)
        machine.handle(event("PermissionRequest", session: "s2", tool: "Bash"), now: t0)
        XCTAssertEqual(machine.tick(now: at(24 * 60 * 60)), [], "your turn / approval stays until you act")
        XCTAssertEqual(machine.attentionSessions.count, 2)
    }

    func testYourTurnTimesOutAfter30Minutes() {
        var machine = StateMachine(config: .init(yourTurnTimeout: 30 * 60, useApprovalTimer: true))
        machine.handle(event("Stop"), now: t0)
        XCTAssertEqual(machine.tick(now: at(30 * 60 - 1)), [])
        let removed = machine.tick(now: at(30 * 60))
        XCTAssertEqual(removed.map(\.to), [.idle])
        XCTAssertNil(removed.first?.session)
        XCTAssertTrue(machine.sessions.isEmpty)
        XCTAssertEqual(machine.aggregateState, .idle)
    }

    func testStaleWorkingSessionIsRemoved() {
        var machine = StateMachine(config: .init(staleTimeout: 100))
        machine.handle(event("UserPromptSubmit"), now: t0)
        XCTAssertEqual(machine.tick(now: at(99)), [])
        XCTAssertEqual(machine.tick(now: at(100)).map(\.to), [.idle])
    }

    func testDockBadgeMarksMostRecentRunningSession() {
        var machine = StateMachine(config: .init(useApprovalTimer: true))
        machine.handle(event("UserPromptSubmit", session: "a"), now: t0)
        machine.handle(event("UserPromptSubmit", session: "b"), now: at(1))
        machine.handle(event("Stop", session: "c"), now: at(2))
        let transitions = machine.dockBadgeAppeared(now: at(3))
        XCTAssertEqual(transitions.map(\.sessionId), ["b"])
        XCTAssertEqual(machine.sessions["b"]?.state, .needsApproval)
        XCTAssertEqual(machine.sessions["a"]?.state, .working)
    }

    func testDockBadgeWithoutRunningSessionDoesNothing() {
        var machine = StateMachine(config: .init(useApprovalTimer: true))
        machine.handle(event("Stop"), now: t0)
        XCTAssertEqual(machine.dockBadgeAppeared(now: at(1)), [])
    }

    func testPriorityAcrossSessions() {
        var machine = StateMachine(config: .init(approvalDelay: 3, useApprovalTimer: true))
        machine.handle(event("UserPromptSubmit", session: "a"), now: t0)
        XCTAssertEqual(machine.aggregateState, .working)
        machine.handle(event("Stop", session: "b"), now: at(1))
        XCTAssertEqual(machine.aggregateState, .yourTurn)
        machine.handle(event("PreToolUse", session: "a", tool: "t"), now: at(2))
        XCTAssertEqual(machine.aggregateState, .yourTurn)
        machine.tick(now: at(6))
        XCTAssertEqual(machine.aggregateState, .needsApproval)
        XCTAssertEqual(machine.orderedSessions.map(\.id), ["a", "b"])
        XCTAssertEqual(machine.attentionSessions.count, 2)
    }

    func testUnknownEventsOnlyRefreshActivity() {
        var machine = StateMachine(config: .init(useApprovalTimer: true))
        machine.handle(event("Stop"), now: t0)
        XCTAssertEqual(machine.handle(event("PreCompact"), now: at(29 * 60)), [])
        XCTAssertEqual(machine.tick(now: at(31 * 60)), [], "unknown event refreshed lastEventAt")
        XCTAssertEqual(machine.handle(event("PreCompact", session: "new"), now: at(1)), [])
        XCTAssertNil(machine.sessions["new"])
    }

    func testNoTransitionWhenStateUnchanged() {
        var machine = StateMachine(config: .init(useApprovalTimer: true))
        machine.handle(event("UserPromptSubmit"), now: t0)
        XCTAssertEqual(machine.handle(event("UserPromptSubmit"), now: at(1)), [])
        XCTAssertEqual(machine.sessions["s1"]?.stateSince, t0)
    }

    // MARK: - Claude Code signals

    func testNoTimerByDefault() {
        var machine = StateMachine()
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "Bash", command: "npm install"), now: at(1))
        XCTAssertEqual(machine.tick(now: at(120)), [], "long commands are not false alarms")
        XCTAssertEqual(machine.aggregateState, .working)
    }

    func testPermissionRequestNeedsApproval() {
        var machine = StateMachine()
        machine.handle(event("UserPromptSubmit"), now: t0)
        machine.handle(event("PreToolUse", tool: "Bash", command: "rm -rf dist"), now: at(1))
        let transitions = machine.handle(event("PermissionRequest", tool: "Bash", command: "rm -rf dist"), now: at(1.1))
        XCTAssertEqual(transitions.map(\.to), [.needsApproval])
        XCTAssertEqual(machine.sessions["s1"]?.pendingTool?.plainText, "Vill köra rm -rf dist")
        XCTAssertEqual(machine.handle(event("PostToolUse", tool: "Bash"), now: at(9)).map(\.to), [.working])
    }

    func testNotificationTypes() {
        var machine = StateMachine()
        machine.handle(event("UserPromptSubmit"), now: t0)
        var prompt = event("Notification"); prompt.notificationType = "permission_prompt"
        XCTAssertEqual(machine.handle(prompt, now: at(1)).map(\.to), [.needsApproval])

        var other = StateMachine()
        other.handle(event("Stop"), now: t0)
        var idle = event("Notification"); idle.notificationType = "idle_prompt"
        XCTAssertEqual(other.handle(idle, now: at(60)), [], "already yourTurn")
        var unknown = event("Notification"); unknown.notificationType = "auth_success"
        XCTAssertEqual(other.handle(unknown, now: at(61)), [])
    }

    func testAskUserQuestionWaitsImmediately() {
        var machine = StateMachine()
        machine.handle(event("UserPromptSubmit"), now: t0)
        let ask = HookEvent(
            eventName: "PreToolUse", sessionId: "s1", cwd: cwd, toolName: "AskUserQuestion",
            toolInput: .object(["questions": .array([.object(["question": .string("Vilken databas?")])])])
        )
        XCTAssertEqual(machine.handle(ask, now: at(1)).map(\.to), [.needsApproval])
        XCTAssertEqual(machine.sessions["s1"]?.pendingTool?.plainText, "Vilken databas?")
    }

    func testSessionStartAndEnd() {
        var machine = StateMachine()
        XCTAssertEqual(machine.handle(event("SessionStart"), now: t0), [])
        XCTAssertEqual(machine.sessions["s1"]?.state, .idle)
        XCTAssertEqual(machine.orderedSessions.count, 1, "listed as active (Redo)")
        let end = machine.handle(event("SessionEnd"), now: at(5))
        XCTAssertEqual(end.map(\.to), [.idle])
        XCTAssertTrue(machine.sessions.isEmpty)
    }

    func testIdleSessionExpires() {
        var machine = StateMachine()
        machine.handle(event("SessionStart"), now: t0)
        XCTAssertEqual(machine.tick(now: at(30 * 60)).count, 1)
    }
}
