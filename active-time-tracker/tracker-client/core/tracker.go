package core

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"active-time-tracker/idle"
)

type TrackerConfig struct {
	DataFolder            string
	InactivityThreshold   int // seconds
	ReportIntervalMinutes int
	Hostname              string
}

type TrackerData struct {
	Sessions      []Session      `json:"sessions"`
	ActiveSession *ActiveSession `json:"activeSession"`
}

type Tracker struct {
	config       TrackerConfig
	data         TrackerData
	isWorking    bool
	sessionStart time.Time
	lastLoopTime time.Time
	lastSaveTime time.Time
}

func NewTracker(config TrackerConfig) *Tracker {
	// Ensure data folder exists
	os.MkdirAll(config.DataFolder, 0755)

	t := &Tracker{
		config: config,
		data: TrackerData{
			Sessions: []Session{},
		},
	}
	t.loadData()
	return t
}

func (t *Tracker) getSessionLogFile() string {
	return filepath.Join(t.config.DataFolder, fmt.Sprintf("session_log_%s.json", t.config.Hostname))
}

func (t *Tracker) getActiveStateFile() string {
	return filepath.Join(t.config.DataFolder, fmt.Sprintf("active_state_%s.json", t.config.Hostname))
}

func (t *Tracker) loadData() {
	// Load Active State
	stateData, err := os.ReadFile(t.getActiveStateFile())
	if err == nil {
		var wrapper struct {
			ActiveSession *ActiveSession `json:"activeSession"`
		}
		json.Unmarshal(stateData, &wrapper)
		t.data.ActiveSession = wrapper.ActiveSession
	}

	// Load Sessions
	sessionData, err := os.ReadFile(t.getSessionLogFile())
	if err == nil {
		var wrapper struct {
			Sessions []Session `json:"sessions"`
		}
		json.Unmarshal(sessionData, &wrapper)
		if wrapper.Sessions != nil {
			t.data.Sessions = wrapper.Sessions
		}
	}
}

func (t *Tracker) saveActiveState() {
	wrapper := map[string]interface{}{
		"activeSession": t.data.ActiveSession,
	}
	b, _ := json.MarshalIndent(wrapper, "", "  ")
	os.WriteFile(t.getActiveStateFile(), b, 0644)
}

func (t *Tracker) getCsvFile() string {
	return filepath.Join(t.config.DataFolder, fmt.Sprintf("session_history_%s.csv", t.config.Hostname))
}

func (t *Tracker) saveSessions() {
	wrapper := map[string]interface{}{
		"sessions": t.data.Sessions,
	}
	b, _ := json.MarshalIndent(wrapper, "", "  ")
	os.WriteFile(t.getSessionLogFile(), b, 0644)

	// Export to CSV
	if len(t.data.Sessions) > 0 {
		csvContent := "Date,Start,End,Duration,DurationHms\n"
		for _, s := range t.data.Sessions {
			csvContent += fmt.Sprintf("%s,%s,%s,%d,%s\n", s.Date, s.Start, s.End, s.Duration, s.DurationHms)
		}
		os.WriteFile(t.getCsvFile(), []byte(csvContent), 0644)
	}
}

func (t *Tracker) Start() {
	fmt.Println("Work Time Tracker Started...")
	fmt.Printf("Data Path: %s\n", t.config.DataFolder)
	fmt.Printf("Hostname: %s\n", t.config.Hostname)
	fmt.Printf("Inactivity Threshold: %ds\n", t.config.InactivityThreshold)

	t.handleRecovery()

	t.lastLoopTime = time.Now().Round(0)
	t.lastSaveTime = time.Now().Round(0)

	for {
		now := time.Now().Round(0) // strip monotonic so all Sub() uses wall-clock
		t.loopTick(now)
		time.Sleep(1 * time.Second)
	}
}

func (t *Tracker) handleRecovery() {
	if t.data.ActiveSession == nil {
		return
	}

	rec := t.data.ActiveSession
	lastHbStr := fmt.Sprintf("%s %s", rec.Date, rec.LastHeartbeatTime)
	lastHbTime, err := time.ParseInLocation("2006-01-02 15:04:05", lastHbStr, time.Local)
	if err != nil {
		return
	}

	gapSeconds := time.Since(lastHbTime).Seconds()
	if gapSeconds <= float64(t.config.InactivityThreshold) {
		fmt.Printf(">>> Brief interruption detected (%.0fs). Seamlessly resuming...\n", gapSeconds)
		startStr := fmt.Sprintf("%s %s", rec.Date, rec.StartTime)
		var errParse error
		t.sessionStart, errParse = time.ParseInLocation("2006-01-02 15:04:05", startStr, time.Local)
		if errParse != nil || t.sessionStart.IsZero() {
			fmt.Printf("Warning: Could not parse StartTime from active state (%v). Resetting to now.\n", errParse)
			t.sessionStart = time.Now().Round(0)
		}
		t.isWorking = true
	} else {
		fmt.Println(">>> Long gap detected. Finalizing unended session...")
		session := Session{
			Date:        rec.Date,
			Start:       rec.StartTime,
			End:         rec.LastHeartbeatTime,
			Duration:    rec.Duration,
			DurationHms: rec.DurationHms,
		}
		t.data.Sessions = append(t.data.Sessions, session)
		t.data.ActiveSession = nil
		t.saveSessions()
		t.saveActiveState()
	}
}

