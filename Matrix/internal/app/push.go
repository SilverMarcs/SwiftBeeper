package app

import (
	"context"
	"errors"
	"net/http"
	"net/url"

	"maunium.net/go/mautrix/id"

	"relay/core/internal/notifications"
	"relay/core/internal/wire"
)

// updatePusher registers or removes this device's Matrix pusher. The SDK owns
// the authenticated Matrix session; Swift supplies only the notification
// gateway registration, never a Matrix access token.
func (r *Runtime) updatePusher(ctx context.Context, command Command) (any, error) {
	cli := r.rt.Client()
	if cli == nil || cli.Account == nil || cli.Client == nil || cli.Client.AccessToken == "" {
		return nil, errors.New("a logged-in Matrix session is required")
	}
	if len(command.Pushkey) != 64 || command.AppID == "" || len(command.AppID) > 64 {
		return nil, errors.New("invalid pusher registration")
	}
	request := map[string]any{
		"pushkey": command.Pushkey,
		"app_id":  command.AppID,
		"kind":    nil, // A null kind removes the pusher.
	}
	if command.Action == "set-pusher" {
		gateway, err := url.Parse(command.GatewayURL)
		if err != nil || gateway.Scheme != "https" || gateway.Host == "" || gateway.User != nil ||
			gateway.Path != "/_matrix/push/v1/notify" || gateway.RawQuery != "" || gateway.Fragment != "" {
			return nil, errors.New("invalid push gateway URL")
		}
		request["kind"] = "http"
		request["app_display_name"] = "Relay"
		request["device_display_name"] = command.DeviceDisplayName
		request["lang"] = "en"
		// Preserve pushers belonging to the user's other apps and devices.
		request["append"] = true
		// The standard callback carries push-rule tweaks. event_id_only drops
		// them, making a mention indistinguishable from any other encrypted event.
		// The gateway ignores content and forwards only IDs and the mention flag.
		request["data"] = map[string]string{"url": gateway.String()}
	}
	if _, err := cli.Client.MakeRequest(ctx, http.MethodPost, cli.Client.BuildClientURL("v3", "pushers", "set"), request, nil); err != nil {
		return nil, err
	}
	return wire.Success, nil
}

// notificationCredentials hands the notification extension what it needs to
// fetch and decrypt one event on its own: the session and the backup key.
func (r *Runtime) notificationCredentials(ctx context.Context) (any, error) {
	cli := r.rt.Client()
	if cli == nil || cli.Account == nil {
		return nil, errors.New("session required")
	}
	key, err := cli.CryptoStore.GetSecret(ctx, id.SecretMegolmBackupV1)
	if err != nil {
		return nil, errors.New("backup key unavailable")
	}
	return notifications.Credentials{
		Homeserver:  cli.Account.HomeserverURL,
		UserID:      cli.Account.UserID,
		DeviceID:    cli.Account.DeviceID,
		AccessToken: cli.Account.AccessToken,
		BackupKey:   key,
	}, nil
}
