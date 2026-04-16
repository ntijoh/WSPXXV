require 'sinatra'
require 'sqlite3'
require 'slim'
require 'sinatra/reloader'
require 'bcrypt'
require 'stringio'
require_relative 'model/model.rb'

# @return [String]
DB_PATH = File.expand_path('db/brutus.db', __dir__)

# @return [Model]
MODEL = Model.new(DB_PATH)

enable :sessions



set :session_secret, "super duper ultra uber secret string2568576456357468507685746356745879680985473678596070968574352647586970765436789076854374267135137589135670823+521350+362487646252463057834057+362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645362487645"

post('/delete_account') do
  redirect('/login') if session[:user_id].nil?

  user_id = session[:user_id]
  MODEL.characters_for_user(user_id).each do |character|
    MODEL.delete_character(character["id"])
  end
  MODEL.delete_user(user_id)

  session.clear
  redirect('/login')
end


post('/register') do
  user = params["user"]
  pwd = params["pwd"]
  pwd_confirm = params["pwd_confirm"]

  existing_user = MODEL.find_user_by_name(user)

  if existing_user.nil?
    if pwd == pwd_confirm
      pwd_digest = BCrypt::Password.create(pwd)
      user_id = MODEL.create_user(user, pwd_digest)
      session[:user_id] = user_id
      session[:username] = user
      redirect('/')
    else
      redirect('/register?error=Passwords%20do%20not%20match')
    end
  else
    redirect('/register?error=User%20already%20exists')
  end
end


get('/') do
  redirect('/login') if session[:user_id].nil?

  ensure_terminal
  @user = MODEL.find_user_by_id(session[:user_id])
  redirect('/login') if @user.nil?

  unless session[:terminal_booted]
    push_line("Welcome, #{session[:username]}.")
    print_character_menu
    session[:terminal_booted] = true
  end

  @terminal_output = session[:terminal_output]
  slim(:home)
end

get('/register') do
  @error = params[:error]
  session.clear
  slim(:register)
end

get('/login') do
  @error = params[:error]
  slim(:login)
end

get('/logout') do
  session.clear
  redirect('/login')
end

get('/error') do
    @error = session.delete(:error) || "An error occurred."
    slim(:login)
end

post('/login') do
  user = params["user"]
  pwd = params["pwd"]

  result = MODEL.find_user_by_name(user)
  redirect('/login?error=User%20does%20not%20exist') if result.nil?

  if MODEL.locked_out?(result)
    seconds_left = MODEL.lockout_seconds_left(result)
    redirect("/login?error=Too%20many%20attempts.%20Try%20again%20in%20#{seconds_left}%20seconds")
  end

  user_id = result["id"]
  pwd_digest = result["pwd_digest"]

  if BCrypt::Password.new(pwd_digest) == pwd
    MODEL.clear_login_failures(user_id)
    session[:user_id] = user_id
    session[:username] = user
    session[:is_admin] = (result["is_admin"].to_i == 1)
    redirect('/')
  else
    lock_seconds = MODEL.register_failed_login(result, max_attempts: 5, cooldown_seconds: 60)

    if lock_seconds > 0
      redirect("/login?error=Too%20many%20attempts.%20Locked%20for%20#{lock_seconds}%20seconds")
    else
      redirect('/login?error=Incorrect%20password')
    end
  end
end


# @return [void]
def introduction_dialogue_web_intro_only
  puts "#{player_name}: Who are you?"
  puts "???: Who am I? The name's Robbert, a mercenary, nice to meet'cha."
  puts "Robbert: By the way, how'd you get in this mess? How old are you even?"
  puts "How do you respond?"
  puts "1   (full truth)"
  puts "2   (lie about age)"
  puts "3   (stay silent)"
end

# @param choice [String] intro choice input
# @return [void]
def apply_intro_choice(choice)
  case choice
  when "1"
    puts "#{player_name}: I'm twelve. Both of my parents went missing some days ago."
    @game_state[:robbert_trust] += 2
  when "2"
    puts "#{player_name}: I'm... sixteen. I got separated from my unit."
    @game_state[:robbert_trust] -= 1
    puts "Robbert: ...My condolences."
  else
    puts "#{player_name}: ..."
    puts "Robbert: Tough kid, eh? Alright then."
  end
  @game_state[:knows_about_invasion] = true
  describe_room_no_sleep
end

