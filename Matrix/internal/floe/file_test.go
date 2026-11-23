package floe

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"testing"
)

func encryptForTest(t *testing.T, plaintext []byte) (File, []byte) {
	t.Helper()
	key := make([]byte, 32)
	rand.Read(key)
	encryptor, err := NewFloeEncryptor(GCM256_IV256_4K(), key, nil)
	if err != nil {
		t.Fatal(err)
	}
	segLen := encryptor.Params.PtSegLen()
	var ciphertext []byte
	for len(plaintext) > segLen {
		segment, err := encryptor.EncryptSegment(plaintext[:segLen])
		if err != nil {
			t.Fatal(err)
		}
		ciphertext = append(ciphertext, segment...)
		plaintext = plaintext[segLen:]
	}
	segment, err := encryptor.EncryptLastSegment(plaintext)
	if err != nil {
		t.Fatal(err)
	}
	ciphertext = append(ciphertext, segment...)
	hash := sha256.Sum256(ciphertext)
	file := File{
		Version: Version,
		Key:     base64.RawStdEncoding.EncodeToString(key),
		Header:  base64.RawStdEncoding.EncodeToString(encryptor.Header),
	}
	file.Hashes.SHA256 = base64.RawStdEncoding.EncodeToString(hash[:])
	return file, ciphertext
}

func TestDecryptRoundTrip(t *testing.T) {
	segLen := GCM256_IV256_4K().PtSegLen()
	for _, size := range []int{0, 1, segLen - 1, segLen, segLen + 1, 3 * segLen, 3*segLen + 7} {
		plaintext := make([]byte, size)
		rand.Read(plaintext)
		file, ciphertext := encryptForTest(t, plaintext)
		var out bytes.Buffer
		if err := file.Decrypt(bytes.NewReader(ciphertext), &out); err != nil {
			t.Fatalf("size %d: %v", size, err)
		}
		if !bytes.Equal(out.Bytes(), plaintext) {
			t.Fatalf("size %d: plaintext mismatch", size)
		}
	}
}

func TestFindFile(t *testing.T) {
	const mxc = "mxc://local.beeper.com/media"
	file := `{"url":"` + mxc + `","v":"com.beeper.floe.v1","floe_key":"k","floe_header":"h"}`
	for name, content := range map[string]string{
		"main file":    `{"msgtype":"m.image","file":` + file + `}`,
		"thumbnail":    `{"msgtype":"m.video","info":{"thumbnail_file":` + file + `}}`,
		"edit":         `{"m.new_content":{"file":` + file + `}}`,
		"link preview": `{"com.beeper.linkpreviews":[{"beeper:image:encryption":` + file + `}]}`,
	} {
		found := FindFile([]byte(content), mxc)
		if found == nil || found.Key != "k" || found.Header != "h" {
			t.Errorf("%s: got %+v", name, found)
		}
	}
	for name, content := range map[string]string{
		"other media": `{"file":` + file + `}`,
		"AES file":    `{"file":{"url":"` + mxc + `","v":"v2","key":{}}}`,
		"invalid":     `{`,
	} {
		lookFor := mxc
		if name == "other media" {
			lookFor = "mxc://local.beeper.com/other"
		}
		if found := FindFile([]byte(content), lookFor); found != nil {
			t.Errorf("%s: got %+v, want nil", name, found)
		}
	}
}

func TestDecryptRejectsTamperedOrTruncated(t *testing.T) {
	segLen := GCM256_IV256_4K().PtSegLen()
	plaintext := make([]byte, 2*segLen+100)
	rand.Read(plaintext)
	file, ciphertext := encryptForTest(t, plaintext)
	encSegLen := int(GCM256_IV256_4K().EncSegLen)

	truncated := ciphertext[:2*encSegLen]
	if err := file.Decrypt(bytes.NewReader(truncated), &bytes.Buffer{}); err == nil {
		t.Fatal("truncated at a segment boundary: want error")
	}
	tampered := bytes.Clone(ciphertext)
	tampered[len(tampered)-1] ^= 1
	if err := file.Decrypt(bytes.NewReader(tampered), &bytes.Buffer{}); err == nil {
		t.Fatal("tampered: want error")
	}
	file.Hashes.SHA256 = ""
	if err := file.Decrypt(bytes.NewReader(truncated), &bytes.Buffer{}); err == nil {
		t.Fatal("truncated without hash: want error")
	}
}
