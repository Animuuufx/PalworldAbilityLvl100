local VERSION = "v0.7"

local CAN_USE_HOOK = "/Script/Pal.PalUtility:CanUseTargetWorkSuitabilityRankUp"
local ADD_RANK_HOOK = "/Script/Pal.PalIndividualCharacterParameter:SetWorkSuitabilityAddRank"
local STATIC_ITEM_HOOK = "/Script/Pal.PalStaticItemDataBase:CanUseItemToCharacter"
local PROCESSOR_ITEM_HOOK = "/Script/Pal.PalItemUseProcessor:CanUseItemToCharacter"
local SLOT_TARGET_HOOK = "/Script/Pal.PalItemSlot:CanUseItemToCharacter"

local handbook_codes = {
    EmitFlame = true,
    Watering = true,
    Seeding = true,
    GenerateElectricity = true,
    Handcraft = true,
    Collection = true,
    Deforest = true,
    Mining = true,
    ProductMedicine = true,
    Cool = true,
    Transport = true,
    MonsterFarm = true,
}

local suitability_ids = {
    EmitFlame = 1,
    Watering = 2,
    Seeding = 3,
    GenerateElectricity = 4,
    Handcraft = 5,
    Collection = 6,
    Deforest = 7,
    Mining = 8,
    ProductMedicine = 9,
    Cool = 10,
    Transport = 11,
    MonsterFarm = 12,
}

local suitability_names = {}
for name, id in pairs(suitability_ids) do
    suitability_names[id] = name
end

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function()
        if value.get then return value:get() end
        if value.Get then return value:Get() end
        return value
    end)
    return ok and result or nil
end

local function full_name(value)
    local object = unwrap(value)
    if not object then return "<nil>" end
    local ok, name = pcall(function() return object:GetFullName() end)
    return ok and tostring(name) or "<unnamed>"
end

local function handbook_code(value)
    local name = full_name(value)
    return name:match("WorkSuitability_AddTicket_([%w_]+)")
end

local function is_handbook(value)
    return handbook_codes[handbook_code(value)] == true
end

-- The reflected signatures have changed between Palworld builds. Do not rely
-- on a fixed parameter position; scan the context and every UFunction arg.
local function find_handbook(context, ...)
    local values = { context, ... }
    for _, value in ipairs(values) do
        local code = handbook_code(value)
        if code and handbook_codes[code] then
            return unwrap(value), code
        end
    end
    return nil, nil
end

local function looks_like_character_parameter(value)
    local object = unwrap(value)
    if not object then return false end

    local ok, result = pcall(function()
        if object.GetCharacterID then
            object:GetCharacterID()
            return true
        end
        if object.GetWorkSuitabilityRank then
            return true
        end
        if object.SetWorkSuitabilityAddRank then
            return true
        end
        return false
    end)
    return ok and result == true
end

local function find_target(context, ...)
    local values = { context, ... }
    for _, value in ipairs(values) do
        if looks_like_character_parameter(value) then
            return unwrap(value)
        end
    end
    return nil
end

local pending_target = {}
local mutation_seen = {}

local function target_key(target, code)
    return full_name(target) .. "|" .. tostring(code or "")
end

local function mark_pending(target, code)
    target = unwrap(target)
    if target ~= nil and code ~= nil then
        pending_target[target_key(target, code)] = true
    end
end

local function get_work_rank(target, id)
    target = unwrap(target)
    if not target or not id then return nil end

    local getters = {
        "GetWorkSuitabilityAddRank",
        "GetWorkSuitabilityRankWithCharacterRank",
        "GetWorkSuitabilityRank",
    }

    for _, name in ipairs(getters) do
        local ok, value = pcall(function()
            local fn = target[name]
            if type(fn) == "function" then
                return fn(target, id)
            end
            return nil
        end)
        if ok and value ~= nil then
            local n = tonumber(unwrap(value))
            if n ~= nil then return math.floor(n) end
        end
    end

    return nil
end

local setter_fn = nil
local function get_setter()
    if setter_fn ~= nil then return setter_fn end

    local ok, fn = pcall(function()
        return StaticFindObject("/Script/Pal.PalIndividualCharacterParameter:SetWorkSuitabilityAddRank")
    end)

    if ok and fn then
        setter_fn = fn
        return fn
    end

    return nil
end

local function call_set_work_suitability(target, id, value)
    target = unwrap(target)
    id = tonumber(id)
    value = tonumber(value)

    if not target or not id or not value then
        return false
    end

    value = math.max(1, math.min(100, math.floor(value)))

    local ok, result = pcall(function()
        local fn = get_setter()
        if fn then
            return fn(target, id, value)
        end
        return target:SetWorkSuitabilityAddRank(id, value)
    end)

    if ok then
        print("[WorkSuitabilityUnlock " .. VERSION .. "] Missing suitability initialized: id=" .. tostring(id) .. " rank=" .. tostring(value) .. " target=" .. full_name(target))
        return true
    end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Missing suitability initialization failed: " .. tostring(result))
    return false