# @return [void]
def describe_room_no_sleep
  case @current_room
  when :battlefield
    puts "Day #{@day}, #{@time.capitalize}: A horrendous sight."
    puts "You hold your head high."
  when :boulder_site
    puts "The massive meteor-like boulder dominates the landscape."
  end
end

post('/command') do
  redirect('/login') if session[:user_id].nil?
  ensure_terminal

  input = params[:command].to_s.strip
  push_line("PS C:\\Brutus> #{input}")
  command, *params_arr = input.downcase.split(/\s+/)

  if command == "clear"
    session[:terminal_output] = []
    return redirect('/')
  end


  if session[:is_admin]
    if command == "admin_users"
      MODEL.all_users.each do |u|
        role = u["is_admin"].to_i == 1 ? "admin" : "user"
        push_line("[#{u["id"]}] #{u["name"]} (#{role})")
      end
      return redirect('/')
    end

    if command == "admin_delete"
      target_id = params_arr.first.to_i
      if target_id <= 0
        push_line("Usage: admin_delete <user_id>")
        return redirect('/')
      end

      if target_id == session[:user_id]
        push_line("You cannot delete your own account while logged in.")
        return redirect('/')
      end

      target = MODEL.find_user_by_id(target_id)
      if target.nil?
        push_line("User not found.")
        return redirect('/')
      end

      if target["is_admin"].to_i == 1
        push_line("Cannot delete another admin.")
        return redirect('/')
      end

      MODEL.delete_user_with_characters(target_id)
      push_line("User #{target["name"]} deleted.")
      return redirect('/')
    end
  end


  if session[:ui_state] == 'intro_choice'
    load_game_state
    choice = input.strip

    if choice == "1" || choice == "2"
      out = capture_output { apply_intro_choice(choice) }
    else
      out = capture_output { apply_intro_choice("3") }
    end
      append_captured_output(out)
    session[:ui_state] = 'game'
    session[:game] = snapshot_game_state
    return redirect('/')
  end

  if session[:ui_state] == 'character_create'
    name = input.strip
    if name.length < 3 || name.length > 20 || name.include?(" ")
      push_line("Invalid name. Use 3-20 chars, no spaces.")
    else
      character_id = MODEL.create_character_for_user(session[:user_id], name)
      session[:character_id] = character_id
      session[:ui_state] = 'game'
      session.delete(:game)

      game_initialize
      @playername = name
      session[:game] = snapshot_game_state

      push_line("Character '#{name}' created and selected.")
      push_line('Type "help" for commands.')
      session[:ui_state] = 'intro_choice'
      intro_out = capture_output { introduction_dialogue_web_intro_only }
      append_captured_output(intro_out)
    end
    redirect('/')
  end

  if session[:character_id].nil?
    case command
    when 'help'
      push_line("Character commands: list, create, select <id>, delete <id>")
    when 'list'
      print_character_menu
    when 'create'
      session[:ui_state] = 'character_create'
      push_line("Enter your new character name:")
    when 'select'
      char_id = params_arr.first.to_i
      owned = MODEL.user_owns_character?(session[:user_id], char_id)
      if owned
        character = MODEL.find_character(char_id)
        session[:character_id] = char_id
        session[:ui_state] = 'game'
        session.delete(:game)

        game_initialize
        @playername = character["name"]
        session[:game] = snapshot_game_state

        push_line("Selected '#{@playername}'.")
        push_line('Type "help" for commands.')
        describe_out = capture_output { describe_room }
        append_captured_output(describe_out)
      else
        push_line("Invalid character id.")
      end
    when 'delete'
      char_id = params_arr.first.to_i
      owned = MODEL.user_owns_character?(session[:user_id], char_id)
      if owned
        MODEL.delete_character(char_id)
        push_line("Character deleted.")
      else
        push_line("Invalid character id.")
      end
    else
      push_line("Pick a character first. Type 'list' or 'create'.")
    end

    return redirect('/')
  end

  # Game mode
  load_game_state

  game_out = capture_output do
    case command
    when 'look' then describe_room
    when 'go', 'move' then move_to(params_arr.join(' '))
    when 'take', 'get' then take_item(params_arr.join(' '))
    when 'use' then use_item(params_arr.join(' '))
    when 'equip' then equip(params_arr.join(' '))
    when 'unequip' then unequip(params_arr.join(' '))
    when 'inventory', 'items' then show_inventory
    when 'stats' then show_stats
    when 'help' then show_help
    when 'quit', 'exit'
      session[:character_id] = nil
      session[:ui_state] = 'character_menu'
      session.delete(:game)
      puts "You leave the adventure."
      print_character_menu
    when 'characters'
      session[:character_id] = nil
      session[:ui_state] = 'character_menu'
      puts "Returned to character menu."
      print_character_menu
    else
      puts "I don't understand that command."
    end
  end

  append_captured_output(game_out)
  session[:game] = snapshot_game_state

  MODEL.update_character_stats(
    character_id: session[:character_id],
    level: @level,
    xp: @experience,
    hp: @health,
    max_hp: [@health, 10].max
  )
  redirect('/')
