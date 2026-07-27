package core

import (
	"fmt"
)

// Session represents a finalized work session.
type Session struct {
	Date        string `json:"date"`
	Start       string `json:"start"`
	End         string `json:"end"`
	Duration    int    `json:"duration"`
	DurationHms string `json:"durationHms"`
}

// ActiveSession represents an ongoing work session that is saved periodically.
type ActiveSession struct {
	Date              string `json:"date"`
	StartTime         string `json:"startTime"`
	LastHeartbeatTime string `json:"lastHeartbeatTime"`
	Duration          int    `json:"duration"`
	DurationHms       string `json:"durationHms"`
}

// FormatDuration formats seconds into HH:mm:ss
func FormatDuration(seconds int) string {
	h := seconds / 3600
	m := (seconds % 3600) / 60
	s := seconds % 60
	return fmt.Sprintf("%02d:%02d:%02d", h, m, s)
}
