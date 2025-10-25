CREATE TABLE status (
  id     INTEGER  PRIMARY KEY,  -- integer in sqlite almoust infinity
  time   DATETIME DEFAULT CURRENT_TIMESTAMP,
  status TEXT     NOT NULL
);

CREATE TABLE disk (
  id     INTEGER  PRIMARY KEY,  -- integer in sqlite almoust infinity
  time   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  server TEXT     NOT NULL,
  disk   TEXT     NOT NULL,
  space  INTEGER  NOT NULL
);
