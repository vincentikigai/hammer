package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	"active-time-tracker/core"
)

func resolveDataFolder() string {
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

	return dataFolder
}

func main() {
	// --- CLI flags ---
	reportMode := flag.Bool("report", false, "Regenerate reports and exit (does not start the tracker)")
	datesFlag := flag.String("dates", "", "Comma-separated list of dates to regenerate (e.g. 2026-07-29,2026-07-28). Used with --report. Defaults to today.")
	flag.Usage = func() {
		fmt.Println("Active Time Tracker")
		fmt.Println()
		fmt.Println("Usage:")
		fmt.Println("  active-time-tracker                           Start tracking")
		fmt.Println("  active-time-tracker --report                  Regenerate report for today")
		fmt.Println("  active-time-tracker --report --dates DATE,...  Regenerate reports for specific dates")
		fmt.Println()
		fmt.Println("Options:")
		flag.PrintDefaults()
		fmt.Println()
		fmt.Println("Environment:")
		fmt.Println("  ACTIVE_TIME_FOLDER  Path to the shared data folder (default: ~/ActiveTime)")
	}
	flag.Parse()

	dataFolder := resolveDataFolder()

	// --- Report-only mode ---
	if *reportMode {
		var dates []string
		if *datesFlag != "" {
			dates = strings.Split(*datesFlag, ",")
			for i, d := range dates {
				dates[i] = strings.TrimSpace(d)
			}
		} else {
			// Default to today
			dates = []string{time.Now().Format("2006-01-02")}
		}

		fmt.Printf("Data folder: %s\n\n", dataFolder)
		if err := core.GenerateReportsForDates(dataFolder, dates); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("\nDone!")
		return
	}

	// --- Normal tracker mode ---
	hostname, err := os.Hostname()
	if err != nil {
		hostname = "unknown_device"
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
