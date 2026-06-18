-- ==========================================
-- 1. GAME CONFIGURATION & CHARACTER DATABASE
-- ==========================================
local CharacterData = {
    {
        name = "Warrior",
        desc = "High defense, physical damage.",
        hp = 150,
        mp = 50,
        magicElement = "Earth",
        powers = { "Ground Slam", "Stone Shield" },
        sprite = "char_warrior"
    },
    {
        name = "Mage",
        desc = "Master of elements, fragile body.",
        hp = 80,
        mp = 200,
        magicElement = "Fire",
        powers = { "Fireball", "Flame Burst" },
        sprite = "char_mage"
    },
    {
        name = "Rogue",
        desc = "Fast attacks, shadow magic.",
        hp = 110,
        mp = 90,
        magicElement = "Shadow",
        powers = { "Shadow Step", "Dark Blade" },
        sprite = "char_rogue"
    },
    {
        name = "Healer",
        desc = "Holy magic, restores health.",
        hp = 100,
        mp = 150,
        magicElement = "Light",
        powers = { "Holy Cure", "Radiant Shield" },
        sprite = "char_healer"
    }
}

-- Current active state variables
local selectedCharacter = nil
local isGameStarted = false

-- ==========================================
-- 2. NEW GAME ENGINE / CHARACTER SELECTION LAYER
-- ==========================================
local NewGameEngine = {}

-- 1. Choose Character Logic
function NewGameEngine:chooseCharacter(index)
    if CharacterData[index] then
        selectedCharacter = CharacterData[index]
        print("----------------------------------------")
        print("Character Selected: " .. selectedCharacter.name)
        print("HP: " .. selectedCharacter.hp .. " | MP: " .. selectedCharacter.mp)
        print("Magic Element: " .. selectedCharacter.magicElement)
        print("Powers Loaded: " .. table.concat(selectedCharacter.powers, ", "))
        print("----------------------------------------")
        return true
    else
        print("Error: Invalid Character Index!")
        return false
    end
end

-- 2. Use Magic / Power Logic
function NewGameEngine:castMagic(powerName)
    if not selectedCharacter then
        print("Error: Please select a character first!")
        return false
    end
    
    -- Check if the character possesses this power
    local hasPower = false
    for _, power in ipairs(selectedCharacter.powers) do
        if power == powerName then
            hasPower = true
            break
        end
    end
    
    if hasPower then
        if selectedCharacter.mp >= 20 then
            selectedCharacter.mp = selectedCharacter.mp - 20
            print(selectedCharacter.name .. " casted [" .. powerName .. "] using " .. selectedCharacter.magicElement .. " magic! (Remaining MP: " .. selectedCharacter.mp .. ")")
            -- Trigger visual / sound effect code here
            return true
        else
            print("Not enough Magic Points (MP) to cast " .. powerName)
            return false
        end
    else
        print(selectedCharacter.name .. " does not know how to use " .. powerName)
        return false
    end
end

-- 3. Game Launch Setup
function NewGameEngine:start()
    if not selectedCharacter then
        print("Cannot start game: Select your character first!")
        return
    end
    isGameStarted = true
    print("New Game Mode Started Successfully with " .. selectedCharacter.name .. "!")
end

-- ==========================================
-- 3. INTEGRATION & TESTING EXAMPLE
-- ==========================================

-- Step 1: Game Open hotay he character select option (Simulating Input)
print("=== Welcome to the New Game Mode ===")
print("Available Characters:")
for i, char in ipairs(CharacterData) do
    print(i .. ". " .. char.name .. " -> " .. char.desc)
end

-- Step 2: Player selects Mage (Index 2)
NewGameEngine:chooseCharacter(2)

-- Step 3: Game starts after selection
NewGameEngine:start()

-- Step 4: Player uses magic powers during gameplay
NewGameEngine:castMagic("Fireball")
NewGameEngine:castMagic("Flame Burst")