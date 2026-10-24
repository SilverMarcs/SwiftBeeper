package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/gif" // Register decoders for imageDimensions.
	_ "image/jpeg"
	_ "image/png"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto/attachment"
	"maunium.net/go/mautrix/event"

	"relay/core/internal/wire"
)

// Sending an attachment takes two commands: stage-upload moves the file into
// the core and returns an uploadID, then send-message uploads it to Matrix.

const maxUploadSizeBytes = int64(500 * 1024 * 1024)

var safeUploadIDPattern = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)

// uploadAssetResponse carries only what the app reads back.
type uploadAssetResponse struct {
	UploadID string  `json:"uploadID"`
	Width    float64 `json:"width,omitempty"`
	Height   float64 `json:"height,omitempty"`
}

// uploadMetadata is stored as metadata.json beside each staged file.
type uploadMetadata struct {
	UploadID string `json:"uploadID"`
	FilePath string `json:"filePath"`
	FileName string `json:"fileName"`
	MimeType string `json:"mimeType"`
	FileSize int64  `json:"fileSize"`
	Width    int    `json:"width,omitempty"`
	Height   int    `json:"height,omitempty"`
}

// StageUpload takes a Swift-owned temporary file from root/incoming without
// JSON/base64 copies of its bytes. Both directories share the state
// directory, so a rename moves it for free.
func (s *Dispatcher) StageUpload(source, name, mime, root string) (any, error) {
	incoming := filepath.Join(root, "incoming")
	relative, err := filepath.Rel(incoming, source)
	if err != nil || filepath.IsAbs(relative) || relative == ".." || strings.HasPrefix(relative, ".."+string(os.PathSeparator)) {
		return nil, errors.New("invalid staging path")
	}
	name = filepath.Base(name)
	if name == "." || name == "" {
		name = "file"
	}
	info, err := os.Lstat(source)
	if err != nil || info.Size() > maxUploadSizeBytes || !info.Mode().IsRegular() {
		return nil, errors.New("invalid upload")
	}
	uploadID := randomID()
	directory := filepath.Join(s.uploadRootDir(), uploadID)
	if err = os.MkdirAll(directory, 0o700); err != nil {
		return nil, err
	}
	target := filepath.Join(directory, name)
	if err = os.Rename(source, target); err != nil {
		return nil, err
	}
	if mime == "" {
		mime = "application/octet-stream"
	}
	meta := uploadMetadata{UploadID: uploadID, FilePath: target, FileName: name, MimeType: mime, FileSize: info.Size()}
	meta.Width, meta.Height = imageDimensions(target)
	if err = writeUploadMetadata(meta); err != nil {
		return nil, err
	}
	return uploadAssetResponse{UploadID: uploadID, Width: float64(meta.Width), Height: float64(meta.Height)}, nil
}

func (s *Dispatcher) uploadRootDir() string {
	return filepath.Join(s.rt.DataDir(), "api-uploads")
}

func writeUploadMetadata(meta uploadMetadata) error {
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

func (s *Dispatcher) loadUploadMetadata(uploadID string) (uploadMetadata, error) {
	if !safeUploadIDPattern.MatchString(uploadID) {
		return uploadMetadata{}, errors.New("invalid uploadID")
	}
	data, err := os.ReadFile(filepath.Join(s.uploadRootDir(), uploadID, "metadata.json"))
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

// uploadAttachment uploads a staged file to the homeserver, encrypting it for
// encrypted rooms, and returns the media message content to send.
func (s *Dispatcher) uploadAttachment(ctx context.Context, input wire.MessageAttachmentInput, encrypt bool) (*event.MessageEventContent, error) {
	meta, err := s.loadUploadMetadata(input.UploadID)
	if err != nil {
		return nil, err
	}
	fileName := strings.TrimSpace(input.FileName)
	if fileName == "" {
		fileName = meta.FileName
	}
	mimeType := strings.TrimSpace(input.MimeType)
	if mimeType == "" {
		mimeType = meta.MimeType
	}
	file, err := os.Open(meta.FilePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open uploaded asset: %w", err)
	}
	defer file.Close()
	stat, err := file.Stat()
	if err != nil {
		return nil, fmt.Errorf("failed to stat uploaded asset: %w", err)
	}

	var uploadReader io.Reader = file
	var encryptedReader io.ReadSeekCloser
	var encryptedFile *event.EncryptedFileInfo
	uploadMime, uploadName := mimeType, fileName
	if encrypt {
		encryptedFile = &event.EncryptedFileInfo{EncryptedFile: *attachment.NewEncryptedFile()}
		encryptedReader = encryptedFile.EncryptStream(file)
		uploadReader = encryptedReader
		uploadMime, uploadName = "application/octet-stream", "encrypted"
	}
	uploadResp, err := s.rt.Client().Client.UploadMedia(ctx, mautrix.ReqUploadMedia{
		Content: uploadReader, ContentLength: stat.Size(), ContentType: uploadMime, FileName: uploadName,
	})
	if encryptedReader != nil {
		// Closing records the ciphertext hash in encryptedFile.
		_ = encryptedReader.Close()
	}
	if err != nil {
		return nil, fmt.Errorf("failed to upload media to Matrix: %w", err)
	}

	content := &event.MessageEventContent{
		MsgType:  messageTypeForMime(mimeType),
		Body:     fileName,
		URL:      uploadResp.ContentURI.CUString(),
		FileName: fileName,
		Info: &event.FileInfo{
			MimeType: mimeType,
			Size:     int(stat.Size()),
		},
	}
	if encryptedFile != nil {
		encryptedFile.URL = content.URL
		content.URL = ""
		content.File = encryptedFile
	}
	if input.Size.Width > 0 || input.Size.Height > 0 {
		content.Info.Width = int(input.Size.Width)
		content.Info.Height = int(input.Size.Height)
	}
	return content, nil
}

func messageTypeForMime(mimeType string) event.MessageType {
	switch {
	case strings.HasPrefix(mimeType, "image/"):
		return event.MsgImage
	case strings.HasPrefix(mimeType, "video/"):
		return event.MsgVideo
	case strings.HasPrefix(mimeType, "audio/"):
		return event.MsgAudio
	default:
		return event.MsgFile
	}
}
