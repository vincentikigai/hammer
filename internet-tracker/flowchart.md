# IP Logger Script Flowchart

```mermaid
flowchart TD
    A[Script Start] --> B[Initialize Variables<br/>currentIP='', currentDNS='', startTime]
    B --> C{Check if CSV exists<br/>and has content}
    C -->|No| D[Create CSV header]
    C -->|Yes| E[Resume from previous session]
    D --> F[Enter Main Loop]
    E --> F

    F --> G[Get IP, DNS, Ping, Timestamp]
    G --> H{IP or DNS changed?}

    H -->|Yes| I[Save Previous Record<br/>with end_time and duration]
    H -->|No| J[Update Current Record Duration<br/>in CSV file]

    I --> K[Update Variables<br/>currentIP = new IP<br/>currentDNS = new DNS<br/>startTime = now]
    K --> L[Save New IP Record<br/>to CSV with empty end_time]

    L --> M[Sleep 10 seconds]
    J --> M
    M --> F

    F -->|Termination| N[Finally Block:<br/>Update Last Record<br/>with end_time and final duration]
    N --> O[Script End]
```

## Flow Description

The IP Logger script monitors internet connection changes and logs them to a CSV file. Key features:

1. **Initialization**: Sets up variables and creates CSV header if needed
2. **Main Loop**: Every 10 seconds, gets current IP/DNS/ping data
3. **Change Detection**: If IP or DNS changed, saves the previous session record and starts a new one
4. **Duration Updates**: On every heartbeat (changed or not), updates the duration of the current session in the CSV
5. **Termination**: When script ends, updates the final record with end time and duration

This ensures that:
- New IP changes are logged immediately
- Current session duration is always up-to-date in the CSV
- Power outages only lose at most 10 seconds of data
- Manual termination properly closes the current session record