package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef uintptr_t RelayCoreHandle;
typedef uintptr_t RelayCoreRealtimeHandle;
typedef void (*RelayCoreRealtimeCallback)(uintptr_t realtime_handle, const char *payload);

static inline void relay_call_realtime(RelayCoreRealtimeCallback cb, uintptr_t realtime_handle, const char *payload) {
	cb(realtime_handle, payload);
}
*/
import "C"

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"runtime/cgo"
	"sync"
	"time"
	"unsafe"

	"relay/core/internal/app"
	"relay/core/internal/dispatch"
)

type ffiRuntime struct {
	runtime *app.Runtime

	mu             sync.Mutex
	nextRealtimeID uintptr
	realtime       map[uintptr]*ffiRealtime
}

type ffiRealtime struct {
	conn *dispatch.RealtimeConnection
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
	if cfg.StateDir != "" {
		_ = os.Setenv("GOMUKS_ROOT", cfg.StateDir)
		_ = os.Setenv("DEBUG_DIR", filepath.Join(cfg.StateDir, "logs"))
		_ = os.Setenv("GOMUKS_LOGS_HOME", filepath.Join(cfg.StateDir, "logs"))
		_ = os.Chdir(cfg.StateDir)
	}
	rt, err := app.New(cfg)
	if err != nil {
		return 0
	}
	return C.RelayCoreHandle(cgo.NewHandle(&ffiRuntime{
		runtime:  rt,
		realtime: make(map[uintptr]*ffiRealtime),
	}))
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
	rt := h.Value().(*ffiRuntime)
	rt.runtime.Stop()
	rt.mu.Lock()
	for id, conn := range rt.realtime {
		if conn != nil && conn.conn != nil {
			conn.conn.Close()
		}
		delete(rt.realtime, id)
	}
	rt.mu.Unlock()
	h.Delete()
}

//export RelayCoreHandleRequest
func RelayCoreHandleRequest(handle C.RelayCoreHandle, reqJSON *C.char) *C.char {
	var req app.Request
	if err := json.Unmarshal([]byte(goString(reqJSON)), &req); err != nil {
		return marshalResult(map[string]any{"error": fmt.Sprintf("invalid request: %v", err)})
	}
	timeout := 20 * time.Second
	if target, err := url.Parse(req.URL); err == nil {
		switch target.Path {
		case "/manage/login-custom", "/manage/verify":
			// Authentication restores crypto state through several server calls.
			// It must not share the short deadline used for ordinary local reads.
			timeout = 2 * time.Minute
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	response, err := runtimeFromHandle(handle).runtime.Handle(ctx, req)
	if err != nil {
		return marshalResult(map[string]any{"error": "Local request could not complete"})
	}
	return marshalResult(map[string]any{"response": response})
}

//export RelayCoreRealtimeConnect
func RelayCoreRealtimeConnect(handle C.RelayCoreHandle, callback C.RelayCoreRealtimeCallback) C.RelayCoreRealtimeHandle {
	rt := runtimeFromHandle(handle)
	rt.mu.Lock()
	rt.nextRealtimeID++
	realtimeID := rt.nextRealtimeID
	rt.mu.Unlock()

	conn, err := rt.runtime.OpenRealtime(func(payload json.RawMessage) error {
		payloadCString := cString(string(payload))
		C.relay_call_realtime(callback, C.uintptr_t(realtimeID), payloadCString)
		C.free(unsafe.Pointer(payloadCString))
		return nil
	})
	if err != nil {
		return 0
	}

	rt.mu.Lock()
	rt.realtime[realtimeID] = &ffiRealtime{conn: conn}
	rt.mu.Unlock()
	return C.RelayCoreRealtimeHandle(realtimeID)
}

//export RelayCoreRealtimeSend
func RelayCoreRealtimeSend(handle C.RelayCoreHandle, realtimeHandle C.RelayCoreRealtimeHandle, payloadJSON *C.char) *C.char {
	rt := runtimeFromHandle(handle)
	rt.mu.Lock()
	conn := rt.realtime[uintptr(realtimeHandle)]
	rt.mu.Unlock()
	if conn == nil || conn.conn == nil {
		return marshalResult(map[string]any{"error": "realtime connection not found"})
	}
	if err := conn.conn.Send([]byte(goString(payloadJSON))); err != nil {
		return marshalResult(map[string]any{"error": err.Error()})
	}
	return nil
}

//export RelayCoreRealtimeClose
func RelayCoreRealtimeClose(handle C.RelayCoreHandle, realtimeHandle C.RelayCoreRealtimeHandle) {
	rt := runtimeFromHandle(handle)
	rt.mu.Lock()
	conn := rt.realtime[uintptr(realtimeHandle)]
	delete(rt.realtime, uintptr(realtimeHandle))
	rt.mu.Unlock()
	if conn != nil && conn.conn != nil {
		conn.conn.Close()
	}
}

//export RelayCoreFreeCString
func RelayCoreFreeCString(value *C.char) {
	if value != nil {
		C.free(unsafe.Pointer(value))
	}
}

func main() {}
