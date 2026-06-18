require "import"
import "android.app.*"
import "android.os.*"
import "android.widget.*"
import "android.view.*"
import "android.text.InputFilter"
import "android.media.MediaPlayer"
import "android.content.DialogInterface" 
import "android.content.Intent" 
import "android.net.Uri"         
import "java.util.Locale"
import "java.net.URLEncoder"
import "com.androlua.Http" 

-- SharedPreferences for saving user data locally
local activity = activity
local preferences = activity.getSharedPreferences("99CardGamePrefs", activity.MODE_PRIVATE)
local isFirstTime = preferences.getBoolean("isFirstTime", true)

-- Firebase Database Configuration
local FIREBASE_URL = "https://card-game-f8aa2-default-rtdb.firebaseio.com/"

-- Global Variables for Audio and Multiplayer State
local currentMusicPlayer = nil
local isMultiplayer = false
local myRole = "player1" 
local currentRoomId = ""
local multiplayerTimer = nil

-- Absolute Audio File Paths
local BACKGROUND_MUSIC_PATH = "/storage/emulated/0/解说/Tools/The end of kindness /sound/mixkit-driving-ambition-32.mp3"
local SOUND_SHUFFLE = "/storage/emulated/0/解说/Tools/The end of kindness /sound/card_shuffle.mp3"
local SOUND_CARD_PUT = "/storage/emulated/0/解说/Tools/The end of kindness /sound/card_put.mp3"

local audioManager = activity.getSystemService("audio")

-- Forward Declarations
local showMainMenu
local startNewGame
local stopMultiplayerTimer
local showMultiplayerLobby

-- ==========================================
-- BACKGROUND MUSIC MANAGEMENT
-- ==========================================
local function playMusic(filePath, isLooping)
  if currentMusicPlayer ~= nil then
    pcall(function()
      if currentMusicPlayer.isPlaying() then currentMusicPlayer.stop() end
      currentMusicPlayer.release()
    end)
    currentMusicPlayer = nil
  end

  local success, err = pcall(function()
    currentMusicPlayer = MediaPlayer()
    currentMusicPlayer.setDataSource(filePath)
    currentMusicPlayer.setLooping(isLooping)
    currentMusicPlayer.prepare()
    currentMusicPlayer.start()
  end)
  if not success then
    print("Music System Error: Track initialization failed.")
    currentMusicPlayer = nil
  end
end

local function stopAllMusic()
  if currentMusicPlayer ~= nil then
    pcall(function()
      if currentMusicPlayer.isPlaying() then currentMusicPlayer.stop() end
      currentMusicPlayer.release()
    end)
    currentMusicPlayer = nil
  end
end

-- ==========================================
-- SOUND EFFECT SYSTEM
-- ==========================================
local function playSoundEffect(filePath)
  pcall(function()
    local mp = MediaPlayer()
    mp.setDataSource(filePath)
    mp.prepare()
    mp.start()
    mp.setOnCompletionListener({onCompletion = function(m) m.release() end})
  end)
end

-- ==========================================
-- FIREBASE CORE API FUNCTIONS
-- ==========================================
local function syncDataToFirebase(username, wins, losses)
  local safeName = username:gsub("[%s%.%#%$%[%]]", "_")
  local targetUrl = FIREBASE_URL .. "players/" .. safeName .. ".json"
  local jsonPayload = string.format('{"username":"%s", "wins":%d, "losses":%d, "lastLogin":"%s"}', 
    username, wins, losses, os.date("%Y-%m-%d %H:%M:%S"))
  
  Http.put(targetUrl, jsonPayload, function(code, body) end)
end

-- ==========================================
-- GAMEPLAY STATE & VARIABLES
-- ==========================================
local runningTotal = 0
local isPlayerTurn = true
local playerHand = {}
local deck = {}
local txtTotalScore, txtGameStatus, cardsContainer

local function createDeck()
  deck = {}
  local suits = {"â™ ", "â™¥", "â™¦", "â™£"}
  local values = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}
  for _, suit in ipairs(suits) do
    for _, val in ipairs(values) do table.insert(deck, {value = val, suit = suit}) end
  end
  math.randomseed(os.time())
  for i = #deck, 2, -1 do
    local j = math.random(i)
    deck[i], deck[j] = deck[j], deck[i]
  end
end

local function drawCard()
  if #deck == 0 then createDeck() end
  return table.remove(deck, 1)
