package main

/*
#include <stdint.h>
typedef uintptr_t RelayCoreHandle;
*/
import "C"

import (
	"context"
	"encoding/json"
	"time"

	"relay/core/internal/app"
)

//export RelayCoreCommand
func RelayCoreCommand(handle C.RelayCoreHandle, input *C.char) *C.char {
	var command app.Command
	raw := json.RawMessage(goString(input))
	if json.Unmarshal(raw, &command) != nil {
		return marshalResult(map[string]any{"error": "Invalid local command"})
	}
	timeout := 20 * time.Second
	if command.Action == "login-custom" || command.Action == "verify" {
		timeout = 2 * time.Minute
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	result, err := runtimeFromHandle(handle).runtime.Execute(ctx, command, raw)
	if err != nil {
		return marshalResult(map[string]any{"error": err.Error()})
	}
	return marshalResult(result)
}
