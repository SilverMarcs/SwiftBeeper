package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"

	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// roomBridge is what a room's m.bridge state says about its login.
type roomBridge struct {
	// protocolID is the bridge type, such as "slackgo", which matches the
	// bridge's key in com.beeper.bridge_state.
	protocolID string
	// receiver is the remote ID of the login the room belongs to, for
	// bridges that keep a room per login.
	receiver string
}

// bridgeInfoContent is the part of an m.bridge event the core reads.
type bridgeInfoContent struct {
	Protocol struct {
		ID string `json:"id"`
	} `json:"protocol"`
	Channel struct {
		Receiver string `json:"fi.mau.receiver"`
	} `json:"channel"`
}

// loadRoomBridges reads the m.bridge state of each room. A room can hold
// several, such as stale ones from an earlier bridge, so each keeps all.
func (s *Dispatcher) loadRoomBridges(ctx context.Context, roomArgs []any) (map[id.RoomID][]roomBridge, error) {
	result := make(map[id.RoomID][]roomBridge)
	if len(roomArgs) == 0 {
		return result, nil
	}
	rows, err := s.rt.Client().DB.Query(ctx, `SELECT cs.room_id, e.content
		FROM current_state cs JOIN event e ON e.rowid=cs.event_rowid
		WHERE cs.room_id IN (`+sqlSlots(len(roomArgs))+`) AND cs.event_type='m.bridge'
		ORDER BY cs.room_id, cs.state_key`, roomArgs...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var roomID id.RoomID
		var content []byte
		if err = rows.Scan(&roomID, &content); err != nil {
			return nil, err
		}
		var info bridgeInfoContent
		if json.Unmarshal(content, &info) != nil || info.Protocol.ID == "" {
			continue
		}
		result[roomID] = append(result[roomID], roomBridge{
			protocolID: info.Protocol.ID,
			receiver:   info.Channel.Receiver,
		})
	}
	return result, rows.Err()
}

// repliesInThreads reports whether the room's network replies in threads, as
// Slack does in channels and DMs alike.
func (s *Dispatcher) repliesInThreads(ctx context.Context, roomID id.RoomID) bool {
	bridges, err := s.loadRoomBridges(ctx, []any{roomID})
	if err != nil {
		return false
	}
	for _, bridge := range bridges[roomID] {
		if capabilitiesForBridge(bridge.protocolID).Threads {
			return true
		}
	}
	return false
}

// fillNetworkDetails adds the network logos and workspaces that bridges
// publish in their rooms' m.bridge state: the protocol's avatar is the
// network's logo, and on Slack the network section is the login's workspace.
func (s *Dispatcher) fillNetworkDetails(ctx context.Context, accounts []wire.Account) error {
	// Grouped by network section, so WhatsApp communities or Discord servers
	// add a row each, not one per room.
	rows, err := s.rt.Client().DB.Query(ctx, `SELECT json_extract(e.content,'$.protocol.id'),
		       MAX(COALESCE(json_extract(e.content,'$.protocol.avatar_url'),'')),
		       COALESCE(json_extract(e.content,'$.network.id'),''),
		       MAX(COALESCE(json_extract(e.content,'$.network.displayname'),'')),
		       MAX(COALESCE(json_extract(e.content,'$.network.avatar_url'),''))
		FROM current_state cs JOIN event e ON e.rowid=cs.event_rowid
		WHERE cs.event_type='m.bridge'
		GROUP BY 1, 3`)
	if err != nil {
		return err
	}
	defer rows.Close()
	logos := make(map[string]string)
	networks := make(map[string]wire.Workspace)
	for rows.Next() {
		var protocolID sql.NullString
		var logo, networkID, networkName, networkImage string
		if err = rows.Scan(&protocolID, &logo, &networkID, &networkName, &networkImage); err != nil {
			return err
		}
		if !protocolID.Valid {
			continue
		}
		if logo != "" {
			logos[protocolID.String] = logo
		}
		if networkID != "" {
			networks[protocolID.String+"\x00"+networkID] = wire.Workspace{ID: networkID, Name: networkName, ImgURL: networkImage}
		}
	}
	if err = rows.Err(); err != nil {
		return err
	}
	for index := range accounts {
		account := &accounts[index]
		account.NetworkImgURL = logos[account.BridgeID]
		if account.Workspace == nil {
			continue
		}
		// A copy: the cached accounts share the pointer.
		workspace := *account.Workspace
		if network, ok := networks[account.BridgeID+"\x00"+workspace.ID]; ok {
			if network.Name != "" {
				workspace.Name = network.Name
			}
			workspace.ImgURL = network.ImgURL
		}
		account.Workspace = &workspace
	}
	return nil
}