end

local function applyCardLogic(cardValue, choice)
  if cardValue == "A" then runningTotal = runningTotal + choice
  elseif cardValue == "2" then
    if runningTotal < 50 then runningTotal = runningTotal * 2
    else
      if runningTotal % 2 == 0 then runningTotal = math.floor(runningTotal / 2)
      else runningTotal = runningTotal * 2 end
    end
  elseif cardValue == "3" or cardValue == "4" or cardValue == "5" or cardValue == "6" or cardValue == "7" or cardValue == "8" then
    runningTotal = runningTotal + tonumber(cardValue)
  elseif cardValue == "9" then 
  elseif cardValue == "10" then
    runningTotal = runningTotal + choice
    if runningTotal < 0 then runningTotal = 0 end
  elseif cardValue == "K" or cardValue == "Q" or cardValue == "J" then
    runningTotal = runningTotal + 10
  end
end

local function syncMultiplayerGameOver(winnerRole)
  stopMultiplayerTimer()
  local currentName = preferences.getString("userName", "Player")
  local wins = preferences.getInt("userWins", 0)
  local losses = preferences.getInt("userLosses", 0)
  local editor = preferences.edit()

  if myRole == winnerRole then
    wins = wins + 1
    editor.putInt("userWins", wins)
    txtGameStatus.setText("ðŸŽ‰ Victory! You won the match!")
  else
    losses = losses + 1
    editor.putInt("userLosses", losses)
    txtGameStatus.setText("ðŸ”´ Defeat! Your opponent won.")
  end
  editor.apply()
  syncDataToFirebase(currentName, wins, losses)
  
  Http.put(FIREBASE_URL .. "rooms/" .. currentRoomId .. "/status.json", '"finished"', function(c, b) end)
  if cardsContainer then cardsContainer.removeAllViews() end
end

local function checkGameOver()
  if runningTotal > 99 then
    txtTotalScore.setText("Total: " .. runningTotal)
    if isMultiplayer then
      local winner = (myRole == "player1") and "player2" or "player1"
      syncMultiplayerGameOver(winner)
    else
      local currentName = preferences.getString("userName", "Player")
      local wins = preferences.getInt("userWins", 0)
      local losses = preferences.getInt("userLosses", 0)
      local editor = preferences.edit()
      
      if isPlayerTurn then
        txtGameStatus.setText("ðŸ”´ Game Over! You exceeded 99.")
        losses = losses + 1; editor.putInt("userLosses", losses)
      else
        txtGameStatus.setText("ðŸŽ‰ Congratulations! Computer exceeded 99.")
        wins = wins + 1; editor.putInt("userWins", wins)
      end
      editor.apply()
      syncDataToFirebase(currentName, wins, losses)
      if cardsContainer then cardsContainer.removeAllViews() end
    end
    return true
  end
  return false
end

-- ==========================================
-- COMPUTER TURN ENGINE (OFFLINE MODE ONLY)
-- ==========================================
local function computerTurn()
  if checkGameOver() then return end
  txtGameStatus.setText("ðŸ¤– Computer is thinking...")
  
  Handler().postDelayed(Runnable({
    run = function()
      local choice = 0
      if runningTotal + 11 > 99 then choice = 1 else choice = 11 end
      playSoundEffect(SOUND_CARD_PUT)
      applyCardLogic("3", 0) 
      txtTotalScore.setText("Total: " .. runningTotal)
      
      if not checkGameOver() then
        isPlayerTurn = true
        txtGameStatus.setText("ðŸŸ¢ Your Turn! Choose a card.")
        updateUI()
      end
    end
  }), 2000)
end

-- ==========================================
-- REAL-TIME MULTIPLAYER SYNC ENGINE (POLLING)
-- ==========================================
stopMultiplayerTimer = function()
  if multiplayerTimer then
    multiplayerTimer.cancel()
    multiplayerTimer = nil
  end
end