func (t *Tracker) loopTick(now time.Time) {
	today := now.Format("2006-01-02")

	// 1. Sleep/Suspend Detection
	loopGap := now.Sub(t.lastLoopTime).Seconds()
	if loopGap > float64(t.config.InactivityThreshold) {
		if t.isWorking {
			sessionEnd := t.lastLoopTime
			duration := sessionEnd.Sub(t.sessionStart).Seconds()
			if duration > 1 {
				endDate := t.sessionStart.Format("2006-01-02")
				session := Session{
					Date:        endDate,
					Start:       t.sessionStart.Format("15:04:05"),
					End:         sessionEnd.Format("15:04:05"),
					Duration:    int(duration),
					DurationHms: FormatDuration(int(duration)),
				}
				t.data.Sessions = append(t.data.Sessions, session)
				fmt.Printf("[%s] Sleep detected! Session ended retroactively at %s (%s)\n", now.Format("15:04:05"), sessionEnd.Format("15:04:05"), session.DurationHms)
			}
			t.isWorking = false
			t.data.ActiveSession = nil
			t.saveSessions()
			t.saveActiveState()
		}
	}
	t.lastLoopTime = now

	idleDuration, err := idle.GetIdleTime()
	if err != nil {
		fmt.Println("Idle detection error:", err)
		return
	}
	idleSeconds := idleDuration.Seconds()

	if idleSeconds < float64(t.config.InactivityThreshold) {
		// Active
		if !t.isWorking {
			t.isWorking = true
			t.sessionStart = now
			fmt.Printf("[%s] Session Start\n", now.Format("15:04:05"))
		}

		// Midnight Split Check
		if t.isWorking && t.sessionStart.YearDay() != now.YearDay() {
			oldDate := t.sessionStart.Format("2006-01-02")
			y, m, d := t.sessionStart.Date()
			sessionEnd := time.Date(y, m, d, 23, 59, 59, 0, t.sessionStart.Location())
			duration := sessionEnd.Sub(t.sessionStart).Seconds()

			session := Session{
				Date:        oldDate,
				Start:       t.sessionStart.Format("15:04:05"),
				End:         "23:59:59",
				Duration:    int(duration),
				DurationHms: FormatDuration(int(duration)),
			}
			t.data.Sessions = append(t.data.Sessions, session)
			
			// Start new day session
			y, m, d = now.Date()
			t.sessionStart = time.Date(y, m, d, 0, 0, 0, 0, now.Location())
			fmt.Printf("[%s] Midnight Split - New day session started.\n", now.Format("15:04:05"))
			t.saveSessions()
		}

		// Heartbeat Save (every 30 seconds)
		if now.Second()%30 == 0 {
			duration := int(now.Sub(t.sessionStart).Seconds())
			t.data.ActiveSession = &ActiveSession{
				Date:              today,
				StartTime:         t.sessionStart.Format("15:04:05"),
				LastHeartbeatTime: now.Format("15:04:05"),
				Duration:          duration,
				DurationHms:       FormatDuration(duration),
			}
			t.saveActiveState()
		}

	} else {
		// Inactive
		if t.isWorking {
			t.isWorking = false
			sessionEnd := now.Add(-time.Duration(t.config.InactivityThreshold) * time.Second)
			duration := int(sessionEnd.Sub(t.sessionStart).Seconds())
			if duration > 1 {
				session := Session{
					Date:        today,
					Start:       t.sessionStart.Format("15:04:05"),
					End:         sessionEnd.Format("15:04:05"),
					Duration:    duration,
					DurationHms: FormatDuration(duration),
				}
				t.data.Sessions = append(t.data.Sessions, session)
				fmt.Printf("[%s] Session End - Duration: %s\n", now.Format("15:04:05"), session.DurationHms)
				t.data.ActiveSession = nil
				t.saveSessions()
				t.saveActiveState()
			}
		}
	}

	// Periodic report saving
	if now.Sub(t.lastSaveTime).Minutes() > float64(t.config.ReportIntervalMinutes) {
		GenerateUnifiedReports(t.config.DataFolder)
		fmt.Printf("[%s] Auto Report updated.\n", now.Format("15:04:05"))
		t.lastSaveTime = now
	}
}

// StopGracefully saves the final state when the application is closing
func (t *Tracker) StopGracefully() {
	if t.isWorking && !t.sessionStart.IsZero() {
		now := time.Now().Round(0)
		duration := int(now.Sub(t.sessionStart).Seconds())
		
		// Instead of finalizing the session, just record a high-precision heartbeat.
		// This delegates the decision (seamless resume vs finalize) to handleRecovery on the next startup.
		t.data.ActiveSession = &ActiveSession{
			Date:              now.Format("2006-01-02"),
			StartTime:         t.sessionStart.Format("15:04:05"),
			LastHeartbeatTime: now.Format("15:04:05"),
			Duration:          duration,
			DurationHms:       FormatDuration(duration),
		}
		t.saveActiveState()
		fmt.Println("\n[SIG] Final active state saved. Awaiting next startup for seamless resume check.")
	}
	
	GenerateUnifiedReports(t.config.DataFolder)
	fmt.Println("[SIG] Tracker stopped.")
}
