util.AddNetworkString( "cloadout.apply" )

local cvarPrimaryLimit = CreateConVar(
    "custom_loadout_primary_limit",
    "5000",
    bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ),
    "[Custom Loadout] Limits how much primary ammo is given to players.",
    0, 9999
)

local cvarSecondaryLimit = CreateConVar(
    "custom_loadout_secondary_limit",
    "50",
    bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY ),
    "[Custom Loadout] Limits how much secondary ammo is given to players.",
    0, 9999
)

-- store player loadouts
CLoadout.cache = {}

function CLoadout:IsAvailableForPlayer( ply )
    -- builderx compatibility
    if ply.GetBuild and ply:GetBuild() then
        return false, "Your loadout will be applied once you leave build mode."
    end

    return true
end

function CLoadout:GiveWeapons( ply )
    if not IsValid( ply ) or ply:Health() <= 0 then return end

    ply:StripWeapons()

    local cache = self.cache[ply:SteamID()]
    local items = cache.items

    if #items == 0 then return end

    ply:StripAmmo()

    local maxPrimary = cvarPrimaryLimit:GetInt()
    local maxSecondary = cvarSecondaryLimit:GetInt()

    local preferredWeapon

    for _, item in ipairs( items ) do
        local swep = list.Get( "Weapon" )[item[1]]
        if not swep then continue end

        -- dont give admin-only weapons if ply is not a admin (duh)
        if ( swep.AdminOnly or not swep.Spawnable ) and not ply:IsAdmin() then continue end

        -- sandbox compatibility (yeah...)
        if not gamemode.Call( "PlayerGiveSWEP", ply, item[1], swep ) then continue end

        if self:IsBlacklisted( ply, item[1] ) then continue end

        local success, weapon = pcall( ply.Give, ply, swep.ClassName )

        if success and IsValid( weapon ) then
            -- give ammo
            local primaryAmount = math.Clamp( item[2], 0, maxPrimary )
            local secondaryAmount = math.Clamp( item[3], 0, maxSecondary )

            if primaryAmount > 0 and weapon:GetPrimaryAmmoType() ~= -1 then
                ply:GiveAmmo( primaryAmount, weapon:GetPrimaryAmmoType() )
            end

            if secondaryAmount > 0 and weapon:GetSecondaryAmmoType() ~= -1 then
                ply:GiveAmmo( secondaryAmount, weapon:GetSecondaryAmmoType() )
            end

            if cache.preferred == swep.ClassName then
                -- if this is the prefered weapon by this ply, remember it
                preferredWeapon = swep.ClassName
            end
        end
    end

    if preferredWeapon then
        ply:SelectWeapon( preferredWeapon )
    end
end

function CLoadout:Apply( ply )
    if not self:IsAvailableForPlayer( ply ) then return end

    local steam_id = ply:SteamID()

    -- timers were used here just to override other addon"s shenanigans

    if self.cache[steam_id] and self.cache[steam_id].enabled then
        timer.Simple( 0.1, function() CLoadout:GiveWeapons( ply ) end )

        return true
    end
end

function CLoadout:ReceiveData( len, ply )
    local data = net.ReadData( len )
    data = util.Decompress( data )

    if not data or data == "" then return end

    local steam_id = ply:SteamID()
    local loadout = util.JSONToTable( data )

    if not loadout then
        CLoadout.PrintF( "Failed to parse %s\"s loadout!", ply:Nick() )

        return
    end

    self.cache[steam_id] = {
        enabled = loadout.enabled,
        preferred = loadout.preferred,
        items = {}
    }

    -- no need to go further if the loadout is not enabled
    if not loadout.enabled then return end

    -- filter inexistent weapons
    for _, item in ipairs( loadout.items ) do
        local swep = list.Get( "Weapon" )[item[1]]

        if swep then
            table.insert(
                self.cache[steam_id].items,
                {
                    item[1],                    -- class
                    tonumber( item[2] ) or 0,   -- primary ammo
                    tonumber( item[3] ) or 0    -- secondary ammo
                }
            )
        end
    end

    local canUse, reason = self:IsAvailableForPlayer( ply )

    if not canUse then
        ply:ChatPrint( "[Custom Loadout] " .. reason )

        return
    end

    self:GiveWeapons( ply )
end

-- remove the loadout from cache when players leave
hook.Add( "PlayerDisconnected", "CLoadout_ClearCache", function( ply )
    if not ply:IsBot() and CLoadout.cache[ply:SteamID()] then
        CLoadout.cache[ply:SteamID()] = nil
    end
end )

-- apply the loadout
hook.Add( "PlayerLoadout", "CLoadout_ApplyLoadout", function( ply )
    return CLoadout:Apply( ply )
end )

-- apply the loadout when leaving build mode (builderx)
hook.Add( "builderx.mode.onswitch", "CLoadout_ApplyLoadoutOnExitBuild", function( ply, bIsBuild )
    if not bIsBuild then
        CLoadout:Apply( ply )
    end
end )

net.Receive( "cloadout.apply", function( len, ply )
    CLoadout:ReceiveData( len, ply )
end )