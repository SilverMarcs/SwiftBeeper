package dispatch

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix"

	errs "relay/core/internal/errors"
)

const beeperPrivateAPIAuthHeader = "Bearer BEEPER-PRIVATE-API-PLEASE-DONT-USE"

type manageStateOutput struct {
	ClientState    *jsoncmd.ClientState `json:"client_state"`
	HomeserverHost string               `json:"homeserver_host,omitempty"`
}

func (s *Dispatcher) manageState(w http.ResponseWriter, r *http.Request) error {
	state, err := s.getManageState()
	if err != nil {
		return err
	}
	return writeJSON(w, state)
}

func (s *Dispatcher) getManageState() (manageStateOutput, error) {
	client := s.rt.Client()
	if client == nil || client.Client == nil {
		return manageStateOutput{}, fmt.Errorf("gomuks runtime is not initialized")
	}
	state := manageStateOutput{
		ClientState: client.State(),
	}
	if client.Client.HomeserverURL != nil {
		host := strings.ToLower(strings.TrimSpace(client.Client.HomeserverURL.Hostname()))
		state.HomeserverHost = host
	}
	return state, nil
}

func (s *Dispatcher) manageLoginCustom(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		HomeserverURL string           `json:"homeserverURL"`
		Request       mautrix.ReqLogin `json:"request"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	req.HomeserverURL = strings.TrimSpace(req.HomeserverURL)
	if req.HomeserverURL == "" {
		return errs.Validation(map[string]any{"homeserverURL": "homeserverURL is required"})
	}
	if strings.TrimSpace(string(req.Request.Type)) == "" {
		return errs.Validation(map[string]any{"request": "request.type is required"})
	}
	err := s.rt.SubmitJSONCommand(r.Context(), jsoncmd.ReqLoginCustom, &jsoncmd.LoginCustomParams{
		HomeserverURL: req.HomeserverURL,
		Request:       &req.Request,
	}, nil)
	if err != nil {
		if !strings.Contains(strings.ToLower(err.Error()), "already logged in") {
			return errs.Internal(err)
		}
	}
	state, err := s.getManageState()
	if err != nil {
		return err
	}
	return writeJSON(w, state)
}

func (s *Dispatcher) manageVerify(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		RecoveryKey string `json:"recoveryKey"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	req.RecoveryKey = strings.TrimSpace(req.RecoveryKey)
	if req.RecoveryKey == "" {
		return errs.Validation(map[string]any{"recoveryKey": "recoveryKey is required"})
	}
	err := s.rt.SubmitJSONCommand(r.Context(), jsoncmd.ReqVerify, &jsoncmd.VerifyParams{RecoveryKey: req.RecoveryKey}, nil)
	if err != nil {
		return errs.Internal(err)
	}
	state, err := s.getManageState()
	if err != nil {
		return err
	}
	return writeJSON(w, state)
}

func (s *Dispatcher) manageBeeperStartLogin(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Domain string `json:"domain"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	data, status, err := beeperAPIPost(r.Context(), req.Domain, "/user/login", map[string]any{})
	if err != nil {
		return err
	}
	if status >= 300 {
		return writeJSONStatus(w, status, dataOrFallback(data, map[string]any{"error": "beeper login start failed"}))
	}
	return writeJSON(w, dataOrFallback(data, map[string]any{}))
}

func (s *Dispatcher) manageBeeperRequestCode(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Domain  string `json:"domain"`
		Request string `json:"request"`
		Email   string `json:"email"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	req.Request = strings.TrimSpace(req.Request)
	req.Email = strings.TrimSpace(req.Email)
	if req.Request == "" {
		return errs.Validation(map[string]any{"request": "request is required"})
	}
	if req.Email == "" {
		return errs.Validation(map[string]any{"email": "email is required"})
	}
	data, status, err := beeperAPIPost(r.Context(), req.Domain, "/user/login/email", map[string]any{
		"request": req.Request,
		"email":   req.Email, "appType": "gomuks", "onlyExistingAccounts": true,
	})
	if err != nil {
		return err
	}
	if status >= 300 {
		return writeJSONStatus(w, status, dataOrFallback(data, map[string]any{"error": "beeper email code request failed"}))
	}
	return writeJSON(w, dataOrFallback(data, map[string]any{}))
}

func (s *Dispatcher) manageBeeperSubmitCode(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Domain   string `json:"domain"`
		Request  string `json:"request"`
		Response string `json:"response"`
	}
	if err := decodeJSON(r, &req); err != nil {
		return err
	}
	req.Request = strings.TrimSpace(req.Request)
	req.Response = strings.TrimSpace(req.Response)
	if req.Request == "" {
		return errs.Validation(map[string]any{"request": "request is required"})
	}
	if req.Response == "" {
		return errs.Validation(map[string]any{"response": "response is required"})
	}
	data, status, err := beeperAPIPost(r.Context(), req.Domain, "/user/login/response", map[string]any{
		"request":  req.Request,
		"response": strings.ReplaceAll(req.Response, " ", ""), "appType": "gomuks", "onlyExistingAccounts": true,
	})
	if err != nil {
		return err
	}
	if status >= 300 {
		return writeJSONStatus(w, status, dataOrFallback(data, map[string]any{"error": "beeper code submission failed"}))
	}
	return writeJSON(w, dataOrFallback(data, map[string]any{}))
}

func beeperAPIPost(ctx context.Context, rawDomain, endpoint string, payload any) (map[string]any, int, error) {
	domain, err := normalizeBeeperDomain(rawDomain)
	if err != nil {
		return nil, 0, errs.Validation(map[string]any{"domain": err.Error()})
	}
	if payload == nil {
		payload = map[string]any{}
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, 0, errs.Internal(fmt.Errorf("failed to encode request: %w", err))
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api."+domain+endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, 0, errs.Internal(fmt.Errorf("failed to create request: %w", err))
	}
	req.Header.Set("Authorization", beeperPrivateAPIAuthHeader)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, 0, errs.Internal(fmt.Errorf("beeper API request failed: %w", err))
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if len(respBody) == 0 {
		return nil, resp.StatusCode, nil
	}
	var decoded map[string]any
	if err = json.Unmarshal(respBody, &decoded); err != nil {
		return map[string]any{"raw": string(respBody)}, resp.StatusCode, nil
	}
	return decoded, resp.StatusCode, nil
}

func normalizeBeeperDomain(raw string) (string, error) {
	domain := strings.ToLower(strings.TrimSpace(raw))
	domain = strings.TrimPrefix(domain, "https://")
	domain = strings.TrimPrefix(domain, "http://")
	domain = strings.TrimPrefix(domain, "matrix.")
	domain = strings.TrimPrefix(domain, "api.")
	domain = strings.TrimSuffix(domain, "/")
	switch domain {
	case "beeper.com", "beeper-staging.com", "beeper-dev.com":
		return domain, nil
	default:
		return "", fmt.Errorf("must be one of: beeper.com, beeper-staging.com, beeper-dev.com")
	}
}

func dataOrFallback(data map[string]any, fallback map[string]any) map[string]any {
	if data != nil {
		return data
	}
	return fallback
}

func writeJSONStatus(w http.ResponseWriter, status int, value any) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	return json.NewEncoder(w).Encode(value)
}
