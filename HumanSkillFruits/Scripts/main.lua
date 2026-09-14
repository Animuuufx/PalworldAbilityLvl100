local VERSION = "v0.1.1-safe"
local TAG = "[HumanSkillFruits " .. VERSION .. "]"

local function log(message)
    print(TAG .. " " .. tostring(message))
end

-- IMPORTANT:
-- This build deliberately performs NO UObject lookup, reflection scan,
-- TArray access, ProcessEvent call, timer, or world polling during startup
-- or world entry. The previous probe performed reflected class/function
-- enumeration as soon as PalPlayerCharacter appeared and could crash the
-- current Palworld/UE4SS build while the world was still initializing.
--
-- v0.1.1-safe is a stability baseline. Once this enters a world cleanly,
-- the skill-fruit hooks will be reintroduced one at a time using known
-- current-build functions instead of scanning live UClasses automatically.

local function safe_hotkey_test()
    log("Alt+F8 hotkey received. No Unreal objects were accessed.")
end

local function register_safe_hotkey()
    local ok, err = pcall(function()
        if Key == nil or ModifierKey == nil then
            log("Key API unavailable; skipping hotkey registration.")
            return
        end

        if IsKeyBindRegistered and IsKeyBindRegistered(Key.F8, {ModifierKey.ALT}) then
            log("Alt+F8 is already registered; leaving existing binding unchanged.")
            return
        end

        if RegisterKeyBind then
            RegisterKeyBind(Key.F8, {ModifierKey.ALT}, safe_hotkey_test)
            log("Registered Alt+F8 safe test hotkey.")
        else
            log("RegisterKeyBind unavailable; running without hotkeys.")
        end
    end)

    if not ok then
        log("Hotkey registration failed safely: " .. tostring(err))
    end
end

register_safe_hotkey()
log("Loaded stability build. No automatic world access is active.")
