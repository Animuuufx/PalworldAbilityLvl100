local VERSION = "v0.1.4-parameter-probe"
local TAG = "[HumanSkillFruits " .. VERSION .. "]"

local source = debug.getinfo(1, "S").source
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source
local mod_root = script_path:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local status_path = mod_root .. "/probe_status.txt"

local function log(message)
    print(TAG .. " " .. tostring(message))
end

local function write_status(lines)
    local ok, err = pcall(function()
        local file = assert(io.open(status_path, "w"))
        file:write("HumanSkillFruits " .. VERSION .. "\n")
        for _, line in ipairs(lines) do
            file:write(tostring(line) .. "\n")
        end
        file:close()
    end)

    if not ok then
        log("Could not write probe status file: " .. tostring(err))
    end
end

local function full_name(obj, fallback)
    if obj == nil then return fallback or "<nil>" end
    local ok, value = pcall(function() return obj:GetFullName() end)
    if ok and value ~= nil then return tostring(value) end
    return fallback or "<object found>"
end

local function run_parameter_probe()
    log("Alt+F8 received; scheduling one manual player + CharacterParameterComponent lookup.")

    if ExecuteInGameThread == nil then
        local message = "ExecuteInGameThread unavailable; probe cancelled."
        log(message)
        write_status({message})
        return
    end

    ExecuteInGameThread(function()
        local ok_find, player_or_err = pcall(function()
            return FindFirstOf("PalPlayerCharacter")
        end)

        if not ok_find then
            local message = "PalPlayerCharacter lookup failed safely: " .. tostring(player_or_err)
            log(message)
            write_status({message})
            return
        end

        local player = player_or_err
        if player == nil then
            local message = "PalPlayerCharacter lookup returned nil."
            log(message)
            write_status({message})
            return
        end

        local player_name = full_name(player, "<player object found>")
        log("Player found: " .. player_name)

        -- Public Palworld SDK references expose CharacterParameterComponent
        -- directly on PalPlayerCharacter. Read ONLY this one known property.
        local ok_component, component_or_err = pcall(function()
            return player.CharacterParameterComponent
        end)

        if not ok_component then
            local message = "CharacterParameterComponent read failed safely: " .. tostring(component_or_err)
            log(message)
            write_status({
                "SUCCESS: player found.",
                "Player: " .. player_name,
                message
            })
            return
        end

        local component = component_or_err
        if component == nil then
            local message = "CharacterParameterComponent was nil."
            log(message)
            write_status({
                "SUCCESS: player found.",
                "Player: " .. player_name,
                message
            })
            return
        end

        local component_name = full_name(component, "<CharacterParameterComponent object found>")
        log("SUCCESS: CharacterParameterComponent found: " .. component_name)

        write_status({
            "SUCCESS: PalPlayerCharacter found.",
            "Player: " .. player_name,
            "SUCCESS: CharacterParameterComponent found.",
            "Component: " .. component_name,
            "No IndividualParameter, SaveParameter, MasteredWaza, EquipWaza, reflection scan, TArray access, writes, hooks, timers, or polling were used."
        })
    end)
end

local function register_probe_hotkey()
    if RegisterKeyBind == nil or Key == nil or ModifierKey == nil then
        log("Keybind API unavailable; probe hotkey not registered.")
        return
    end

    local ok, err = pcall(function()
        RegisterKeyBind(Key.F8, {ModifierKey.ALT}, run_parameter_probe)
    end)

    if ok then
        log("Registered Alt+F8 manual CharacterParameterComponent probe.")
    else
        log("Alt+F8 registration failed: " .. tostring(err))
    end
end

register_probe_hotkey()
log("Loaded. No automatic world access is active; press Alt+F8 only after entering a world.")
