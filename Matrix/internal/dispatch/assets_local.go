package dispatch

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func (s *Dispatcher) MobileAsset(ctx context.Context, source string) (string, error) {
	return s.resolveAssetURL(ctx, source)
}

// Stage a Swift-owned temporary file without JSON/base64 copies of its bytes.
// Both directories share the state directory, so a rename moves it for free.
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
	info, err := os.Lstat(source)
	if err != nil || info.Size() > maxUploadSizeBytes || !info.Mode().IsRegular() {
		return nil, fmt.Errorf("invalid upload")
	}
	uploadID := randomID()
	directory := filepath.Join(s.uploadRootDir(), uploadID)
	if err = os.MkdirAll(directory, 0700); err != nil {
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
	if err = s.writeUploadMetadata(meta); err != nil {
		return nil, err
	}
	return uploadAssetResponse{UploadID: uploadID, Width: float64(meta.Width), Height: float64(meta.Height)}, nil
}
