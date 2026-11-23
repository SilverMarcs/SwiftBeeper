package dispatch

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"testing"

	"maunium.net/go/mautrix/crypto/attachment"
)

func TestStreamToCacheAES(t *testing.T) {
	plaintext := make([]byte, 100_000)
	rand.Read(plaintext)
	encFile := attachment.NewEncryptedFile()
	encrypter := encFile.EncryptStream(bytes.NewReader(plaintext))
	ciphertext, err := io.ReadAll(encrypter)
	if err != nil {
		t.Fatal(err)
	}
	// Closing the encrypter records the ciphertext hash that decryption checks.
	if err = encrypter.Close(); err != nil {
		t.Fatal(err)
	}
	// Decrypt with a copy read back from JSON, as the media table stores it.
	stored, _ := json.Marshal(encFile)
	encFile = &attachment.EncryptedFile{}
	if err = json.Unmarshal(stored, encFile); err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()

	cachePath := filepath.Join(dir, "media.decrypted")
	if err = streamToCache(bytes.NewReader(ciphertext), aesDecrypt(encFile), dir, cachePath); err != nil {
		t.Fatal(err)
	}
	if cached, _ := os.ReadFile(cachePath); !bytes.Equal(cached, plaintext) {
		t.Fatal("decrypted cache doesn't match the plaintext")
	}

	tampered := bytes.Clone(ciphertext)
	tampered[0] ^= 1
	tamperedPath := filepath.Join(dir, "tampered.decrypted")
	if err = streamToCache(bytes.NewReader(tampered), aesDecrypt(encFile), dir, tamperedPath); err == nil {
		t.Fatal("tampered ciphertext: want error")
	}
	if _, err = os.Stat(tamperedPath); !os.IsNotExist(err) {
		t.Fatal("tampered ciphertext became the cache")
	}

	plainPath := filepath.Join(dir, "plain")
	if err = streamToCache(bytes.NewReader(plaintext), nil, dir, plainPath); err != nil {
		t.Fatal(err)
	}
	if cached, _ := os.ReadFile(plainPath); !bytes.Equal(cached, plaintext) {
		t.Fatal("plain cache doesn't match the download")
	}
}