local function startMultiplayerPolling()
  stopMultiplayerTimer()
  multiplayerTimer = Timer({
    run = function()
      Http.get(FIREBASE_URL .. "rooms/" .. currentRoomId .. ".json", function(code, body)
        if code == 200 and body and body ~= "null" then
          local currentTurn = body:match('"turn"%s*:%s*"([^"]+)"')
          local cloudTotal = body:match('"runningTotal"%s*:%s*(%d+)')
          local roomStatus = body:match('"status"%s*:%s*"([^"]+)"')
          
          activity.runOnUiThread(Runnable({
            run = function()
              if roomStatus == "finished" then
                stopMultiplayerTimer()
                return
              end
              
              if cloudTotal then
                runningTotal = tonumber(cloudTotal)
                if txtTotalScore then txtTotalScore.setText("Total: " .. runningTotal) end
              end
              
              if currentTurn then
                if currentTurn == myRole then
                  if not isPlayerTurn then
                    isPlayerTurn = true
                    if txtGameStatus then txtGameStatus.setText("ðŸŸ¢ It's your turn! Play a card.") end
                    updateUI()
                  end
                else
                  isPlayerTurn = false
                  if txtGameStatus then txtGameStatus.setText("â³ Opponent's turn. Waiting...") end
                end
              end
              
              if runningTotal > 99 then
                local losingRole = currentTurn
                local winningRole = (losingRole == "player1") and "player2" or "player1"
                syncMultiplayerGameOver(winningRole)
              end
            end
          }))
        end
      end)
    end
  })
  multiplayerTimer.scheduleAtFixedRate(0, 1500)
end

local function sendMoveToFirebase()
  local nextTurn = (myRole == "player1") and "player2" or "player1"
  local targetUrl = FIREBASE_URL .. "rooms/" .. currentRoomId .. ".json"
  
  local patchData = string.format('{"runningTotal":%d, "turn":"%s"}', runningTotal, nextTurn)
  
  Http.patch(targetUrl, patchData, function(code, body)
    if code == 200 then
      isPlayerTurn = false
      txtGameStatus.setText("â³ Move sent! Waiting for opponent...")
      updateUI()
    end
  end)
end

local function showChoiceDialog(cardValue, callback)
  local dialog = AlertDialog.Builder(activity).setCancelable(false)
  if cardValue == "A" then
    dialog.setTitle("Ace Card Choice").setMessage("Add 1 or 11?")
    dialog.setPositiveButton("Add 11", DialogInterface.OnClickListener({onClick = function(d,w) callback(11) end}))
    dialog.setNegativeButton("Add 1", DialogInterface.OnClickListener({onClick = function(d,w) callback(1) end}))
  elseif cardValue == "10" then
    dialog.setTitle("10 Card Choice").setMessage("Add or Subtract 10?")
    dialog.setPositiveButton("Add 10", DialogInterface.OnClickListener({onClick = function(d,w) callback(10) end}))
    dialog.setNegativeButton("Subtract 10", DialogInterface.OnClickListener({onClick = function(d,w) callback(-10) end}))
  end
  dialog.show()
end

-- ==========================================
-- MAIN GAMEPLAY SCREEN UI
-- ==========================================
startNewGame = function()
  runningTotal = 0
  createDeck()
  
  playSoundEffect(SOUND_SHUFFLE)
  
  playerHand = {}
  for i = 1, 5 do table.insert(playerHand, drawCard()) end

  local gameLayout = LinearLayout(activity)
  gameLayout.setOrientation(LinearLayout.VERTICAL)
  gameLayout.setGravity(Gravity.CENTER)
  gameLayout.setPadding(40, 40, 40, 40)

  txtTotalScore = TextView(activity)
  txtTotalScore.setText("Total: " .. runningTotal)
  txtTotalScore.setTextSize(36)
  txtTotalScore.setGravity(Gravity.CENTER)
  txtTotalScore.setPadding(0, 0, 0, 20)
  gameLayout.addView(txtTotalScore)

  txtGameStatus = TextView(activity)
  txtGameStatus.setText(isPlayerTurn and "ðŸŸ¢ Your Turn! Play a card." or "â³ Opponent's turn. Waiting...")
  txtGameStatus.setTextSize(16)
  txtGameStatus.setGravity(Gravity.CENTER)
  txtGameStatus.setPadding(0, 0, 0, 40)
  gameLayout.addView(txtGameStatus)

  cardsContainer = LinearLayout(activity)
  cardsContainer.setOrientation(LinearLayout.HORIZONTAL)
  cardsContainer.setGravity(Gravity.CENTER)
  gameLayout.addView(cardsContainer)

  updateUI = function()
    cardsContainer.removeAllViews()
    if not isPlayerTurn then return end

    for i, card in ipairs(playerHand) do
      local btnCard = Button(activity)
      btnCard.setText(card.value .. card.suit)
      btnCard.setPadding(10, 10, 10, 10)
      
      btnCard.setOnClickListener(function()
        if not isPlayerTurn then return end
        local playedCard = card
        
        local function executeTurn(chosenValue)
          table.remove(playerHand, i)
          playSoundEffect(SOUND_CARD_PUT)
          applyCardLogic(playedCard.value, chosenValue)
          table.insert(playerHand, drawCard()) 
          
          txtTotalScore.setText("Total: " .. runningTotal)
          
          if not checkGameOver() then
            if isMultiplayer then
              sendMoveToFirebase()
            else
              isPlayerTurn = false
              updateUI()
              computerTurn()
            end
          end
        end

        if playedCard.value == "A" or playedCard.value == "10" then
          showChoiceDialog(playedCard.value, executeTurn)
        else
          executeTurn(0) 
        end
      end)
      cardsContainer.addView(btnCard)
    end
  end

  updateUI() 

  local btnLeave = Button(activity)
  btnLeave.setText("Leave Game")
  btnLeave.setPadding(0, 40, 0, 0)
  btnLeave.setOnClickListener(function() 
    stopMultiplayerTimer()
    showMainMenu() 
  end)
  gameLayout.addView(btnLeave)

  activity.setContentView(gameLayout)
  
  if isMultiplayer then startMultiplayerPolling() end
