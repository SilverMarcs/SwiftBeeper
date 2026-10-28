CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  pushkey TEXT NOT NULL UNIQUE,
  token TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS notification_blocks (
  room_id TEXT PRIMARY KEY,
  blocked_until INTEGER NOT NULL
);

-- Successful deliveries and short in-flight leases, shared by both send paths.
CREATE TABLE IF NOT EXISTS notification_deliveries (
  device_id TEXT NOT NULL,
  room_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  claim TEXT NOT NULL,
  claimed_until INTEGER NOT NULL,
  sent INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (device_id, room_id, event_id)
);
CREATE INDEX IF NOT EXISTS notification_deliveries_expiry ON notification_deliveries (claimed_until);
CREATE INDEX IF NOT EXISTS notification_deliveries_claim ON notification_deliveries (claim);
