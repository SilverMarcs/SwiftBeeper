package floe

import (
	"bufio"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"io"
)

// Version marks a file encrypted with Beeper's FLOE scheme (MSC4571).
const Version = "com.beeper.floe.v1"

// File is a FLOE-encrypted file, as it appears in event content.
type File struct {
	URL     string `json:"url"`
	Version string `json:"v"`
	Key     string `json:"floe_key"`
	Header  string `json:"floe_header"`
	Hashes  struct {
		SHA256 string `json:"sha256"`
	} `json:"hashes"`
}

// FindFile returns the FLOE file for mxc anywhere in event content, which
// covers the main file, its thumbnail, edits and link previews alike.
func FindFile(content []byte, mxc string) *File {
	var tree any
	if json.Unmarshal(content, &tree) != nil {
		return nil
	}
	return findFile(tree, mxc)
}

func findFile(content any, mxc string) *File {
	switch value := content.(type) {
	case map[string]any:
		if value["url"] == mxc && value["v"] == Version {
			raw, _ := json.Marshal(value)
			var file File
			if json.Unmarshal(raw, &file) == nil && file.Key != "" && file.Header != "" {
				return &file
			}
		}
		for _, child := range value {
			if file := findFile(child, mxc); file != nil {
				return file
			}
		}
	case []any:
		for _, child := range value {
			if file := findFile(child, mxc); file != nil {
				return file
			}
		}
	}
	return nil
}

// Decrypt writes the plaintext of the ciphertext in r to w. It fails if any
// segment fails authentication or the ciphertext is truncated, so the caller
// must discard what was written on error.
func (f File) Decrypt(r io.Reader, w io.Writer) error {
	key, err := base64.RawStdEncoding.DecodeString(f.Key)
	if err != nil {
		return fmt.Errorf("invalid FLOE key: %w", err)
	}
	header, err := base64.RawStdEncoding.DecodeString(f.Header)
	if err != nil {
		return fmt.Errorf("invalid FLOE header: %w", err)
	}
	var wantHash []byte
	if f.Hashes.SHA256 != "" {
		if wantHash, err = base64.RawStdEncoding.DecodeString(f.Hashes.SHA256); err != nil {
			return fmt.Errorf("invalid FLOE hash: %w", err)
		}
	}
	decryptor, err := NewFloeDecryptor(GCM256_IV256_4K(), key, nil, header)
	if err != nil {
		return err
	}
	var hasher hash.Hash
	if wantHash != nil {
		hasher = sha256.New()
		r = io.TeeReader(r, hasher)
	}
	// A full segment is the last one only when nothing follows it, so look one
	// byte past it before deciding.
	segLen := int(decryptor.Params.EncSegLen)
	input := bufio.NewReaderSize(r, segLen+1)
	segment := make([]byte, segLen)
	for {
		n, err := io.ReadFull(input, segment)
		if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
			return err
		}
		last := n < segLen
		if !last {
			if _, err = input.Peek(1); errors.Is(err, io.EOF) {
				last = true
			} else if err != nil {
				return err
			}
		}
		var plaintext []byte
		if last {
			plaintext, err = decryptor.DecryptLastSegment(segment[:n])
		} else {
			plaintext, err = decryptor.DecryptSegment(segment)
		}
		if err != nil {
			return err
		}
		if _, err = w.Write(plaintext); err != nil {
			return err
		}
		if last {
			break
		}
	}
	if hasher != nil && !hmac.Equal(hasher.Sum(nil), wantHash) {
		return errors.New("FLOE ciphertext hash mismatch")
	}
	return nil
}