end

-- ==========================================
-- MULTIPLAYER LOBBY INTERFACE MANAGEMENT
-- ==========================================
showMultiplayerLobby = function()
  local lobbyLayout = LinearLayout(activity)
  lobbyLayout.setOrientation(LinearLayout.VERTICAL)
  lobbyLayout.setGravity(Gravity.CENTER)
  lobbyLayout.setPadding(40, 40, 40, 40)

  local title = TextView(activity)
  title.setText("Online Multiplayer Lobby")
  title.setTextSize(24)
  title.setPadding(0, 0, 0, 40)
  lobbyLayout.addView(title)

  local btnHost = Button(activity)
  btnHost.setText("Create New Room (Host)")
  btnHost.setOnClickListener(function()
    math.randomseed(os.time())
    currentRoomId = tostring(math.random(1000, 9999))
    local currentName = preferences.getString("userName", "Player")
    
    local roomPayload = string.format('{"player1":"%s", "runningTotal":0, "turn":"player1", "status":"waiting"}', currentName)
    
    Http.put(FIREBASE_URL .. "rooms/" .. currentRoomId .. ".json", roomPayload, function(code, body)
      if code == 200 then
        isMultiplayer = true
        myRole = "player1"
        isPlayerTurn = true
        
        print("Room created! ID: " .. currentRoomId)
        
        local waitDialog = ProgressDialog(activity)
        waitDialog.setTitle("Waiting for Player 2")
        waitDialog.setMessage("Room ID: " .. currentRoomId .. "\nGive this code to your opponent...")
        waitDialog.setCancelable(true)
        waitDialog.show()
        
        local lobbyTimer
        lobbyTimer = Timer({
          run = function()
            Http.get(FIREBASE_URL .. "rooms/" .. currentRoomId .. "/player2.json", function(c, b)
              if c == 200 and b and b ~= "null" then
                lobbyTimer.cancel()
                activity.runOnUiThread(Runnable({
                  run = function()
                    waitDialog.dismiss()
                    Http.put(FIREBASE_URL .. "rooms/" .. currentRoomId .. "/status.json", '"playing"', function()
                      startNewGame()
                    end)
                  end
                }))
              end
            end)
          end
        })
        lobbyTimer.scheduleAtFixedRate(0, 2000)
      end
    end)
  end)
  lobbyLayout.addView(btnHost)

  local btnJoin = Button(activity)
  btnJoin.setText("Join Existing Room")
  btnJoin.setOnClickListener(function()
    local inputDialog = AlertDialog.Builder(activity)
    inputDialog.setTitle("Enter Room ID")
    local inputField = EditText(activity)
    inputField.setInputType(2)
    inputDialog.setView(inputField)
    
    inputDialog.setPositiveButton("Join Match", DialogInterface.OnClickListener({
      onClick = function(d, w)
        local roomId = tostring(inputField.getText())
        if roomId == "" then return end
        
        Http.get(FIREBASE_URL .. "rooms/" .. roomId .. ".json", function(code, body)
          if code == 200 and body and body ~= "null" then
            local currentName = preferences.getString("userName", "Player")
            
            Http.put(FIREBASE_URL .. "rooms/" .. roomId .. "/player2.json", '"'..currentName..'"', function(c, b)
              if c == 200 then
                isMultiplayer = true
                myRole = "player2"
                isPlayerTurn = false
                currentRoomId = roomId
                print("Joined room successfully!")
                startNewGame()
              end
            end)
          else
            print("Error: Room ID not found!")
          end
        end)
      end
    }))
    inputDialog.setNegativeButton("Cancel", nil)
    inputDialog.show()
  end)
  lobbyLayout.addView(btnJoin)

  local btnBack = Button(activity)
  btnBack.setText("Back to Menu")
  btnBack.setOnClickListener(function() showMainMenu() end)
  lobbyLayout.addView(btnBack)

  activity.setContentView(lobbyLayout)
