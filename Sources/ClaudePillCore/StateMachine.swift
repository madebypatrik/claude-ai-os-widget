import Foundation

public struct StateMachineConfig: Sendable, Equatable {
    /// Time a tool may stay between PreToolUse and PostToolUse before we assume it waits for approval.
    public var approvalDelay: TimeInterval
    /// A `yourTurn` session without events for this long is removed. Nil = stays until the
    /// session continues or ends (sessions waiting for the user are then never auto-removed).
    public var yourTurnTimeout: TimeInterval?
    /// A session that only started ("Redo") is removed after this long without events.
    public var idleTimeout: TimeInterval
    /// Any session without events for this long is removed (crashed / closed windows).
    public var staleTimeout: TimeInterval
    /// Tools that never need approval and therefore never start the approval timer.
    public var autoApprovedTools: Set<String>
    /// Timer heuristic (no PostToolUse within `approvalDelay` = waiting). Off for Claude Code,
    /// which reports approvals explicitly via PermissionRequest / Notification.
    public var useApprovalTimer: Bool

    public init(
        approvalDelay: TimeInterval = 3,
        yourTurnTimeout: TimeInterval? = nil,
        idleTimeout: TimeInterval = 30 * 60,
        staleTimeout: TimeInterval = 2 * 60 * 60,
        autoApprovedTools: Set<String> = [],
        useApprovalTimer: Bool = false
    ) {
        self.approvalDelay = approvalDelay
        self.yourTurnTimeout = yourTurnTimeout
        self.idleTimeout = idleTimeout
        self.staleTimeout = staleTimeout
        self.autoApprovedTools = autoApprovedTools
        self.useApprovalTimer = useApprovalTimer
    }
}

public struct StateTransition: Equatable, Sendable {
    public var sessionId: String
    public var from: AgentState
    public var to: AgentState
    /// The session after the transition, or nil if it was removed.
    public var session: Session?
}

/// Pure state logic from spec §6. Time is always passed in, so it is fully unit-testable.
public struct StateMachine: Sendable {
    public var config: StateMachineConfig
    public private(set) var sessions: [String: Session] = [:]

    public init(config: StateMachineConfig = StateMachineConfig()) {
        self.config = config
    }

    // MARK: - Queries

    /// Most urgent displayed state across sessions (`needsApproval` > `yourTurn` > `working` > `idle`).
    public var aggregateState: AgentState {
        sessions.values.map(\.state.displayState).max() ?? .idle
    }

    /// Sessions sorted by urgency, then by how long they have waited.
    public var orderedSessions: [Session] {
        sessions.values.sorted {
            if $0.state.displayState != $1.state.displayState {
                return $0.state.displayState > $1.state.displayState
            }
            if $0.stateSince != $1.stateSince { return $0.stateSince < $1.stateSince }
            return $0.id < $1.id
        }
    }

    public var attentionSessions: [Session] { orderedSessions.filter { $0.state.needsAttention } }

    // MARK: - Events

