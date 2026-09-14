local VERSION = "v0.1.2-hotkey"
local TAG = "[HumanSkillFruits " .. VERSION .. "]"

local source = debug.getinfo(1, "S").source
local script_path = source:sub(1, 1) == "@" and source:sub(2) or source
local mod_root = script_path:match("^(.*)[\\/]Scripts[\\/]main%.lua$") or "."
local status_path = mod_root .. "/hotkey_status.txt"

local function log(message)
    print(TAG .. " " .. tostring(message))
end

local function write_status(message)
    local ok, err = pcall(function()
        local file = assert(io.open(status_path, "w"))
        file:write("HumanSkillFruits " .. VERSION .. "\n")
        file:write(tostring(message) .. "\n")
        file:write("No Palworld UObject was accessed by this test.\n")
        file:close()
    end)

    if not ok then
        log("Could not write hotkey status file: " .. tostring(err))
        return false
    end
    return true
end

local function safe_hotkey_test()
    local message = "F8 hotkey received successfully."
    log(message)
    write_status(message)
end

local function register_hotkey(key, label)
    if RegisterKeyBind == nil then
        return false, "RegisterKeyBind unavailable"
    end

    local ok, err = pcall(function()
        RegisterKeyBind(key, safe_hotkey_test)
    end)

    if ok then
        log("Registered " .. label .. " safe test hotkey.")
        return true
    end

    return false, tostring(err)
end

local registered = false

if Key ~= nil then
    local f8_ok, f8_err = register_hotkey(Key.F8, "F8")
    if f8_ok then
        registered = true
    else
        log("F8 registration failed: " .. tostring(f8_err))
        -- Some UE4SS/game setups already reserve F8. F7 is only a fallback
        -- and executes the exact same no-UObject callback.
        local f7_ok, f7_err = register_hotkey(Key.F7, "F7 fallback")
        registered = f7_ok
        if not f7_ok then
            log("F7 fallback registration failed: " .. tostring(f7_err))
        end
    end
else
    log("Key API unavailable; no hotkey registered.")
end

if registered then
    log("Loaded safe hotkey build. Press F8 (or F7 only if F8 was unavailable).")
else
    log("Loaded, but no safe test hotkey could be registered.")
end

-- Deliberately no FindFirstOf, StaticFindObject, UObject reflection,
-- ProcessEvent, TArray access, timers, polling, or world hooks in this build.