end

# @param seconds [Numeric] delay duration
# @return [void]
def web_sleep(seconds)
  puts "__SLEEP__:#{seconds}"
end

# @param text [String] output line text
# @param delay_ms [Integer] reveal delay in milliseconds
# @return [void]
def push_line(text, delay_ms: 0)
  session[:terminal_output] ||= []
  show_at = (Time.now.to_f * 1000).to_i + delay_ms
  session[:terminal_output] << { "text" => text.to_s, "show_at" => show_at }
  session[:terminal_output] = session[:terminal_output].last(300)
end

# @param output [String] captured stdout text
# @return [void]
def append_captured_output(output)
  delay_ms = 0

  output.to_s.each_line do |raw|
    line = raw.chomp
    next if line.strip.empty?

    if line.start_with?("__SLEEP__:")
      seconds = line.split(":", 2).last.to_f
      delay_ms += (seconds * 1000).to_i
    else
      push_line(line, delay_ms: delay_ms)
    end
  end
end

helpers do
  

  def current_character
    return nil if session[:character_id].nil?
    MODEL.find_character(session[:character_id])
  end


  def player_name
    @playername.to_s.empty? ? "Unknown" : @playername
  end

  def ensure_terminal
    session[:terminal_output] ||= []
    session[:ui_state] ||= 'character_menu'
    session[:terminal_booted] ||= false
  end


  def capture_output
    old_stdout = $stdout
    buffer = StringIO.new
    $stdout = buffer
    yield
    buffer.string
    ensure
    $stdout = old_stdout
  end

  def characters_for_user(user_id)
    MODEL.characters_for_user(user_id)
  end


  def print_character_menu
    chars = characters_for_user(session[:user_id])

    if chars.empty?
      push_line("No characters found.")
      push_line("Create a character.")
    else
      chars.each { |c| push_line("[#{c['id']}] #{c['name']}") }
      push_line("select <id>")
      push_line("create")
      push_line("delete <id>")
    end
    push_line("Type 'help' for a list of commands.")
  end

  def snapshot_game_state
    {
      'game_over' => @game_over,
      'current_room' => @current_room.to_s,
      'player_inventory' => @player_inventory,
      'game_state' => @game_state,
      'level' => @level,
      'experience' => @experience,
      'playername' => @playername,
      'health' => @health,
      'time' => @time,
      'day' => @day,
      'thehour' => @thehour,
      'theminute' => @theminute,
      'equipped_weapon' => @equipped_weapon,
      'enemies' => @enemies
    }
  end

  def load_game_state
    g = session[:game] || {}
    @game_over = g['game_over']
    @current_room = (g['current_room'] || 'battlefield').to_sym
    @player_inventory = g['player_inventory'] || []
    @game_state = g['game_state'] || {}
    @level = g['level'] || 1
    @experience = g['experience'] || 0
    @playername = g['playername'] || ""
    @health = g['health'] || 10
    @time = g['time'] || 'afternoon'
    @day = g['day'] || 1
    @thehour = g['thehour'] || 13
    @theminute = g['theminute'] || 10
    @equipped_weapon = g['equipped_weapon']
    @enemies = g['enemies'] || {
      "stragglers" => { hp: 15, damage: 3, xp: 10 },
      "imperialscout" => { hp: 20, damage: 5, xp: 15 },
      "mercenary" => { hp: 25, damage: 6, xp: 20 }
    }
  end

  def colorize(text, _color)
      text
  end
end

# @return [Hash<Symbol, String>]
COLORS = {
  red: "\e[31m",
  green: "\e[32m",
  yellow: "\e[33m",
  blue: "\e[34m",
  magenta: "\e[35m",
  cyan: "\e[36m",
  reset: "\e[0m"
}

