package core

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ArchiveStaleSessions sweeps the data folder for hanging active sessions from other devices
// and archives them into their respective session logs.
func ArchiveStaleSessions(dataFolder string, currentHostname string, inactivityThreshold int) {
	files, err := filepath.Glob(filepath.Join(dataFolder, "active_state_*.json"))
	if err != nil || len(files) == 0 {
		return
	}

	now := time.Now().Round(0)

	for _, file := range files {
		baseName := filepath.Base(file)
		// Format: active_state_HOSTNAME.json
		parts := strings.TrimSuffix(strings.TrimPrefix(baseName, "active_state_"), ".json")
		hostname := parts

		// Don't archive our own active session, we handle that in loopTick/handleRecovery
		if hostname == currentHostname {
			continue
		}

		// Read active state
		data, err := os.ReadFile(file)
		if err != nil {
			continue
		}

		var wrapper struct {
			ActiveSession *ActiveSession `json:"activeSession"`
		}
		if err := json.Unmarshal(data, &wrapper); err != nil || wrapper.ActiveSession == nil {
			continue
		}

		rec := wrapper.ActiveSession
		lastHbStr := fmt.Sprintf("%s %s", rec.Date, rec.LastHeartbeatTime)
		lastHbTime, errParse := time.ParseInLocation("2006-01-02 15:04:05", lastHbStr, time.Local)
		if errParse != nil {
			continue
		}

		gapSeconds := now.Sub(lastHbTime).Seconds()
		if gapSeconds > float64(inactivityThreshold) {
			// Found a stale session! Archive it.
			fmt.Printf("\n[Cross-Device Archiver] Found stale session for %s (%.0f seconds ago). Archiving...\n", hostname, gapSeconds)
			
			// Load the target device's session log
			sessionLogFile := filepath.Join(dataFolder, fmt.Sprintf("session_log_%s.json", hostname))
			var remoteSessions []Session
			
			logData, err := os.ReadFile(sessionLogFile)
			if err == nil {
				var logWrapper struct {
					Sessions []Session `json:"sessions"`
				}
				if json.Unmarshal(logData, &logWrapper) == nil && logWrapper.Sessions != nil {
					remoteSessions = logWrapper.Sessions
				}
			}

			// Create the finalized session
			session := Session{
				Date:        rec.Date,
				Start:       rec.StartTime,
				End:         rec.LastHeartbeatTime,
				Duration:    rec.Duration,
				DurationHms: rec.DurationHms,
			}
			remoteSessions = append(remoteSessions, session)

			// Save the updated session log
			outWrapper := map[string]interface{}{
				"sessions": remoteSessions,
			}
			b, _ := json.MarshalIndent(outWrapper, "", "  ")
			if err := os.WriteFile(sessionLogFile, b, 0644); err == nil {
				// Delete the stale active state to prevent reprocessing
				os.Remove(file)
				fmt.Printf("[Cross-Device Archiver] Successfully archived session for %s.\n", hostname)
			}
		}
	}
}