end

-- ==========================================
-- CONTROL PANEL VIEW (SETTINGS)
-- ==========================================
local function showSettingsScreen()
  local setLayout = LinearLayout(activity)
  setLayout.setOrientation(LinearLayout.VERTICAL)
  setLayout.setGravity(Gravity.CENTER)
  setLayout.setPadding(50, 50, 50, 50)

  local title = TextView(activity)
  title.setText("Settings - Control Panel")
  title.setTextSize(24)
  title.setPadding(0, 0, 0, 40)
  setLayout.addView(title)

  local volLabel = TextView(activity)
  volLabel.setText("System Volume:")
  setLayout.addView(volLabel)

  local seekBar = SeekBar(activity)
  local maxVol = audioManager.getStreamMaxVolume(3)
  local currentVol = audioManager.getStreamVolume(3)
  seekBar.setMax(maxVol)
  seekBar.setProgress(currentVol)
  seekBar.setPadding(30, 20, 30, 40)
  seekBar.setOnSeekBarChangeListener({
    onProgressChanged = function(sb, progress, fromUser)
      audioManager.setStreamVolume(3, progress, 0)
    end
  })
  setLayout.addView(seekBar)

  local btnEditName = Button(activity)
  btnEditName.setText("Edit Profile Name")
  btnEditName.setOnClickListener(function()
    local editDialog = AlertDialog.Builder(activity)
    editDialog.setTitle("Change Name")
    local input = EditText(activity)
    local filters = luajava.createArray("android.text.InputFilter", {InputFilter.LengthFilter(17)})
    input.setFilters(filters)
    input.setText(preferences.getString("userName", ""))
    editDialog.setView(input)
    
    editDialog.setPositiveButton("Save", DialogInterface.OnClickListener({
      onClick = function(d, w)
        local newName = tostring(input.getText())
        if newName == "" or string.find(newName, "[^%w%s]") then return end
        
        local wins = preferences.getInt("userWins", 0)
        local losses = preferences.getInt("userLosses", 0)
        
        local editor = preferences.edit()
        editor.putString("userName", newName)
        editor.apply()
        
        syncDataToFirebase(newName, wins, losses)
      end
    }))
    editDialog.setNegativeButton("Cancel", nil)
    editDialog.show()
  end)
  setLayout.addView(btnEditName)

  local btnResetData = Button(activity)
  btnResetData.setText("Reset Game Data")
  btnResetData.setOnClickListener(function()
    local confirmDialog = AlertDialog.Builder(activity)
    confirmDialog.setTitle("âš ï¸ Reset Warning")
    confirmDialog.setMessage("Clear all stats?")
    confirmDialog.setPositiveButton("Yes", DialogInterface.OnClickListener({
      onClick = function(d, w)
        local currentName = preferences.getString("userName", "Player")
        syncDataToFirebase(currentName, 0, 0) 
        local editor = preferences.edit()
        editor.clear(); editor.putBoolean("isFirstTime", true); editor.apply()
        activity.recreate() 
      end
    }))
    confirmDialog.setNegativeButton("No", nil)
    confirmDialog.show()
  end)
  setLayout.addView(btnResetData)

  local btnBack = Button(activity)
  btnBack.setText("Back")
  btnBack.setOnClickListener(function() showMainMenu() end)
  setLayout.addView(btnBack)

  activity.setContentView(setLayout)
end

