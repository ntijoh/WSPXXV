require 'sqlite3'
require 'bcrypt'

def drop_tables(db)
  tables = %w[
    enemy_drops
    place_enemies
    commands
    character_events
    character_items
    character_stats
    user_characters
    places
    items
    enemies
    characters
    users
  ]

  tables.each do |table|
    db.execute("DROP TABLE IF EXISTS #{table}")
  end
end

def create_tables(db)
  db.execute <<~SQL
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      pwd_digest TEXT NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
      is_admin INTEGER NOT NULL DEFAULT 0
      failed_login_attempts INTEGER NOT NULL DEFAULT 0
      locked_until TEXT
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE characters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      description TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE user_characters (
      user_id INTEGER NOT NULL,
      character_id INTEGER NOT NULL,
      PRIMARY KEY (user_id, character_id),
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE character_stats (
      character_id INTEGER PRIMARY KEY,
      level INTEGER NOT NULL DEFAULT 1,
      xp INTEGER NOT NULL DEFAULT 0,
      hp INTEGER NOT NULL DEFAULT 10,
      max_hp INTEGER NOT NULL DEFAULT 10,
      attack INTEGER NOT NULL DEFAULT 1,
      defense INTEGER NOT NULL DEFAULT 0,
      gold INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE enemies (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT,
      hp INTEGER NOT NULL,
      attack INTEGER NOT NULL,
      defense INTEGER NOT NULL DEFAULT 0,
      xp_reward INTEGER NOT NULL DEFAULT 0
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT,
      item_type TEXT NOT NULL,
      attack_bonus INTEGER NOT NULL DEFAULT 0,
      defense_bonus INTEGER NOT NULL DEFAULT 0,
      heal_amount INTEGER NOT NULL DEFAULT 0,
      value INTEGER NOT NULL DEFAULT 0
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE enemy_drops (
      enemy_id INTEGER NOT NULL,
      item_id INTEGER NOT NULL,
      drop_rate REAL NOT NULL,
      min_qty INTEGER NOT NULL DEFAULT 1,
      max_qty INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY (enemy_id, item_id),
      FOREIGN KEY (enemy_id) REFERENCES enemies(id) ON DELETE CASCADE,
      FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE places (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT NOT NULL
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE place_enemies (
      place_id INTEGER NOT NULL,
      enemy_id INTEGER NOT NULL,
      spawn_weight INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY (place_id, enemy_id),
      FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE CASCADE,
      FOREIGN KEY (enemy_id) REFERENCES enemies(id) ON DELETE CASCADE
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE commands (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT NOT NULL
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE character_events (
      character_id INTEGER NOT NULL,
      event_key TEXT NOT NULL,
      triggered INTEGER NOT NULL DEFAULT 0,
      triggered_at TEXT,
      notes TEXT,
      PRIMARY KEY (character_id, event_key),
      FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
    )
  SQL

  db.execute <<~SQL
    CREATE TABLE character_items (
      character_id INTEGER NOT NULL,
      item_id INTEGER NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (character_id, item_id),
      FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE,
      FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
    )
  SQL
end

def populate_static_data(db)
  seed_commands(db)
  seed_places(db)
  seed_enemies(db)
  seed_items(db)
  seed_place_enemies(db)
  seed_enemy_drops(db)
  seed_demo_user_and_character(db)
end

def seed_commands(db)
  commands = [
    ['look', 'Describe your current location'],
    ['go', 'Move to another place'],
    ['attack', 'Attack a target enemy'],
    ['inventory', 'Show your inventory'],
    ['use', 'Use an item'],
    ['equip', 'Equip an item'],
    ['stats', 'Show character stats'],
    ['help', 'List all available commands']
  ]

  commands.each do |name, description|
    db.execute('INSERT INTO commands (name, description) VALUES (?, ?)', [name, description])
  end
end

def seed_places(db)
  places = [
    ['Battlefield', 'A ruined battlefield covered with smoke and debris.'],
    ['Boulder Site', 'A massive meteor-like boulder, scorched and bloodstained.']
  ]

  places.each do |name, description|
    db.execute('INSERT INTO places (name, description) VALUES (?, ?)', [name, description])
  end
end

def seed_enemies(db)
  enemies = [
    ['Stragglers', 'Wounded survivors desperate to fight.', 15, 3, 0, 10],
    ['Imperial Scout', 'A fast recon soldier from the enemy ranks.', 20, 5, 1, 15],
    ['Mercenary', 'A hardened fighter with battlefield experience.', 25, 6, 2, 20]
  ]

  enemies.each do |name, description, hp, attack, defense, xp_reward|
    db.execute(
      'INSERT INTO enemies (name, description, hp, attack, defense, xp_reward) VALUES (?, ?, ?, ?, ?, ?)',
      [name, description, hp, attack, defense, xp_reward]
    )
  end
end

def seed_items(db)
  items = [
    ['Sword', 'A standard iron sword.', 'weapon', 8, 0, 0, 30],
    ['Spear', 'A long spear with strong reach.', 'weapon', 10, 0, 0, 40],
    ['Bandages', 'Simple medical cloth for healing.', 'consumable', 0, 0, 4, 10],
    ['Iron Helmet', 'Heavy helmet that protects your head.', 'armor', 0, 3, 0, 25],
    ['Iron Chestplate', 'Solid chest armor.', 'armor', 0, 5, 0, 45],
    ['Iron Leggings', 'Leg armor with decent protection.', 'armor', 0, 4, 0, 35]
  ]

  items.each do |name, description, item_type, atk, defn, heal, value|
    db.execute(
      'INSERT INTO items (name, description, item_type, attack_bonus, defense_bonus, heal_amount, value) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [name, description, item_type, atk, defn, heal, value]
    )
  end
end

def seed_place_enemies(db)
  place_enemy = [
    ['Battlefield', 'Stragglers', 6],
    ['Battlefield', 'Imperial Scout', 3],
    ['Battlefield', 'Mercenary', 1],
    ['Boulder Site', 'Mercenary', 1]
  ]

  place_enemy.each do |place_name, enemy_name, weight|
    place_id = db.get_first_value('SELECT id FROM places WHERE name = ?', [place_name])
    enemy_id = db.get_first_value('SELECT id FROM enemies WHERE name = ?', [enemy_name])

    db.execute(
      'INSERT INTO place_enemies (place_id, enemy_id, spawn_weight) VALUES (?, ?, ?)',
      [place_id, enemy_id, weight]
    )
  end
end

def seed_enemy_drops(db)
  drops = [
    ['Stragglers', 'Bandages', 0.30, 1, 2],
    ['Imperial Scout', 'Spear', 0.20, 1, 1],
    ['Mercenary', 'Iron Helmet', 0.25, 1, 1],
    ['Mercenary', 'Iron Chestplate', 0.20, 1, 1],
    ['Mercenary', 'Iron Leggings', 0.20, 1, 1]
  ]

  drops.each do |enemy_name, item_name, rate, min_qty, max_qty|
    enemy_id = db.get_first_value('SELECT id FROM enemies WHERE name = ?', [enemy_name])
    item_id = db.get_first_value('SELECT id FROM items WHERE name = ?', [item_name])

    db.execute(
      'INSERT INTO enemy_drops (enemy_id, item_id, drop_rate, min_qty, max_qty) VALUES (?, ?, ?, ?, ?)',
      [enemy_id, item_id, rate, min_qty, max_qty]
    )
  end
end

def seed_demo_user_and_character(db)
  pwd_digest = BCrypt::Password.create('demo123')
  db.execute('INSERT INTO users (name, pwd_digest) VALUES (?, ?)', ['demo', pwd_digest])

  db.execute('INSERT INTO characters (name, description) VALUES (?, ?)', ['Brutus', 'A young survivor of the battlefield.'])

  user_id = db.get_first_value('SELECT id FROM users WHERE name = ?', ['demo'])
  character_id = db.get_first_value('SELECT id FROM characters WHERE name = ?', ['Brutus'])

  db.execute('INSERT INTO user_characters (user_id, character_id) VALUES (?, ?)', [user_id, character_id])
  db.execute('INSERT INTO character_stats (character_id, level, xp, hp, max_hp, attack, defense, gold) VALUES (?, 1, 0, 10, 10, 3, 0, 0)', [character_id])

  %w[knows_about_invasion found_parents boulder_event].each do |event_key|
    db.execute(
      'INSERT INTO character_events (character_id, event_key, triggered) VALUES (?, ?, 0)',
      [character_id, event_key]
    )
  end
end