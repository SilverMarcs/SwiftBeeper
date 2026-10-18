package app

import (
	"context"
	"fmt"

	"maunium.net/go/mautrix/id"
	"relay/core/internal/notifications"
)

func (r *Runtime) notificationCredentials(ctx context.Context) (any, error) {
	cli := r.rt.Client()
	if cli == nil || cli.Account == nil {
		return nil, fmt.Errorf("session required")
	}
	key, err := cli.CryptoStore.GetSecret(ctx, id.SecretMegolmBackupV1)
	if err != nil {
		return nil, fmt.Errorf("backup key unavailable")
	}
	return notifications.Credentials{Homeserver: cli.Account.HomeserverURL,
		UserID: cli.Account.UserID, DeviceID: cli.Account.DeviceID, AccessToken: cli.Account.AccessToken, BackupKey: key}, nil
}