    @discardableResult
    public mutating func handle(_ event: HookEvent, now: Date = Date()) -> [StateTransition] {
        let kind = event.kind
        guard kind != .unknown else {
            sessions[event.sessionId]?.lastEventAt = now
            return []
        }
        if kind == .sessionEnd {
            return remove(sessionId: event.sessionId).map { [$0] } ?? []
        }

        var session = sessions[event.sessionId]
            ?? Session(id: event.sessionId, cwd: event.cwd ?? "", stateSince: now, lastEventAt: now)
        if let cwd = event.cwd, !cwd.isEmpty, cwd != session.cwd {
            session.cwd = cwd
            session.projectName = Session.projectName(for: cwd)
        }
        session.lastEventAt = now
        let previous = session.state

        switch kind {
        case .sessionStart:
            break // registers the session as "Redo" (idle)

        case .userPromptSubmit:
            Self.set(&session, to: .working, now: now)
            Self.clearTool(&session)

        case .preToolUse:
            session.pendingToolCount += 1
            let summary = event.toolSummary
            let autoApproved = !config.useApprovalTimer
                || (event.toolName.map { config.autoApprovedTools.contains($0) } ?? false)
            if let summary, summary.asksUser {
                // AskUserQuestion / ExitPlanMode: Claude is waiting for you right away.
                if session.state != .needsApproval { Self.set(&session, to: .needsApproval, now: now) }
                session.pendingTool = summary
                session.approvalDeadline = nil
                break
            }
            switch session.state {
            case .needsApproval:
                break // Still waiting for the user; keep showing the first blocked tool.
            case .toolPending:
                if !autoApproved, session.approvalDeadline == nil {
                    session.pendingTool = summary
                    session.approvalDeadline = now.addingTimeInterval(config.approvalDelay)
                }
            default:
                Self.set(&session, to: .toolPending, now: now)
                session.pendingTool = summary
                session.approvalDeadline = autoApproved ? nil : now.addingTimeInterval(config.approvalDelay)
            }

        case .postToolUse:
            session.pendingToolCount = max(0, session.pendingToolCount - 1)
            switch session.state {
            case .toolPending, .needsApproval:
                if session.pendingToolCount == 0 {
                    Self.set(&session, to: .working, now: now)
                    Self.clearTool(&session)
                }
            case .idle, .yourTurn:
                Self.set(&session, to: .working, now: now)
                Self.clearTool(&session)
            case .working:
                break
            }

        case .permissionRequest:
            if let summary = event.toolSummary { session.pendingTool = summary }
            if session.state != .needsApproval { Self.set(&session, to: .needsApproval, now: now) }
            session.approvalDeadline = nil

        case .notification:
            switch event.notificationType {
            case "permission_prompt", "elicitation_dialog":
                if session.state != .needsApproval { Self.set(&session, to: .needsApproval, now: now) }
                session.approvalDeadline = nil
            case "idle_prompt":
                if session.state != .yourTurn, session.state != .needsApproval {
                    Self.set(&session, to: .yourTurn, now: now)
                    Self.clearTool(&session)
                }
            default:
                break
            }

        case .stop:
            Self.set(&session, to: .yourTurn, now: now)
            Self.clearTool(&session)

        case .sessionEnd, .unknown:
            break
        }

        sessions[session.id] = session
        guard previous != session.state else { return [] }
        return [StateTransition(sessionId: session.id, from: previous, to: session.state, session: session)]
    }

    /// Advances timers. Call about once per second.
    @discardableResult
    public mutating func tick(now: Date = Date()) -> [StateTransition] {
        var transitions: [StateTransition] = []
        for id in sessions.keys.sorted() {
            guard var session = sessions[id] else { continue }
            let idleFor = now.timeIntervalSince(session.lastEventAt)

            let expired: Bool
            if session.state.needsAttention {
                // Waiting for the user: keep it until they act (or the optional timeout).
                expired = session.state == .yourTurn && config.yourTurnTimeout.map { idleFor >= $0 } == true
            } else if session.state == .idle {
                expired = idleFor >= config.idleTimeout
            } else {
                expired = idleFor >= config.staleTimeout
            }
            if expired {
                sessions[id] = nil
                transitions.append(StateTransition(sessionId: id, from: session.state, to: .idle, session: nil))
                continue
            }

            if session.state == .toolPending, let deadline = session.approvalDeadline, now >= deadline {
                session.state = .needsApproval // stateSince stays at PreToolUse
                session.approvalDeadline = nil
                sessions[id] = session
                transitions.append(StateTransition(sessionId: id, from: .toolPending, to: .needsApproval, session: session))
            }
        }
        return transitions
    }

    /// VS Code's Dock badge appeared: mark the most recently active running session as waiting.
    @discardableResult
    public mutating func dockBadgeAppeared(now: Date = Date()) -> [StateTransition] {
        let candidate = sessions.values
            .filter { $0.state == .working || $0.state == .toolPending }
            .max { $0.lastEventAt < $1.lastEventAt }
        guard var session = candidate else { return [] }
        let previous = session.state
        if previous != .toolPending { session.stateSince = now }
        session.state = .needsApproval
        session.approvalDeadline = nil
        sessions[session.id] = session
        return [StateTransition(sessionId: session.id, from: previous, to: .needsApproval, session: session)]
    }

    /// Removes a session (e.g. from a context menu). Returns the transition if it existed.
    @discardableResult
    public mutating func remove(sessionId: String) -> StateTransition? {
        guard let session = sessions.removeValue(forKey: sessionId) else { return nil }
        return StateTransition(sessionId: sessionId, from: session.state, to: .idle, session: nil)
    }

    // MARK: - Helpers

    private static func set(_ session: inout Session, to state: AgentState, now: Date) {
        guard session.state != state else { return }
        session.state = state
        session.stateSince = now
    }

    private static func clearTool(_ session: inout Session) {
        session.pendingTool = nil
        session.approvalDeadline = nil
        session.pendingToolCount = 0
    }
}
