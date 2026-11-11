package dispatch

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"slices"
	"strings"
	"sync"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
	"maunium.net/go/mautrix/pushrules"
)

// Slack thread replies notify the way Slack's own app does: only in a thread
// you started, one you replied in, or one that mentions you. Push rules carry
// this, so the homeserver decides once for every device. They follow the
// mention rule in this order:
//
//	started → @channel/@here → one rule per followed thread → silence
//
// Override rules precede room rules, so a followed thread also notifies in a
// muted chat; the thread tweak tells the push gateway to let it through.
const (
	// RelayRulePrefix starts the ID of every push rule Relay manages.
	RelayRulePrefix         = "com.silvermarcs.relay."
	mentionRuleID           = RelayRulePrefix + "mention"
	threadStartedRuleID     = RelayRulePrefix + "thread_started"
	threadRoomMentionRuleID = RelayRulePrefix + "thread_room_mention"
	threadSilenceRuleID     = RelayRulePrefix + "slack_threads"
	threadFollowRulePrefix  = RelayRulePrefix + "thread."
	// "started" or "followed"; the gateway lets either through a muted chat.
	threadTweak = pushrules.PushActionTweak(RelayRulePrefix + "thread")
	// When a followed thread was last active, in Unix milliseconds. Kept in
	// the rule so every device prunes the same threads.
	threadActiveTweak = pushrules.PushActionTweak(RelayRulePrefix + "thread_active")
	slackGhostPattern = "@slackgo_*"
	relatesToTypeKey  = `content.m\.relates_to.rel_type`
	relatesToEventKey = `content.m\.relates_to.event_id`
	// A thread quiet for this long is no longer followed.
	threadFollowWindow = 14 * 24 * time.Hour
	// A followed thread's activity time is rewritten at most this often.
	threadRenewInterval = 24 * time.Hour
	threadPruneInterval = 6 * time.Hour
)

// threadFollows serializes this process's thread rule writes. The followed
// set itself is read from the synced push rules.
type threadFollows struct {
	mu sync.Mutex
	// Activity this process wrote since rules were last read, so a reply
	// arriving before sync echoes the write doesn't write it again.
	written   map[id.EventID]int64
	rules     *pushrules.PushRuleset
	lastPrune time.Time
}

type threadActivity struct {
	roomID id.RoomID
	rootID id.EventID
	at     int64
	mine   bool
}

// ConfigureThreadNotifications puts the fixed thread rules in place after the
// mention rule, follows threads you replied in recently, and prunes quiet ones.
func (s *Dispatcher) ConfigureThreadNotifications(ctx context.Context, rules *pushrules.PushRuleset) error {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil || rules == nil {
		return errors.New("a logged-in Matrix session is required")
	}
	s.threads.mu.Lock()
	defer s.threads.mu.Unlock()
	me := cli.Account.UserID
	// Each pass fixes the first rule out of place; a settled account needs none.
	for range 3 {
		fixed, err := s.fixThreadRuleOrder(ctx, rules, me)
		if err != nil || !fixed {
			if err != nil {
				return err
			}
			break
		}
		if rules, err = cli.Client.GetPushRules(ctx); err != nil {
			return err
		}
	}
	activity, err := s.recentThreadReplies(ctx, me)
	if err != nil {
		return err
	}
	return s.applyThreadActivity(ctx, rules, activity, true)
}

// observeThreadActivity follows threads you reply in and renews followed
// threads as they move, from any client's events in a sync.
func (s *Dispatcher) observeThreadActivity(syncComplete *jsoncmd.SyncComplete) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return
	}
	cutoff := time.Now().Add(-threadFollowWindow).UnixMilli()
	var activity []threadActivity
	for _, room := range syncComplete.Rooms {
		if room == nil {
			continue
		}
		for _, evt := range room.Events {
			if evt == nil || evt.RelationType != event.RelThread || evt.RelatesTo == "" || evt.Timestamp.UnixMilli() < cutoff {
				continue
			}
			activity = append(activity, threadActivity{
				roomID: evt.RoomID, rootID: evt.RelatesTo, at: evt.Timestamp.UnixMilli(), mine: evt.Sender == cli.Account.UserID,
			})
		}
	}
	s.threads.mu.Lock()
	prune := time.Since(s.threads.lastPrune) > threadPruneInterval
	s.threads.mu.Unlock()
	if len(activity) == 0 && !prune {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		s.threads.mu.Lock()
		defer s.threads.mu.Unlock()
		if rules := cli.PushRules.Load(); rules != nil {
			_ = s.applyThreadActivity(ctx, rules, activity, prune)
		}
	}()
}

