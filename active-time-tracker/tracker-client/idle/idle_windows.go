//go:build windows

package idle

import (
	"syscall"
	"time"
	"unsafe"
)

var (
	user32           = syscall.NewLazyDLL("user32.dll")
	getLastInputInfo = user32.NewProc("GetLastInputInfo")
	kernel32         = syscall.NewLazyDLL("kernel32.dll")
	getTickCount     = kernel32.NewProc("GetTickCount")
)

type lastInputInfo struct {
	cbSize uint32
	dwTime uint32
}

// GetIdleTime returns the time elapsed since the last user input (mouse or keyboard).
func GetIdleTime() (time.Duration, error) {
	var lii lastInputInfo
	lii.cbSize = uint32(unsafe.Sizeof(lii))

	ret, _, err := getLastInputInfo.Call(uintptr(unsafe.Pointer(&lii)))
	if ret == 0 {
		return 0, err
	}

	tickCount, _, _ := getTickCount.Call()

	// tickCount and lii.dwTime are uint32 representing milliseconds.
	idleMs := uint32(tickCount) - lii.dwTime
	return time.Duration(idleMs) * time.Millisecond, nil
}
