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
	var command app.MobileCommand
	if json.Unmarshal([]byte(goString(input)), &command) != nil {
		return marshalResult(map[string]any{"error": "Invalid local command"})
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	result, err := runtimeFromHandle(handle).runtime.MobileExecute(ctx, command)
	if err != nil {
		return marshalResult(map[string]any{"error": "Local Matrix operation could not complete"})
	}
	return marshalResult(result)
}
