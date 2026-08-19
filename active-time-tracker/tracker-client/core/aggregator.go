package core

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// loadStaleActiveSessions evaluates all active_state_*.json files in dataFolder.
// If an active session's last heartbeat is older than 180 seconds, it projects
// that active session as a finalized Session in memory (without touching any disk files).
func loadStaleActiveSessions(dataFolder string) []Session {
	files, err := filepath.Glob(filepath.Join(dataFolder, "active_state_*.json"))
	if err != nil || len(files) == 0 {
		return nil
	}

	now := time.Now().Round(0)
	var projected []Session

	for _, file := range files {
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
		if gapSeconds > 180 && rec.Duration >= 60 {
			session := Session{
				Date:        rec.Date,
				Start:       rec.StartTime,
				End:         rec.LastHeartbeatTime,
				Duration:    rec.Duration,
				DurationHms: rec.DurationHms,
			}
			projected = append(projected, session)
		}
	}
	return projected
}

// GenerateUnifiedReports reads all session_log*.json files in the data folder,
// aggregates all sessions by date, sorts them chronologically, and writes
// a unified markdown report for each date.
func GenerateUnifiedReports(dataFolder string) error {
	files, err := filepath.Glob(filepath.Join(dataFolder, "session_log*.json"))
	if err != nil {
		return err
	}

	// Read all sessions from device logs
	var allSessions []Session
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			continue
		}
		var wrapper struct {
			Sessions []Session `json:"sessions"`
		}
		if err := json.Unmarshal(data, &wrapper); err == nil {
			allSessions = append(allSessions, wrapper.Sessions...)
		}
	}

	// Read-only projection of any stale active sessions from other devices
	allSessions = append(allSessions, loadStaleActiveSessions(dataFolder)...)

	// Group by date
	sessionsByDate := make(map[string][]Session)
	for _, s := range allSessions {
		sessionsByDate[s.Date] = append(sessionsByDate[s.Date], s)
	}

	// Generate a report for each date
	for date, sessions := range sessionsByDate {
		// Sort sessions chronologically
		sort.Slice(sessions, func(i, j int) bool {
			return sessions[i].Start < sessions[j].Start
		})

		generateDailyReport(dataFolder, date, sessions)
	}
	return nil
}

// GenerateReportsForDates regenerates reports only for the specified dates.
// If dates is empty, it falls back to regenerating all dates found in the logs.
func GenerateReportsForDates(dataFolder string, dates []string) error {
	files, err := filepath.Glob(filepath.Join(dataFolder, "session_log*.json"))
	if err != nil {
		return err
	}
	if len(files) == 0 {
		return fmt.Errorf("no session_log*.json files found in %s", dataFolder)
	}

	fmt.Printf("Found %d session log file(s):\n", len(files))
	var allSessions []Session
	for _, file := range files {
		fmt.Printf("  -> %s\n", filepath.Base(file))
		data, err := os.ReadFile(file)
		if err != nil {
			continue
		}
		var wrapper struct {
			Sessions []Session `json:"sessions"`
		}
		if err := json.Unmarshal(data, &wrapper); err == nil {
			allSessions = append(allSessions, wrapper.Sessions...)
		}
	}
	fmt.Printf("Total sessions loaded: %d\n", len(allSessions))
	staleProjections := loadStaleActiveSessions(dataFolder)
	if len(staleProjections) > 0 {
		fmt.Printf("Loaded %d in-memory projection(s) for stale active sessions.\n", len(staleProjections))
		allSessions = append(allSessions, staleProjections...)
	}

	// Group all sessions by date
	sessionsByDate := make(map[string][]Session)
	for _, s := range allSessions {
		sessionsByDate[s.Date] = append(sessionsByDate[s.Date], s)
	}

	// Filter to requested dates, or all dates if none specified
	targetDates := dates
	if len(targetDates) == 0 {
		for d := range sessionsByDate {
			targetDates = append(targetDates, d)
		}
		sort.Strings(targetDates)
	}

	for _, date := range targetDates {
		sessions, ok := sessionsByDate[date]
		if !ok || len(sessions) == 0 {
			fmt.Printf("! No sessions found for %s\n", date)
			continue
		}
		sort.Slice(sessions, func(i, j int) bool {
			return sessions[i].Start < sessions[j].Start
		})
		generateDailyReport(dataFolder, date, sessions)
		total := 0
		for _, s := range sessions {
			total += s.Duration
		}
		fmt.Printf("+ Regenerated %s — %d session(s), total %s\n", date, len(sessions), FormatDuration(total))
	}
	return nil
}

func generateDailyReport(dataFolder, date string, sessions []Session) {
	totalSeconds := 0
	for _, s := range sessions {
		totalSeconds += s.Duration
	}

	var sb strings.Builder
	folderName := filepath.Base(dataFolder)
	if folderName == "." || folderName == "\\" || folderName == "/" {
		folderName = "Work Time"
	} else {
		// Insert spaces into CamelCase (e.g. ScreenTime -> Screen Time)
		re := regexp.MustCompile(`([a-z])([A-Z])`)
		folderName = re.ReplaceAllString(folderName, "${1} ${2}")
	}
	sb.WriteString(fmt.Sprintf("# %s Report - %s\n\n", folderName, date))
	sb.WriteString(fmt.Sprintf("- **Total Duration**: %s\n", FormatDuration(totalSeconds)))
	sb.WriteString(fmt.Sprintf("- **Total Sessions**: %d\n\n", len(sessions)))
	sb.WriteString("## Session Details\n\n")
	sb.WriteString("| Start | End | Duration |\n")
	sb.WriteString("| :--- | :--- | :--- |\n")

	for i := 0; i < len(sessions); i++ {
		curr := sessions[i]
		
		start := curr.Start
		if start == "" {
			start = "---"
		}
		end := curr.End
		if end == "" {
			end = "---"
		}
		
		sb.WriteString(fmt.Sprintf("| %s | %s | **%s** |\n", start, end, curr.DurationHms))

		// Check for break
		if i < len(sessions)-1 {
			next := sessions[i+1]
			
			// Parse times to calculate gap
			endTime, err1 := time.Parse("15:04:05", curr.End)
			startTime, err2 := time.Parse("15:04:05", next.Start)
			
			if err1 == nil && err2 == nil {
				gap := startTime.Sub(endTime).Seconds()
				if gap > 0 {
					sb.WriteString(fmt.Sprintf("| _Break_ | _%s_ | _Interruption_ |\n", FormatDuration(int(gap))))
				}
			}
		}
	}

	reportFile := filepath.Join(dataFolder, fmt.Sprintf("report_%s.md", strings.ReplaceAll(date, "/", "-")))
	os.WriteFile(reportFile, []byte(sb.String()), 0644)
}
