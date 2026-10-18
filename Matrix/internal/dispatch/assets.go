package dispatch

import (
	"context"
	"crypto/rand"
	"crypto/sha256"

	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"

	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	errs "relay/core/internal/errors"
)

// encryptedFileRegistry caches EncryptedFile info for mxc URLs so
// the serve endpoint can decrypt media fetched from the homeserver.
var (
	encryptedFileMu       sync.RWMutex
	encryptedFileRegistry = make(map[string]*event.EncryptedFileInfo)
)

func registerEncryptedFile(mxcURL string, file *event.EncryptedFileInfo) {
	if file == nil || mxcURL == "" {
		return
	}
	encryptedFileMu.Lock()
	encryptedFileRegistry[mxcURL] = file
	encryptedFileMu.Unlock()
}

func lookupEncryptedFile(mxcURL string) *event.EncryptedFileInfo {
	encryptedFileMu.RLock()
	defer encryptedFileMu.RUnlock()
	return encryptedFileRegistry[mxcURL]
}

const maxUploadSizeBytes = int64(500 * 1024 * 1024)

var safeUploadIDPattern = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)

// uploadAssetResponse is a custom type that omits zero-value fields
// (the library type includes "error":"" which Swift treats as non-nil error).
type uploadAssetResponse struct {
	UploadID string  `json:"uploadID"`
	SrcURL   string  `json:"srcURL,omitempty"`
	FileName string  `json:"fileName,omitempty"`
	MimeType string  `json:"mimeType,omitempty"`
	FileSize float64 `json:"fileSize,omitempty"`
	Width    float64 `json:"width,omitempty"`
	Height   float64 `json:"height,omitempty"`
	Duration float64 `json:"duration,omitempty"`
	Error    string  `json:"error,omitempty"`
}

type uploadMetadata struct {
	UploadID string  `json:"uploadID"`
	FilePath string  `json:"filePath"`
	FileName string  `json:"fileName"`
	MimeType string  `json:"mimeType"`
	FileSize int64   `json:"fileSize"`
	Width    int     `json:"width,omitempty"`
	Height   int     `json:"height,omitempty"`
	Duration float64 `json:"duration,omitempty"`
}

func (s *Dispatcher) serveAsset(w http.ResponseWriter, r *http.Request) error {
	assetURL := strings.TrimSpace(r.URL.Query().Get("url"))
	if assetURL == "" {
		return errs.Validation(map[string]any{"url": "url is required"})
	}
	filePath, err := s.resolveServePath(r.Context(), assetURL)
	if err != nil {
		return err
	}
	if _, statErr := os.Stat(filePath); statErr != nil {
		return errs.NotFound("Asset not found")
	}
	http.ServeFile(w, r, filePath)
	return nil
}

func (s *Dispatcher) resolveServePath(ctx context.Context, raw string) (string, error) {
	if strings.HasPrefix(raw, "file://") {
		parsed, err := url.Parse(raw)
		if err != nil {
			return "", errs.Validation(map[string]any{"url": "invalid file url"})
		}
		path := filepath.Clean(parsed.Path)
		if !s.isAllowedServePath(path) {
			return "", errs.Forbidden("Access denied: path is outside allowed directories")
		}
		return path, nil
	}
	path, err := s.resolveAssetURL(ctx, raw)
	if err != nil {
		return "", errs.NotFound(err.Error())
	}
	return path, nil
}

