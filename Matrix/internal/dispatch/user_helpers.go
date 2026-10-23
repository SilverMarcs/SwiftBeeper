package dispatch

import (
	"strings"

	"maunium.net/go/mautrix/event"

	"relay/core/internal/compat"
)

// newUser trims every field and falls back to the user ID for a missing name.
func newUser(userID, fullName, imgURL, username string, isSelf bool) compat.User {
	userID = strings.TrimSpace(userID)
	fullName = strings.TrimSpace(fullName)
	if fullName == "" {
		fullName = userID
	}
	return compat.User{
		ID:       userID,
		Username: strings.TrimSpace(username),
		FullName: fullName,
		ImgURL:   strings.TrimSpace(imgURL),
		IsSelf:   isSelf,
	}
}

func userFromLocalBridgeProfile(remoteID string, profile map[string]any) compat.User {
	return newUser(
		remoteID,
		firstString(profile, "name", "display_name", "displayName"),
		firstString(profile, "avatar", "avatar_url"),
		firstString(profile, "username", "handle"),
		true,
	)
}

func userFromMemberEvent(userID string, member event.MemberEventContent, selfUserID string) compat.User {
	return newUser(userID, member.Displayname, string(member.AvatarURL), "", userID == selfUserID)
}
