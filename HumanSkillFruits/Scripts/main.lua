local VERSION = "v0.1.3-player-probe"
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

local function run_player_probe()
    log("Alt+F8 received; scheduling one manual player lookup.")

    if ExecuteInGameThread == nil then
        log("ExecuteInGameThread unavailable; probe cancelled without UObject access.")
        write_status({"Probe cancelled: ExecuteInGameThread unavailable."})
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

        -- Do not enumerate properties/functions and do not touch skill arrays yet.
        -- This name read is the only additional UObject operation in this build.
        local object_name = "<player object found>"
        local ok_name, name_or_err = pcall(function()
            return player:GetFullName()
        end)
        if ok_name and name_or_err ~= nil then
            object_name = tostring(name_or_err)
        else
            log("Player object found; GetFullName was unavailable, continuing safely.")
        end

        log("SUCCESS: player object found: " .. object_name)
        write_status({
            "SUCCESS: PalPlayerCharacter found.",
            "Object: " .. object_name,
            "No reflection scan, property enumeration, TArray access, skill access, hooks, or polling were performed."
        })
    end)
end

local function register_probe_hotkey()
    if RegisterKeyBind == nil or Key == nil or ModifierKey == nil then
        log("Keybind API unavailable; probe hotkey not registered.")
        return
    end

    local ok, err = pcall(function()
        RegisterKeyBind(Key.F8, {ModifierKey.ALT}, run_player_probe)
    end)

    if ok then
        log("Registered Alt+F8 manual player probe.")
    else
        log("Alt+F8 registration failed: " .. tostring(err))
    end
end

register_probe_hotkey()
log("Loaded. No automatic world access is active; press Alt+F8 only after entering a world.")