# @return [void]
def game_initialize
  @game_over = false
  @current_room = :battlefield
  @player_inventory = []
  @game_state = {
    robbert_trust: 0,
    knows_about_invasion: false,
    found_parents: false,
    boulder_event: false,
    hearing_fighting_battlefield: false,
    next_to_robbert: true,
    at_battlefield: true,
    equipped_chestplate: false,
    equipped_helmet: false,
    equipped_leggings: false,
    name_lie: false,
    yourself_question: false
  }
  
  @level = 1
  @experience = 0
  @playername = ""
  @health = rand(5..10)
  @time = "afternoon"
  @day = 1
  @thehour = 13
  @theminute = 10
  @enemies = {
    "stragglers" => { hp: 15, damage: 3, xp: 10 },
    "imperialscout" => { hp: 20, damage: 5, xp: 15 },
    "mercenary" => { hp: 25, damage: 6, xp: 20 }
  }
end

# @return [void]
def start
  character_creation
  introduction_dialogue  
  puts "\nType 'help' for a list of commands.\n"
  game_loop
end

# @return [void]
def character_creation
  system('cls')
  web_sleep(1)
  puts "???: What's your name, kid?"
  web_sleep(1)
  puts "#{colorize('He stretches out his war-torn hand.', :green)}"
  @playername = gets.chomp
  web_sleep(1)
  puts "#{colorize('*You grab his hand and pull yourself up*', :green)}"
  web_sleep(2)
  puts "You: My name is #{player_name}."
  web_sleep(2)
  if @playername.length > 10
    puts "???: What?? That's too long!\n???: At least give me a nickname I can use!"
    @playername = gets.chomp
  end

  while @playername.include?("Brutus") || @playername.length >= 10 || @playername.length <= 2 || @playername.include?(' ')
    puts "???: Stop lying. No parent would name their child that."
    sleep 0.7
    if !@game_state[:name_lie]
      @game_state[:robbert_trust] -= 2
      @game_state[:name_lie] = true
    end
    puts "???: What's your actual name?"
    @playername = gets.chomp
  end

  firstletter = @playername[0]&.upcase
  case firstletter
  when "S"
    puts "???: #{player_name}, huh? Strong name. Don't worry, I've been on more battlefields than you can count. I'll get you out of here."
  when "G"
    puts "???: #{player_name}, huh..?"
    puts "#{colorize('He looks at you strangely', :green)}."
  when "J"
    puts "???: #{player_name}, huh? An honorable name. I can tell you'll be great. Don't worry, I've been on more battlefields than you can count. I'll get you out of here."
  when "H"
    puts "???: #{player_name}, huh? A name of vice. Don't worry, I've been on more battlefields than you can count. I'll get you out of here."
  when "A"
    puts "???: #{player_name}, huh? A wise name. Don't worry, I've been on more battlefields than you can count. I'll get you out of here."
  when "N"
    puts "???: #{player_name}, huh? An interesting name. Don't worry, I've been on more battlefields than you can count. I'll get you out of here."
  when "R"
    puts "???: #{player_name}, huh? Peculiar name. Don't worry, I've been on more battlefields than you can count. I'll get you out of here."
  when "X"
    puts "???: #{player_name}..? Fascinating name. 'X' just so happens to be my favorite letter. I can tell we'll get along well."
  else
    puts "???: #{player_name}, huh? Don't worry, I've been on more battlefields than you can count. I'll get you out of here."
  end
end

# @return [void]
def game_loop
  until @game_over
    print "> "
    input = gets.chomp.downcase.strip
    
    next if handle_special_commands(input)
    
    command, *params = input.split
    case command
    when 'look'
      describe_room
    when 'go', 'move'
      direction = params.first
      move_to(direction)
    when 'talk', 'ask'
      topic = params.join(' ')
      handle_dialogue(topic)
    when 'take', 'get'
      item = params.join(' ')
      take_item(item)
    when 'use'
      item = params.join(' ')
      use_item(item)
    when 'equip'
      item = params.join(' ')
      equip(item)
    when 'inventory', 'items'
      show_inventory
    when 'attack'
      enemy = params.join(' ')
      enemy_types = ["Stragglers", "Imperial Scout", "Mercenary"]
      nevermind = ["no", "nevermind", "stop", "quit"]
      if !enemy_types.include?(enemy)
        puts "Who are you attacking?"
        puts "Valid choices:\nStragglers\nMercenary\nImperial Scout"
        print "> "
        enemy = gets.chomp.downcase.strip
        if nevermind.include?(enemy)
          puts "Tragedy averted."
        end
          
      end
      initiate_combat(enemy)
    when 'stats'
      show_stats
    when 'wait'
      advance_time
    when 'unequip'
      item = params.join(' ')
      unequip(item)
    when 'help'
      show_help
    when 'quit', 'exit'
      @game_over = true
    when 'listen'
      ''
    else
      puts "I don't understand that command."
    end
  end
  puts "Thanks for playing, #{player_name}."
