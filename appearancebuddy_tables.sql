-- AppearanceBuddy / ALE transmog schema
-- Reconstructed from REQUIRED_TRANSMOG_TABLE_COLUMNS in transmog.lua (lines 561-585)
-- and the unique-key checks at lines 704-707.
--
-- The upstream repo references migrations/2026_07_20_appearancebuddy_auth.sql and
-- migrations/2026_07_20_appearancebuddy_characters.sql, but neither ships in the zip.
--
-- CREATE TABLE IF NOT EXISTS means existing tables are left untouched.
-- Run once:   mysql -u root -p < appearancebuddy_tables.sql

-- ---------------------------------------------------------------
-- acore_auth
-- ---------------------------------------------------------------
USE acore_auth;

CREATE TABLE IF NOT EXISTS `account_transmog` (
  `account_id`       INT UNSIGNED     NOT NULL,
  `unlocked_item_id` INT UNSIGNED     NOT NULL,
  `display_id`       INT UNSIGNED     NOT NULL,
  `inventory_type`   TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `item_name`        VARCHAR(255)     NOT NULL DEFAULT '',
  UNIQUE KEY `uk_account_unlocked_item` (`account_id`, `unlocked_item_id`),
  KEY `idx_account_display` (`account_id`, `display_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `account_transmog_removed_appearance` (
  `account_id` INT UNSIGNED NOT NULL,
  `display_id` INT UNSIGNED NOT NULL,
  UNIQUE KEY `uk_account_display` (`account_id`, `display_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------
-- acore_characters
-- ---------------------------------------------------------------
USE acore_characters;

CREATE TABLE IF NOT EXISTS `character_transmog` (
  `player_guid` INT UNSIGNED      NOT NULL,
  `slot`        SMALLINT UNSIGNED NOT NULL,
  `item`        INT UNSIGNED      NULL,
  `real_item`   INT UNSIGNED      NOT NULL DEFAULT 0,
  UNIQUE KEY `uk_player_slot` (`player_guid`, `slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `character_transmog_weapon_enchant` (
  `player_guid`    INT UNSIGNED      NOT NULL,
  `equipment_slot` TINYINT UNSIGNED  NOT NULL,
  `enchant_id`     SMALLINT UNSIGNED NOT NULL,
  UNIQUE KEY `uk_player_equipslot` (`player_guid`, `equipment_slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
