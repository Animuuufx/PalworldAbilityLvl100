local VERSION = "v0.2"

local HOOK = "/Script/Pal.PalUtility:CanUseTargetWorkSuitabilityRankUp"

-- Applied handbook item suffix -> the actual suitability property stored on
-- UPalIndividualCharacterParameter.  The native handbook transaction can
-- then perform its normal +1 rank operation after we seed a missing entry.
local handbook_properties = {
    EmitFlame = "WorkSuitability_EmitFlame",
    Watering = "WorkSuitability_Watering",
    Seeding = "WorkSuitability_Seeding",
    GenerateElectricity = "WorkSuitability_GenerateElectricity",
    Handcraft = "WorkSuitability_Handcraft",
    Collection = "WorkSuitability_Collection",
    Deforest = "WorkSuitability_Deforest",
    Mining = "WorkSuitability_Mining",
    ProductMedicine = "WorkSuitability_ProductMedicine",
    Cool = "WorkSuitability_Cool",
    Transport = "WorkSuitability_Transport",
    MonsterFarm = "WorkSuitability_MonsterFarm",
}

local function unwrap(value)
    if value == nil then
        return nil
    end

    local ok, result = pcall(function()
        if value.get then
            return value:get()
        end
        return value
    end)

    return ok and result or nil
end

local function full_name(value)
    local object = unwrap(value)
    if not object then
        return "<nil>"
    end

    local ok, name = pcall(function()
        return object:GetFullName()
    end)
    return ok and tostring(name) or "<unnamed>"
end

local function handbook_code(value)
    local name = full_name(value)
    return name:match("WorkSuitability_AddTicket_([%w_]+)")
end

local function seed_missing_suitability(parameter, property_name, code)
    -- Database/default Pal parameters use an integer rank of 0 to mean that
    -- the Pal does not currently possess that work suitability.  Setting the
    -- reflected parameter to rank 1 before the native handbook eligibility
    -- check lets the game's normal handbook path recognize and rank it up.
    local current_ok, current = pcall(function()
        return tonumber(parameter[property_name])
    end)

    if not current_ok then
        print("[WorkSuitabilityUnlock " .. VERSION .. "] ERROR: unable to read " .. property_name)
        return false
    end

    current = current or 0
    if current > 0 then
        return false
    end

    local write_ok, write_err = pcall(function()
        parameter[property_name] = 1
    end)

    if not write_ok then
        print("[WorkSuitabilityUnlock " .. VERSION .. "] ERROR: failed to seed " .. property_name .. ": " .. tostring(write_err))
        return false
    end

    local verify_ok, verify = pcall(function()
        return tonumber(parameter[property_name])
    end)

    if not verify_ok or (verify or 0) < 1 then
        print("[WorkSuitabilityUnlock " .. VERSION .. "] ERROR: " .. property_name .. " did not verify after write.")
        return false
    end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Added missing suitability: " .. code .. " -> " .. property_name .. " = " .. tostring(verify))
    return true
end

print("[WorkSuitabilityUnlock " .. VERSION .. "] Loading.")
print("[WorkSuitabilityUnlock " .. VERSION .. "] Hook target: " .. HOOK)

local pre_id, post_id = RegisterHook(HOOK, function(Context, IndividualParameter, Item)
    local code = handbook_code(Item)
    local property_name = code and handbook_properties[code] or nil

    if not property_name then
        return nil
    end

    local parameter = unwrap(IndividualParameter)
    if not parameter then
        print("[WorkSuitabilityUnlock " .. VERSION .. "] ERROR: target parameter is unavailable for " .. code)
        return nil
    end

    print("[WorkSuitabilityUnlock " .. VERSION .. "] Handbook detected: " .. code)
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Target: " .. full_name(parameter))

    -- Only seed a missing suitability. Existing suitabilities are untouched;
    -- their normal native handbook rank-up behavior remains unchanged.
    seed_missing_suitability(parameter, property_name, code)

    -- Do not override the native boolean result. The original function must
    -- evaluate the now-present suitability and continue the normal transaction.
    return nil
end)

if pre_id and post_id then
    print("[WorkSuitabilityUnlock " .. VERSION .. "] Hook registered successfully. PreId=" .. tostring(pre_id) .. " PostId=" .. tostring(post_id))
else
    print("[WorkSuitabilityUnlock " .. VERSION .. "] ERROR: failed to register handbook eligibility hook.")
end