end

local function initialize_missing_suitability(target, code)
    local id = suitability_ids[code]
    target = unwrap(target)
    if not id or not target then return false end

    local key = target_key(target, code)
    if mutation_seen[key] then return true end

    local current = get_work_rank(target, id)
    if current ~= nil and current > 0 then
        mutation_seen[key] = true
        print("[WorkSuitabilityUnlock " .. VERSION .. "] Existing suitability detected: " .. code .. " rank=" .. tostring(current))
        return true
    end

    -- This is the actual unlock operation: create the first persistent +1
    -- handbook rank on a Pal whose species has zero of this suitability.
    local ok = call_set_work_suitability(target, id, 1)
    if ok then
        mutation_seen[key] = true
    end
    return ok
end

print("[WorkSuitabilityUnlock " .. VERSION .. "] Loading.")
print("[WorkSuitabilityUnlock " .. VERSION .. "] Handbook-only suitability unlock enabled.")

local slot_pre, slot_post = RegisterHook(SLOT_TARGET_HOOK, function(Context, ...)
    local item, code = find_handbook(Context, ...)
    if not code then return nil end

    local target = find_target(Context, ...)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Slot handbook detected: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Slot target: " .. full_name(target))

    if target then
        mark_pending(target, code)
    end

    return true
end)

if slot_pre and slot_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Slot target hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: slot target hook registration failed.")
end

local static_pre, static_post = RegisterHook(STATIC_ITEM_HOOK, function(Context, ...)
    local item, code = find_handbook(Context, ...)
    if not code then return nil end

    local target = find_target(Context, ...)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Item-data handbook detected: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Item-data target: " .. full_name(target))

    if target then
        mark_pending(target, code)
    end

    return true
end)

if static_pre and static_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Static item target hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: static item target hook registration failed.")
end

local processor_pre, processor_post = RegisterHook(
    PROCESSOR_ITEM_HOOK,
    function(Context, ...)
        local item, code = find_handbook(Context, ...)
        if not code then return nil end

        local target = find_target(Context, ...)
        print("[WorkSuitabilityUnlock " .. VERSION .. "] Processor handbook detected: " .. code)
        print("[WorkSuitabilityUnlock " .. VERSION .. "] Processor target: " .. full_name(target))

        if target then
            local key = target_key(target, code)
            mutation_seen[key] = nil
            mark_pending(target, code)
        end

        return true
    end,
    function(Context, ...)
        local item, code = find_handbook(Context, ...)
        if not code then return nil end

        local target = find_target(Context, ...)
        if not target then
            print("[WorkSuitabilityUnlock " .. VERSION .. "] Processor post could not resolve target for " .. code)
            return nil
        end

        local key = target_key(target, code)
        -- Existing suitabilities are left completely to the game's native
        -- handbook transaction. Only zero/missing suitability is initialized.
        if not mutation_seen[key] then
            initialize_missing_suitability(target, code)
        end

        pending_target[key] = nil
        return nil
    end
)

if processor_pre and processor_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Item processor hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: processor hook registration failed.")
end

local can_use_pre, can_use_post = RegisterHook(CAN_USE_HOOK, function(Context, ...)
    local item, code = find_handbook(Context, ...)
    if not code then return nil end

    local target = find_target(Context, ...)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Handbook eligibility override: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Eligibility target: " .. full_name(target))

    if target then
        mark_pending(target, code)
    end

    return true
end)

if can_use_pre and can_use_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Rank-up eligibility hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: eligibility hook registration failed.")
end

local add_pre, add_post = RegisterHook(ADD_RANK_HOOK, function(Context, WorkSuitability, AddRank)
    local target = unwrap(Context)
    local suitability = tonumber(unwrap(WorkSuitability))
    local amount = tonumber(unwrap(AddRank))

    print("[WorkSuitabilityUnlock " .. VERSION .. "] SetWorkSuitabilityAddRank called: target=" .. full_name(target) .. " suitability=" .. tostring(suitability) .. " addRank=" .. tostring(amount))

    if not target or not suitability then return nil end

    local code = suitability_names[suitability]
    local key = target_key(target, code)

    if code and pending_target[key] and (amount == nil or amount <= 0) then
        -- Some missing-suitability paths reach the setter with zero because the
        -- native transaction expected the suitability to exist already. Turn
        -- that zero into the first real handbook rank.
        AddRank:Set(1)
        mutation_seen[key] = true
        print("[WorkSuitabilityUnlock " .. VERSION .. "] Converted missing handbook rank to 1: " .. code)
    end

    return nil
end)

if add_pre and add_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Rank mutation hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: rank mutation hook registration failed.")
end
