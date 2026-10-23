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
	"unsafe"

	"relay/core/internal/app"
)

type ffiRuntime struct {
	runtime        *app.Runtime
	nextRealtimeID atomic.Uint64
}

func cString(value string) *C.char {
	return C.CString(value)
}

func goString(value *C.char) string {
	if value == nil {
		return ""
	}
	return C.GoString(value)
}

func marshalResult(value any) *C.char {
	raw, err := json.Marshal(value)
	if err != nil {
		return cString(`{"error":"failed to marshal ffi result"}`)
	}
	return cString(string(raw))
}

func runtimeFromHandle(handle C.RelayCoreHandle) *ffiRuntime {
	return cgo.Handle(handle).Value().(*ffiRuntime)
}

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

//export RelayCoreStart
func RelayCoreStart(handle C.RelayCoreHandle) C.int {
	rt := runtimeFromHandle(handle)
	if err := rt.runtime.Start(context.Background()); err != nil {
		return 1
	}
	return 0
}

//export RelayCoreDestroy
func RelayCoreDestroy(handle C.RelayCoreHandle) {
	h := cgo.Handle(handle)
	h.Value().(*ffiRuntime).runtime.Stop()
	h.Delete()
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

//export RelayCoreRealtimeSubscribe
func RelayCoreRealtimeSubscribe(handle C.RelayCoreHandle, realtimeHandle C.RelayCoreRealtimeHandle, payloadJSON *C.char) *C.char {
	var roomIDs []string
	if err := json.Unmarshal([]byte(goString(payloadJSON)), &roomIDs); err != nil {
		return marshalResult(map[string]any{"error": "invalid room subscriptions"})
	}
	if err := runtimeFromHandle(handle).runtime.SubscribeRealtime(uint64(realtimeHandle), roomIDs); err != nil {
		return marshalResult(map[string]any{"error": err.Error()})
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