// applyThreadActivity follows or renews threads for activity and, when prune
// is set, stops following quiet ones. The caller holds s.threads.mu.
func (s *Dispatcher) applyThreadActivity(ctx context.Context, rules *pushrules.PushRuleset, activity []threadActivity, prune bool) error {
	cli := s.rt.Client()
	if rules != s.threads.rules {
		s.threads.rules, s.threads.written = rules, make(map[id.EventID]int64)
	}
	followed, configured := followedThreads(rules)
	// The rules written before the silence rule exists would land after it.
	if !configured {
		return nil
	}
	for root, at := range s.threads.written {
		followed[root] = max(followed[root], at)
	}
	var errs []error
	for _, act := range activity {
		current, ok := followed[act.rootID]
		if !ok && (!act.mine || !s.isFollowable(ctx, act.roomID, act.rootID)) {
			continue
		}
		if ok && act.at < current+threadRenewInterval.Milliseconds() {
			continue
		}
		if err := putThreadFollow(ctx, cli.Client, act.rootID, act.at); err != nil {
			errs = append(errs, err)
			continue
		}
		followed[act.rootID], s.threads.written[act.rootID] = act.at, act.at
	}
	if prune {
		cutoff := time.Now().Add(-threadFollowWindow).UnixMilli()
		for root, at := range followed {
			if at >= cutoff {
				continue
			}
			err := cli.Client.DeletePushRule(ctx, "global", pushrules.OverrideRule, threadFollowRuleID(root))
			if err != nil && !errors.Is(err, mautrix.MNotFound) {
				errs = append(errs, err)
				continue
			}
			delete(s.threads.written, root)
		}
		if len(errs) == 0 {
			s.threads.lastPrune = time.Now()
		}
	}
	return errors.Join(errs...)
}

// recentThreadReplies lists Slack threads you replied in within the follow
// window, each with its latest reply, so a launch catches up on any sync whose
// events this process didn't see. Threads you started need no follow rule.
func (s *Dispatcher) recentThreadReplies(ctx context.Context, me id.UserID) ([]threadActivity, error) {
	cli := s.rt.Client()
	rows, err := cli.DB.Query(ctx, `
		SELECT mine.room_id, mine.relates_to, MAX(t.timestamp)
		FROM (SELECT DISTINCT room_id, relates_to FROM event
			WHERE relation_type='m.thread' AND sender=? AND timestamp>?) mine
		JOIN event t ON t.room_id=mine.room_id AND t.relates_to=mine.relates_to AND t.relation_type='m.thread'
		WHERE `+slackRoomSQL("mine.room_id")+`
			AND NOT EXISTS (SELECT 1 FROM event root WHERE root.event_id=mine.relates_to AND root.sender=?)
		GROUP BY mine.room_id, mine.relates_to`,
		me, time.Now().Add(-threadFollowWindow).UnixMilli(), me)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var activity []threadActivity
	for rows.Next() {
		var act threadActivity
		if err = rows.Scan(&act.roomID, &act.rootID, &act.at); err != nil {
			return nil, err
		}
		act.mine = true
		activity = append(activity, act)
	}
	return activity, rows.Err()
}

// slackRoomSQL matches a room with a Slack ghost among its members.
func slackRoomSQL(roomColumn string) string {
	return `EXISTS (SELECT 1 FROM current_state cs WHERE cs.room_id=` + roomColumn +
		` AND cs.event_type='m.room.member' AND cs.state_key >= '@slackgo_' AND cs.state_key < '@slackgo` + "`" + `')`
}

