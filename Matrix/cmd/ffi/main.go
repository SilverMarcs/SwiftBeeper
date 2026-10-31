// Command ffi builds libRelayCore, the C archive linked into RelayCore.framework,
// which the app and its extensions share to run the Matrix core in process.
// Commands and results are JSON strings; changes stream to a callback.
package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef uintptr_t RelayCoreHandle;
typedef uintptr_t RelayCoreRealtimeHandle;
// The payload is valid only during the call; copy it before returning.
typedef void (*RelayCoreRealtimeCallback)(uintptr_t realtime_handle, const char *payload, size_t length);

static inline void relay_call_realtime(RelayCoreRealtimeCallback cb, uintptr_t realtime_handle, const char *payload, size_t length) {
	cb(realtime_handle, payload, length);
}
*/
import "C"

import (
	"context"
	"encoding/json"
	"runtime/cgo"
	"sync/atomic"
	"time"
	"unsafe"

	"relay/core/internal/app"
)

type ffiRuntime struct {
	runtime        *app.Runtime
	nextRealtimeID atomic.Uint64
}

func goString(value *C.char) string {
	if value == nil {
		return ""
	}
	return C.GoString(value)
}

// marshalResult returns value as a C JSON string the caller frees with
// RelayCoreFreeCString.
func marshalResult(value any) *C.char {
	raw, err := json.Marshal(value)
	if err != nil {
		return C.CString(`{"error":"failed to marshal ffi result"}`)
	}
	return C.CString(string(raw))
}

func errorResult(message string) *C.char {
	return marshalResult(map[string]any{"error": message})
}

func runtimeFromHandle(handle C.RelayCoreHandle) *ffiRuntime {
	return cgo.Handle(handle).Value().(*ffiRuntime)
}

// RelayCoreCreate returns a handle for a new core, or 0 on failure.
//
//export RelayCoreCreate
func RelayCoreCreate(cfgJSON *C.char) C.RelayCoreHandle {
	var cfg app.Config
	if raw := goString(cfgJSON); raw != "" {
		if err := json.Unmarshal([]byte(raw), &cfg); err != nil {
			return 0
		}
	}
	rt, err := app.New(cfg)
	if err != nil {
		return 0
	}
	return C.RelayCoreHandle(cgo.NewHandle(&ffiRuntime{runtime: rt}))
}

// RelayCoreStart returns 0 on success and 1 on failure.
//
//export RelayCoreStart
func RelayCoreStart(handle C.RelayCoreHandle) C.int {
	if err := runtimeFromHandle(handle).runtime.Start(context.Background()); err != nil {
		return 1
	}
	return 0
}

// RelayCoreStop pauses sync and closes the database, so another process can
// open it. RelayCoreStart reopens it on the same handle.
//
//export RelayCoreStop
func RelayCoreStop(handle C.RelayCoreHandle) {
	runtimeFromHandle(handle).runtime.Stop()
}

//export RelayCoreDestroy
func RelayCoreDestroy(handle C.RelayCoreHandle) {
	h := cgo.Handle(handle)
	h.Value().(*ffiRuntime).runtime.Stop()
	h.Delete()
}

// RelayCoreCommand runs one JSON command and returns its JSON result, or an
// object with an "error" message.
//
//export RelayCoreCommand
func RelayCoreCommand(handle C.RelayCoreHandle, input *C.char) *C.char {
	var command app.Command
	raw := json.RawMessage(goString(input))
	if json.Unmarshal(raw, &command) != nil {
		return errorResult("Invalid local command")
	}
	timeout := 20 * time.Second
	if command.Action == "login-custom" || command.Action == "verify" || command.Action == "share-message" {
		timeout = 2 * time.Minute
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	result, err := runtimeFromHandle(handle).runtime.Execute(ctx, command, raw)
	if err != nil {
		return errorResult(err.Error())
	}
	return marshalResult(result)
}

// RelayCoreRealtimeConnect opens the app's change stream. Opening a new one
// closes the previous stream.
//
//export RelayCoreRealtimeConnect
func RelayCoreRealtimeConnect(handle C.RelayCoreHandle, callback C.RelayCoreRealtimeCallback) C.RelayCoreRealtimeHandle {
	rt := runtimeFromHandle(handle)
	realtimeID := rt.nextRealtimeID.Add(1)
	rt.runtime.OpenRealtime(realtimeID, func(payload []byte) {
		if len(payload) == 0 {
			return
		}
		// The callback is synchronous and copies the bytes, so Go memory can be
		// passed without a C copy.
		C.relay_call_realtime(callback, C.uintptr_t(realtimeID), (*C.char)(unsafe.Pointer(&payload[0])), C.size_t(len(payload)))
	})
	return C.RelayCoreRealtimeHandle(realtimeID)
}

// RelayCoreRealtimeSubscribe takes a JSON array of the room IDs to stream
// message changes for. It returns NULL on success, or an error result.
//
//export RelayCoreRealtimeSubscribe
func RelayCoreRealtimeSubscribe(handle C.RelayCoreHandle, realtimeHandle C.RelayCoreRealtimeHandle, payloadJSON *C.char) *C.char {
	var roomIDs []string
	if err := json.Unmarshal([]byte(goString(payloadJSON)), &roomIDs); err != nil {
		return errorResult("invalid room subscriptions")
	}
	if err := runtimeFromHandle(handle).runtime.SubscribeRealtime(uint64(realtimeHandle), roomIDs); err != nil {
		return errorResult(err.Error())
	}
	return nil
}

//export RelayCoreRealtimeClose
func RelayCoreRealtimeClose(handle C.RelayCoreHandle, realtimeHandle C.RelayCoreRealtimeHandle) {
	runtimeFromHandle(handle).runtime.CloseRealtime(uint64(realtimeHandle))
}

//export RelayCoreFreeCString
func RelayCoreFreeCString(value *C.char) {
	if value != nil {
		C.free(unsafe.Pointer(value))
	}
}

func main() {}