end

# @return [void]
def introduction_dialogue
  web_sleep(4)
  if @playername[0]&.upcase == "G"
    puts "#{player_name}: ...Who are you?"
  else
    puts "#{player_name}: Who are you?"
  end

  puts "\n???: Who am I? The name's #{colorize('Robbert', :blue)}, a mercenary, nice to meet'cha."
  web_sleep(4)
  puts "#{colorize('Robbert', :blue)}: By the way, how'd you get in this mess? How old are you even?"
  web_sleep(4)
  
  # Player's response options
  puts "\nHow do you respond?"
  puts "1. Tell the full truth"
  puts "2. Lie about your age"
  puts "3. Stay silent"
  print "> "
  answer = gets.chomp.to_i

  case answer
  when 1
    puts "#{player_name}: I'm twelve. Both of my parents went missing some days ago."
    @game_state[:robbert_trust] += 2
    web_sleep(4)
  when 2
    puts "#{player_name}: I'm... sixteen. I got separated from my unit."
    @game_state[:robbert_trust] -= 1
    web_sleep(3)
    puts "#{colorize('Robbert', :blue)}: ...My condolences. Then again, you're probably not the only one."
    web_sleep(3)
    puts "#{colorize('Robbert', :blue)}: Wouldn't surprise me if the churches were working their asses off right now."
    web_sleep(3)
  else
    puts "#{player_name}: ..."
    puts "#{colorize('Robbert', :blue)}: Tough kid, eh? Alright then."
    web_sleep(3)
  end
  puts "#{colorize('*You take a look around*', :green)}"
  @game_state[:knows_about_invasion] = true
  web_sleep(4)
  describe_room
end

# @return [void]
def show_help
  puts "Available commands:"
  puts "clear - Clear terminal output"
  puts "look - Describe current location"
  puts "go/move [direction] - Move to new area"
  puts "search - Look for items"
  puts "listen - Listen to your surroundings"
  puts "examine - Examine something interesting"
  puts "approach - Get closer to something"
  puts "talk/ask [topic] - Ask about something"
  puts "take/get [item] - Pick up an item"
  puts "use [item] - Use an item from your inventory"
  puts "equip [item] - Equip an item"
  puts "unequip [item] - Unequip an item"
  puts "inventory/items - Show your inventory"
  puts "attack - Fight enemies"
  puts "wait - Pass time"
  puts "stats - Show your status"
  puts "help - Show this menu"
  puts "quit/exit - Return to character menu"
  if session[:is_admin]
    puts "admin_users - List all users"
    puts "admin_delete [user_id] - Delete a non-admin user"
  end

end

# @return [void]
def show_stats
  puts "#{player_name}, Level #{@level}"
  puts "health: #{@health}"
  puts "Experience: #{@experience}/#{@level * 10}"
  puts "Weapon: #{current_weapon[:name]} (#{current_weapon[:damage]} damage)"
end

