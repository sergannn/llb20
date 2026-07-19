CREATE TABLE IF NOT EXISTS players (
  id BIGINT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  href VARCHAR(512) NOT NULL,
  birthday VARCHAR(64) NULL,
  country VARCHAR(128) NULL,
  country_id BIGINT NULL,
  city VARCHAR(128) NULL,
  registered_at VARCHAR(128) NULL,
  avatar_url TEXT NULL,
  source_page INT NULL,
  elo INT NULL,
  rating_text TEXT NULL,
  detail_json JSON NULL,
  detail_fetched_at VARCHAR(64) NULL,
  contacts_raw TEXT NULL,
  phone TEXT NULL,
  email TEXT NULL,
  telegram TEXT NULL,
  whatsapp TEXT NULL,
  created_at VARCHAR(64) NOT NULL,
  updated_at VARCHAR(64) NOT NULL,
  KEY idx_players_name (name),
  KEY idx_players_detail_fetched (detail_fetched_at),
  KEY idx_players_elo (elo),
  KEY idx_players_phone (phone(32)),
  KEY idx_players_email (email(128))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS player_ratings (
  player_id BIGINT NOT NULL,
  rating_key VARCHAR(128) NOT NULL,
  discipline VARCHAR(255) NULL,
  rating_label VARCHAR(255) NULL,
  elo INT NULL,
  comps_year INT NULL,
  comps_total INT NULL,
  source VARCHAR(64) NOT NULL,
  fetched_at VARCHAR(64) NOT NULL,
  PRIMARY KEY (player_id, rating_key),
  KEY idx_player_ratings_key_elo (rating_key, elo),
  KEY idx_player_ratings_player (player_id),
  CONSTRAINT fk_player_ratings_player FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS player_tournament_entries (
  player_id BIGINT NOT NULL,
  membership_node_id BIGINT NOT NULL DEFAULT 0,
  tournament_id BIGINT NOT NULL,
  title TEXT NOT NULL,
  date_text VARCHAR(255) NULL,
  points VARCHAR(128) NULL,
  place VARCHAR(128) NULL,
  source_page INT NULL,
  fetched_at VARCHAR(64) NOT NULL,
  PRIMARY KEY (player_id, tournament_id, membership_node_id),
  KEY idx_player_tournament_entries_player (player_id),
  KEY idx_player_tournament_entries_tournament (tournament_id),
  CONSTRAINT fk_player_tournament_entries_player FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tournaments (
  id BIGINT PRIMARY KEY,
  title TEXT NOT NULL,
  href VARCHAR(512) NOT NULL,
  source_kind VARCHAR(64) NOT NULL,
  status_class VARCHAR(255) NULL,
  date_text VARCHAR(255) NULL,
  club VARCHAR(255) NULL,
  club_id BIGINT NULL,
  participants_count INT NULL,
  participants_limit INT NULL,
  source_page INT NULL,
  comp_id BIGINT NULL,
  detail_json JSON NULL,
  detail_fetched_at VARCHAR(64) NULL,
  created_at VARCHAR(64) NOT NULL,
  updated_at VARCHAR(64) NOT NULL,
  KEY idx_tournaments_source_page (source_page),
  KEY idx_tournaments_comp_id (comp_id),
  KEY idx_tournaments_detail_fetched (detail_fetched_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tournament_stages (
  comp_id BIGINT NOT NULL,
  stage_id BIGINT NOT NULL,
  tournament_id BIGINT NULL,
  name VARCHAR(255) NULL,
  fetched_at VARCHAR(64) NOT NULL,
  PRIMARY KEY (comp_id, stage_id),
  KEY idx_stages_tournament (tournament_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS tournament_participants (
  comp_id BIGINT NOT NULL,
  stage_id BIGINT NOT NULL,
  player_id BIGINT NOT NULL,
  seed INT NULL,
  name VARCHAR(255) NULL,
  birth_year INT NULL,
  `rank` VARCHAR(128) NULL,
  country VARCHAR(128) NULL,
  city VARCHAR(128) NULL,
  place VARCHAR(128) NULL,
  avatar_url TEXT NULL,
  fetched_at VARCHAR(64) NOT NULL,
  PRIMARY KEY (comp_id, stage_id, player_id),
  KEY idx_participants_player (player_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS archive_tournament_participants (
  tournament_id BIGINT NOT NULL,
  membership_node_id BIGINT NOT NULL DEFAULT 0,
  seed INT NULL,
  name VARCHAR(255) NOT NULL,
  level VARCHAR(255) NULL,
  points VARCHAR(128) NULL,
  place VARCHAR(128) NULL,
  fetched_at VARCHAR(64) NOT NULL,
  PRIMARY KEY (tournament_id, membership_node_id, name),
  KEY idx_archive_participants_membership (membership_node_id),
  KEY idx_archive_participants_tournament (tournament_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS archive_tournament_fetches (
  tournament_id BIGINT NOT NULL PRIMARY KEY,
  status VARCHAR(64) NOT NULL,
  rows_count INT NOT NULL DEFAULT 0,
  fetched_at VARCHAR(64) NOT NULL,
  KEY idx_archive_fetches_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS matches (
  comp_id BIGINT NOT NULL,
  stage_id BIGINT NOT NULL,
  game_no BIGINT NOT NULL,
  tournament_id BIGINT NULL,
  round_name VARCHAR(255) NULL,
  status_class VARCHAR(255) NULL,
  player1_id BIGINT NULL,
  player1_name VARCHAR(255) NULL,
  player1_elo_before INT NULL,
  player1_elo_after INT NULL,
  player2_id BIGINT NULL,
  player2_name VARCHAR(255) NULL,
  player2_elo_before INT NULL,
  player2_elo_after INT NULL,
  score1 VARCHAR(64) NULL,
  score2 VARCHAR(64) NULL,
  params TEXT NULL,
  table_no VARCHAR(64) NULL,
  planned_at VARCHAR(128) NULL,
  started_at VARCHAR(128) NULL,
  finished_at VARCHAR(128) NULL,
  video TEXT NULL,
  raw_json JSON NULL,
  fetched_at VARCHAR(64) NOT NULL,
  PRIMARY KEY (comp_id, stage_id, game_no),
  KEY idx_matches_tournament (tournament_id),
  KEY idx_matches_player1 (player1_id),
  KEY idx_matches_player2 (player2_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS player_rating_events (
  player_id BIGINT NOT NULL,
  comp_id BIGINT NOT NULL,
  stage_id BIGINT NOT NULL,
  game_no BIGINT NOT NULL,
  side INT NOT NULL,
  player_name VARCHAR(255) NULL,
  elo_before INT NULL,
  elo_after INT NULL,
  fetched_at VARCHAR(64) NOT NULL,
  PRIMARY KEY (player_id, comp_id, stage_id, game_no, side),
  KEY idx_rating_events_player (player_id),
  KEY idx_rating_events_comp_stage (comp_id, stage_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS import_meta (
  key_name VARCHAR(128) PRIMARY KEY,
  value_text TEXT NOT NULL,
  updated_at VARCHAR(64) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS llb_app_users (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  llb_username VARCHAR(190) NOT NULL,
  llb_username_hash CHAR(64) NOT NULL,
  password_ciphertext TEXT NOT NULL,
  password_iv VARCHAR(64) NOT NULL,
  password_tag VARCHAR(64) NOT NULL,
  request_ip VARCHAR(64) NULL,
  user_agent VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_login_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_llb_username_hash (llb_username_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
