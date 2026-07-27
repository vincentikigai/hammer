package main

import (
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"syscall"

	"active-time-tracker/core"
)

func main() {
	hostname, err := os.Hostname()
	if err != nil {
		hostname = "unknown_device"
	}

	dataFolder := os.Getenv("ACTIVE_TIME_FOLDER")
	if dataFolder == "" {
		homeDir, _ := os.UserHomeDir()
		dataFolder = filepath.Join(homeDir, "ActiveTime")
	}

	// Expand Windows %VAR% and $VAR/$HOME variables
	re := regexp.MustCompile(`%([^%]+)%`)
	dataFolder = re.ReplaceAllStringFunc(dataFolder, func(m string) string {
		return os.Getenv(m[1 : len(m)-1])
	})
	dataFolder = os.ExpandEnv(dataFolder)

	// Expand leading ~ to the actual home directory (works on macOS/Linux)
	if len(dataFolder) >= 2 && dataFolder[:2] == "~/" {
		homeDir, _ := os.UserHomeDir()
		dataFolder = filepath.Join(homeDir, dataFolder[2:])
	} else if dataFolder == "~" {
		homeDir, _ := os.UserHomeDir()
		dataFolder = homeDir
	}

	config := core.TrackerConfig{
		DataFolder:            dataFolder,
		InactivityThreshold:   180, // 3 minutes
		ReportIntervalMinutes: 60,
		Hostname:              hostname,
	}

	tracker := core.NewTracker(config)

	// Handle graceful shutdown
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-c
		tracker.StopGracefully()
		os.Exit(0)
	}()

	tracker.Start()
}