local function showAboutScreen()
  local aboutLayout = LinearLayout(activity)
  aboutLayout.setOrientation(LinearLayout.VERTICAL)
  aboutLayout.setGravity(Gravity.TOP)
  aboutLayout.setPadding(40, 40, 40, 40)

  local scrollView = ScrollView(activity)
  local scrollContent = LinearLayout(activity)
  scrollContent.setOrientation(LinearLayout.VERTICAL)

  local aboutTitle = TextView(activity)
  aboutTitle.setText("About & Game Guide")
  aboutTitle.setTextSize(24)
  aboutTitle.setGravity(Gravity.CENTER)
  aboutTitle.setPadding(0, 0, 0, 30)
  scrollContent.addView(aboutTitle)

  local guideText = TextView(activity)
  guideText.setText([[99 DYNAMIC CALCULATION RULES:
1. Ace: Choice of 1 or 11 points.
2. 2 Multiplier: Inverts or doubles matching scores.
3. 3 to 8: Regular additions.
4. 9: Pass Turn card (+0 value layout).
5. 10: Selection variant modifier (+10/-10 subtraction variant).
6. King / Queen: Direct flat score value +10 addition.
7. Jack: Flat +10 value modification. Keeps the active loop turn alive.]])
  guideText.setTextSize(14)
  guideText.setPadding(0, 0, 20, 30)
  scrollContent.addView(guideText)

  local btnWhatsApp = Button(activity)
  btnWhatsApp.setText("Join My WhatsApp Group")
  btnWhatsApp.setOnClickListener(function()
    local intent = Intent(Intent.ACTION_VIEW).setData(Uri.parse("https://chat.whatsapp.com/Cq9qmBKXpjP3t7Jy7oPtWk"))
    activity.startActivity(intent) 
  end)
  scrollContent.addView(btnWhatsApp)

  local btnFeedback = Button(activity)
  btnFeedback.setText("Send Feedback to Developer")
  btnFeedback.setOnClickListener(function()
    local phoneNumber = "92323234391" 
    local currentName = preferences.getString("userName", "Player")
    local wins = preferences.getInt("userWins", 0)
    local losses = preferences.getInt("userLosses", 0)
    
    local feedbackTemplate = "Respected Developer,\n\n" ..
                             "I am writing this to provide my feedback regarding the 99 Card Game application. " ..
                             "The gameplay mechanic, audio processing, and calculation flows operate exceptionally smoothly. " ..
                             "Here are my current profiling insights for verification:\n" ..
                             "â€¢ Player Username: " .. currentName .. "\n" ..
                             "â€¢ Match Wins: " .. tostring(wins) .. "\n" ..
                             "â€¢ Match Losses: " .. tostring(losses) .. "\n\n" ..
                             "Everything works flawlessly! Thank you for developing such an amazing game platform. Looking forward to future feature updates!"
    
    local encodedMsg = URLEncoder.encode(feedbackTemplate, "UTF-8")
    local intent = Intent(Intent.ACTION_VIEW).setData(Uri.parse("https://wa.me/" .. phoneNumber .. "?text=" .. encodedMsg))
    activity.startActivity(intent) 
  end)
  scrollContent.addView(btnFeedback)

  local btnBack = Button(activity)
  btnBack.setText("Back to Menu")
  btnBack.setOnClickListener(function() showMainMenu() end)
  scrollContent.addView(btnBack)

  scrollView.addView(scrollContent)
  aboutLayout.addView(scrollView)
  activity.setContentView(aboutLayout)
end

local function showMoreOptionsScreen()
  local moreLayout = LinearLayout(activity)
  moreLayout.setOrientation(LinearLayout.VERTICAL)
  moreLayout.setGravity(Gravity.CENTER)
  moreLayout.setPadding(40, 40, 40, 40)

  local title = TextView(activity)
  title.setText("More Options Menu")
  title.setTextSize(24)
  title.setPadding(0, 0, 0, 40)
  moreLayout.addView(title)

  local btnSettings = Button(activity)
  btnSettings.setText("Settings")
  btnSettings.setOnClickListener(function()
    showSettingsScreen()            
  end)
  moreLayout.addView(btnSettings)

  local btnBack = Button(activity)
  btnBack.setText("Back to Menu")
  btnBack.setOnClickListener(function() showMainMenu() end)
  moreLayout.addView(btnBack)

  activity.setContentView(moreLayout)
end

