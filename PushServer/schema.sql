CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  pushkey TEXT NOT NULL UNIQUE,
  token TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS notification_blocks (
  room_id TEXT PRIMARY KEY,
  blocked_until INTEGER NOT NULL
);
