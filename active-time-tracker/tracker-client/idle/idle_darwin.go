//go:build darwin

package idle

import (
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// GetIdleTime returns the time elapsed since the last user input (mouse or keyboard).
func GetIdleTime() (time.Duration, error) {
	// macOS command to get idle time in nanoseconds from IOHIDSystem
	cmd := exec.Command("ioreg", "-c", "IOHIDSystem")
	out, err := cmd.Output()
	if err != nil {
		return 0, err
	}

	lines := strings.Split(string(out), "\n")
	for _, line := range lines {
		if strings.Contains(line, "HIDIdleTime") {
			parts := strings.Split(line, "=")
			if len(parts) == 2 {
				nanoStr := strings.TrimSpace(parts[1])
				nanos, err := strconv.ParseInt(nanoStr, 10, 64)
				if err != nil {
					return 0, err
				}
				return time.Duration(nanos), nil
			}
		}
	}
	return 0, nil
}
