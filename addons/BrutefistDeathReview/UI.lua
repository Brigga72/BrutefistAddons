local _, D = ...
function D:Show(previous,diagnostics)
    if InCombatLockdown() then self:Print('Open the report after combat.');return end
    if not self.window then
        local f=CreateFrame('Frame',nil,UIParent)
        self.window=f
        f:SetSize(760,520);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG')
        f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag('LeftButton')
        f:SetScript('OnDragStart',function() f:StartMoving() end)
        f:SetScript('OnDragStop',function() f:StopMovingOrSizing() end)
        local bg=f:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(0.025,0.025,0.035,0.98)
        local title=f:CreateFontString(nil,'OVERLAY','GameFontNormal')
        title:SetPoint('TOPLEFT',16,-14);title:SetText('Death Review - Ctrl+A, Ctrl+C to copy; Escape closes')
        local close=CreateFrame('Button',nil,f,'UIPanelCloseButton');close:SetPoint('TOPRIGHT')
        local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate')
        scroll:SetPoint('TOPLEFT',16,-42);scroll:SetPoint('BOTTOMRIGHT',-36,16)
        local edit=CreateFrame('EditBox',nil,scroll)
        edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(700);edit:SetHeight(450);edit:SetMaxLetters(0)
        edit:SetScript('OnEscapePressed',function() f:Hide() end)
        scroll:SetScrollChild(edit);self.edit=edit
    end
    local text
    if previous then text=self.saved and (self.saved.lastReview or self.saved.lastReport) end
    self.edit:SetText(text or (diagnostics and self:Report() or self:Review()))
    self.window:Show();self.edit:SetFocus();self.edit:HighlightText()
end
SLASH_BRUTEFISTDEATHREVIEW1='/bdeath'
SlashCmdList.BRUTEFISTDEATHREVIEW=function(input)
    input=(input or ''):lower():match('^%s*(.-)%s*$')
    if not D.ready then return end
    if input=='start' then D:Start()
    elseif input=='stop' then D:Stop('Manual stop');D:Print('Snapshot saved. /bdeath report to copy it.')
    elseif input=='previous' then D:Show(true)
    elseif input=='diagnostics' then D:Show(false,true)
    elseif input=='report' or input=='' then D:Show()
    else D:Print('/bdeath start | stop | report | previous | diagnostics') end
end
