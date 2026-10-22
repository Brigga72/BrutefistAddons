local addon, G = ...
function G:Report()
    self:RefreshProfile(true)
    local v,b,_,i=GetBuildInfo()
    local lines={"Brutefist Gear Advisor "..self.version,"Client "..self:Text(v).." build "..self:Text(b).." interface "..self:Text(i),
        "Tooltip hook: "..(self.hookStatus or "not initialized"),
        "Two-handed questing profile. Automatic values and manual fallbacks listed below.",
        "Typical questing uses calibrated crit and a simplified Flurry estimate. Weapon comparisons estimate Windfury and Stormstrike; hit/item procs remain unmodeled.",
        "Strength AP conversion and all score weights are starter assumptions."}
    local keys={}
    for k in pairs(self.defaults) do keys[#keys+1]=k end
    table.sort(keys)
    lines[#lines+1]="Saved manual settings (automatic effective values listed later):"
    for _,k in ipairs(keys) do lines[#lines+1]=k.."="..self.db[k] end
    local info=type(C_Item)=="table" and type(C_Item.GetItemStats)=="function"
    lines[#lines+1]="C_Item.GetItemStats available: "..tostring(info)
    lines[#lines+1]="Identical diagnostic lines suppressed: " .. (self.duplicates or 0)
    for _, line in ipairs(self:CalibrationReport()) do lines[#lines+1]=line end
    for _, line in ipairs(self:QuestingReport()) do lines[#lines+1]=line end
    lines[#lines+1]="Weapon assumptions: Windfury AP/rank uses readable rendered tooltip or manual fallback, ICD manual (default 0), no recursive or Stormstrike-triggered procs. Stormstrike interval assumes on cooldown, no resets. Normalized AP speed assumed 3.3. Usability/weapon skill: check native tooltip."
    for _, line in ipairs(self:Probe()) do lines[#lines+1]=line end
    for _, line in ipairs(self:SkillProbe()) do lines[#lines+1]=line end
    for _, line in ipairs(self:AdaptiveReport()) do lines[#lines+1]=line end
    lines[#lines+1]="--- Recent comparisons / unsupported stat keys ---"
    for _,l in ipairs(self.history) do lines[#lines+1]=l end
    return table.concat(lines,"\n")
end
function G:Diagnostics()
    if InCombatLockdown() then self:Print("Open diagnostics after combat.");return end
    if not self.window then
        local f=CreateFrame("Frame",nil,UIParent);self.window=f
        f:SetSize(650,420);f:SetPoint("CENTER");f:SetFrameStrata("DIALOG")
        local bg=f:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(0.03,0.03,0.03,0.98)
        local title=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
        title:SetPoint("TOPLEFT",16,-16);title:SetText("Gear diagnostics: Ctrl+A, Ctrl+C")
        local close=CreateFrame("Button",nil,f,"UIPanelCloseButton");close:SetPoint("TOPRIGHT")
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",16,-45);scroll:SetPoint("BOTTOMRIGHT",-35,16)
        local edit=CreateFrame("EditBox",nil,scroll);self.edit=edit
        edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(595);edit:SetHeight(340);scroll:SetScrollChild(edit)
        edit:SetScript("OnEscapePressed",function() f:Hide() end)
    end
    self.edit:SetText(self:Report());self.window:Show();self.edit:SetFocus();self.edit:HighlightText()
end
local frame=CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent",function(_,_,name)
    if name~=addon then return end
    BrutefistGearDB=BrutefistGearDB or {};G.db=BrutefistGearDB
    for k,v in pairs(G.defaults) do
        local n=G:Number(G.db[k]); if not n or n<0 or n>(k=="windfuryAP" and 2000 or 100) then G.db[k]=v end
        if (k=="meleeShare" or k=="flurryHaste" or k=="windfuryChance") and G.db[k]>1 or (k=="apPerDPS" or k=="spellBase" or k=="stormstrikeInterval" or k=="weaponNormalization") and G.db[k]<=0 then G.db[k]=v end
    end
    G:Hook();G:Print("v" .. G.version .. " ready. Hover an item; /bgear diag for diagnostics. /bgear for settings.")
end)
SLASH_BRUTEFISTGEAR1="/bgear"
SlashCmdList.BRUTEFISTGEAR=function(input)
    local cmd,key,value=input:match("^(%S*)%s*(%S*)%s*(.-)$")
    if cmd=="baseline" then G:Baseline();return end
    if cmd=="calibrate" then G:Calibrate();return end
    if cmd=="diag" or cmd=="probe" then G:Diagnostics();return end
    if cmd=="set" then
        local n=tonumber(value)
        if G.defaults[key]==nil or not n or n~=n or n<0 or n>(key=="windfuryAP" and 2000 or 100) then
            G:Print("Use /bgear set KEY VALUE. /bgear lists valid keys.");return
        end
        if (key=="meleeShare" or key=="flurryHaste" or key=="windfuryChance") and n>1 or (key=="apPerDPS" or key=="spellBase" or key=="stormstrikeInterval" or key=="weaponNormalization") and n<=0 then
            G:Print("Shares/Flurry must be 0 through 1; AP divisor/base spell must be positive.");return
        end
        G.db[key]=n;G.runtimeProfile=nil;G.profileTime=nil;G:Print(key.."="..n..". Manual fallback saved; readable automatic values take precedence.");return
    end
    if cmd=="reset" then for k,v in pairs(G.defaults) do G.db[k]=v end;G:Print("Starter profile restored.");return end
    G:Print("/bgear baseline, /bgear calibrate, /bgear diag, /bgear probe, /bgear set KEY VALUE, /bgear reset")
    G:Print("Questing model: meleeShare=0.85, flurryHaste=0.25, apPerDPS=14, spellBase=100, spellCoefficient=0.4. All adjustable assumptions.")
    G:Print("Fallback weights: apWeight=1, spellWeight=0.3, agilityWeight=1 (adjustable assumptions).")
    G:Print("Conversions: strengthAP=2 (assumed), intellectBonus=0.04, intellectAP=1, intellectSP=0.3 (confirmed talents).")
end