# @param enemy [String] enemy key/name input
# @return [Boolean, void] false when cancelled/invalid, otherwise nil
def initiate_combat(enemy)
  nevermind = ["no", "nevermind", "stop", "exit", "quit"]
  
  if nevermind.include?(enemy) || !@enemies.key?(enemy.downcase)
    return false
  end
  
  enemy_key = enemy.downcase  
  puts "\nYou encounter #{enemy}! Battle begins!"
  @game_state[:next_to_robbert] = false
  enemy_stats = @enemies[enemy_key]
  enemy_hp = enemy_stats[:hp]
  
  while enemy_hp > 0
    puts "\nEnemy HP: #{enemy_hp}"
    puts "Your HP: #{@health}"
    puts "\nWhat will you do?"
    puts "1. Attack"
    puts "2. Run"
    print "> "
    choice = gets.strip.to_s.downcase
    
    case choice
    when "1", "attack"
      puts ""
      player_damage = current_weapon[:damage] + rand(1..3)
      puts "You attack with your #{current_weapon[:name]} and deal #{player_damage} damage!"
      enemy_hp -= player_damage
      
      if enemy_hp <= 0
        puts "You defeated the #{enemy}!"
        gain_experience(enemy_stats[:xp])
        loot_chance(enemy)
        @game_state[:next_to_robbert] = true
        break
      end
      
      enemy_damage = enemy_stats[:damage] + rand(0..2)
      puts "The #{enemy} attacks you for #{enemy_damage} damage!"
      @health -= enemy_damage
      
      if @health <= 0
        puts "You have been defeated..."
        @game_over = true
        break
      end
    when "2", "run"
      escape_chance = rand(1..10)
      if escape_chance > 5
        puts "You managed to escape!"
        break
      else
        puts "You couldn't escape!"
        enemy_damage = enemy_stats[:damage] + rand(0..2)
        puts "The #{enemy} attacks you for #{enemy_damage} damage!"
        @health -= enemy_damage
        
        if @health <= 0
          puts "You have been defeated..."
          @game_over = true
          break
        end
      end
    else
      puts "Invalid choice!"
    end
  end
end

# @param enemy [String] defeated enemy key
# @return [void]
def loot_chance(enemy)
  chance = rand(1..10)
  case enemy
  when "stragglers"
    if chance > 7
      puts "You found some bandages!"
      @player_inventory << "bandages"
    end
  when "imperial_scout"
    if chance > 5 && !@player_inventory.include?("spear")
      puts "You found an Imperial Spear!"
      @player_inventory << "spear"
    end
  when "mercenary"
    if chance > 3
      roll = rand(1..3)
      if roll == 1 && !@player_inventory.include?("Iron Helmet")
        puts "You found an iron helmet!"
        @player_inventory << "Iron Helmet"
      else 
        roll = rand(2..3)
      end
      if roll == 2 && !@player_inventory.include?("Iron Chestplate")
        puts "You found an iron chestplate!"
        @player_inventory << "Iron Chestplate"
      else
        roll = 3
      end
      if roll == 3 && !@player_inventory.include?("Iron Leggings")
        puts "You found iron leggings!"
        @player_inventory << "Iron Leggings"
      end
      if @player_inventory.include?("Iron Helmet", "Iron Chestplate", "Iron Leggings")
        puts "Nothing worth taking."
      end
    end
  end
end

# @param xp [Integer] amount of experience gained
# @return [void]
def gain_experience(xp)
  @experience += xp
  puts "You gained #{xp} experience points!"
  
  if @experience >= @level * 10
    level_up
  end
end

# @return [void]
def level_up
  @level += 1
  @health += 3
  @experience = 0
  puts "You leveled up! You are now level #{@level}!"
  puts "Your health increased to #{@health}!"
end

# @return [void]
def describe_room
  case @current_room
  when :battlefield
    puts "\nDay #{@day}, #{@time.capitalize}:  \nA horrendous sight."
    web_sleep(1.2)
    puts "You start to wonder if it was all really worth it in the end."
    web_sleep(3)
    puts "A mercenary is staring at you from the ground."
    web_sleep(1)
    puts "And another."
    web_sleep(1)
    puts "And another."
    web_sleep(2)
    puts "You hold your head high." 
    web_sleep(1)
   
  when :boulder_site
    puts "\n"
    puts "The massive meteor-like boulder dominates the landscape. The boulder, charred and bloody, bears properties of both metal and stone."
    puts "The colossal stone dwarfed the corpses half-buried under the boulder, causing you to miss them at first glance."  
  end
end

# @param direction [String, nil] parsed direction argument
# @return [void]
def move_to(direction)
  case [@current_room, direction] 
  when [:battlefield, "toward fighting"], [:battlefield, "fighting"], [:battlefield, "toward"]
    if @game_state[:hearing_fighting_battlefield]
    puts "You move toward the sounds of clashing steel..."
    initiate_combat("stragglers")
    else
      "You seem to be a bit out of it."
    end
  
  when [:battlefield, "northeast"], [:battlefield, "ne"], [:battlefield, "boulder"]
    if @game_state[:boulder_event] && !@game_state[:found_parents]
      @current_room = :boulder_site
      puts "You move towards the massive boulder"
    else
      puts "You don't see anything interesting in that direction."
    end
  
  when [:boulder_site, "return"], [:boulder_site, "back"], [:boulder_site, "battlefield"]
    @current_room = :battlefield
    puts "You return to the main battlefield."
  else
    puts "You can't go that way."
  end
