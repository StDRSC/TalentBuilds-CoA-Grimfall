TalentBuildsDB = TalentBuildsDB or {}

local function Say(msg) print("|cff33ff99TB:|r " .. msg) end

local MAX_ACTION_BUTTONS = 120

local function SaveBars()
    local bars = {}
    for i = 1, MAX_ACTION_BUTTONS do
        local actionType, id, subType = GetActionInfo(i)
        if actionType then
			if actionType == "spell" then
                local name = GetSpellName(id, BOOKTYPE_SPELL)
                if name then bars[i] = { type = "spell", name = name } end
				
            elseif actionType == "item" then bars[i] = { type = "item", id = id }
			
            elseif actionType == "companion" then
				local cID, name = GetCompanionInfo(subType, id)
                bars[i] = { type = "companion", id = id, subType = subType, name = name }
				
            elseif actionType == "macro" then
                local mName, mIcon, mBody = GetMacroInfo(id)
                if mName then bars[i] = { type = "macro", name = mName, icon = mIcon, body = mBody } end
            end
        end
    end
    return bars
end

local function FindOrCreateMacro(macroData)
    local numGlobal, numChar = GetNumMacros()
    for i = 1, numGlobal + numChar do
        local name, _, body = GetMacroInfo(i)
        if name == macroData.name and body == macroData.body then return i end
    end
	
    if numGlobal + numChar < 54 then
        CreateMacro(macroData.name, macroData.icon or 1, macroData.body, 0)
        local newGlobal, newChar = GetNumMacros()
        for i = 1, newGlobal + newChar do
            if (GetMacroInfo(i)) == macroData.name then return i end
        end
    end
end

local function LoadBars(bars)
    if not bars or next(bars) == nil then return end
    if InCombatLockdown() then
        Say("Cannot restore action bars in combat.")
        return
    end

    local spellCache = {}
    for book = 1, MAX_SKILLLINE_TABS do
        local _, _, offset, numSpells = GetSpellTabInfo(book)
        for i = 1, numSpells do
            local index = offset + i
            if not IsPassiveSpell(index, BOOKTYPE_SPELL) then
                local name = GetSpellName(index, BOOKTYPE_SPELL)
                if name then spellCache[name] = index end
            end
        end
    end

    ClearCursor()
    
    for i = 1, MAX_ACTION_BUTTONS do
        local actionType, id = GetActionInfo(i)
        if actionType and id then
            PickupAction(i)
            ClearCursor()
        end

        local data = bars[i]
        if data then
            if data.type == "spell" then
                local spellIndex = spellCache[data.name] 
                if spellIndex then
                    PickupSpell(spellIndex, BOOKTYPE_SPELL)
                    PlaceAction(i)
                end
				
            elseif data.type == "item" then
                PickupItem(data.id)
                if GetCursorInfo() == "item" then PlaceAction(i) else ClearCursor() end
				
            elseif data.type == "companion" then
				local found
				local num = GetNumCompanions(data.subType)
				for index = 1, num do
					local _, creatureName = GetCompanionInfo(data.subType, index)
					if creatureName == data.name then
						found = index
						break 
					end
				end
				PickupCompanion(data.subType, found)
                if GetCursorInfo() == "companion" then PlaceAction(i) else ClearCursor() end
				
            elseif data.type == "macro" then
                local mSlot = FindOrCreateMacro(data)
                if mSlot then
                    PickupMacro(mSlot)
                    if GetCursorInfo() == "macro" then PlaceAction(i) else ClearCursor() end
                end
            end
        end
    end
end

local function GetDialog()
    local f = CoATalentFrameBuildTransfer
    if f and f.edit and f.import then return f end
end

local SHARE_PATH = {3, 1, 10}

local function FindShareButton()
    local c = CoATalentFrame
    if not c then return end
    for _, idx in ipairs(SHARE_PATH) do
        c = select(idx, c:GetChildren())
        if not c then return end
    end
    if c:GetObjectType() ~= "Button" then return end
    if not c:GetScript("OnClick") then return end
    return c
end

local watcher = CreateFrame("Frame")