// isFollowable reports whether a thread you replied in needs a follow rule:
// it is in a Slack chat and, as far as this device knows, you didn't start it.
func (s *Dispatcher) isFollowable(ctx context.Context, roomID id.RoomID, root id.EventID) bool {
	cli := s.rt.Client()
	var found int
	err := cli.DB.QueryRow(ctx, `SELECT 1 WHERE `+slackRoomSQL("?")+`
		AND NOT EXISTS (SELECT 1 FROM event WHERE event_id=? AND sender=?)`, roomID, root, cli.Account.UserID).Scan(&found)
	return err == nil
}

// fixThreadRuleOrder corrects the first fixed thread rule that is missing,
// changed, or out of order, and reports whether it wrote anything.
func (s *Dispatcher) fixThreadRuleOrder(ctx context.Context, rules *pushrules.PushRuleset, me id.UserID) (bool, error) {
	cli := s.rt.Client().Client
	var order []string
	byID := make(map[string]*pushrules.PushRule)
	for _, rule := range rules.Override {
		if rule != nil && !strings.HasPrefix(rule.RuleID, ".") {
			order = append(order, rule.RuleID)
			byID[rule.RuleID] = rule
		}
	}
	position := func(ruleID string) int { return slices.Index(order, ruleID) }
	previous := mentionRuleID
	if position(previous) < 0 {
		return false, errors.New("the mention rule is missing")
	}
	// Each leading rule follows the one before it, starting at the mention rule.
	for _, fixed := range []struct {
		id   string
		rule threadRule
	}{
		{threadStartedRuleID, threadRule{conditions: startedConditions(me), actions: threadActions("started")}},
		{threadRoomMentionRuleID, threadRule{conditions: roomMentionConditions(), actions: notifyActions()}},
	} {
		at, after := position(fixed.id), position(previous)
		if at < 0 || at < after || !fixed.rule.matches(byID[fixed.id]) {
			return true, fixed.rule.put(ctx, cli, fixed.id, "after", previous, at >= 0 && at < after)
		}
		previous = fixed.id
	}
	// The silence rule comes after the leading rules and every followed thread.
	last := position(previous)
	for index, ruleID := range order {
		if strings.HasPrefix(ruleID, threadFollowRulePrefix) && index > last {
			last = index
		}
	}
	silence := position(threadSilenceRuleID)
	silenceRule := threadRule{conditions: silenceConditions(), actions: pushrules.PushActionArray{}}
	if silence < 0 || silence < last || !silenceRule.matches(byID[threadSilenceRuleID]) {
		return true, silenceRule.put(ctx, cli, threadSilenceRuleID, "after", order[last], silence >= 0 && silence < last)
	}
	return false, nil
}

type threadRule struct {
	conditions []*pushrules.PushCondition
	actions    pushrules.PushActionArray
}

func (r threadRule) matches(rule *pushrules.PushRule) bool {
	if rule == nil || !rule.Enabled {
		return false
	}
	have, err1 := json.Marshal([]any{rule.Conditions, rule.Actions})
	want, err2 := json.Marshal([]any{r.conditions, r.actions})
	return err1 == nil && err2 == nil && string(have) == string(want)
}

// put writes the rule at the given position. A rule that exists elsewhere is
// deleted first, since moving one by rewriting it isn't specified.
func (r threadRule) put(ctx context.Context, cli *mautrix.Client, ruleID, anchor, anchorID string, move bool) error {
	if move {
		if err := cli.DeletePushRule(ctx, "global", pushrules.OverrideRule, ruleID); err != nil && !errors.Is(err, mautrix.MNotFound) {
			return err
		}
	}
	ruleURL := cli.BuildURLWithQuery(mautrix.ClientURLPath{"v3", "pushrules", "global", "override", ruleID}, map[string]string{anchor: anchorID})
	if _, err := cli.MakeRequest(ctx, http.MethodPut, ruleURL, map[string]any{"conditions": r.conditions, "actions": r.actions}, nil); err != nil {
		return err
	}
	// Rewriting a disabled rule need not enable it.
	_, err := cli.MakeRequest(ctx, http.MethodPut,
		cli.BuildClientURL("v3", "pushrules", "global", "override", ruleID, "enabled"), map[string]bool{"enabled": true}, nil)
	return err
}