end

# @param item [String] item name/key
# @return [void]
def take_item(item)
  case [@current_room, item]
  when [:battlefield, 'sword']
    if !@player_inventory.include?('sword')
      @player_inventory << 'sword'
      puts "You take the sword."
    else
      puts "You already have a sword."
    end
  when [:battlefield, 'spear']
    if !@player_inventory.include?('spear')
      @player_inventory << 'spear'
      puts "You take the spear."
    else
      puts "You already have a spear."
    end
  when [:boulder_site, 'pendant']
    if @game_state[:found_parents] && !@player_inventory.include?('pendant')
      @player_inventory << 'pendant'
      puts "You take your family pendant from your parents' remains."
      puts "#{colorize('Robbert', :blue)} watches silently, his face grim with determination."
    else
      puts "I don't see that here."
    end
  else
    puts "I don't see that here."
  end
end

# @return [Hash{Symbol=>Object}] weapon name and damage
def current_weapon
  if @player_inventory.include?("spear") && @equipped_weapon == "spear"
    {name: "spear", damage: 10}
  elsif @player_inventory.include?("sword") && (@equipped_weapon == "sword" || @equipped_weapon.nil?)
    {name: "sword", damage: 8}
  else
    {name: "fists", damage: 3}
  end
end

# @return [void]
def show_inventory
  if @player_inventory.empty?
    puts "Your inventory is empty."
  else
    puts "You are carrying:"
    @player_inventory.each { |item| puts "- #{item}" }
  end
end

# @param item [String] item name/key
# @return [void]
def equip(item)
  weapons = ['spear', 'sword', 'fist']
  armor = ['Iron Helmet', 'Iron Chestplate', 'Iron Leggings']
  if @player_inventory.include?(item) && weapons.include?(item)
    puts "You equip the #{item}."
    @equipped_weapon = item
  elsif @player_inventory.include?(item) && armor.include?(item)
    puts "You equip the #{item}."
    if item == 'Iron Helmet' && @game_state[:equipped_helmet] == false
      @game_state[:equipped_helmet] = true
      @health += 3
    elsif item == 'Iron Chestplate' && @game_state[:equipped_chestplate] == false
      @game_state[:equipped_chestplate] = true
      @health += 5
    elsif item == 'Iron Leggings' && @game_state[:equipped_leggings] == false
      @game_state[:equipped_leggings] = true
      @health += 4
    end
  elsif item == "fist"
    puts "#{colorize('You throw your weapon to the ground, now armed and dangerous.', :green)}"
  else
    puts "You can't equip that."
  end
end

# @param item [String] item name/key
# @return [void]
def unequip(item)
  weapons = ['spear', 'sword', 'fist']
  armor = ['Iron Helmet', 'Iron Chestplate', 'Iron Leggings']
  if @player_inventory.include?(item) && weapons.include?(item)
    puts "You unequip the #{item}."
    @equipped_weapon = 'fist'
  elsif @player_inventory.include?(item) && armor.include?(item)
    puts "You unequip the #{item}."
    if item == 'Iron Helmet' && @game_state[:equipped_helmet] == true
      @game_state[:equipped_helmet] = false
      @health -= 3
    elsif item == 'Iron Chestplate' && @game_state[:equipped_chestplate] == true
      @game_state[:equipped_chestplate] = false
      @health -= 5
    elsif item == 'Iron Leggings' && @game_state[:equipped_leggings] == true
      @game_state[:equipped_leggings] = false
      @health -= 4
    end
  end
end

# @param item [String] item name/key
# @return [void]
def use_item(item)
  if @player_inventory.include?(item)
    case item
    when 'sword'
      puts "You take a stance, imagining an enemy. The only thing they fear is you."
    when 'spear'
      puts "A finely crafted spear glimmers even in the darkest depths."
    when 'bandages'
      heal_amount = rand(3..5)
      @health += heal_amount
      @player_inventory.delete('bandages')
      puts "You use the bandages to heal #{heal_amount} health. Your health is now #{@health}."
    else
      puts "You use the #{item}, but nothing happens."
    end
  else
    puts "You don't have that item."
  end
end



