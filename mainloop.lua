local logger = require("logger")
local select_screen = require("select_screen.select_screen")
local replay_browser = require("replay_browser")
local options = require("options")
local utf8 = require("utf8")
local analytics = require("analytics")
local main_config_input = require("config_inputs")
local tableUtils = require("tableUtils")
local Game = require("Game")
local util = require("util")
require("replay")

local mobile = false
if love.system.getOS() == 'iOS' or love.system.getOS() == 'Android' then
  mobile = true
end

local wait, resume = coroutine.yield, coroutine.resume

local main_endless_select, main_timeattack_select, makeSelectPuzzleSetFunction, main_net_vs_setup, main_select_puzz, main_local_vs_setup, main_set_name, main_local_vs_yourself_setup, exit_game, training_setup

local PLAYING = "playing" -- room states
local CHARACTERSELECT = "character select" -- room states
connection_up_time = 0 -- connection_up_time counts "E" messages, not seconds
logged_in = 0
GAME.connected_server_ip = nil -- the ip address of the server you are connected to
GAME.connected_network_port = nil -- the port of the server you are connected to
my_user_id = nil -- your user id
leaderboard_report = nil
replay_of_match_so_far = nil -- current replay of spectatable replay
spectator_list = nil
spectators_string = ""
leftover_time = 0
local wait_game_update = nil
local has_game_update = false
local main_menu_last_index = 1
local puzzle_menu_last_index = 3

function fmainloop()
  local func, arg = main_title, nil
  if GAME.portrait_mode == nil then --portrait_mode function hasn't run yet
    if mobile and (config.portraitMode == nil) then --portrait mode preference was never saved, default true on mobile
      portrait_mode(true) 
    else
      portrait_mode(config.portraitMode) --fine if we pass nil here.
    end
  end
  if config.inputMethod == nil then
    if mobile then
      config.inputMethod = "touch"
    else
      config.inputMethod = "controller"
    end
  end
  while true do
    leftover_time = 1 / 120 -- prevents any left over time from getting big transitioning between menus
---@diagnostic disable-next-line: redundant-parameter
    func, arg = func(unpack(arg or {}))
    GAME.showGameScale = false
    if GAME.needsAssetReload then
      GAME:refreshCanvasAndImagesForNewScale()
      GAME.needsAssetReload = false
    end
    collectgarbage("collect")
    logger.trace("Transitioning to next fmainloop function")
  end
end

-- Wrapper for doing something at 60hz
-- The rest of the stuff happens at whatever rate is convenient
-- Note there should only be one of these in the current loop as it handles key input ect.
function variable_step(f)
  for i = 1, 4 do
    if leftover_time >= 1 / 60 then
      joystick_ax()
      f()
      key_counts()
      this_frame_keys = {}
      this_frame_released_keys = {}
      this_frame_unicodes = {}

      leftover_time = leftover_time - 1 / 60
      if leftover_time >= 1 / 60 then
        GAME.droppedFrames = GAME.droppedFrames + 1
      end
    end
  end
end

local function titleDrawPressStart(percent) 
  local textMaxWidth = canvas_width - 40
  local textHeight = 40
  local x = (canvas_width / 2) - (textMaxWidth / 2)
  local y = canvas_height * 0.75
  gprintf(loc("continue_button"), x, y, textMaxWidth, "center", {1,1,1,percent}, nil, 16)
end

function main_title()

  if not themes[config.theme].images.bg_title then
    return main_select_mode
  end

  GAME.backgroundImage = themes[config.theme].images.bg_title
  
  local ret = nil
  local percent = 0
  local incrementAmount = 0.01
  local decrementAmount = 0.02
  local increment = incrementAmount

  local totalTime = 0
  while true do
    titleDrawPressStart(percent)
    local lastTime = leftover_time
    wait()
    totalTime = totalTime + (leftover_time - lastTime)
    variable_step(
      function()
        if increment > 0 and percent >= 1 then
          increment = -decrementAmount
        elseif increment < 0 and percent <= 0.5 then
          increment = incrementAmount
        end
        percent =  util.bound(0, percent + increment, 1)
        
        if love.mouse.isDown(1, 2, 3) or #love.touch.getTouches() > 0 or (tableUtils.length(this_frame_released_keys) > 0 and totalTime > 0.1) then
          ret = {main_select_mode}
        end
      end
    )
    if ret then
      return unpack(ret)
    end
  end
end

