local VERSION = "v1.0"

local CAN_USE_HOOK = "/Script/Pal.PalUtility:CanUseTargetWorkSuitabilityRankUp"
local ADD_RANK_HOOK = "/Script/Pal.PalIndividualCharacterParameter:SetWorkSuitabilityAddRank"
local STATIC_ITEM_HOOK = "/Script/Pal.PalStaticItemDataBase:CanUseItemToCharacter"
local PROCESSOR_ITEM_HOOK = "/Script/Pal.PalItemUseProcessor:CanUseItemToCharacter"
local SERVER_USE_HOOK = "/Script/Pal.PalItemUseProcessor:UseItemToCharacter_ServerInternal"
local SLOT_TARGET_HOOK = "/Script/Pal.PalItemSlot:CanUseItemToCharacter"
local REQUEST_USE_HOOK = "/Script/Pal.PalItemSlot:RequestUseToCharacter"

local handbook_codes = {
    EmitFlame = true,
    Watering = true,
    Seeding = true,
    GenerateElectricity = true,
    Handcraft = true,
    Collection = true,
    Deforest = true,
    Mining = true,
    OilExtraction = true,
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
    OilExtraction = 9,
    ProductMedicine = 10,
    Cool = 11,
    Transport = 12,
    MonsterFarm = 13,
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
    if type(value) == "string" then
        return value:match("WorkSuitability_AddTicket_([%w_]+)")
    end
    local name = full_name(value)
    return name:match("WorkSuitability_AddTicket_([%w_]+)")
end

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

-- PalItemSlot:CanUseItemToCharacter only receives the target FPalInstanceID.
-- The handbook itself lives on the slot, so inspect the slot directly.
local function slot_handbook_code(slot)
    slot = unwrap(slot)
    if not slot then return nil end

    local ok, first, second = pcall(function()
        return slot:TryGetStaticItemData()
    end)

    if ok then
        local code = handbook_code(first)
        if code and handbook_codes[code] then return code end
        code = handbook_code(second)
        if code and handbook_codes[code] then return code end
    end

    local ok_id, item_id = pcall(function()
        return slot:GetItemId()
    end)
    if ok_id and item_id then
        local raw = unwrap(item_id)

        local ok_static, static_id = pcall(function()
            return raw.StaticId
        end)
        if ok_static and static_id then
            local code = handbook_code(tostring(unwrap(static_id)))
            if code and handbook_codes[code] then return code end
        end

        local code = handbook_code(tostring(raw))
        if code and handbook_codes[code] then return code end
    end

    return nil
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

local function get_character_manager(context)
    local manager = nil

    pcall(function()
        local util = StaticFindObject("/Script/Pal.Default__PalUtility")
        if util and util:IsValid() then
            manager = util:GetCharacterManager(context)
        end
    end)

    if manager and manager:IsValid() then return manager end

    pcall(function()
        manager = FindFirstOf("PalCharacterManager")
    end)

    if manager and manager:IsValid() then return manager end
    return nil
end

-- Inventory/item-use functions use FPalInstanceID rather than the parameter
-- object. Resolve that ID through PalCharacterManager.
local function resolve_target(context, ...)
    local direct = find_target(context, ...)
    if direct then return direct end

    local manager = get_character_manager(context)
    if not manager then return nil end

    local values = { ... }
    for _, value in ipairs(values) do
        local id = unwrap(value)
        if id ~= nil then
            local ok, target = pcall(function()
                return manager:GetIndividualCharacterParameter(id)
            end)
            if ok and target and target:IsValid() then
                return target
            end
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

    local ok = call_set_work_suitability(target, id, 1)
    if ok then
        mutation_seen[key] = true
    end
    return ok
end

local function prepare_target_for_handbook(target, code, source)
    target = unwrap(target)
    if not target or not code then return false end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] " .. tostring(source) .. " handbook target: " .. full_name(target) .. " code=" .. code)
    mark_pending(target, code)

    local ready = initialize_missing_suitability(target, code)
    if ready then
        print("[WorkSuitabilityUnlock " .. VERSION .. "] " .. tostring(source) .. " prepared missing suitability: " .. code)
    end
    return ready
end

print("[WorkSuitabilityUnlock " .. VERSION .. "] Loading.")
print("[WorkSuitabilityUnlock " .. VERSION .. "] Handbook-only suitability unlock enabled.")

local slot_pre, slot_post = RegisterHook(SLOT_TARGET_HOOK, function(Context, ...)
    local code = slot_handbook_code(Context)
    if not code then return nil end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Slot handbook detected: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Slot target allowed for handbook: " .. code)

    return true
end)

if slot_pre and slot_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Slot target hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: slot target hook registration failed.")
end

local request_pre, request_post = RegisterHook(REQUEST_USE_HOOK, function(Context, ...)
    local code = slot_handbook_code(Context)
    if not code then return nil end

    local target = resolve_target(Context, ...)
    prepare_target_for_handbook(target, code, "RequestUseToCharacter")
    return nil
end)

if request_pre and request_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Request-use handbook hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: request-use hook registration failed.")
end

local static_pre, static_post = RegisterHook(STATIC_ITEM_HOOK, function(Context, ...)
    local item, code = find_handbook(Context, ...)
    if not code then return nil end

    local target = resolve_target(Context, ...)
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

        local target = resolve_target(Context, ...)
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

        local target = resolve_target(Context, ...)
        if not target then
            print("[WorkSuitabilityUnlock " .. VERSION .. "] Processor post could not resolve target for " .. code)
            return nil
        end

        local key = target_key(target, code)
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

local server_pre, server_post = RegisterHook(
    SERVER_USE_HOOK,
    function(Context, ...)
        local item, code = find_handbook(Context, ...)
        if not code then return nil end

        local target = resolve_target(Context, ...)
        print("[WorkSuitabilityUnlock " .. VERSION .. "] Server-use handbook detected: " .. code)
        prepare_target_for_handbook(target, code, "ServerUse")

        -- Do not override the server-use return value. We only make the target
        -- satisfy the missing-suitability prerequisite before native execution.
        return nil
    end,
    function(Context, ...)
        local item, code = find_handbook(Context, ...)
        if not code then return nil end

        local target = resolve_target(Context, ...)
        if target then
            print("[WorkSuitabilityUnlock " .. VERSION .. "] Server-use post completed for " .. code .. " target=" .. full_name(target))
        end
        return nil
    end
)

if server_pre and server_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Server-use handbook hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: server-use handbook hook registration failed.")
end

local can_use_pre, can_use_post = RegisterHook(CAN_USE_HOOK, function(Context, ...)
    local item, code = find_handbook(Context, ...)
    if not code then return nil end

    local target = resolve_target(Context, ...)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Handbook eligibility override: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Eligibility target: " .. full_name(target))

    if target then
        prepare_target_for_handbook(target, code, "Eligibility")
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
