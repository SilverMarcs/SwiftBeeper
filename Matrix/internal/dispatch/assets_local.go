package dispatch

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"maunium.net/go/mautrix/event"
)

func (s *Dispatcher) MobileAsset(ctx context.Context, source string) (string, error) {
	return s.resolveServePath(ctx, source)
}

// The encrypted-file registry is process-local. Reconstruct just the requested
// descriptor from the durable SDK store after an offline cold launch.
func (s *Dispatcher) mobileRestoreFileDescriptor(ctx context.Context, mxc string) {
	if lookupEncryptedFile(mxc) != nil {
		return
	}
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return
	}
	var raw []byte
	err := cli.DB.QueryRow(ctx, `SELECT COALESCE(decrypted,content) FROM event WHERE json_extract(COALESCE(decrypted,content),'$.file.url')=? OR json_extract(COALESCE(decrypted,content),'$.info.thumbnail_file.url')=? LIMIT 1`, mxc, mxc).Scan(&raw)
	if err != nil {
		return
	}
	var content event.MessageEventContent
	if json.Unmarshal(raw, &content) != nil {
		return
	}
	if content.File != nil && string(content.File.URL) == mxc {
		registerEncryptedFile(mxc, content.File)
	}
	if content.Info != nil && content.Info.ThumbnailFile != nil && string(content.Info.ThumbnailFile.URL) == mxc {
		registerEncryptedFile(mxc, content.Info.ThumbnailFile)
	}
}

// Stage a Swift-owned temporary file without JSON/base64 copies of its bytes.
func (s *Dispatcher) MobileStageUpload(ctx context.Context, source, name, mime, root string) (any, error) {
	incoming := filepath.Join(root, "incoming")
	relative, err := filepath.Rel(incoming, source)
	if err != nil || filepath.IsAbs(relative) || relative == ".." || strings.HasPrefix(relative, ".."+string(os.PathSeparator)) {
		return nil, fmt.Errorf("invalid staging path")
	}
	name = filepath.Base(name)
	if name == "." || name == "" {
		name = "file"
	}
	file, err := os.Open(source)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || info.Size() > maxUploadSizeBytes || !info.Mode().IsRegular() {
		return nil, fmt.Errorf("invalid upload")
	}
	uploadID := randomID()
	directory := filepath.Join(s.uploadRootDir(), uploadID)
	if err = os.MkdirAll(directory, 0700); err != nil {
		return nil, err
	}
	target := filepath.Join(directory, name)
	output, err := os.OpenFile(target, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return nil, err
	}
	_, copyErr := io.Copy(output, file)
	closeErr := output.Close()
	if copyErr != nil {
		return nil, copyErr
	}
	if closeErr != nil {
		return nil, closeErr
	}
	if mime == "" {
		mime = "application/octet-stream"
	}
	meta := uploadMetadata{UploadID: uploadID, FilePath: target, FileName: name, MimeType: mime, FileSize: info.Size()}
	meta.Width, meta.Height = imageDimensions(target)
	if err = s.writeUploadMetadata(meta); err != nil {
		return nil, err
	}
	return uploadAssetResponse{UploadID: uploadID, SrcURL: fileURLFromPath(target), FileName: name, MimeType: mime, FileSize: float64(info.Size()), Width: float64(meta.Width), Height: float64(meta.Height)}, nil
}
