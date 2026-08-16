# Worktime Tracker: Domain Logic

This document illustrates the pure Domain Driven Design (DDD) model for the work tracker, separating core domain behaviors and events from technical implementation details.

```mermaid
flowchart TD
    subgraph Initialization ["Startup & Recovery Domain"]
        Start(("Tracker Start")) --> LoadData["Load Data & activeSession"]
        LoadData --> IsActive{"Unended activeSession<br/>present?"}
        
        IsActive -->|"Yes"| CheckGap{"(Now - lastHeartbeatTime)<br/>> InactivityThreshold?"}
        CheckGap -->|"Yes (Long Gap)"| Finalize["Action: Finalize unended session<br/>at lastHeartbeatTime"]
        CheckGap -->|"No (Short Gap)"| Resume["Action: Seamlessly Resume Session"]
        
        IsActive -->|"No"| StateIdle
        Finalize --> StateIdle
        Resume --> StateWorking
    end

    subgraph StateMachine ["Core Domain Events (State Machine)"]
        StateIdle(("State: Idle"))
        StateWorking(("State: Working"))

        StateIdle -->|"Event: User Input Detected"| CreateSession["Action: Start New Session"]
        CreateSession --> StateWorking

        StateWorking -->|"Event: Inactivity Threshold Exceeded"| EndSession["Action: End Session"]
        EndSession --> StateIdle

        StateWorking -->|"Event: Midnight Reached"| SplitSession["Action: Split Session &<br/>Generate yesterday's final MD Report"]
        SplitSession --> StateWorking
        
        StateWorking -->|"Event: Heartbeat Tick (30s)"| UpdateDisk["Action: Save activeSession<br/>heartbeat to disk"]
        UpdateDisk --> StateWorking

        StateWorking -->|"Event: System Suspended & Woken<br/>(Time gap > Threshold)"| SleepFallback["Action: Retroactively End Session<br/>at lastHeartbeatTime"]
        SleepFallback --> StateIdle
    end

    subgraph Termination ["Termination Domain"]
        StateIdle -.->|"Event: Tracker Terminated"| CleanExit["Action: Graceful Exit"]
        StateWorking -.->|"Event: Tracker Terminated"| GracefulExit["Action: Save high-precision heartbeat<br/>& preserve activeSession"]
        GracefulExit --> End(("Tracker End"))
        CleanExit --> End
    end

    subgraph CrossDevice ["Cross-Device Read-Side Projection Domain"]
        StateWorking -.->|"Event: Generate Unified Report"| CrossDeviceProject["Action: Evaluate remote activeState files in-memory<br/>Project stale remote sessions into report without mutating remote disk files"]
    end
```

## Domain Logic Highlights

### 1. State-Driven Architecture
The domain operates primarily between two states: **Idle** and **Working**. Transitions between these states are triggered by pure domain events (e.g., User Input, Inactivity, Midnight, System Suspend).

### 2. Single-Writer File Isolation Principle
In a cloud-synced storage environment (e.g., OneDrive), **each device is the sole owner and writer of its own state files** (`active_state_[Hostname].json` and `session_log_[Hostname].json`). No device is ever permitted to write, modify, or delete another device's state or log files on disk. This guarantees zero file lock collisions and eliminates sync conflict duplicates at the root level.

### 3. Event: Startup Recovery
"activeSession present" means an unended session was found saved on disk, indicating a previous instance of the tracker was closed improperly. On startup, the tracker evaluates the time gap since the last heartbeat. If the gap is small (less than `$InactivityThreshold`), it seamlessly resumes the "Working" state. If it's a large gap (e.g., computer restarted the next day), it finalizes the lost session.

### 4. Event: Midnight Reached
Sessions that span across midnight trigger an automatic split into two parts: one ending at 23:59:59 of the previous day, and another starting at 00:00:00 of the new day. At the moment of this split, the final markdown report for the previous day is explicitly generated. This maintains accurate daily boundaries and ensures the previous day's log is complete.

### 5. Event: Inactivity Threshold Exceeded
The domain considers the user "Working" as long as the time since their last input stays below the `$InactivityThreshold`. When this threshold is exceeded, the session ends.

### 6. Event: Heartbeat Tick
While in the "Working" state, a periodic heartbeat event saves the state to disk. This ensures that any sudden interruptions won't result in total data loss.

### 7. Event: System Suspended & Woken
If the system is suspended (e.g., sleep mode) while working, an event detects the sudden massive jump in time upon waking up. This automatically triggers a retroactive session closure at the last known heartbeat, preventing "sleep hours" from inflating work time.

### 8. Event: Tracker Terminated (Seamless Restart)
When the tracker is closed (e.g. for an update or OS restart), it does not forcefully finalize the session. Instead, it saves a final high-precision heartbeat. This defers the decision to the next startup's Recovery logic, allowing restarts that take less than `$InactivityThreshold` to seamlessly resume without fragmenting the session.

### 9. Event: Read-Side Cross-Device Projection
When generating unified reports across multiple devices, the reporting engine reads all `session_log_[hostname].json` files alongside all `active_state_[hostname].json` files. If a remote state file has not received a heartbeat for longer than `$InactivityThreshold` (indicating the remote device was put to sleep), the reporting engine dynamically projects that session as finalized **in-memory** for the report, without modifying or deleting the remote device's file on disk.
