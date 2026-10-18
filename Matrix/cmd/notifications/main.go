package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"runtime/debug"
	"time"
	"unsafe"

	"relay/core/internal/notifications"
)

func init() { debug.SetMemoryLimit(18 << 20) }

//export RelayNotificationPreview
func RelayNotificationPreview(input *C.char) *C.char {
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

func main() {}
