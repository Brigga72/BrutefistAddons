local _,G=...
local skills={[1]=172,[5]=160,[8]=55,[10]=136,[6]=229}
function G:WeaponSkill(item)
    if InCombatLockdown() or not C_SkillInfo or type(C_SkillInfo.GetNumSkillLines)~="function" or type(C_SkillInfo.GetSkillLineInfo)~="function" then return end
    if not C_Item or type(C_Item.GetItemInfoInstant)~="function" then return end
    local ok,_,_,_,_,_,class,subclass=pcall(C_Item.GetItemInfoInstant,item.link)
    class,subclass=self:Number(class),self:Number(subclass)
    if not ok or class~=2 or not subclass or not skills[subclass] then return end
    local worked,count=pcall(C_SkillInfo.GetNumSkillLines);count=worked and self:Number(count) or nil
    if not count or count<0 or count>200 or count%1~=0 then return end
    for i=1,count do
        local success,row=pcall(C_SkillInfo.GetSkillLineInfo,i)
        if success and self:Table(row) then
            local id=self:Number(row.skillID)
            if id==skills[subclass] then
                local rank,max,modifier,temp=self:Number(row.rank),self:Number(row.maxRank),self:Number(row.modifier),self:Number(row.tempPoints)
                if rank and max and modifier and temp and max>0 then return {rank=rank,max=max,effective=rank+modifier+temp,name=self:Text(row.name)} end
            end
        end
    end
end
function G:SkillWarning(item,old)
    local a,b=self:WeaponSkill(item),self:WeaponSkill(old)
    if not a or not b then return "Weapon skill unavailable; check your Skills panel." end
    if a.effective<b.effective then
        return string.format("Train %s before judging performance: %d/%d versus equipped skill %d/%d. Damage estimate excludes skill penalties.",a.name,a.rank,a.max,b.rank,b.max)
    end
    if a.rank<a.max then return string.format("%s skill %d/%d; damage estimate excludes skill penalties.",a.name,a.rank,a.max) end
    return nil
end
