//go:build linux

package idle

import (
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// GetIdleTime returns the time elapsed since the last user input (mouse or keyboard).
// Note: Requires `xprintidle` to be installed on the system (e.g., sudo apt-get install xprintidle)
func GetIdleTime() (time.Duration, error) {
	cmd := exec.Command("xprintidle")
	out, err := cmd.Output()
	if err != nil {
		return 0, err
	}
	
	millisStr := strings.TrimSpace(string(out))
	millis, err := strconv.ParseInt(millisStr, 10, 64)
	if err != nil {
		return 0, err
	}
	
	return time.Duration(millis) * time.Millisecond, nil
}
