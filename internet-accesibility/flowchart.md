# Internet Monitor Flowchart

This document visualizes the enhanced logic of the `internet_monitor.ps1` script, which distinguishes between global and local connectivity issues.

```mermaid
flowchart TD
    A["Script Start"] --> B["Setup Modules & Config"]
    B --> C["Send Startup TEST Notification<br/>(Light: Green/Info)"]
    
    C --> D["Enter Main Loop"]
    
    subgraph Loop ["Monitoring Loop"]
        D --> E["Ping google.com<br/>(Primary)"]
        E --> F{"Google Success?"}
        
        F -->|"Yes"| G["State: Connected<br/>Light: Green"]
        G --> H["Reset failCount = 0"]
        H --> I{"State Changed?"}
        I -->|"Yes"| J["Notify: 'Internet Restored'<br/>Light: Green/Info"]
        I -->|"No"| K["Log: Connected"]
        
        F -->|"No"| L["Ping baidu.com<br/>(Fallback)"]
        L --> M{"Baidu Success?"}
        
        M -->|"Yes"| N["State: GlobalDown<br/>Light: Yellow"]
        M -->|"No"| O["State: InternetDown<br/>Light: Red"]
        
        N --> P["Increment failCount"]
        O --> P
        
        P --> Q{"failCount >= Threshold<br/>AND State Changed?"}
        Q -->|"Yes"| R["Notify based on State<br/>(Yellow/Warning or Red/Error)"]
        Q -->|"No"| S["Log: State failures"]
        
        J --> T["Wait $INTERVAL seconds"]
        K --> T
        R --> T
        S --> T
        T --> D
    end
```

## Logic Highlights

### 1. Granular Connection States
- **Connected (Green)**: Google is reachable. All is well.
- **Global Internet Not Reachable (Yellow)**: Google is down but Baidu is up. This often indicates a VPN issue or a localized block on international traffic.
- **Internet Interrupted (Red)**: Both Google and Baidu are down. This usually means your local internet connection is completely lost.

### 2. Color-Coded Notifications (Lights)
The script uses visual cues in both the terminal and Windows notifications:
- **Green (Info)**: Used for restoration and successful startup.
- **Yellow (Warning)**: Used for global connectivity issues.
- **Red (Error)**: Used for complete internet outages.

### 3. Smart Alerting
The script only sends notifications when the connection state actually *changes* (e.g., from Connected to GlobalDown). This prevents repeated alerts while the connection remains in a specific down state, though terminal logging continues to show the current failure count.
