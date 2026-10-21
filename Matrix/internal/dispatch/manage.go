package dispatch

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix"
)

const beeperPrivateAPIAuthHeader = "Bearer BEEPER-PRIVATE-API-PLEASE-DONT-USE"

type manageStateOutput struct {
	ClientState    *jsoncmd.ClientState `json:"client_state"`
	HomeserverHost string               `json:"homeserver_host,omitempty"`
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

func (s *Dispatcher) manageLoginCustom(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		HomeserverURL string           `json:"homeserverURL"`
		Request       mautrix.ReqLogin `json:"request"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	req.HomeserverURL = strings.TrimSpace(req.HomeserverURL)
	if req.HomeserverURL == "" {
		return nil, errors.New("homeserverURL is required")
	}
	if strings.TrimSpace(string(req.Request.Type)) == "" {
		return nil, errors.New("request.type is required")
	}
	cli := s.rt.Client()
	homeserver, err := url.Parse(req.HomeserverURL)
	if err != nil || homeserver.Scheme != "https" || homeserver.Host == "" {
		return nil, errors.New("homeserverURL: valid HTTPS URL is required")
	}
	cli.Client.HomeserverURL = homeserver
	err = cli.Login(ctx, &req.Request)
	if err != nil {
		if !strings.Contains(strings.ToLower(err.Error()), "already logged in") {
			return nil, err
		}
	}
	state, err := s.getManageState()
	if err != nil {
		return nil, err
	}
	return state, nil
}

func (s *Dispatcher) manageVerify(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		RecoveryKey string `json:"recoveryKey"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	req.RecoveryKey = strings.TrimSpace(req.RecoveryKey)
	if req.RecoveryKey == "" {
		return nil, errors.New("recoveryKey is required")
	}
	err := s.rt.Client().Verify(ctx, req.RecoveryKey)
	if err != nil {
		return nil, err
	}
	state, err := s.getManageState()
	if err != nil {
		return nil, err
	}
	return state, nil
}

func (s *Dispatcher) manageBeeperStartLogin(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Domain string `json:"domain"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	data, status, err := beeperAPIPost(ctx, req.Domain, "/user/login", map[string]any{})
	if err != nil {
		return nil, err
	}
	if status >= 300 {
		return nil, fmt.Errorf("beeper login start failed (%d): %v", status, data)
	}
	return dataOrFallback(data, map[string]any{}), nil
}

func (s *Dispatcher) manageBeeperRequestCode(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Domain  string `json:"domain"`
		Request string `json:"request"`
		Email   string `json:"email"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	req.Request = strings.TrimSpace(req.Request)
	req.Email = strings.TrimSpace(req.Email)
	if req.Request == "" {
		return nil, errors.New("request is required")
	}
	if req.Email == "" {
		return nil, errors.New("email is required")
	}
	data, status, err := beeperAPIPost(ctx, req.Domain, "/user/login/email", map[string]any{
		"request": req.Request,
		"email":   req.Email, "appType": "gomuks", "onlyExistingAccounts": true,
	})
	if err != nil {
		return nil, err
	}
	if status >= 300 {
		return nil, fmt.Errorf("beeper email code request failed (%d): %v", status, data)
	}
	return dataOrFallback(data, map[string]any{}), nil
}

func (s *Dispatcher) manageBeeperSubmitCode(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Domain   string `json:"domain"`
		Request  string `json:"request"`
		Response string `json:"response"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	req.Request = strings.TrimSpace(req.Request)
	req.Response = strings.TrimSpace(req.Response)
	if req.Request == "" {
		return nil, errors.New("request is required")
	}
	if req.Response == "" {
		return nil, errors.New("response is required")
	}
	data, status, err := beeperAPIPost(ctx, req.Domain, "/user/login/response", map[string]any{
		"request":  req.Request,
		"response": strings.ReplaceAll(req.Response, " ", ""), "appType": "gomuks", "onlyExistingAccounts": true,
	})
	if err != nil {
		return nil, err
	}
	if status >= 300 {
		return nil, fmt.Errorf("beeper code submission failed (%d): %v", status, data)
	}
	return dataOrFallback(data, map[string]any{}), nil
}

func beeperAPIPost(ctx context.Context, rawDomain, endpoint string, payload any) (map[string]any, int, error) {
	domain, err := normalizeBeeperDomain(rawDomain)
	if err != nil {
		return nil, 0, fmt.Errorf("invalid domain: %w", err)
	}
	if payload == nil {
		payload = map[string]any{}
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to encode request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api."+domain+endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, 0, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Authorization", beeperPrivateAPIAuthHeader)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("beeper API request failed: %w", err)
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
