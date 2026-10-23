package dispatch

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"errors"

	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"

	"os"
	"path/filepath"
	"regexp"
	"strings"

	"maunium.net/go/mautrix/crypto/attachment"
	"maunium.net/go/mautrix/id"
)

const maxUploadSizeBytes = int64(500 * 1024 * 1024)

var safeUploadIDPattern = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)

// uploadAssetResponse carries only what the app reads back.
type uploadAssetResponse struct {
	UploadID string  `json:"uploadID"`
	Width    float64 `json:"width,omitempty"`
	Height   float64 `json:"height,omitempty"`
}

type uploadMetadata struct {
	UploadID string `json:"uploadID"`
	FilePath string `json:"filePath"`
	FileName string `json:"fileName"`
	MimeType string `json:"mimeType"`
	FileSize int64  `json:"fileSize"`
	Width    int    `json:"width,omitempty"`
	Height   int    `json:"height,omitempty"`
}

// resolveAssetURL returns a local file for Matrix media, downloading and
// decrypting it on the first request.
func (s *Dispatcher) resolveAssetURL(ctx context.Context, raw string) (string, error) {
	normalized := strings.TrimSpace(raw)
	if strings.HasPrefix(normalized, "localmxc://") {
		normalized = "mxc://" + strings.TrimPrefix(normalized, "localmxc://")
	}
	parsedMXC := id.ContentURIString(normalized).ParseOrIgnore()
	if !parsedMXC.IsValid() {
		return "", fmt.Errorf("URL must be mxc:// or localmxc://")
	}

	cacheDir := s.assetCacheDir()
	sum := sha256.Sum256([]byte(normalized))
	plainPath := filepath.Join(cacheDir, hex.EncodeToString(sum[:]))
	decryptedPath := plainPath + ".decrypted"
	// A decrypted copy is always right. A plain copy is right only when the
	// media isn't encrypted, which the SDK's media table records.
	if _, err := os.Stat(decryptedPath); err == nil {
		return decryptedPath, nil
	}
	var encFile *attachment.EncryptedFile
	if media, err := s.rt.Client().DB.Media.Get(ctx, parsedMXC); err == nil && media != nil {
		encFile = media.EncFile
	}
	cachePath := plainPath
	if encFile != nil {
		cachePath = decryptedPath
	} else if _, err := os.Stat(plainPath); err == nil {
		return plainPath, nil
	}
	if err := os.MkdirAll(cacheDir, 0o700); err != nil {
		return "", fmt.Errorf("failed to create asset cache dir: %w", err)
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

	if encFile != nil {
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
		return uploadMetadata{}, errors.New("invalid uploadID")
	}
	metaPath := filepath.Join(s.uploadRootDir(), uploadID, "metadata.json")
	data, err := os.ReadFile(metaPath)
	if err != nil {
		return uploadMetadata{}, errors.New("Upload not found")
	}
	var meta uploadMetadata
	if err = json.Unmarshal(data, &meta); err != nil {
		return uploadMetadata{}, fmt.Errorf("failed to parse upload metadata: %w", err)
	}
	if meta.FilePath == "" {
		return uploadMetadata{}, errors.New("Upload has expired")
	}
	if _, err = os.Stat(meta.FilePath); err != nil {
		return uploadMetadata{}, errors.New("Upload has expired")
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

func (s *Dispatcher) uploadRootDir() string {
	return filepath.Join(s.rt.StateDir(), "api-uploads")
}

func (s *Dispatcher) assetCacheDir() string {
	return filepath.Join(s.rt.StateDir(), "assets")
}

func randomID() string {
	buf := make([]byte, 16)
	_, _ = rand.Read(buf)
	return hex.EncodeToString(buf)
}
