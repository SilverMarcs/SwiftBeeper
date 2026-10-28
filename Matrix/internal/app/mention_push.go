package app

import (
	"context"
	"errors"
	"net/http"
	"reflect"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/pushrules"
)

const mentionPushRuleID = "com.silvermarcs.relay.mention"

// This account-level exception precedes per-room mute rules, without changing
// the rooms' mute/archive state or the global master switch. First-match push
// rules produce one delivery for the event, not a separate mention event.
func (r *Runtime) configureMentionNotifications(ctx context.Context) error {
	cli := r.rt.Client()
	if cli == nil || cli.Account == nil {
		return errors.New("a logged-in Matrix session is required")
	}
	rules, err := cli.Client.GetPushRules(ctx)
	if err != nil {
		return err
	}
	conditions := []*pushrules.PushCondition{{
		Kind: pushrules.KindEventPropertyContains,
		Key:  `content.m\.mentions.user_ids`, Value: string(cli.Account.UserID),
	}}
	actions := pushrules.PushActionArray{
		{Action: pushrules.ActionNotify},
		{Action: pushrules.ActionSetTweak, Tweak: pushrules.TweakSound, Value: "default"},
		{Action: pushrules.ActionSetTweak, Tweak: pushrules.TweakHighlight, Value: true},
		{Action: pushrules.ActionSetTweak, Tweak: pushrules.PushActionTweak(mentionPushRuleID), Value: true},
	}
	var existing *pushrules.PushRule
	var before string
	for _, rule := range rules.Override {
		if rule.RuleID == ".m.rule.master" {
			continue
		}
		if rule.RuleID == mentionPushRuleID {
			existing = rule
			if before == "" && rule.Enabled && reflect.DeepEqual(rule.Conditions, conditions) && reflect.DeepEqual(rule.Actions, actions) {
				return nil
			}
		} else if before == "" {
			before = rule.RuleID
		}
	}
	query := map[string]string{}
	if before != "" {
		query["before"] = before
	}
	ruleURL := cli.Client.BuildURLWithQuery(mautrix.ClientURLPath{"v3", "pushrules", "global", "override", mentionPushRuleID}, query)
	if _, err = cli.Client.MakeRequest(ctx, http.MethodPut, ruleURL, map[string]any{
		"conditions": conditions, "actions": actions,
	}, nil); err != nil {
		return err
	}
	if existing != nil && !existing.Enabled {
		_, err = cli.Client.MakeRequest(ctx, http.MethodPut,
			cli.Client.BuildClientURL("v3", "pushrules", "global", "override", mentionPushRuleID, "enabled"),
			map[string]bool{"enabled": true}, nil)
	}
	return err
}
