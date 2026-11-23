`floe.go` is mautrix-go v0.33.0's `crypto/floe`, unchanged: the Go FLOE
implementation from <https://github.com/Snowflake-Labs/floe-specification>.
Beeper's WhatsApp bridge encrypts media with it (`com.beeper.floe.v1`,
MSC4571), which the mautrix-go that gomuks v0.2601.0 builds against can't
decrypt. `file.go` reimplements the decrypting half of mautrix-go's
`crypto/attachment/floe.go`, and finds a file's keys in event content.

When the SDK moves to mautrix-go v0.33.0 or later, `Decrypt` can give way to
mautrix's `EncryptedFile.DecryptStream`. Keep the key lookup from events
(`FindFile`, `dispatch.floeFile`) for media rows whose `enc_file` has no
`floe_key`: every row stored before the upgrade lost its keys.