// A Slack ghost's reply in a thread whose first message you sent.
func startedConditions(me id.UserID) []*pushrules.PushCondition {
	return []*pushrules.PushCondition{
		{Kind: pushrules.KindEventMatch, Key: "sender", Pattern: slackGhostPattern},
		{Kind: pushrules.KindUnstableRelatedEventMatch, RelType: event.RelThread, Key: "sender", Pattern: string(me)},
	}
}

// A Slack ghost's @channel or @here in a thread, which notifies like one in
// the channel itself: room-wide mentions don't pass muted chats, so this
// sets no thread tweak. Slack ghosts lack Matrix's @room power level, so the
// default room-mention rule wouldn't match them.
func roomMentionConditions() []*pushrules.PushCondition {
	return []*pushrules.PushCondition{
		{Kind: pushrules.KindEventMatch, Key: "sender", Pattern: slackGhostPattern},
		{Kind: pushrules.KindEventMatch, Key: relatesToTypeKey, Pattern: string(event.RelThread)},
		{Kind: pushrules.KindEventPropertyIs, Key: `content.m\.mentions.room`, Value: true},
	}
}

// Any Slack ghost's thread reply that no earlier rule let through. The thread
// relation is unencrypted, so this matches encrypted replies too.
func silenceConditions() []*pushrules.PushCondition {
	return []*pushrules.PushCondition{
		{Kind: pushrules.KindEventMatch, Key: "sender", Pattern: slackGhostPattern},
		{Kind: pushrules.KindEventMatch, Key: relatesToTypeKey, Pattern: string(event.RelThread)},
	}
}

func notifyActions() pushrules.PushActionArray {
	return pushrules.PushActionArray{
		{Action: pushrules.ActionNotify},
		{Action: pushrules.ActionSetTweak, Tweak: pushrules.TweakSound, Value: "default"},
	}
}

func threadActions(kind string) pushrules.PushActionArray {
	return append(notifyActions(), &pushrules.PushAction{Action: pushrules.ActionSetTweak, Tweak: threadTweak, Value: kind})
}

// putThreadFollow follows one thread, or renews it, just ahead of the
// silence rule. Edits and reactions on the root have other relation types.
func putThreadFollow(ctx context.Context, cli *mautrix.Client, root id.EventID, activeAt int64) error {
	actions := append(threadActions("followed"),
		&pushrules.PushAction{Action: pushrules.ActionSetTweak, Tweak: threadActiveTweak, Value: activeAt})
	ruleURL := cli.BuildURLWithQuery(mautrix.ClientURLPath{"v3", "pushrules", "global", "override", threadFollowRuleID(root)},
		map[string]string{"before": threadSilenceRuleID})
	_, err := cli.MakeRequest(ctx, http.MethodPut, ruleURL, map[string]any{
		"conditions": []*pushrules.PushCondition{
			{Kind: pushrules.KindEventMatch, Key: relatesToTypeKey, Pattern: string(event.RelThread)},
			{Kind: pushrules.KindEventMatch, Key: relatesToEventKey, Pattern: string(root)},
		},
		"actions": actions,
	}, nil)
	return err
}

// Event IDs can hold characters a rule ID shouldn't; the root itself is in
// the rule's condition.
func threadFollowRuleID(root id.EventID) string {
	sum := sha256.Sum256([]byte(root))
	return threadFollowRulePrefix + hex.EncodeToString(sum[:12])
}

// followedThreads reads each followed thread's root and last activity, and
// whether the silence rule that follow rules precede exists.
func followedThreads(rules *pushrules.PushRuleset) (map[id.EventID]int64, bool) {
	followed := make(map[id.EventID]int64)
	configured := false
	for _, rule := range rules.Override {
		if rule == nil {
			continue
		}
		if rule.RuleID == threadSilenceRuleID {
			configured = true
		}
		if !strings.HasPrefix(rule.RuleID, threadFollowRulePrefix) {
			continue
		}
		var root id.EventID
		for _, cond := range rule.Conditions {
			if cond != nil && cond.Key == relatesToEventKey {
				root = id.EventID(cond.Pattern)
			}
		}
		var at int64
		for _, action := range rule.Actions {
			if action != nil && action.Tweak == threadActiveTweak {
				if value, ok := action.Value.(float64); ok {
					at = int64(value)
				}
			}
		}
		if root != "" {
			followed[root] = at
		}
	}
	return followed, configured
}
