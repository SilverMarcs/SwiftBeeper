package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"runtime/debug"
	"sync"
	"time"
	"unsafe"

	"relay/core/internal/notifications"
)

// Only the notification service extension calls RelayNotificationPreview, and
// it runs under a tight memory limit. The app shares this library, so the
// limit applies on first use rather than at load.
var limitMemory = sync.OnceFunc(func() { debug.SetMemoryLimit(18 << 20) })

// RelayNotificationPreview takes a JSON notifications.Request and returns a
// JSON preview, or NULL when there is none.
//
//export RelayNotificationPreview
func RelayNotificationPreview(input *C.char) *C.char {
	limitMemory()
	var request notifications.Request
	if input == nil || json.Unmarshal([]byte(C.GoString(input)), &request) != nil {
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 22*time.Second)
	defer cancel()
	preview, err := notifications.Fetch(ctx, request)
	if err != nil {
		return nil
	}
	data, err := json.Marshal(preview)
	if err != nil {
		return nil
	}
	return C.CString(string(data))
}

//export RelayNotificationFree
func RelayNotificationFree(value *C.char) { C.free(unsafe.Pointer(value)) }
