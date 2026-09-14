local VERSION = "v0.1.0-probe"
local TAG = "[HumanSkillFruits " .. VERSION .. "]"

local function log(msg)
    print(TAG .. " " .. tostring(msg))
end

local function valid(obj)
    if obj == nil then return false end
    local ok, result = pcall(function() return obj:IsValid() end)
    return ok and result == true
end

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok and result ~= nil then return result end
    return value
end

local function name_of(value)
    value = unwrap(value)
    if value == nil then return "nil" end
    local ok, result = pcall(function()
        if value.ToString then return value:ToString() end
        if value.GetFName then return value:GetFName():ToString() end
        return tostring(value)
    end)
    return ok and tostring(result) or tostring(value)
end

local function get_player_controller()
    local ok, controller = pcall(function()
        if UEHelpers and UEHelpers.GetPlayerController then
            return UEHelpers:GetPlayerController()
        end
        return FindFirstOf("PalPlayerController")
    end)
    if ok and valid(controller) then return controller end
    return nil
end

local function get_player_character()
    local controller = get_player_controller()
    if controller then
        local ok, character = pcall(function() return controller:GetDefaultPlayerCharacter() end)
        if ok and valid(character) then return character end
        local pawn_ok, pawn = pcall(function() return controller.Pawn end)
        if pawn_ok and valid(pawn) then return pawn end
    end
    local character = FindFirstOf("PalPlayerCharacter")
    if valid(character) then return character end
    return nil
end

local function get_individual_parameter(actor)
    if not valid(actor) then return nil end
    local candidates = {
        function() return actor.CharacterParameterComponent.IndividualParameter end,
        function() return actor.CharacterParameterComponent:GetIndividualParameter() end,
        function() return actor.IndividualParameter end,
    }
    for _, getter in ipairs(candidates) do
        local ok, value = pcall(getter)
        value = unwrap(value)
        if ok and valid(value) then return value end
    end
    return nil
end