do
  function main_select_mode()
    CLICK_MENUS = {}
    if next(currently_playing_tracks) == nil then
      stop_the_music()
      if themes[config.theme].musics["main"] then
        find_and_add_music(themes[config.theme].musics, "main")
      end
    end
    character_loader_clear()
    stage_loader_clear()
    resetNetwork()
    undo_stonermode()
    GAME.backgroundImage = themes[config.theme].images.bg_main
    GAME.battleRoom = nil
    GAME.input:clearInputConfigurationsForPlayers()
    GAME.input:requestPlayerInputConfigurationAssignments(1)
    reset_filters()
    local menu_x, menu_y = unpack(themes[config.theme].main_menu_screen_pos)
    local main_menu
    local ret = nil
    GAME.rich_presence:setPresence(nil, nil, true)
    local function goEscape()
      main_menu:set_active_idx(#main_menu.buttons)
    end

    local function selectFunction(myFunction, args)
      local function constructedFunction()
        main_menu_last_index = main_menu.active_idx
        main_menu:remove_self()
        ret = {myFunction, args}
      end
      return constructedFunction
    end

    match_type_message = ""
    local items = {
      {loc("mm_1_endless"), main_endless_select},
      {loc("mm_1_puzzle"), main_select_puzz},
      {loc("mm_1_time"), main_timeattack_select},
      {loc("mm_1_vs"), main_local_vs_yourself_setup},
      {loc("mm_1_training"), training_setup},
      --{loc("mm_2_vs_online", "burke.ro"), main_net_vs_setup, {"burke.ro"}},
      --{loc("mm_2_vs_online", ""), main_net_vs_setup, {"18.188.43.50"}},
      --{loc("mm_2_vs_online", "Shosoul's Server"), main_net_vs_setup, {"149.28.227.184"}},
      --{loc("mm_2_vs_online", ""), main_net_vs_setup, {"betaserver.panelattack.com", 59569}},
      {loc("mm_2_vs_online", "devserver.panelattack.com"), main_net_vs_setup, {"devserver.panelattack.com", 59568}},
      --{loc("mm_2_vs_online", "(USE ONLY WITH OTHER CLIENTS ON THIS TEST BUILD 025beta)"), main_net_vs_setup, {"18.188.43.50"}},
      --{loc("mm_2_vs_online", "This test build is for offline-use only"), main_select_mode},
      --{loc("mm_2_vs_online", "domi1819.xyz"), main_net_vs_setup, {"domi1819.xyz"}},
      --{loc("mm_2_vs_online", "(development-use only)"), main_net_vs_setup, {"localhost"}},
      --{loc("mm_2_vs_online", "LittleEndu's server"), main_net_vs_setup, {"51.15.207.223"}},
      --{loc("mm_2_vs_online", "server for ranked Ex Mode"), main_net_vs_setup, {"exserver.panelattack.com", 49568}},
      {loc("mm_2_vs_local"), main_local_vs_setup},
      {loc("mm_replay_browser"), replay_browser.main},
      {loc("mm_configure"), main_config_input},
      {loc("mm_set_name"), main_set_name},
      {loc("mm_options"), options.main}
    }

    if TESTS_ENABLED then
      table.insert(items, 6, {"Vs Computer", main_local_vs_computer_setup})
    end

    main_menu = Click_menu(menu_x, menu_y, nil, themes[config.theme].main_menu_max_height, main_menu_last_index)
    for i = 1, #items do
      main_menu:add_button(items[i][1], selectFunction(items[i][2], items[i][3]), goEscape)
    end
    main_menu:add_button(loc("mm_fullscreen", "(LAlt+Enter)"), fullscreen, goEscape)
    --main_menu:add_button("Portrait mode: " --[[to do: loc("mm_portrait_mode")]].. ((GAME.portrait_mode and "on") or "off"), handlePortraitModeToggle, goEscape)
    main_menu:add_button(loc("mm_quit"), exit_game, exit_game)

    while true do

      main_menu:draw()

      if wait_game_update ~= nil then
        has_game_update = wait_game_update:pop()
        if has_game_update ~= nil and has_game_update then
          wait_game_update = nil
          GAME_UPDATER_GAME_VERSION = "NEW VERSION FOUND! RESTART THE GAME!"
        end
      end
      
      local fontHeight = get_global_font():getHeight()
      local infoYPosition = canvas_height - 30 - fontHeight/2

      local loveString = Game.loveVersionString()
      if loveString == "11.3.0" then
        gprintf(loc("love_version_warning"), -5, infoYPosition, canvas_width, "right")
        infoYPosition = infoYPosition - fontHeight
      end

      if GAME_UPDATER_GAME_VERSION then
        gprintf("PA Version: " .. GAME_UPDATER_GAME_VERSION, -5, infoYPosition, canvas_width, "right")
        infoYPosition = infoYPosition - fontHeight
        if has_game_update then
          menu_draw(panels[config.panels].images.classic[1][1], 1262, 685)
        end
      end

      wait()

      variable_step(
        function()
          main_menu:update()
        end
      )
      if ret then
        return unpack(ret)
      end
    end
  end
end

local function use_current_stage()
  if current_stage == nil then
    pick_random_stage()
  else
    stage_loader_load(current_stage)
    stage_loader_wait()
    GAME.backgroundImage = UpdatingImage(stages[current_stage].images.background, false, 0, 0, canvas_width, canvas_height)
    GAME.background_overlay = themes[config.theme].images.bg_overlay
    GAME.foreground_overlay = themes[config.theme].images.fg_overlay
  end
end

function pick_random_stage()
  current_stage = tableUtils.getRandomElement(stages_ids_for_current_theme)
  if stages[current_stage]:is_bundle() then -- may pick a bundle!
    current_stage = tableUtils.getRandomElement(stages[current_stage].sub_stages)
  end
  use_current_stage()
end

local function pick_use_music_from()
  if config.use_music_from == "stage" or config.use_music_from == "characters" then
    current_use_music_from = config.use_music_from
    return
  end
  local percent = math.random(1, 4)
  if config.use_music_from == "either" then
    current_use_music_from = percent <= 2 and "stage" or "characters"
  elseif config.use_music_from == "often_stage" then
    current_use_music_from = percent == 1 and "characters" or "stage"
  else
    current_use_music_from = percent == 1 and "stage" or "characters"
  end
end

function Stack.wait_for_random_character(self)
  if self.character == random_character_special_value then
    self.character = tableUtils.getRandomElement(characters_ids_for_current_theme)
  end
  if characters[self.character]:is_bundle() then -- may have picked a bundle
    self.character = tableUtils.getRandomElement(characters[self.character].sub_characters)
  end
  character_loader_load(self.character)
  character_loader_wait()
end

local function commonGameSetup()
  stop_the_music()
  use_current_stage()
  pick_use_music_from()
end

function createNewReplay(match)
  local mode = match.mode
  local result = {}
  result.engineVersion = VERSION

  result[mode] = {}
  local modeReplay = result[mode]

  modeReplay.seed = match.seed

  if mode == "endless" or mode == "time" then
    modeReplay.do_countdown = P1.do_countdown or false
    modeReplay.speed = P1.speed
    modeReplay.difficulty = P1.difficulty
    modeReplay.cur_wait_time = P1.cur_wait_time or default_input_repeat_delay
    modeReplay.in_buf = ""
  elseif mode == "vs" then
    modeReplay.P = ""
    modeReplay.O = ""
    modeReplay.I = ""
    modeReplay.Q = ""
    modeReplay.in_buf = ""
    modeReplay.P1_level = P1.level
    modeReplay.P1_inputMethod = P1.inputMethod or "controller"
    modeReplay.P1_name = GAME.battleRoom.playerNames[1]
    modeReplay.P1_char = P1.character
    modeReplay.P1_char = P1.character
    modeReplay.P1_cur_wait_time = P1.cur_wait_time
    modeReplay.do_countdown = true
    if P2 then
      modeReplay.P2_level = P2.level
      modeReplay.P2_inputMethod = P2.inputMethod or "controller"
      modeReplay.P2_name = GAME.battleRoom.playerNames[2]
      modeReplay.P2_char = P2.character
      modeReplay.P2_cur_wait_time = P2.cur_wait_time

      modeReplay.P1_win_count = GAME.match.battleRoom.playerWinCounts[P1.player_number]
      modeReplay.P2_win_count = GAME.match.battleRoom.playerWinCounts[P2.player_number]
    end
  end

  return result
end

local function handle_pause(self)
  if GAME.match.supportsPause then
    if menu_pause() or (not GAME.focused and not GAME.gameIsPaused) then
      GAME.gameIsPaused = not GAME.gameIsPaused

      setMusicPaused(GAME.gameIsPaused)

      if not GAME.renderDuringPause then
        if GAME.gameIsPaused then
          reset_filters()
        else
          use_current_stage()
        end
      end
    end
  end
end

local function finalizeAndWriteReplay(extraPath, extraFilename)

  replay[GAME.match.mode].in_buf = P1.confirmedInput

  local now = os.date("*t", to_UTC(os.time()))
  local sep = "/"
  local path = "replays" .. sep .. "v" .. VERSION .. sep .. string.format("%04d" .. sep .. "%02d" .. sep .. "%02d", now.year, now.month, now.day)
  if extraPath then
    path = path .. sep .. extraPath
  end
  local filename = "v" .. VERSION .. "-" .. string.format("%04d-%02d-%02d-%02d-%02d-%02d", now.year, now.month, now.day, now.hour, now.min, now.sec)
  if extraFilename then
    filename = filename .. "-" .. extraFilename
  end
  filename = filename .. ".txt"
  logger.info("saving replay as " .. path .. sep .. filename)
  write_replay_file(path, filename)
end

local function finalizeAndWriteVsReplay(battleRoom, outcome_claim, incompleteGame)

  incompleteGame = incompleteGame or false
  
  local extraPath, extraFilename = "", ""

  if GAME.match:warningOccurred() then
    extraFilename = extraFilename .. "-WARNING-OCCURRED"
  end

  if P2 then
    replay[GAME.match.mode].I = P2.confirmedInput

    local rep_a_name, rep_b_name = battleRoom.playerNames[1], battleRoom.playerNames[2]
    --sort player names alphabetically for folder name so we don't have a folder "a-vs-b" and also "b-vs-a"
    if rep_b_name < rep_a_name then
      extraPath = rep_b_name .. "-vs-" .. rep_a_name
    else
      extraPath = rep_a_name .. "-vs-" .. rep_b_name
    end
    extraFilename = extraFilename .. rep_a_name .. "-L" .. P1.level .. "-vs-" .. rep_b_name .. "-L" .. P2.level
    if match_type and match_type ~= "" then
      extraFilename = extraFilename .. "-" .. match_type
    end
    if incompleteGame then
      extraFilename = extraFilename .. "-INCOMPLETE"
    else
      if outcome_claim == 1 or outcome_claim == 2 then
        extraFilename = extraFilename .. "-P" .. outcome_claim .. "wins"
      elseif outcome_claim == 0 then
        extraFilename = extraFilename .. "-draw"
      end
    end
  else -- vs Self
    extraPath = "Vs Self"
    extraFilename = extraFilename .. "vsSelf-" .. "L" .. P1.level
  end

  finalizeAndWriteReplay(extraPath, extraFilename)
end

local function runMainGameLoop(updateFunction, variableStepFunction, abortGameFunction, processGameResultsFunction)

  local returnFunction = nil
  while true do
    -- Uncomment this to cripple your game :D
    -- love.timer.sleep(0.030)

    -- Render only if we are not catching up to a current spectate match
    if not (P1 and P1.play_to_end) and not (P2 and P2.play_to_end) then
      GAME.match:render()
      wait()
    end

    returnFunction = updateFunction()
    if returnFunction then 
      return unpack(returnFunction)
    end
    
    if (P1 and P1.play_to_end) or (P2 and P2.play_to_end) then
      GAME.match:run()
    else
      variable_step(
        function()
          if not returnFunction then
            GAME.match:run()

            returnFunction = variableStepFunction()

            if not returnFunction  then
              handle_pause()

              if menu_escape_game() then
                GAME:clearMatch()
                returnFunction = abortGameFunction()
              end
            end
          end
        end
      )
    end

    if not returnFunction then
      local gameResult = P1:gameResult()
      if gameResult then
        returnFunction = processGameResultsFunction(gameResult)
      end
    end

    if returnFunction then
      undo_stonermode()
      return unpack(returnFunction)
    end
  end
end

local function main_endless_time_setup(mode, speed, difficulty, level)

  GAME.match = Match(mode)

  current_stage = config.stage
  if current_stage == random_stage_special_value then
    current_stage = nil
  end
  commonGameSetup()

  P1 = Stack{which=1, match=GAME.match, is_local=true, panels_dir=config.panels, speed=speed, difficulty=difficulty, level=level, character=config.character}

  GAME.match.P1 = P1
  P1:wait_for_random_character()
  P1.do_countdown = config.ready_countdown_1P or false
  P2 = nil

  replay = createNewReplay(GAME.match)

  P1:starting_state()

  local nextFunction = nil
  if mode == "endless" then
    nextFunction = main_endless_select
  elseif mode == "time" then
    nextFunction = main_timeattack_select
  end
  
  local function update() 
  end

  local function variableStep() 
  end

  local function abortGame() 
    return {main_dumb_transition, {nextFunction, "", 0, 0}}
  end

  local function processGameResults(gameResult) 
    local extraPath, extraFilename
    local stack = P1
    if stack.level == nil then
      if GAME.match.mode == "endless" then
        GAME.scores:saveEndlessScoreForLevel(P1.score, P1.difficulty)
        extraPath = "Endless"
        extraFilename = "Spd" .. stack.speed .. "-Dif" .. stack.difficulty .. "-endless"
      elseif GAME.match.mode == "time" then
        GAME.scores:saveTimeAttack1PScoreForLevel(P1.score, P1.difficulty)
        extraPath = "Time Attack"
        extraFilename = "Spd" .. stack.speed .. "-Dif" .. stack.difficulty .. "-timeattack"
      end
      finalizeAndWriteReplay(extraPath, extraFilename)
    end

    return {game_over_transition, {nextFunction, nil, P1:pick_win_sfx()}}
  end
  
  return runMainGameLoop, {update, variableStep, abortGame, processGameResults}

end

local function createBasicTrainingMode(name, width, height) 

  local delayBeforeStart = 150
  local delayBeforeRepeat = 900
  local attacksPerVolley = 50
  local attackPatterns = {}

  for i = 1, attacksPerVolley do
    attackPatterns[#attackPatterns+1] = {width = width, height = height, startTime = i, metal = false, chain = false, endsChain = false}
  end

  local customTrainingModeData = {name = name, delayBeforeStart = delayBeforeStart, delayBeforeRepeat = delayBeforeRepeat, attackPatterns = attackPatterns}

  return customTrainingModeData
end

function training_setup()
  local trainingModeSettings = {}
  trainingModeSettings.height = 1
  trainingModeSettings.width = 4
  local customModeID = 1
  local customTrainingModes = {}
  customTrainingModes[0] = {name = "None"}
  customTrainingModes[1] = createBasicTrainingMode(loc("combo_storm"), 4, 1)
  customTrainingModes[2] = createBasicTrainingMode(loc("factory"), 6, 2)
  customTrainingModes[3] = createBasicTrainingMode(loc("large_garbage"), 6, 12)
  for customfile, value in ipairs(trainings) do
    customTrainingModes[#customTrainingModes+1] = value
  end
  
  local ret = nil
  local menu_x, menu_y = unpack(themes[config.theme].main_menu_screen_pos)

  local trainingSettingsMenu

  local function update_custom_setting()
    trainingSettingsMenu:set_button_setting(1, customTrainingModes[customModeID].name)
    trainingSettingsMenu:set_button_setting(2, "Custom")
    trainingSettingsMenu:set_button_setting(3, "Custom")
  end

  local function update_size()
    customModeID = 0
    trainingSettingsMenu:set_button_setting(1, customTrainingModes[customModeID].name)
    trainingSettingsMenu:set_button_setting(2, trainingModeSettings.width)
    trainingSettingsMenu:set_button_setting(3, trainingModeSettings.height)
  end

  local function custom_right()
    customModeID = util.bound(1, customModeID + 1, #customTrainingModes)
    update_custom_setting()
  end

  local function custom_left()
    customModeID = util.bound(1, customModeID - 1, #customTrainingModes)
    update_custom_setting()
  end

  local function increase_height()
    trainingModeSettings.height = util.bound(1, trainingModeSettings.height + 1, 69)
    update_size()
  end

  local function decrease_height()
    trainingModeSettings.height = util.bound(1, trainingModeSettings.height - 1, 69)
    update_size()
  end

  local function increase_width()
    trainingModeSettings.width = util.bound(1, trainingModeSettings.width + 1, 6)
    update_size()
  end

  local function decrease_width()
    trainingModeSettings.width = util.bound(1, trainingModeSettings.width - 1, 6)
    update_size()
  end

  local function goToStart()
    trainingSettingsMenu:set_active_idx(#trainingSettingsMenu.buttons - 1)
  end

  local function goEscape()
    trainingSettingsMenu:set_active_idx(#trainingSettingsMenu.buttons)
  end

  local function exitSettings()
    ret = {main_select_mode}
  end

  local function start_custom_game()
    customTrainingModes[0] = createBasicTrainingMode("", trainingModeSettings.width, trainingModeSettings.height)
    ret = {main_local_vs_yourself_setup, {customTrainingModes[customModeID]}}
  end

  local function nextMenu()
    trainingSettingsMenu:selectNextIndex()
  end
  
  trainingSettingsMenu = Click_menu(menu_x, menu_y, nil, themes[config.theme].main_menu_max_height, 1)
  trainingSettingsMenu:add_button("Custom", goToStart, goEscape, custom_left, custom_right)
  trainingSettingsMenu:add_button(loc("width"), nextMenu, goEscape, decrease_width, increase_width)
  trainingSettingsMenu:add_button(loc("height"), nextMenu, goEscape, decrease_height, increase_height)
  trainingSettingsMenu:add_button(loc("go_"), start_custom_game, goEscape)
  trainingSettingsMenu:add_button(loc("back"), exitSettings, exitSettings)
  trainingSettingsMenu:set_button_setting(1, customTrainingModes[customModeID].name)
  trainingSettingsMenu:set_button_setting(2, trainingModeSettings.width)
  trainingSettingsMenu:set_button_setting(3, trainingModeSettings.height)

  while true do
    trainingSettingsMenu:draw()
    wait()
    variable_step(
      function()
        trainingSettingsMenu:update()
      end
    )

    if ret then
      trainingSettingsMenu:remove_self()
      return unpack(ret)
    end
  end
end

local endlessMenuLastIndex = 1
local function main_select_speed_99(mode)
  -- stack rise speed
  local speed = nil
  local difficulty = nil
  local level = config.endless_level or nil

  local startGameSet = false
  local exitSet = false
  local loc_difficulties = {loc("easy"), loc("normal"), loc("hard"), "EX Mode"} -- TODO: localize "EX Mode"

  GAME.backgroundImage = themes[config.theme].images.bg_main
  reset_filters()
  if next(currently_playing_tracks) == nil then
    stop_the_music()
    if themes[config.theme].musics["main"] then
      find_and_add_music(themes[config.theme].musics, "main")
    end
  end

  local gameSettingsMenu, updateType, updateMenus

  local function goEscape()
    gameSettingsMenu:set_active_idx(#gameSettingsMenu.buttons)
  end

  local function exitSettings()
    endlessMenuLastIndex = 1
    exitSet = true
  end

  local function increaseSpeed(menu, button, index)
    if speed then
      speed = util.bound(1, speed + 1, 99)
      updateMenus()
    end
  end

  local function decreaseSpeed(menu, button, index)
    if speed then
      speed = util.bound(1, speed - 1, 99)
      updateMenus()
    end
  end

  local function increaseDifficulty(menu, button, index)
    difficulty = util.bound(1, (difficulty or 1) + 1, 4)
    level = nil
    speed = config.endless_speed or 1
    updateMenus()
  end

  local function decreaseDifficulty(menu, button, index)
    difficulty = util.bound(1, (difficulty or 1) - 1, 4)
    level = nil
    speed = config.endless_speed or 1
    updateMenus()
  end

  local function increaseLevel(menu, button, index)
    level = util.bound(1, (level or 1) + 1, 11)
    difficulty = nil
    speed = nil
    updateMenus()
  end

  local function decreaseLevel(menu, button, index)
    level = util.bound(1, (level or 1) - 1, 11)
    difficulty = nil
    speed = nil
    updateMenus()
  end

  local function startGame()
    if config.endless_speed ~= speed or config.endless_difficulty ~= difficulty or config.endless_level ~= level then
      config.endless_speed = speed
      config.endless_difficulty = difficulty
      config.endless_level = level
      logger.debug("saving settings...")
      wait()
      write_conf_file()
    end
    stop_the_music()
    startGameSet = true
  end

  local function nextMenu()
    gameSettingsMenu:selectNextIndex()
  end

  local function addDifficultyButtons()
    gameSettingsMenu:set_button_setting(1, loc("endless_classic"))
    gameSettingsMenu:add_button(loc("difficulty"), nextMenu, goEscape, decreaseDifficulty, increaseDifficulty)
    gameSettingsMenu:add_button(loc("speed"), nextMenu, goEscape, decreaseSpeed, increaseSpeed)
  end

  local function addLevelButtons()
    gameSettingsMenu:set_button_setting(1, loc("endless_modern"))
    gameSettingsMenu:add_button(loc("level"), nextMenu, goEscape, decreaseLevel, increaseLevel)
  end

  local function toggleType()
    if difficulty == nil then
      difficulty = config.endless_difficulty or 1
      speed = config.endless_speed or 1
      level = nil
    else
      difficulty = nil
      speed = nil
      level = config.endless_level or 1
    end

    gameSettingsMenu:remove_button(#gameSettingsMenu.buttons) -- go
    gameSettingsMenu:remove_button(#gameSettingsMenu.buttons) -- back

    if difficulty then
      gameSettingsMenu:remove_button(#gameSettingsMenu.buttons) -- level
      addDifficultyButtons()
    else
      gameSettingsMenu:remove_button(#gameSettingsMenu.buttons) -- difficulty
      gameSettingsMenu:remove_button(#gameSettingsMenu.buttons) -- speed
      addLevelButtons()
    end

    gameSettingsMenu:add_button(loc("go_"), startGame, goEscape)
    gameSettingsMenu:add_button(loc("back"), exitSettings, exitSettings)

    updateMenus()
  end

  local function updateMenuDifficulty()
    if difficulty then
      local difficultyString = ""
      if difficulty then
        difficultyString = loc_difficulties[difficulty]
      end
      gameSettingsMenu:set_button_setting(2, difficultyString)
    end
  end

  local function updateMenuSpeed()
    if difficulty then
      gameSettingsMenu:set_button_setting(3, speed)
    end
  end

  local function updateMenuLevel()
    if level then
      local levelString = ""
      if level then
        levelString = tostring(level)
      end
      gameSettingsMenu:set_button_setting(2, levelString)
    end
  end

  updateMenus = function()
    updateMenuDifficulty()
    updateMenuSpeed()
    updateMenuLevel()
    endlessMenuLastIndex = util.bound(1, #gameSettingsMenu.buttons - 1, #gameSettingsMenu.buttons)
  end

  local menu_x, menu_y = unpack(themes[config.theme].main_menu_screen_pos)
  gameSettingsMenu = Click_menu(menu_x, menu_y, nil, themes[config.theme].main_menu_max_height, endlessMenuLastIndex)
  gameSettingsMenu:add_button(loc("endless_type"), nextMenu, goEscape, toggleType, toggleType)
  addLevelButtons()
  gameSettingsMenu:add_button(loc("go_"), startGame, goEscape)
  gameSettingsMenu:add_button(loc("back"), exitSettings, exitSettings)
  if not config.endless_level then
    toggleType()
  end
  updateMenus()

  while true do

    if difficulty then
      -- Draw the current score and record
      local record = 0
      local lastScore = 0
      if mode == "time" then
        lastScore = GAME.scores:lastTimeAttack1PForLevel(difficulty)
        record = GAME.scores:recordTimeAttack1PForLevel(difficulty)
      elseif mode == "endless" then
        lastScore = GAME.scores:lastEndlessForLevel(difficulty)
        record = GAME.scores:recordEndlessForLevel(difficulty)
      end
      local xPosition1 = 520
      local xPosition2 = xPosition1 + 150
      local yPosition = gameSettingsMenu.y - 60

      lastScore = tostring(lastScore)
      record = tostring(record)
      draw_pixel_font("last score", themes[config.theme].images.IMG_pixelFont_blue_atlas, xPosition1, yPosition, 0.5, 1.0)
      draw_pixel_font(lastScore, themes[config.theme].images.IMG_pixelFont_blue_atlas, xPosition1, yPosition + 24, 0.5, 1.0)
      draw_pixel_font("record", themes[config.theme].images.IMG_pixelFont_blue_atlas, xPosition2, yPosition, 0.5, 1.0)
      draw_pixel_font(record, themes[config.theme].images.IMG_pixelFont_blue_atlas, xPosition2, yPosition + 24, 0.5, 1.0)
    end

    gameSettingsMenu:draw()

    wait()
    variable_step(
      function()
        gameSettingsMenu:update()
      end
    )

    if startGameSet then
      endlessMenuLastIndex = util.bound(1, #gameSettingsMenu.buttons - 1, #gameSettingsMenu.buttons)
      gameSettingsMenu:remove_self()
      return main_endless_time_setup, {mode, speed, difficulty, level}
    elseif exitSet then
      gameSettingsMenu:remove_self()
      return main_select_mode, {}
    end
  end
end

function main_endless_select()
  return main_select_speed_99, {"endless"}
end

function main_timeattack_select()
  return main_select_speed_99, {"time"}
end

-- The menu where you spectate / join net vs games
function main_net_vs_lobby()
  if next(currently_playing_tracks) == nil then
    stop_the_music()
    if themes[config.theme].musics["main"] then
      find_and_add_music(themes[config.theme].musics, "main")
    end
  end
  GAME.backgroundImage = themes[config.theme].images.bg_main
  GAME.battleRoom = nil
  undo_stonermode()
  reset_filters()
  character_loader_clear()
  stage_loader_clear()
  local items
  local unpaired_players = {} -- list
  local willing_players = {} -- set
  local spectatable_rooms = {}
  -- reset player ids and match type
  -- this is necessary because the player ids are only supplied on initial joining and then assumed to stay the same for consecutive games in the same room
  select_screen.my_player_number = nil
  select_screen.op_player_number = nil
  match_type = ""
  match_type_message = ""
  local notice = {[true] = loc("lb_select_player"), [false] = loc("lb_alone")}
  local leaderboard_string = ""
  local my_rank
  --attempt login
  read_user_id_file()
  if not my_user_id then
    my_user_id = "need a new user id"
  end
  local login_status_message = "   " .. loc("lb_login")
  local noticeTextObject = nil
  local noticeLastText = nil
  local login_status_message_duration = 2
  local login_denied = false
  local showing_leaderboard = false
  local lobby_menu_x = {[true] = themes[config.theme].main_menu_screen_pos[1] - 200, [false] = themes[config.theme].main_menu_screen_pos[1]} --will be used to make room in case the leaderboard should be shown.
  local lobby_menu_y = themes[config.theme].main_menu_screen_pos[2] + 10
  local sent_requests = {}
  if connection_up_time <= login_status_message_duration then
    json_send({login_request = true, user_id = my_user_id})
  end
  local lobby_menu = nil
  local items = {}
  local lastPlayerIndex = 0
  local updated = true -- need update when first entering
  local ret = nil
  local requestedSpectateRoom = nil
  local playerData = nil
  GAME.rich_presence:setPresence(nil, "In Lobby", true)
  while true do
    if connection_up_time <= login_status_message_duration then
      local messages = server_queue:pop_all_with("login_successful", "login_denied")
      for _, msg in ipairs(messages) do
        if msg.login_successful then
          current_server_supports_ranking = true
          logged_in = true
          if msg.new_user_id then
            my_user_id = msg.new_user_id
            logger.trace("about to write user id file")
            write_user_id_file()
            login_status_message = loc("lb_user_new", config.name)
          elseif msg.name_changed then
            login_status_message = loc("lb_user_update", msg.old_name, msg.new_name)
            login_status_message_duration = 5
          else
            login_status_message = loc("lb_welcome_back", config.name)
          end
        elseif msg.login_denied then
          current_server_supports_ranking = true
          login_denied = true
          --TODO: create a menu here to let the user choose "continue unranked" or "get a new user_id"
          --login_status_message = "Login for ranked matches failed.\n"..msg.reason.."\n\nYou may continue unranked,\nor delete your invalid user_id file to have a new one assigned."
          login_status_message_duration = 10
          return main_dumb_transition, {main_select_mode, loc("lb_error_msg") .. "\n\n" .. json.encode(msg), 60, 600}
        end
      end
      if connection_up_time == 2 and not current_server_supports_ranking then
        login_status_message = loc("lb_login_timeout")
        login_status_message_duration = 7
      end
    end
    local messages = server_queue:pop_all_with("choose_another_name", "create_room", "unpaired", "game_request", "leaderboard_report", "spectate_request_granted")
    for _, msg in ipairs(messages) do
      updated = true
      items = {}
      if msg.choose_another_name and msg.choose_another_name.used_names then
        return main_dumb_transition, {main_select_mode, loc("lb_used_name"), 60, 600}
      elseif msg.choose_another_name and msg.choose_another_name.reason then
        return main_dumb_transition, {main_select_mode, "Error: " .. msg.choose_another_name.reason, 60, 300}
      end
      if msg.create_room or msg.spectate_request_granted then
        GAME.battleRoom = BattleRoom()
        if msg.spectate_request_granted then
          if not requestedSpectateRoom then
            error("expected requested room")
          end
          GAME.battleRoom.spectating = true
          GAME.battleRoom.playerNames[1] = requestedSpectateRoom.a
          GAME.battleRoom.playerNames[2] = requestedSpectateRoom.b
        else
          GAME.battleRoom.playerNames[1] = config.name
          GAME.battleRoom.playerNames[2] = msg.opponent
        end
        love.window.requestAttention()
        play_optional_sfx(themes[config.theme].sounds.notification)
        lobby_menu:remove_self()
        return select_screen.main, {select_screen, "2p_net_vs", msg}
      end
      if msg.players then
        playerData = msg.players
      end
      if msg.unpaired then
        unpaired_players = msg.unpaired
        -- players who leave the unpaired list no longer have standing invitations to us.\
        -- we also no longer have a standing invitation to them, so we'll remove them from sent_requests
        local new_willing = {}
        local new_sent_requests = {}
        for _, player in ipairs(unpaired_players) do
          new_willing[player] = willing_players[player]
          new_sent_requests[player] = sent_requests[player]
        end
        willing_players = new_willing
        sent_requests = new_sent_requests
        if msg.spectatable then
          spectatable_rooms = msg.spectatable
        end
      end
      if msg.game_request then
        willing_players[msg.game_request.sender] = true
        love.window.requestAttention()
        play_optional_sfx(themes[config.theme].sounds.notification)
      end
      if msg.leaderboard_report then
        if lobby_menu then
          lobby_menu:show_controls(true)
        end
        leaderboard_report = msg.leaderboard_report
        for rank = #leaderboard_report, 1, -1 do
          local user = leaderboard_report[rank]
          if user.user_name == config.name then
            my_rank = rank
          end
        end
        leaderboard_first_idx_to_show = math.max((my_rank or 1) - 8, 1)
        leaderboard_last_idx_to_show = math.min(leaderboard_first_idx_to_show + 20, #leaderboard_report)
        leaderboard_string = build_viewable_leaderboard_string(leaderboard_report, leaderboard_first_idx_to_show, leaderboard_last_idx_to_show)
      end
    end

    local function toggleLeaderboard()
      updated = true
      if not showing_leaderboard then
        --lobby_menu:set_button_text(#lobby_menu.buttons - 1, loc("lb_hide_board"))
        showing_leaderboard = true
        json_send({leaderboard_request = true})
      else
        --lobby_menu:set_button_text(#lobby_menu.buttons - 1, loc("lb_show_board"))
        showing_leaderboard = false
        lobby_menu.x = lobby_menu_x[showing_leaderboard]
      end
    end

    -- If we got an update to the lobby, refresh the menu
    if updated then
      spectator_list = {}
      spectators_string = ""
      local oldLobbyMenu = nil
      if lobby_menu then
        oldLobbyMenu = lobby_menu
        lobby_menu:remove_self()
        lobby_menu = nil
      end

      local function commonSelectLobby()
        updated = true
        spectator_list = {}
        spectators_string = ""
        lobby_menu:remove_self()
      end

      local function goEscape()
        lobby_menu:set_active_idx(#lobby_menu.buttons)
      end

      local function exitLobby()
        commonSelectLobby()
        ret = {main_select_mode}
      end

      local function requestGameFunction(opponentName)
        return function()
          sent_requests[opponentName] = true
          request_game(opponentName)
          updated = true
        end
      end

      local function requestSpectateFunction(room)
        return function()
          requestedSpectateRoom = room
          request_spectate(room.roomNumber)
        end
      end

      local function playerRatingString(playerName)
        local rating = ""
        if playerData and playerData[playerName] and playerData[playerName].rating then
          rating = " (" .. playerData[playerName].rating .. ")"
        end
        return rating
      end
      local menuHeight = (themes[config.theme].main_menu_y_max - lobby_menu_y)
      lobby_menu = Click_menu(lobby_menu_x[showing_leaderboard], lobby_menu_y, nil, menuHeight, 1)
      for _, v in ipairs(unpaired_players) do
        if v ~= config.name then
          local unmatchedPlayer = v .. playerRatingString(v) .. (sent_requests[v] and " " .. loc("lb_request") or "") .. (willing_players[v] and " " .. loc("lb_received") or "")
          lobby_menu:add_button(unmatchedPlayer, requestGameFunction(v), goEscape)
        end
      end
      for _, room in ipairs(spectatable_rooms) do
        if room.name then
          local roomName = loc("lb_spectate") .. " " .. room.a .. playerRatingString(room.a) .. " vs " .. room.b .. playerRatingString(room.b) .. " (" .. room.state .. ")"
          --local roomName = loc("lb_spectate") .. " " .. room.name .. " (" .. room.state .. ")" --printing room names
          lobby_menu:add_button(roomName, requestSpectateFunction(room), goEscape)
        end
      end
      if showing_leaderboard then
        lobby_menu:add_button(loc("lb_hide_board"), toggleLeaderboard, toggleLeaderboard)
      else
        lobby_menu:add_button(loc("lb_show_board"), toggleLeaderboard, goEscape)
      end
      lobby_menu:add_button(loc("lb_back"), exitLobby, exitLobby)

      -- Restore the lobby selection
      -- (If the lobby only had 2 buttons it was before we got lobby info so don't restore the selection)
      if oldLobbyMenu and #oldLobbyMenu.buttons > 2 then
        if oldLobbyMenu.active_idx == #oldLobbyMenu.buttons then
          lobby_menu:set_active_idx(#lobby_menu.buttons)
        elseif oldLobbyMenu.active_idx == #oldLobbyMenu.buttons - 1 and #lobby_menu.buttons >= 2 then
          lobby_menu:set_active_idx(#lobby_menu.buttons - 1) --the position of the "hide leaderboard" menu item
        else
          local desiredIndex = util.bound(1, oldLobbyMenu.active_idx, #lobby_menu.buttons)
          local previousText = oldLobbyMenu.buttons[oldLobbyMenu.active_idx].stringText
          for i = 1, #lobby_menu.buttons do
            if #oldLobbyMenu.buttons >= i then
              if lobby_menu.buttons[i].stringText == previousText then
                desiredIndex = i
                break
              end
            end
          end
          lobby_menu:set_active_idx(desiredIndex)
        end

        oldLobbyMenu = nil
      end
    end

    if lobby_menu then
      local noticeText = notice[#lobby_menu.buttons > 2]
      if connection_up_time <= login_status_message_duration then
        noticeText = login_status_message
      end

      local noticeHeight = 0
      local button_padding = 4
      if noticeText ~= noticeLastText then
        noticeTextObject = love.graphics.newText(get_global_font(), noticeText)
        noticeHeight = noticeTextObject:getHeight() + (button_padding * 2)
        lobby_menu.yMin = lobby_menu_y + noticeHeight
        local menuHeight = (themes[config.theme].main_menu_y_max - lobby_menu.yMin)
        lobby_menu:setHeight(menuHeight)
      end
      if noticeTextObject then
        local noticeX = lobby_menu_x[showing_leaderboard] + 2
        local noticeY = lobby_menu.y - noticeHeight - 10
        local noticeWidth = noticeTextObject:getWidth() + (button_padding * 2)
        local grey = 0.0
        local alpha = 0.6
        grectangle_color("fill", noticeX / GFX_SCALE, noticeY / GFX_SCALE, noticeWidth / GFX_SCALE, noticeHeight / GFX_SCALE, grey, grey, grey, alpha)
        --grectangle_color("line", noticeX / GFX_SCALE, noticeY / GFX_SCALE, noticeWidth / GFX_SCALE, noticeHeight / GFX_SCALE, grey, grey, grey, alpha)

        menu_drawf(noticeTextObject, noticeX + button_padding, noticeY + button_padding)
      end

      if showing_leaderboard then
        gprint(leaderboard_string, lobby_menu_x[showing_leaderboard] + 400, lobby_menu_y)
      end
      gprint(join_community_msg, themes[config.theme].main_menu_screen_pos[1] + 30, canvas_height - 50)
      lobby_menu:draw()
    end
    updated = false
    wait()
    variable_step(
      function()
        if showing_leaderboard then
          if menu_up() and leaderboard_report then
            if showing_leaderboard then
              if leaderboard_first_idx_to_show > 1 then
                leaderboard_first_idx_to_show = leaderboard_first_idx_to_show - 1
                leaderboard_last_idx_to_show = leaderboard_last_idx_to_show - 1
                leaderboard_string = build_viewable_leaderboard_string(leaderboard_report, leaderboard_first_idx_to_show, leaderboard_last_idx_to_show)
              end
            end
          elseif menu_down() and leaderboard_report then
            if showing_leaderboard then
              if leaderboard_last_idx_to_show < #leaderboard_report then
                leaderboard_first_idx_to_show = leaderboard_first_idx_to_show + 1
                leaderboard_last_idx_to_show = leaderboard_last_idx_to_show + 1
                leaderboard_string = build_viewable_leaderboard_string(leaderboard_report, leaderboard_first_idx_to_show, leaderboard_last_idx_to_show)
              end
            end
          elseif menu_escape() or menu_enter() then
            toggleLeaderboard()
          end
        elseif lobby_menu then
          lobby_menu:update()
        end
      end
    )
    if ret then
      json_send({logout = true})
      return unpack(ret)
    end
    if not do_messages() then
      return main_dumb_transition, {main_select_mode, loc("ss_disconnect") .. "\n\n" .. loc("ss_return"), 60, 300}
    end
    drop_old_data_messages() -- We are in the lobby, we shouldn't have any game data messages
  end
end

-- creates a leaderboard string that is sorted by rank
function build_viewable_leaderboard_string(report, first_viewable_idx, last_viewable_idx)
  str = loc("lb_header_board") .. "\n"
  first_viewable_idx = math.max(first_viewable_idx, 1)
  last_viewable_idx = math.min(last_viewable_idx, #report)

  for i = first_viewable_idx, last_viewable_idx do
    rating_spacing = "     " .. string.rep("  ", (3 - string.len(i)))
    name_spacing = "     " .. string.rep("  ", (4 - string.len(report[i].rating)))
    if report[i].is_you then
      str = str .. loc("lb_you") .. "-> "
    else
      str = str .. "      "
    end
    str = str .. i .. rating_spacing .. report[i].rating .. name_spacing .. report[i].user_name
    if i < #report then
      str = str .. "\n"
    end
  end
  return str
end

-- connects to the server using the given ip address and network port
function main_net_vs_setup(ip, network_port)
  if not config.name then
    return main_set_name
  end
  while config.name == "defaultname" do
    if main_set_name() == {main_select_mode} and config.name ~= "defaultname" then
      return main_net_vs_setup
    end
  end
  P1 = nil
  P2 = {}
  server_queue = ServerQueue()
  gprint(loc("lb_set_connect"), unpack(themes[config.theme].main_menu_screen_pos))
  wait()
  if not network_init(ip, network_port) then
    return main_dumb_transition, {main_select_mode, loc("ss_disconnect") .. "\n\n" .. loc("ss_return"), 60, 300}
  end
  local timeout_counter = 0
  while not connection_is_ready() do
    gprint(loc("lb_connecting"), unpack(themes[config.theme].main_menu_screen_pos))
    wait()
    if not do_messages() then
      return main_dumb_transition, {main_select_mode, loc("ss_disconnect") .. "\n\n" .. loc("ss_return"), 60, 300}
    end
  end
  GAME.connected_server_ip = ip
  GAME.connected_network_port = network_port
  logged_in = false
  return main_net_vs_lobby
end

-- online match in progress
function main_net_vs()

  GAME.match.supportsPause = false

  commonGameSetup()

  --Uncomment below to induce lag
  --STONER_MODE = true
  
  local function update()
    local function handleTaunt()
      local messages = server_queue:pop_all_with("taunt")
      for _, msg in ipairs(messages) do
        if msg.taunt then -- receive taunts
          local taunts = nil
          -- P1.character and P2.character are supposed to be already filtered with current mods, taunts may differ though!
          if msg.player_number == select_screen.my_player_number then
            taunts = characters[P1.character].sounds[msg.type]
          elseif msg.player_number == select_screen.op_player_number then
            taunts = characters[P2.character].sounds[msg.type]
          end
          if taunts then
            for _, t in ipairs(taunts) do
              t:stop()
            end
            if msg.index <= #taunts then
              taunts[msg.index]:play()
            elseif #taunts ~= 0 then
              taunts[math.random(#taunts)]:play()
            end
          end
       end
      end
    end

    local function handleLeaveMessage()
      local messages = server_queue:pop_all_with("leave_room")
      for _, msg in ipairs(messages) do
        if msg.leave_room then -- lost room during game, go back to lobby
          finalizeAndWriteVsReplay(GAME.match.battleRoom, 0, true)

          -- Show a message that the match connection was lost along with the average frames behind.
          local message = loc("ss_room_closed_in_game")

          local P1Behind = P1:averageFramesBehind()
          local P2Behind = P2:averageFramesBehind()
          local maxBehind = math.max(P1Behind, P2Behind)

          if GAME.battleRoom.spectating then
            message = message .. "\n" .. loc("ss_average_frames_behind_player", GAME.battleRoom.playerNames[1], P1Behind)
            message = message .. "\n" .. loc("ss_average_frames_behind_player", GAME.battleRoom.playerNames[2], P2Behind)
          else 
            message = message .. "\n" .. loc("ss_average_frames_behind", maxBehind)
          end

          return {main_dumb_transition, {main_net_vs_lobby, message, 60, -1}}
        end
      end
    end

    local function handleGameEndAsSpectator()
      -- if the game already ended before we caught up, abort trying to catch up to it early in order to get into the next game instead
      if GAME.battleRoom.spectating and (P1.play_to_end or P2.play_to_end) then
        local message = server_queue:pop_next_with("create_room", "character_select")
        if message then
          -- shove the message back in for select_screen to handle
          server_queue:push(message)
          return {main_dumb_transition, {select_screen.main, nil, 0, 0, false, false, {select_screen, "2p_net_vs"}}}
        end
      end
    end

    local transition = nil
    handleTaunt()

    transition = handleLeaveMessage()
    if transition then
      return transition
    end

    transition = handleGameEndAsSpectator()
    if transition then
      return transition
    end

    if not do_messages() then
      return {main_dumb_transition, {main_select_mode, loc("ss_disconnect") .. "\n\n" .. loc("ss_return"), 60, 300}}
    end

    process_all_data_messages() -- Receive game play inputs from the network

    if not GAME.battleRoom.spectating then
      if P1.tooFarBehindError or P2.tooFarBehindError then
        finalizeAndWriteVsReplay(GAME.match.battleRoom, 0, true)
        GAME:clearMatch()
        json_send({leave_room = true})
        local ip = GAME.connected_server_ip
        local port = GAME.connected_network_port
        resetNetwork()
        return {main_dumb_transition, {
          main_net_vs_setup, -- next_func
          loc("ss_latency_error"), -- text
          60, -- timemin
          -1, -- timemax
          nil, -- winnerSFX
          false, -- keepMusic
          {ip, port} -- args
        }}
      end
    end
  end
  
  local function variableStep() 

    if GAME.battleRoom.spectating and menu_escape() then
      logger.trace("spectator pressed escape during a game")
      json_send({leave_room = true})
      GAME:clearMatch()
      return {main_dumb_transition, {main_net_vs_lobby, "", 0, 0}} -- spectator leaving the match
    end
  end

  local function abortGame() 
  end
  
  local function processGameResults(gameResult) 

    local matchOutcome = GAME.match.battleRoom:matchOutcome()
    if matchOutcome then
      local end_text = matchOutcome["end_text"]
      local winSFX = matchOutcome["winSFX"]
      local outcome_claim = matchOutcome["outcome_claim"]
      
      json_send({game_over = true, outcome = outcome_claim})

      finalizeAndWriteVsReplay(GAME.match.battleRoom, outcome_claim)
    
      if GAME.battleRoom.spectating then
        -- next_func, text, winnerSFX, timemax, keepMusic, args
        return {game_over_transition,
          {select_screen.main, end_text, winSFX, nil, false, {select_screen, "2p_net_vs"}}
        }
      else
        return {game_over_transition, 
          {select_screen.main, end_text, winSFX, 60 * 8, false, {select_screen, "2p_net_vs"}}
        }
      end
    end
  end

  return runMainGameLoop, {update, variableStep, abortGame, processGameResults}
end

-- sets up globals for local vs
function main_local_vs_setup()
  GAME.battleRoom = BattleRoom()
  GAME.battleRoom.playerNames[1] = loc("player_n", "1")
  GAME.battleRoom.playerNames[2] = loc("player_n", "2")
  GAME.input:clearInputConfigurationsForPlayers()
  GAME.input:requestPlayerInputConfigurationAssignments(2)
  return select_screen.main, {select_screen, "2p_local_vs"}
end

-- sets up globals for local vs computer
function main_local_vs_computer_setup()
  GAME.battleRoom = BattleRoom()
  return select_screen.main, {select_screen, "2p_local_computer_vs"}
end

-- local 2pvs mode
function main_local_vs()

  commonGameSetup()

  replay = createNewReplay(GAME.match)
  
  local function update() 
    assert((P1.CLOCK == P2.CLOCK), "should run at same speed: " .. P1.CLOCK .. " - " .. P2.CLOCK)
  end
  
  local function variableStep() 

  end

  local function abortGame()
    return {main_dumb_transition, {
            select_screen.main, -- next_func
            "", -- text
            0, -- timemin
            0, -- timemax
            nil, -- winnerSFX
            false, -- keepMusic
            {select_screen, "2p_local_vs"} -- args
    }}
  end
  
  
  local function processGameResults(gameResult) 

    assert((P1.CLOCK == P2.CLOCK), "should run at same speed: " .. P1.CLOCK .. " - " .. P2.CLOCK)

    local matchOutcome = GAME.match.battleRoom:matchOutcome()
    if matchOutcome then
      local end_text = matchOutcome["end_text"]
      local winSFX = matchOutcome["winSFX"]
      local outcome_claim = matchOutcome["outcome_claim"]
      
      finalizeAndWriteVsReplay(GAME.match.battleRoom, outcome_claim)

      return {game_over_transition, 
          {select_screen.main, end_text, winSFX, nil, false, {select_screen, "2p_local_vs"}}
        }
    end
  end

  return runMainGameLoop, {update, variableStep, abortGame, processGameResults}
end

-- sets up globals for vs yourself
function main_local_vs_yourself_setup(trainingModeSettings)
  GAME.battleRoom = BattleRoom()
  if trainingModeSettings then
    GAME.battleRoom.trainingModeSettings = trainingModeSettings
  end
  GAME.battleRoom.playerNames[2] = nil
  return select_screen.main, {select_screen, "1p_vs_yourself"}
end

-- 1vs against yourself
function main_local_vs_yourself()

  commonGameSetup()

  replay = createNewReplay(GAME.match)
  
  local function update() 

  end
  
  local function variableStep() 

  end

  local function abortGame() 
    return {main_dumb_transition, {
      select_screen.main, -- next_func
      "", -- text
      0, -- timemin
      0, -- timemax
      nil, -- winnerSFX
      false, -- keepMusic
      {select_screen, "1p_vs_yourself"} -- args
    }}
  end
  
  local function processGameResults(gameResult) 
    if not GAME.battleRoom.trainingModeSettings  then
      GAME.scores:saveVsSelfScoreForLevel(P1.analytic.data.sent_garbage_lines, P1.level)
      finalizeAndWriteVsReplay(nil, nil)
    end

    return {game_over_transition,
          {select_screen.main, nil, P1:pick_win_sfx(), nil, false, {select_screen, "1p_vs_yourself"}}
        }
  end

  return runMainGameLoop, {update, variableStep, abortGame, processGameResults}
end

-- replay player
function main_replay()

  commonGameSetup()

  Replay.loadFromFile(replay)

  local function update() 
  end

  local frameAdvance = false
  local playbackSpeed = 1
  local maximumSpeed = 20
  local function variableStep()
    -- If we just finished a frame advance, pause again
    if frameAdvance then
      frameAdvance = false
      GAME.gameIsPaused = true
    end

    -- Advance one frame
    if (menu_advance_frame() or this_frame_keys["\\"]) and not frameAdvance then
      frameAdvance = true
      GAME.gameIsPaused = false
      if P1 then
        P1.max_runs_per_frame = 1
      end
      if P2 then
        P2.max_runs_per_frame = 1
      end
    elseif menu_right() then
      playbackSpeed = util.bound(1, playbackSpeed + 1, maximumSpeed)
      if P1 then
        P1.max_runs_per_frame = playbackSpeed
      end
      if P2 then
        P2.max_runs_per_frame = playbackSpeed
      end
    elseif menu_left() then
      playbackSpeed = util.bound(1, playbackSpeed - 1, maximumSpeed)
      if P1 then
        P1.max_runs_per_frame = playbackSpeed
      end
      if P2 then
        P2.max_runs_per_frame = playbackSpeed
      end
    end
  end

  local function abortGame() 
    return {main_dumb_transition, {replay_browser.main, "", 0, 0}}
  end

  local function processGameResults(gameResult) 

    if P2 then
      local matchOutcome = GAME.match.battleRoom:matchOutcome()
      if matchOutcome then
        local end_text = matchOutcome["end_text"]
        local winSFX = matchOutcome["winSFX"]

        return {game_over_transition, {replay_browser.main, end_text, winSFX}}
      end
    else
      return {game_over_transition, {replay_browser.main, nil, P1:pick_win_sfx()}}
    end
  end
  
  return runMainGameLoop, {update, variableStep, abortGame, processGameResults}

end

-- creates a puzzle game function for a given puzzle and index
function makeSelectPuzzleSetFunction(puzzleSet, awesome_idx)
  local next_func = nil
  local setupComplete = false
  local character = nil
  awesome_idx = awesome_idx or 1

  local function setupPuzzles()
    if config.puzzle_randomColors then
      puzzleSet = deepcpy(puzzleSet)
  
      for _, puzzle in pairs(puzzleSet.puzzles) do
        puzzle.stack = Puzzle.randomizeColorString(puzzle.stack)
      end
    end

    current_stage = config.stage
      if current_stage == random_stage_special_value then
        current_stage = nil
      end
      commonGameSetup()
      setupComplete = true
  end

  function next_func()

    -- the body of makeSelectPuzzleSetFunction is already getting called when entering the puzzle select screen
    -- for that reason setup needs to happen inside next_func
    if not setupComplete then
      setupPuzzles()
    end

    GAME.match = Match("puzzle")
    P1 = Stack{which=1, match=GAME.match, is_local=true, level=config.puzzle_level, character=character}
    GAME.match.P1 = P1
    P1:wait_for_random_character()
    if not character then
      character = P1.character
    end
    P1.do_countdown = config.ready_countdown_1P or false
    P2 = nil
    if awesome_idx == nil then
      awesome_idx = math.random(#puzzleSet.puzzles)
    end
    local puzzle = puzzleSet.puzzles[awesome_idx]
    local isValid, validationError = puzzle:validate()
    if isValid then
      P1:set_puzzle_state(puzzle)
    else
      validationError = "Validation error in puzzle set " .. puzzleSet.setName .. "\n"
                        .. validationError
      return main_dumb_transition, {main_select_mode, validationError, 60, -1}
    end

    local function update() 
    end

    local function variableStep() 
      -- Reset puzzle button
      if player_reset() then 
        return {main_dumb_transition, {next_func, "", 0, 0, nil, true}}
      end
    end

    local function abortGame() 
      return {main_dumb_transition, {main_select_puzz, "", 0, 0}}
    end

    local function processGameResults(gameResult) 
      if P1:puzzle_done() then -- writes successful puzzle replay and ends game
        awesome_idx = (awesome_idx % #puzzleSet.puzzles) + 1
        if awesome_idx == 1 then
          return {game_over_transition, {main_select_puzz, loc("pl_you_win"), P1:pick_win_sfx()}}
        else
          return {game_over_transition, {next_func, loc("pl_you_win"), P1:pick_win_sfx(), -1, true}}
        end
      elseif P1:puzzle_failed() then -- writes failed puzzle replay and returns to menu
        SFX_GameOver_Play = 1
        return {game_over_transition, {next_func, loc("pl_you_lose"), nil, -1, true}}
      end
    end
    
    return runMainGameLoop, {update, variableStep, abortGame, processGameResults}
  end

  return next_func
end

function main_select_puzz()
  
  if themes[config.theme].musics.main then
    find_and_add_music(themes[config.theme].musics, "main")
  end
  GAME.backgroundImage = themes[config.theme].images.bg_main
  reset_filters()

  local exitSet = false
  local puzzleMenu
  local ret = nil
  local level = config.puzzle_level
  local randomColors = config.puzzle_randomColors or false

  local function selectFunction(myFunction, args)
    local function constructedFunction()
      puzzle_menu_last_index = puzzleMenu.active_idx
      if config.puzzle_level ~= level or config.puzzle_randomColors ~= randomColors then
        config.puzzle_level = level
        config.puzzle_randomColors = randomColors
        logger.debug("saving settings...")
        wait()
        write_conf_file()
      end
      puzzleMenu:remove_self()
      ret = {myFunction, args}
    end
    return constructedFunction
  end

  local function goEscape()
    puzzleMenu:set_active_idx(#puzzleMenu.buttons)
  end

  local function exitSettings()
    exitSet = true
  end

  local items = {}
  for key, val in pairsSortedByKeys(GAME.puzzleSets) do
    items[#items + 1] = {key, makeSelectPuzzleSetFunction(val)}
  end

  -- Ensure the last index is sane in case puzzles got reloaded differently
  puzzle_menu_last_index = wrap(3, puzzle_menu_last_index, #items + 2)

  local function updateMenuLevel()
    local levelString = ""
    if level then
      levelString = tostring(level)
    end
    puzzleMenu:set_button_setting(1, levelString)
  end

  local function increaseLevel()
    level = util.bound(1, (level or 1) + 1, 11)
    updateMenuLevel()
  end

  local function decreaseLevel()
    level = util.bound(1, (level or 1) - 1, 11)
    updateMenuLevel()
  end

  local function update_randomColors(noToggle)
    if not noToggle then
      randomColors = not randomColors
    end
    puzzleMenu:set_button_setting(2, randomColors and loc("op_on") or loc("op_off"))
  end

  local function nextMenu()
    puzzleMenu:selectNextIndex()
  end

  local menu_x, menu_y = unpack(themes[config.theme].main_menu_screen_pos)
  puzzleMenu = Click_menu(menu_x, menu_y, nil, themes[config.theme].main_menu_max_height, puzzle_menu_last_index)
  puzzleMenu:add_button(loc("level"), nextMenu, goEscape, decreaseLevel, increaseLevel)
  puzzleMenu:add_button(loc("randomColors"), update_randomColors, goEscape, update_randomColors, update_randomColors)
  for i = 1, #items do
    puzzleMenu:add_button(items[i][1], selectFunction(items[i][2], items[i][3]), goEscape)
  end
  puzzleMenu:add_button(loc("back"), exitSettings, exitSettings)
  updateMenuLevel()
  update_randomColors(true)

  while true do
    puzzleMenu:draw()

    wait()
    variable_step(
      function()
        puzzleMenu:update()
      end
    )

    if ret then
      puzzleMenu:remove_self()
      return unpack(ret)
    elseif exitSet then
      puzzleMenu:remove_self()
      return main_select_mode, {}
    end
  end
end

-- menu for setting the username
function main_set_name()
  local name = config.name or ""
  love.keyboard.setTextInput(true) -- enables user to type
  while true do
    local to_print = loc("op_enter_name") .. " (" .. name:len() .. "/" .. NAME_LENGTH_LIMIT .. ")"
    local line2 = name
    if (love.timer.getTime() * 3) % 2 > 1 then
      line2 = line2 .. "| "
    end
    gprintf(to_print, 0, canvas_height/2, canvas_width, "center")
    gprintf(line2, (canvas_width/2) - 60, (canvas_height/2) + 20)
    wait()
    local ret = nil
    variable_step(
      function()
        if this_frame_keys["escape"] then
          ret = {main_select_mode}
        end
        if menu_return_once() then
          config.name = name
          write_conf_file()
          ret = {main_select_mode}
        end
        if menu_backspace() then
          -- Remove the last character.
          -- This could be a UTF-8 character, so handle it properly.
          local utf8offset = utf8.offset(name, -1)
          if utf8offset then
            name = string.sub(name, 1, utf8offset - 1)
          end
        end
        for _, v in ipairs(this_frame_unicodes) do
          -- Don't add more characters than the server char limit
          if name:len() < NAME_LENGTH_LIMIT and v ~= " " then
            name = name .. v
          end
        end
      end
    )
    if ret then
      love.keyboard.setTextInput(false)
      return unpack(ret)
    end
  end
end

-- toggles fullscreen
function fullscreen()
  love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
  return main_select_mode
end

-- sets game to portrait mode if portrait_mode_desired is true, else sets game to landscape
-- does NOT return a function.  If calling this from a menu, be sure to return a menu function afterwards.
function portrait_mode(portrait_mode_desired)
  local window_width, window_height = love.graphics.getDimensions()
  local new_width = window_width
  local was_fullscreen = love.window.getFullscreen()
  config.portraitMode = portrait_mode_desired or false
  if portrait_mode_desired then
    GAME.portrait_mode = true
    GAME.canvasWRatio = 9
    GAME.canvasHRatio = 16
    canvas_width = 720
    canvas_height = 1280
    --love.window.setMode(450, 800)
    if window_width >= window_height then
      --window is landscape. Let's use the current height as the new height, and decrease width.
      if mobile then
        love.window.setMode(1,2) --set to portrait
        new_width, window_height = love.graphics.getDimensions()
      else
        new_width = math.ceil(window_height*9/16)
        love.window.setMode(new_width, window_height ,{resizable=(not was_fullscreen), fullscreen = was_fullscreen})
      end
    end
  else --portrait_mode_desired was false or nil - go to landscape
    GAME.portrait_mode = false
    GAME.canvasWRatio = 16
    GAME.canvasHRatio = 9
    canvas_width = 1280
    canvas_height = 720
    --love.window.setMode(1280,720)
    if window_width <= window_height then
      --window is portrait. Let's use the current height as the new height, and increase width.
      if mobile then
        love.window.setMode(2,1) --set to landscape
        new_width, window_height = love.graphics.getDimensions()
      else
        new_width = math.ceil(window_height*16/9)
        love.window.setMode(new_width, window_height ,{resizable=(not was_fullscreen), fullscreen = was_fullscreen})
      end
    end
  end
  GAME:updateCanvasPositionAndScale(new_width, window_height)
  GAME:refreshCanvasAndImagesForNewScale()
  
  return true
end

--toggles portrait mode
function handlePortraitModeToggle()
  portrait_mode(not GAME.portrait_mode)
  return main_select_mode
end

-- dumb transition that shows a black screen
function main_dumb_transition(next_func, text, timemin, timemax, winnerSFX, keepMusic, args)
  keepMusic = keepMusic or false
  if not keepMusic then
    stop_the_music()
  end
  winnerSFX = winnerSFX or nil
  if not GAME.muteSoundEffects then
    -- TODO: somehow winnerSFX can be 0 instead of nil
    if winnerSFX ~= nil and winnerSFX ~= 0 then
      winnerSFX:play()
    elseif SFX_GameOver_Play == 1 then
      logger.trace(debug.traceback(""))
      themes[config.theme].sounds.game_over:play()
    end
  end
  SFX_GameOver_Play = 0

  reset_filters()
  text = text or ""
  timemin = timemin or 0
  timemax = timemax or -1 -- negative values means the user needs to press enter/escape to continue

  if timemax <= -1 then   
    local button_text = loc("continue_button") or ""
    text = text .. "\n\n" .. button_text
  end

  local t = 0

  local x = canvas_width / 2
  local y = canvas_height / 2
  local backgroundPadding = 10
  local textObject = love.graphics.newText(get_global_font(), text)
  local width = textObject:getWidth()
  local height = textObject:getHeight()
  
  while true do

    -- We need to keep processing network messages during a transition so we don't get booted by the server for not responding.
    if network_connected() then
      do_messages()
    end

    grectangle_color("fill", (x - (width/2) - backgroundPadding) / GFX_SCALE, (y - (height/2) - backgroundPadding) / GFX_SCALE, (width + 2 * backgroundPadding)/GFX_SCALE, (height + 2 * backgroundPadding)/GFX_SCALE, 0, 0, 0, 0.5)
    menu_drawf(textObject, x, y, "center", "center", 0)

    wait()
    local ret = nil
    variable_step(
      function()
        if t >= timemin and ((t >= timemax and timemax >= 0) or (menu_enter() or menu_escape())) then
          ret = {next_func, args}
        end
        t = t + 1
      end
    )
    if ret then
      return unpack(ret)
    end
  end
end

-- show game over screen, last frame of gameplay
function game_over_transition(next_func, text, winnerSFX, timemax, keepMusic, args)
  timemax = timemax or -1 -- negative values means the user needs to press enter/escape to continue
  text = text or ""
  keepMusic = keepMusic or false
  local button_text = loc("continue_button") or ""
  local timemin = 60 -- the minimum amount of frames the game over screen will be displayed for

  local t = 0 -- the amount of frames that have passed since the game over screen was displayed
  local font = get_global_font()
  local winnerTime = 60

  if SFX_GameOver_Play == 1 then
    themes[config.theme].sounds.game_over:play()
    SFX_GameOver_Play = 0
  else
    winnerTime = 0
  end

  -- The music may have already been partially faded due to dynamic music or something else,
  -- record what volume it was so we can fade down from that.
  local initialMusicVolumes = {}
  for k, v in pairs(currently_playing_tracks) do
    initialMusicVolumes[v] = v:getVolume()
  end

  while true do
    GAME.match:render()
    gprint(text, (canvas_width - font:getWidth(text)) / 2, 10)
    gprint(button_text, (canvas_width - font:getWidth(button_text)) / 2, 10 + 30)
    wait()
    local ret = nil
    variable_step(
      function()
        if not keepMusic then
          -- Fade the music out over time
          local fadeMusicLength = 3 * 60
          if t <= fadeMusicLength then
            local percentage = (fadeMusicLength - t) / fadeMusicLength
            for k, v in pairs(initialMusicVolumes) do
              local volume = v * percentage
              setFadePercentageForGivenTracks(volume, {k}, true)
            end
          else
            if t == fadeMusicLength + 1 then
              setMusicFadePercentage(1) -- reset the music back to normal config volume
              stop_the_music()
            end
          end
        end

        -- Play the winner sound effect after a delay
        if not GAME.muteSoundEffects then
          if t >= winnerTime then
            if winnerSFX ~= nil then -- play winnerSFX then nil it so it doesn't loop
              winnerSFX:play()
              winnerSFX = nil
            end
          end
        end

        GAME.match:run()

        if network_connected() then
          do_messages() -- recieve messages so we know if the next game is in the queue
        end

        local left_select_menu = false -- Whether a message has been sent that indicates a match has started or the room has closed
        if this_frame_messages then
          for _, msg in ipairs(this_frame_messages) do
            -- if a new match has started or the room is being closed, flag the left select menu variavle
            if msg.match_start or replay_of_match_so_far or msg.leave_room then
              left_select_menu = true
            end
          end
        end

        -- if conditions are met, leave the game over screen
        if t >= timemin and ((t >= timemax and timemax >= 0) or (menu_enter() or menu_escape() or love.mouse.isDown(1))) or left_select_menu then
          setMusicFadePercentage(1) -- reset the music back to normal config volume
          if not keepMusic then
            stop_the_music()
          end
          SFX_GameOver_Play = 0
          analytics.game_ends(P1.analytic)
          ret = {next_func, args}
        end
        t = t + 1
      end
    )
    if ret then
      GAME:clearMatch()
      return unpack(ret)
    end
  end
end

-- quits the game
function exit_game(...)
  love.event.quit()
  return main_select_mode
end

-- quit handling
function love.quit()
  if PROFILING_ENABLED then
    GAME.profiler.report("profiler.log")
  end
  if network_connected() then
    json_send({logout = true})
  end
  love.audio.stop()
  if love.window.getFullscreen() then
    _, _, config.display = love.window.getPosition()
  else
    config.windowX, config.windowY, config.display = love.window.getPosition()
    config.windowX = math.max(config.windowX, 0)
    config.windowY = math.max(config.windowY, 30) --don't let 'y' be zero, or the title bar will not be visible on next launch.
  end

  config.windowWidth, config.windowHeight, _ = love.window.getMode( )
  config.maximizeOnStartup = love.window.isMaximized()
  config.fullscreen = love.window.getFullscreen()
  config.portraitMode = GAME.portrait_mode
  write_conf_file()
end
