local VERSION = "v0.1.6-saveparameter-probe"
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

local function run_saveparameter_probe()
    log("Alt+F8 received; scheduling one manual player -> CharacterParameterComponent -> IndividualParameter -> SaveParameter lookup.")

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
        if not ok_find or player_or_err == nil then
            local message = ok_find and "PalPlayerCharacter lookup returned nil." or ("PalPlayerCharacter lookup failed safely: " .. tostring(player_or_err))
            log(message)
            write_status({message})
            return
        end

        local player = player_or_err
        local player_name = full_name(player, "<player object found>")
        log("Player found: " .. player_name)

        local ok_component, component_or_err = pcall(function()
            return player.CharacterParameterComponent
        end)
        if not ok_component or component_or_err == nil then
            local message = ok_component and "CharacterParameterComponent was nil." or ("CharacterParameterComponent read failed safely: " .. tostring(component_or_err))
            log(message)
            write_status({"Player: " .. player_name, message})
            return
        end

        local component = component_or_err
        local component_name = full_name(component, "<CharacterParameterComponent object found>")
        log("CharacterParameterComponent found: " .. component_name)

        local ok_individual, individual_or_err = pcall(function()
            return component.IndividualParameter
        end)
        if not ok_individual or individual_or_err == nil then
            local message = ok_individual and "IndividualParameter was nil." or ("IndividualParameter read failed safely: " .. tostring(individual_or_err))
            log(message)
            write_status({"Player: " .. player_name, "Component: " .. component_name, message})
            return
        end

        local individual = individual_or_err
        local individual_name = full_name(individual, "<IndividualParameter object found>")
        log("IndividualParameter found: " .. individual_name)

        -- Known current Palworld data chain:
        -- player -> CharacterParameterComponent -> IndividualParameter -> SaveParameter.
        -- SaveParameter is a struct value, not a UObject. This probe only reads the
        -- property and checks whether UE4SS returned a value. It does NOT inspect any
        -- fields inside the struct and does NOT touch MasteredWaza or EquipWaza yet.
        local ok_save, save_or_err = pcall(function()
            return individual.SaveParameter
        end)

        if not ok_save then
            local message = "SaveParameter read failed safely: " .. tostring(save_or_err)
            log(message)
            write_status({
                "Player: " .. player_name,
                "Component: " .. component_name,
                "Individual: " .. individual_name,
                message
            })
            return
        end

        local save = save_or_err
        if save == nil then
            local message = "SaveParameter was nil."
            log(message)
            write_status({
                "Player: " .. player_name,
                "Component: " .. component_name,
                "Individual: " .. individual_name,
                message
            })
            return
        end

        local save_type = type(save)
        log("SUCCESS: SaveParameter read successfully (Lua type=" .. save_type .. ").")

        write_status({
            "SUCCESS: PalPlayerCharacter found.",
            "Player: " .. player_name,
            "SUCCESS: CharacterParameterComponent found.",
            "Component: " .. component_name,
            "SUCCESS: IndividualParameter found.",
            "Individual: " .. individual_name,
            "SUCCESS: SaveParameter read successfully.",
            "SaveParameter Lua type: " .. save_type,
            "No SaveParameter fields, MasteredWaza, EquipWaza, reflection scan, TArray access, writes, hooks, timers, or polling were used."
        })
    end)
end

local function register_probe_hotkey()
    if RegisterKeyBind == nil or Key == nil or ModifierKey == nil then
        log("Keybind API unavailable; probe hotkey not registered.")
        return
    end

    local ok, err = pcall(function()
        RegisterKeyBind(Key.F8, {ModifierKey.ALT}, run_saveparameter_probe)
    end)

    if ok then
        log("Registered Alt+F8 manual SaveParameter probe.")
    else
        log("Alt+F8 registration failed: " .. tostring(err))
    end
end

register_probe_hotkey()
log("Loaded. No automatic world access is active; press Alt+F8 only after entering a world.")