function showMainMenu()
  playMusic(BACKGROUND_MUSIC_PATH, true)
  isMultiplayer = false 

  local currentName = preferences.getString("userName", "Player")
  local wins = preferences.getInt("userWins", 0)
  local losses = preferences.getInt("userLosses", 0)
  
  local mainLayout = LinearLayout(activity)
  mainLayout.setOrientation(LinearLayout.VERTICAL)
  mainLayout.setGravity(Gravity.CENTER)
  mainLayout.setPadding(40, 40, 40, 40)

  local titleView = TextView(activity)
  titleView.setText("99 card game")
  titleView.setTextSize(28)
  titleView.setGravity(Gravity.CENTER)
  titleView.setPadding(0, 0, 0, 50)
  mainLayout.addView(titleView)

  local btnProfile = Button(activity)
  btnProfile.setText(string.format("Profile (%s) - W: %d | L: %d", currentName, wins, losses))
  mainLayout.addView(btnProfile)

  local btnGameMenu = Button(activity)
  btnGameMenu.setText("99 Card Game")
  btnGameMenu.setOnClickListener(function()
    local modeDialog = AlertDialog.Builder(activity)
    modeDialog.setTitle("Select Game Mode")
    modeDialog.setMessage("Choose how you want to play the 99 Card Game:")
    
    modeDialog.setPositiveButton("Offline (Vs Computer)", DialogInterface.OnClickListener({
      onClick = function(d, w)
        startNewGame()                 
      end
    }))
    
    modeDialog.setNegativeButton("ðŸŒ Online Multiplayer", DialogInterface.OnClickListener({
      onClick = function(d, w)
        showMultiplayerLobby()                 
      end
    }))
    
    modeDialog.show()
  end)
  mainLayout.addView(btnGameMenu)

  local btnMoreOptions = Button(activity)
  btnMoreOptions.setText("More Options")
  btnMoreOptions.setOnClickListener(function() showMoreOptionsScreen() end)
  mainLayout.addView(btnMoreOptions)

  local btnAbout = Button(activity)
  btnAbout.setText("About")
  btnAbout.setOnClickListener(function() showAboutScreen() end)
  mainLayout.addView(btnAbout)

  local btnExit = Button(activity)
  btnExit.setText("Exit")
  btnExit.setOnClickListener(function()
    stopAllMusic(); activity.finish()
  end)
  mainLayout.addView(btnExit)

  activity.setContentView(mainLayout)
end

local function showNameInputScreen()
  local nameLayout = LinearLayout(activity).setOrientation(LinearLayout.VERTICAL)
  nameLayout.setGravity(Gravity.CENTER).setPadding(40, 40, 40, 40)

  local infoText = TextView(activity)
  infoText.setText("Please enter your name:"); infoText.setTextSize(18); infoText.setPadding(0, 0, 0, 20)
  nameLayout.addView(infoText)

  local inputField = EditText(activity)
  local filters = luajava.createArray("android.text.InputFilter", {InputFilter.LengthFilter(17)})
  inputField.setFilters(filters); nameLayout.addView(inputField)

  local btnGetStarted = Button(activity)
  btnGetStarted.setText("Get Started")
  btnGetStarted.setOnClickListener(function()
    local enteredName = tostring(inputField.getText())
    if enteredName == "" or string.find(enteredName, "[^%w%s]") then return end

    local editor = preferences.edit()
    editor.putString("userName", enteredName); editor.putInt("userWins", 0); editor.putInt("userLosses", 0); editor.putBoolean("isFirstTime", false); editor.apply()
    
    syncDataToFirebase(enteredName, 0, 0)
    showMainMenu()
  end)
  nameLayout.addView(btnGetStarted)
  activity.setContentView(nameLayout)
end

local function showWelcomeScreen()
  local welcomeLayout = LinearLayout(activity).setOrientation(LinearLayout.VERTICAL)
  welcomeLayout.setGravity(Gravity.CENTER).setPadding(40, 40, 40, 40)

  local longTextView = TextView(activity)
  longTextView.setText([[Welcome to the official 99 Card Game platform.]])
  longTextView.setTextSize(16); longTextView.setPadding(0, 0, 0, 40); welcomeLayout.addView(longTextView)

  local btnNext = Button(activity)
  btnNext.setText("Next")
  btnNext.setOnClickListener(function() showNameInputScreen() end)
  welcomeLayout.addView(btnNext)
  activity.setContentView(welcomeLayout)
end

function onDestroy()
  stopAllMusic()
  stopMultiplayerTimer()
end

if isFirstTime then showWelcomeScreen() else showMainMenu() end