local VERSION = "v0.4"

local CAN_USE_HOOK = "/Script/Pal.PalUtility:CanUseTargetWorkSuitabilityRankUp"
local ADD_RANK_HOOK = "/Script/Pal.PalIndividualCharacterParameter:SetWorkSuitabilityAddRank"
local STATIC_ITEM_HOOK = "/Script/Pal.PalStaticItemDataBase:CanUseItemToCharacter"
local PROCESSOR_ITEM_HOOK = "/Script/Pal.PalItemUseProcessor:CanUseItemToCharacter"

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

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function()
        if value.get then return value:get() end
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

print("[WorkSuitabilityUnlock " .. VERSION .. "] Loading.")
print("[WorkSuitabilityUnlock " .. VERSION .. "] Target-selection hooks enabled.")

-- Handbook target selection is checked before the rank-up eligibility path.
-- Override only the twelve Applied Work Suitability Handbooks so a Pal with
-- no natural rank in that suitability can still be selected.
local static_pre, static_post = RegisterHook(STATIC_ITEM_HOOK, function(Context, IndividualParameter)
    if not is_handbook(Context) then
        return nil
    end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Item-data target override: " .. handbook_code(Context))
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Target: " .. full_name(IndividualParameter))
    return true
end)

if static_pre and static_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Static item target hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: static item target hook registration failed.")
end

local processor_pre, processor_post = RegisterHook(PROCESSOR_ITEM_HOOK, function(Context, IndividualParameter, Item)
    if not is_handbook(Item) then
        return nil
    end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Processor target override: " .. handbook_code(Item))
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Target: " .. full_name(IndividualParameter))
    return true
end)

if processor_pre and processor_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Item processor target hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: item processor target hook registration failed.")
end

-- Keep the native rank-up eligibility path permissive as a second layer.
local can_use_pre, can_use_post = RegisterHook(CAN_USE_HOOK, function(Context, IndividualParameter, Item)
    if not is_handbook(Item) then
        return nil
    end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Handbook eligibility override: " .. handbook_code(Item))
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Target parameter: " .. full_name(IndividualParameter))
    return true
end)

if can_use_pre and can_use_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Rank-up eligibility hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: rank-up eligibility hook registration failed.")
end

-- Do not manufacture reflected WorkSuitability_* values here. The native
-- SetWorkSuitabilityAddRank implementation owns the persistent add-rank list,
-- save data, delegates, and replication.
local add_pre, add_post = RegisterHook(ADD_RANK_HOOK, function(Context, WorkSuitability, AddRank)
    local target = unwrap(Context)
    local suitability = unwrap(WorkSuitability)
    local amount = unwrap(AddRank)

    print("[WorkSuitabilityUnlock " .. VERSION .. "] SetWorkSuitabilityAddRank called: target=" .. full_name(target) .. " suitability=" .. tostring(suitability) .. " addRank=" .. tostring(amount))
    return nil
end)

if add_pre and add_post then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Rank mutation hook registered.")
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] WARNING: rank mutation hook registration failed.")
end