local function array_values(arr, limit)
    local out = {}
    if arr == nil then return out end
    local count = 0
    pcall(function() count = #arr end)
    if count == 0 then
        pcall(function() count = arr:GetArrayNum() end)
    end
    if limit and count > limit then count = limit end
    for i = 1, count do
        local ok, value = pcall(function() return arr[i] end)
        if ok and value ~= nil then out[#out + 1] = value end
    end
    return out
end

local function read_mastered_waza(parameter)
    if not valid(parameter) then return {} end
    local arr = nil
    pcall(function() arr = parameter.SaveParameter.MasteredWaza end)
    if arr == nil then
        pcall(function() arr = parameter.MasteredWaza end)
    end
    return array_values(arr)
end

local function read_equip_waza(parameter)
    if not valid(parameter) then return {} end
    local arr = nil
    pcall(function() arr = parameter:GetEquipWaza() end)
    if arr == nil then pcall(function() arr = parameter.SaveParameter.EquipWaza end) end
    return array_values(arr, 3)
end

local function skill_label(value)
    local raw = name_of(value)
    raw = raw:gsub("^EPalWazaID::", "")
    raw = raw:gsub("^.-::", "")
    raw = raw:gsub("_", " ")
    return raw
end

local function show_screen(text, duration)
    local lib = nil
    pcall(function() lib = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end)
    if not valid(lib) then return end
    local world = get_player_character()
    if not world then return end
    pcall(function()
        lib:PrintString(world, tostring(text), true, false, nil, duration or 2.0, "HumanSkillFruits")
    end)
end

local function read_player_skills()
    local player = get_player_character()
    local parameter = get_individual_parameter(player)
    if not parameter then return {}, {}, nil end
    return read_mastered_waza(parameter), read_equip_waza(parameter), parameter
end

local function render_skill_bar()
    local mastered = read_player_skills()
    if #mastered == 0 then
        show_screen("Skill Fruit Bar: no learned fruit skills", 1.2)
        return
    end
    local parts = {"Skill Fruit Bar"}
    for i = 1, math.min(#mastered, 8) do
        parts[#parts + 1] = string.format("[%d] %s", i, skill_label(mastered[i]))
    end
    show_screen(table.concat(parts, "   "), 1.2)
end

local function dump_candidate_functions(obj, label)
    if not valid(obj) then
        log(label .. ": object unavailable")
        return
    end
    local cls = nil
    pcall(function() cls = obj:GetClass() end)
    if not valid(cls) then return end

    local seen = {}
    while valid(cls) do
        pcall(function()
            cls:ForEachFunction(function(fn)
                local n = name_of(fn)
                local lower = string.lower(n)
                if not seen[n] and (
                    string.find(lower, "waza", 1, true) or
                    string.find(lower, "skill", 1, true) or
                    string.find(lower, "fruit", 1, true) or
                    string.find(lower, "attack", 1, true) or
                    string.find(lower, "item", 1, true)
                ) then
                    seen[n] = true
                    log(label .. " function: " .. n)
                end
            end)
        end)
        local next_cls = nil
        pcall(function() next_cls = cls:GetSuperStruct() end)
        if next_cls == cls then break end
        cls = next_cls
    end
end

local probed = false
local function runtime_probe()
    if probed then return end
    local player = get_player_character()
    if not player then
        log("player not ready; probe deferred")
        return
    end
    probed = true
    log("runtime probe starting")
    dump_candidate_functions(player, "player")
    local parameter = get_individual_parameter(player)
    dump_candidate_functions(parameter, "player-parameter")
    local controller = get_player_controller()
    dump_candidate_functions(controller, "controller")
    log("runtime probe complete")
end

local function log_skill_state()
    ExecuteInGameThread(function()
        local mastered, equipped = read_player_skills()
        log("MasteredWaza count=" .. tostring(#mastered))
        for i, skill in ipairs(mastered) do
            log("  mastered[" .. i .. "]=" .. name_of(skill))
        end
        log("EquipWaza count=" .. tostring(#equipped))
        for i, skill in ipairs(equipped) do
            log("  equipped[" .. i .. "]=" .. name_of(skill))
        end
        render_skill_bar()
        runtime_probe()
    end)
end

local function select_skill(slot)
    ExecuteInGameThread(function()
        local mastered = read_player_skills()
        if slot < 1 or slot > #mastered then
            show_screen("No learned fruit skill in slot " .. tostring(slot), 1.5)
            return
        end
        local skill = mastered[slot]
        log("skill hotkey " .. tostring(slot) .. " selected " .. name_of(skill))
        show_screen("Selected skill: " .. skill_label(skill) .. " (cast backend pending live probe)", 1.8)
        -- v0.1 intentionally does not guess a cast UFunction signature.
        -- The first live UE4SS log identifies the current build's safe player cast entry point.
    end)
end

local keys = {Key.ONE, Key.TWO, Key.THREE, Key.FOUR, Key.FIVE, Key.SIX, Key.SEVEN, Key.EIGHT}
for i, key in ipairs(keys) do
    pcall(function()
        if not IsKeyBindRegistered(key, {ModifierKey.ALT}) then
            RegisterKeyBind(key, {ModifierKey.ALT}, function() select_skill(i) end)
        end
    end)
end

pcall(function()
    if not IsKeyBindRegistered(Key.F8, {ModifierKey.ALT}) then
        RegisterKeyBind(Key.F8, {ModifierKey.ALT}, log_skill_state)
    end
end)

pcall(function()
    LoopAsync(1000, function()
        ExecuteInGameThread(function()
            if get_player_character() then
                render_skill_bar()
                runtime_probe()
            end
        end)
        return false
    end)
end)

log("loaded")
log("Alt+1..Alt+8 = skill slots; Alt+F8 = dump learned/equipped skills + live function probe")
