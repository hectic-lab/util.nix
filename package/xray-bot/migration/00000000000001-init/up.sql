CREATE TABLE xray_client (
  uuid        TEXT PRIMARY KEY,
  email       TEXT,
  discovered  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE telegram_user (
  telegram_id BIGINT PRIMARY KEY,
  username    TEXT,
  first_name  TEXT,
  registered  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_uuid (
  telegram_id BIGINT NOT NULL REFERENCES telegram_user(telegram_id),
  uuid        TEXT   NOT NULL REFERENCES xray_client(uuid),
  bound_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (telegram_id, uuid)
);
