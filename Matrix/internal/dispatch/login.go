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

type clientStateOutput struct {
	ClientState    *jsoncmd.ClientState `json:"client_state"`
	HomeserverHost string               `json:"homeserver_host,omitempty"`
}

// clientState reports the login and verification state, which every login
// step returns so the app can tell what comes next.
func (s *Dispatcher) clientState() (clientStateOutput, error) {
	cli := s.rt.Client()
	if cli == nil || cli.Client == nil {
		return clientStateOutput{}, errors.New("gomuks runtime is not initialized")
	}
	state := clientStateOutput{ClientState: cli.State()}
	if cli.Client.HomeserverURL != nil {
		state.HomeserverHost = strings.ToLower(strings.TrimSpace(cli.Client.HomeserverURL.Hostname()))
	}
	return state, nil
}

func (s *Dispatcher) loginCustom(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		HomeserverURL string           `json:"homeserverURL"`
		Request       mautrix.ReqLogin `json:"request"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	homeserverURL, err := required(req.HomeserverURL, "homeserverURL")
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(string(req.Request.Type)) == "" {
		return nil, errors.New("request.type is required")
	}
	homeserver, err := url.Parse(homeserverURL)
	if err != nil || homeserver.Scheme != "https" || homeserver.Host == "" {
		return nil, errors.New("homeserverURL: valid HTTPS URL is required")
	}
	cli := s.rt.Client()
	cli.Client.HomeserverURL = homeserver
	if err = cli.Login(ctx, &req.Request); err != nil && !strings.Contains(strings.ToLower(err.Error()), "already logged in") {
		return nil, err
	}
	return s.clientState()
}

func (s *Dispatcher) verify(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		RecoveryKey string `json:"recoveryKey"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	recoveryKey, err := required(req.RecoveryKey, "recoveryKey")
	if err != nil {
		return nil, err
	}
	if err = s.rt.Client().Verify(ctx, recoveryKey); err != nil {
		return nil, err
	}
	return s.clientState()
}

func (s *Dispatcher) beeperStartLogin(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Domain string `json:"domain"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	return beeperAPIPost(ctx, req.Domain, "/user/login", map[string]any{}, "beeper login start failed")
}

func (s *Dispatcher) beeperRequestCode(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Domain  string `json:"domain"`
		Request string `json:"request"`
		Email   string `json:"email"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	request, err := required(req.Request, "request")
	if err != nil {
		return nil, err
	}
	email, err := required(req.Email, "email")
	if err != nil {
		return nil, err
	}
	return beeperAPIPost(ctx, req.Domain, "/user/login/email", map[string]any{
		"request": request, "email": email, "appType": "gomuks", "onlyExistingAccounts": true,
	}, "beeper email code request failed")
}

func (s *Dispatcher) beeperSubmitCode(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Domain   string `json:"domain"`
		Request  string `json:"request"`
		Response string `json:"response"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	request, err := required(req.Request, "request")
	if err != nil {
		return nil, err
	}
	response, err := required(req.Response, "response")
	if err != nil {
		return nil, err
	}
	return beeperAPIPost(ctx, req.Domain, "/user/login/response", map[string]any{
		"request": request, "response": strings.ReplaceAll(response, " ", ""), "appType": "gomuks", "onlyExistingAccounts": true,
	}, "beeper code submission failed")
}

// beeperAPIPost calls Beeper's login API and returns its JSON object, or an
// empty one for an empty body. A non-JSON body is returned under "raw".
// Statuses of 300 and above fail with failure as the message prefix.
func beeperAPIPost(ctx context.Context, rawDomain, endpoint string, payload any, failure string) (map[string]any, error) {
	domain, err := normalizeBeeperDomain(rawDomain)
	if err != nil {
		return nil, fmt.Errorf("invalid domain: %w", err)
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to encode request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api."+domain+endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Authorization", beeperPrivateAPIAuthHeader)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("beeper API request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	var data map[string]any
	if len(respBody) > 0 && json.Unmarshal(respBody, &data) != nil {
		data = map[string]any{"raw": string(respBody)}
	}
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%s (%d): %v", failure, resp.StatusCode, data)
	}
	if data == nil {
		data = map[string]any{}
	}
	return data, nil
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
		return "", errors.New("must be one of: beeper.com, beeper-staging.com, beeper-dev.com")
	}
}
