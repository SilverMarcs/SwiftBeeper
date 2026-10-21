package app

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
)

// The SDK owns the authenticated Matrix session. Swift supplies only the
// notification gateway registration, never a Matrix access token.
func (r *Runtime) updatePusher(ctx context.Context, command Command) (any, error) {
	cli := r.rt.Client()
	if cli == nil || cli.Account == nil || cli.Client == nil || cli.Client.AccessToken == "" {
		return nil, fmt.Errorf("a logged-in Matrix session is required")
	}
	if len(command.Pushkey) != 64 || command.AppID == "" || len(command.AppID) > 64 {
		return nil, fmt.Errorf("invalid pusher registration")
	}
	request := map[string]any{
		"pushkey": command.Pushkey,
		"app_id":  command.AppID,
		"kind":    nil,
	}
	if command.Action == "set-pusher" {
		gateway, err := url.Parse(command.GatewayURL)
		if err != nil || gateway.Scheme != "https" || gateway.Host == "" || gateway.User != nil ||
			gateway.Path != "/_matrix/push/v1/notify" || gateway.RawQuery != "" || gateway.Fragment != "" {
			return nil, fmt.Errorf("invalid push gateway URL")
		}
		request["kind"] = "http"
		request["app_display_name"] = "Relay"
		request["device_display_name"] = command.DeviceDisplayName
		request["lang"] = "en"
		// Preserve pushers belonging to the user's other apps and devices.
		request["append"] = true
		request["data"] = map[string]string{"url": gateway.String(), "format": "event_id_only"}
	}
	_, err := cli.Client.MakeRequest(ctx, http.MethodPost, cli.Client.BuildClientURL("v3", "pushers", "set"), request, nil)
	return map[string]any{"success": err == nil}, err
}