local function SaveBuild(name, gset)
    local pName = UnitName("player")
    local f = GetDialog()
    local btn = FindShareButton()
    if not (f and btn) then
        Say("Share Build button not found (open your talents first)")
        return
    end

    f.edit:SetText("")
    btn:Click()

    local elapsed = 0
    watcher:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        local str = f.edit:GetText()
        if str and str:find("^CoA:") then
            self:SetScript("OnUpdate", nil)
            TalentBuildsDB[pName] = TalentBuildsDB[pName] or {}
            
            TalentBuildsDB[pName][name] = {
                talent = str,
                bars = SaveBars(),
				set = gset
            }
            
            f:Hide()
			if gset ~= nil then Say("saved as '" .. name .. "' with set '" .. gset .. "'")
			else Say("saved as '" .. name .. "'") end
			
        elseif elapsed > 1 then
            self:SetScript("OnUpdate", nil)
            Say("export string did not appear, nothing saved")
        end
    end)
end

local function FindButtonByText(parent, text, depth)
    depth = depth or 0
    if depth > 8 then return end
    for _, c in ipairs({parent:GetChildren()}) do
        if c:GetObjectType() == "Button" and c:GetText() == text then return c end
        local found = FindButtonByText(c, text, depth + 1)
        if found then return found end
    end
end

local applier = CreateFrame("Frame")
local barApplier = CreateFrame("Frame")

local function LoadBuild(name)
    local pName = UnitName("player")
    local build = TalentBuildsDB[pName] and TalentBuildsDB[pName][name]
    if not build then Say("no build named '" .. name .. "' was found.") return end
    
    local str, bars
    if type(build) == "string" then str = build
    else
        str = build.talent
        bars = build.bars
    end

    local f = GetDialog()
    if not f then Say("import dialog not found") return end

    local wasShown = f:IsShown()
    if not wasShown then f:Show() end

    f.edit:SetMaxLetters(0)
    f.edit:SetText(str)
    f.import:Click()

    if not wasShown then f:Hide() end

    local save = FindButtonByText(CoATalentFrame, "Save Changes")
    if not save then
        Say("imported '" .. name .. "', but Save Changes button not found")
        return
    end

    local elapsed = 0
    applier:SetScript("OnUpdate", function(self, e)
        elapsed = elapsed + e
        if elapsed < 0.2 then return end
        if save:IsEnabled() then
            self:SetScript("OnUpdate", nil)
            save:Click()
            Say("applied talents for '" .. name .. "'")
            
            if bars then
                local barElapsed = 0
                barApplier:SetScript("OnUpdate", function(self, ev)
                    barElapsed = barElapsed + ev
                    if barElapsed > 0.5 then
                        self:SetScript("OnUpdate", nil)
                        LoadBars(bars)
                        Say("restored action bars")
						
						if build.set ~= nil then
							if GetEquipmentSetInfoByName(build.set) then
								UseEquipmentSet(build.set)
								Say("equipped set '" .. build.set .. "'")
								
							else Say("no set named '" .. build.set .. "' was found") end
						end
                    end
                end)
            end
			
        elseif elapsed > 2 then
            self:SetScript("OnUpdate", nil)
            Say("Save Changes stayed disabled, nothing was applied")
        end
    end)


end

SLASH_TB1 = "/tb"
SlashCmdList["TB"] = function(msg)
    local pName = UnitName("player")
    local cmd, name, set = msg:match("^(%S*)%s*(%S*)%s*(.-)%s*$")
	if set == "" then set = nil end
    
    if cmd == "save" and name ~= "" then SaveBuild(name, set)
	
    elseif cmd == "load" and name ~= "" then LoadBuild(name)
	
    elseif cmd == "delete" and name ~= "" then
        TalentBuildsDB[pName] = TalentBuildsDB[pName] or {}
        TalentBuildsDB[pName][name] = nil
        Say("deleted '" .. name .. "'")
		
    elseif cmd == "list" then
        TalentBuildsDB[pName] = TalentBuildsDB[pName] or {}
        local n = 0
        for k, v in pairs(TalentBuildsDB[pName]) do
            Say(k)
            n = n + 1
        end
        if n == 0 then Say("no saved builds") end
		
    else
        Say("/tb save <name>")
        Say("/tb save <name> <gear set>")
        Say("/tb load <name>")
        Say("/tb delete <name>")
        Say("/tb list")
    end
end