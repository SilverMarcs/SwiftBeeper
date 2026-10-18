package dispatch

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"relay/core/internal/config"
	errs "relay/core/internal/errors"
	"relay/core/internal/gomuksruntime"
)

// Dispatcher routes the Swift message models to the Matrix client.
type Dispatcher struct {
	cfg config.Config
	rt  *gomuksruntime.Runtime
	ws  *wsHub
}

func New(cfg config.Config, rt *gomuksruntime.Runtime) *Dispatcher {
	s := &Dispatcher{cfg: cfg, rt: rt}
	s.ws = newWSHub(s)
	return s
}

func (s *Dispatcher) Handler() http.Handler {
	mux := http.NewServeMux()
	for pattern, handler := range map[string]apiHandler{
		"GET /manage/state":                s.manageState,
		"POST /manage/beeper/start-login":  s.manageBeeperStartLogin,
		"POST /manage/beeper/request-code": s.manageBeeperRequestCode,
		"POST /manage/beeper/submit-code":  s.manageBeeperSubmitCode,
		"POST /manage/login-custom":        s.manageLoginCustom,
		"POST /manage/verify":              s.manageVerify,
	} {
		mux.Handle(pattern, s.localHandler(handler, true))
	}
	for pattern, handler := range map[string]apiHandler{
		"GET /v1/accounts":                                         s.getAccounts,
		"GET /v1/session":                                          s.getSession,
		"GET /v1/chats":                                            s.listChats,
		"GET /v1/chats/search":                                     s.searchChats,
		"GET /v1/chats/{chatID}":                                   s.getChat,
		"POST /v1/chats/{chatID}/archive":                          s.archiveChat,
		"POST /v1/chats/{chatID}/mute":                             s.muteChat,
		"POST /v1/chats/{chatID}/read":                             s.markChatRead,
		"GET /v1/chats/{chatID}/messages":                          s.listMessages,
		"POST /v1/chats/{chatID}/messages":                         s.sendMessage,
		"PUT /v1/chats/{chatID}/messages/{messageID}":              s.editMessage,
		"POST /v1/chats/{chatID}/messages/{messageID}/reactions":   s.addReaction,
		"DELETE /v1/chats/{chatID}/messages/{messageID}/reactions": s.removeReaction,
		"DELETE /v1/chats/{chatID}/messages/{messageID}":           s.deleteMessage,
		"GET /v1/assets/serve":                                     s.serveAsset,
	} {
		mux.Handle(pattern, s.localHandler(handler, false))
	}
	return mux
}

func (s *Dispatcher) localHandler(handler apiHandler, manage bool) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		expected := s.cfg.AccessToken
		provided := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if manage {
			expected = s.cfg.ManageSecret
			provided = r.Header.Get("X-RelayCore-Manage-Secret")
		}
		if expected == "" || subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) != 1 {
			errs.Write(w, errs.Unauthorized("Invalid local dispatcher credential"))
			return
		}
		if !manage {
			if err := s.requireLoggedInSession(); err != nil {
				errs.Write(w, err)
				return
			}
		}
		if err := handler(w, r); err != nil {
			errs.Write(w, err)
		}
	})
}
