require 'sqlite3'
require_relative 'seeder2'

db_path = File.expand_path('brutus.db', __dir__)
db = SQLite3::Database.new(db_path)

def seed!(db, db_path)
  puts "Using db file: #{db_path}"
  db.execute('PRAGMA foreign_keys = ON')  
  
  puts 'Dropping old tables...'
  drop_tables(db)
  
  puts 'Creating tables...'
  create_tables(db)

  puts 'Populating seed data...'
  populate_static_data(db)

  puts 'Done seeding the database!'
end

seed!(db,db_path)