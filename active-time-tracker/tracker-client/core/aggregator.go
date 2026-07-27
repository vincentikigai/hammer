package core

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// GenerateUnifiedReports reads all *_session_log.json files in the data folder,
// aggregates all sessions by date, sorts them chronologically, and writes
// a unified markdown report for each date.
func GenerateUnifiedReports(dataFolder string) error {
	files, err := filepath.Glob(filepath.Join(dataFolder, "*_session_log.json"))
	if err != nil {
		return err
	}

	// Read all sessions from all devices
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

func generateDailyReport(dataFolder, date string, sessions []Session) {
	totalSeconds := 0
	for _, s := range sessions {
		totalSeconds += s.Duration
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("# Work Time Report - %s\n\n", date))
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
