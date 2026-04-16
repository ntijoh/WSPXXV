require "sqlite3"
require "time"


# Data access layer for the Brutus app.
# Handles persistence for users, characters, and character stats.
class Model
  # @return [SQLite3::Database] active SQLite connection
  attr_reader :db

  # @param user_id [Integer] user id
  # @return [void] 
  def clear_login_failures(user_id)
    @db.execute("UPDATE users SET failed_login_attempts = 0, locked_until = NULL WHERE id = ?", [user_id])
  end

  # @param user_row [Hash] user row from database
  # @return [Boolean] true if lockout is still active
  def locked_out?(user_row)
    return false if user_row["locked_until"].nil? || user_row["locked_until"].to_s.strip.empty?
    Time.parse(user_row["locked_until"]) > Time.now
  end

  # @param user_row [Hash] user row from database
  # @return [Integer] seconds remaining, or 0 if not locked
  def lockout_seconds_left(user_row)
    return 0 if user_row["locked_until"].nil? || user_row["locked_until"].to_s.strip.empty?
    left = (Time.parse(user_row["locked_until"]) - Time.now).ceil
    left.positive? ? left : 0
  end

  # @param user_row [Hash] user row from database
  # @param max_attempts [Integer] failed attempts before lockout
  # @param cooldown_seconds [Integer] lockout duration in seconds
  # @return [Integer] cooldown seconds applied, or 0 if not locked yet
  def register_failed_login(user_row, max_attempts:, cooldown_seconds:)
    attempts = user_row["failed_login_attempts"].to_i + 1

    if attempts >= max_attempts
      locked_until = (Time.now + cooldown_seconds).iso8601
      @db.execute("UPDATE users SET failed_login_attempts = ?, locked_until = ? WHERE id = ?", [attempts, locked_until, user_row["id"]])
      cooldown_seconds
    else
      @db.execute("UPDATE users SET failed_login_attempts = ? WHERE id = ?", [attempts, user_row["id"]])
      0
    end
  end


  # @param db_path [String] path to SQLite database file
  # @return [void]
  def initialize(db_path)
    @db = SQLite3::Database.new(db_path)
    @db.results_as_hash = true
    @db.execute("PRAGMA foreign_keys = ON")
  end

  # Finds a user by username.
  #
  # @param name [String] account username
  # @return [Hash, nil] user row or nil when missing
  def find_user_by_name(name)
    @db.execute("SELECT * FROM users WHERE name = ?", [name]).first
  end

  # Finds a user by id.
  #
  # @param id [Integer] user id
  # @return [Hash, nil] user row or nil when missing
  def find_user_by_id(id)
    @db.execute("SELECT * FROM users WHERE id = ?", [id]).first
  end

  # Creates a user.
  #
  # @param name [String] account username
  # @param pwd_digest [String] bcrypt password digest
  # @return [Integer] id of inserted user
  def create_user(name, pwd_digest)
    @db.execute("INSERT INTO users(name, pwd_digest) VALUES(?, ?)", [name, pwd_digest])
    @db.last_insert_row_id
  end

  # Deletes a user.
  #
  # @param user_id [Integer] user id
  # @return [void]
  def delete_user(user_id)
    @db.execute("DELETE FROM users WHERE id = ?", [user_id])
  end

  # @return [Array<Hash>] user rows with id, name, is_admin, created_at
  def all_users
    @db.execute("SELECT id, name, is_admin, created_at FROM users ORDER BY id ASC")
  end

  # @param user_id [Integer] target user id
  # @return [void]
  def delete_user_with_characters(user_id)
    characters_for_user(user_id).each do |character|
      delete_character(character["id"])
    end
    delete_user(user_id)
  end


  # Lists all characters owned by a user.
  #
  # @param user_id [Integer] owner user id
  # @return [Array<Hash>] list of character rows
  def characters_for_user(user_id)
    @db.execute(<<~SQL, [user_id])
      SELECT c.id, c.name, c.created_at
      FROM characters c
      INNER JOIN user_characters uc ON uc.character_id = c.id
      WHERE uc.user_id = ?
      ORDER BY c.created_at DESC
    SQL
  end

  # Finds a character by id.
  #
  # @param character_id [Integer] character id
  # @return [Hash, nil] character row or nil when missing
  def find_character(character_id)
    @db.execute("SELECT * FROM characters WHERE id = ?", [character_id]).first
  end

  # Creates a character and links it to a user, with default stats.
  #
  # @param user_id [Integer] owner user id
  # @param name [String] character name
  # @return [Integer] id of inserted character
  def create_character_for_user(user_id, name)
    @db.execute("INSERT INTO characters(name, description) VALUES(?, ?)", [name, ""])
    character_id = @db.last_insert_row_id
    @db.execute("INSERT INTO user_characters(user_id, character_id) VALUES(?, ?)", [user_id, character_id])
    @db.execute("INSERT INTO character_stats(character_id, level, xp, hp, max_hp, attack, defense, gold) VALUES (?, 1, 0, 10, 10, 3, 0, 0)", [character_id])
    character_id
  end

  # Checks whether a user owns a character.
  #
  # @param user_id [Integer] user id
  # @param character_id [Integer] character id
  # @return [Boolean] true when ownership exists
  def user_owns_character?(user_id, character_id)
    @db.execute("SELECT 1 FROM user_characters WHERE user_id = ? AND character_id = ?", [user_id, character_id]).any?
  end

  # Deletes a character.
  #
  # @param character_id [Integer] character id
  # @return [void]
  def delete_character(character_id)
    @db.execute("DELETE FROM characters WHERE id = ?", [character_id])
  end

  # Updates persistent stats for a character.
  #
  # @param character_id [Integer] character id
  # @param level [Integer] level value
  # @param xp [Integer] experience value
  # @param hp [Integer] current health value
  # @param max_hp [Integer] maximum health value
  # @return [void]
  def update_character_stats(character_id:, level:, xp:, hp:, max_hp:)
    @db.execute(
      "UPDATE character_stats SET level = ?, xp = ?, hp = ?, max_hp = ? WHERE character_id = ?",
      [level, xp, hp, max_hp, character_id]
    )
  end
end