func (s *Dispatcher) resolveAssetURL(ctx context.Context, raw string) (string, error) {
	normalized := strings.TrimSpace(raw)
	if strings.HasPrefix(normalized, "localmxc://") {
		normalized = "mxc://" + strings.TrimPrefix(normalized, "localmxc://")
	}
	s.mobileRestoreFileDescriptor(ctx, normalized)
	parsedMXC := id.ContentURIString(normalized).ParseOrIgnore()
	if !parsedMXC.IsValid() {
		return "", fmt.Errorf("URL must be mxc:// or localmxc://")
	}

	cacheDir := s.assetCacheDir()
	if err := os.MkdirAll(cacheDir, 0o700); err != nil {
		return "", fmt.Errorf("failed to create asset cache dir: %w", err)
	}
	sum := sha256.Sum256([]byte(normalized))
	cachePath := filepath.Join(cacheDir, hex.EncodeToString(sum[:]))
	if lookupEncryptedFile(normalized) != nil {
		cachePath += ".decrypted"
	}
	if _, err := os.Stat(cachePath); err == nil {
		return cachePath, nil
	}

	resp, err := s.rt.Client().Client.Download(ctx, parsedMXC)
	if err != nil {
		return "", fmt.Errorf("failed to download asset: %w", err)
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read downloaded asset: %w", err)
	}

	// Decrypt if we have encryption info for this mxc URL.
	if encFile := lookupEncryptedFile(normalized); encFile != nil {
		if decryptErr := encFile.DecryptInPlace(data); decryptErr != nil {
			return "", fmt.Errorf("failed to decrypt asset: %w", decryptErr)
		}
	}

	tempPath := cachePath + ".tmp"
	if err = os.WriteFile(tempPath, data, 0o600); err != nil {
		return "", fmt.Errorf("failed to save downloaded asset: %w", err)
	}
	if err = os.Rename(tempPath, cachePath); err != nil {
		_ = os.Remove(tempPath)
		return "", fmt.Errorf("failed to finalize cached asset: %w", err)
	}
	return cachePath, nil
}

func (s *Dispatcher) writeUploadMetadata(meta uploadMetadata) error {
	metaPath := filepath.Join(filepath.Dir(meta.FilePath), "metadata.json")
	data, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to encode upload metadata: %w", err)
	}
	if err = os.WriteFile(metaPath, data, 0o600); err != nil {
		return fmt.Errorf("failed to write upload metadata: %w", err)
	}
	return nil
}

func (s *Dispatcher) loadUploadMetadataByID(uploadID string) (uploadMetadata, error) {
	if !safeUploadIDPattern.MatchString(uploadID) {
		return uploadMetadata{}, errs.Validation(map[string]any{"uploadID": "invalid uploadID"})
	}
	metaPath := filepath.Join(s.uploadRootDir(), uploadID, "metadata.json")
	data, err := os.ReadFile(metaPath)
	if err != nil {
		return uploadMetadata{}, errs.NotFound("Upload not found")
	}
	var meta uploadMetadata
	if err = json.Unmarshal(data, &meta); err != nil {
		return uploadMetadata{}, errs.Internal(fmt.Errorf("failed to parse upload metadata: %w", err))
	}
	if meta.FilePath == "" {
		return uploadMetadata{}, errs.NotFound("Upload has expired")
	}
	if _, err = os.Stat(meta.FilePath); err != nil {
		return uploadMetadata{}, errs.NotFound("Upload has expired")
	}
	return meta, nil
}

func imageDimensions(filePath string) (int, int) {
	file, err := os.Open(filePath)
	if err != nil {
		return 0, 0
	}
	defer file.Close()
	cfg, _, err := image.DecodeConfig(file)
	if err != nil {
		return 0, 0
	}
	return cfg.Width, cfg.Height
}

func fileURLFromPath(path string) string {
	return (&url.URL{Scheme: "file", Path: path}).String()
}

func (s *Dispatcher) uploadRootDir() string {
	return filepath.Join(s.rt.StateDir(), "api-uploads")
}

func (s *Dispatcher) assetCacheDir() string {
	return filepath.Join(s.rt.StateDir(), "assets")
}

func (s *Dispatcher) isAllowedServePath(path string) bool {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return false
	}
	uploadRoot, err := filepath.Abs(s.uploadRootDir())
	if err != nil {
		return false
	}
	assetRoot, err := filepath.Abs(s.assetCacheDir())
	if err != nil {
		return false
	}
	return strings.HasPrefix(absPath, uploadRoot+string(os.PathSeparator)) ||
		strings.HasPrefix(absPath, assetRoot+string(os.PathSeparator))
}

func randomID() string {
	buf := make([]byte, 16)
	_, _ = rand.Read(buf)
	return hex.EncodeToString(buf)
}
