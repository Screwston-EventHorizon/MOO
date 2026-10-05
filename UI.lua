-- MOO UI: the main window (styled like Blizzard's guild window, as Olympus is),
-- the player detail card (rating + gear + stats), and the minimap button.

local _, ns = ...

local W, H = 760, 520
local main, pages, tabs = nil, {}, {}

------------------------------------------------------------------------
-- Widget helpers
------------------------------------------------------------------------
local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Button(parent, label, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 90, h or 22)
    b:SetText(label)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function EditBox(parent, w, maxLetters)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters or 60)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

-- "< value >" picker over a list of {value, label}
local function Cycler(parent, w, getItems, onChange)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(w, 22)
    c.index = 1
    local left = Button(c, "<", 22, 22)
    local right = Button(c, ">", 22, 22)
    left:SetPoint("LEFT")
    right:SetPoint("RIGHT")
    c.label = Text(c, "GameFontHighlightSmall", "CENTER")
    c.label:SetPoint("LEFT", left, "RIGHT", 2, 0)
    c.label:SetPoint("RIGHT", right, "LEFT", -2, 0)
    function c:Refresh()
        local items = getItems()
        if self.index > #items then self.index = 1 end
        local it = items[self.index]
        self.label:SetText(it and it.label or "-")
        self.value = it and it.value
    end
    function c:SetValue(v)
        for i, it in ipairs(getItems()) do if it.value == v then self.index = i end end
        self:Refresh()
    end
    local function step(d)
        local n = #getItems()
        if n == 0 then return end
        c.index = (c.index - 1 + d) % n + 1
        c:Refresh()
        if onChange then onChange(c.value) end
    end
    left:SetScript("OnClick", function() step(-1) end)
    right:SetScript("OnClick", function() step(1) end)
    c:Refresh()
    return c
end

-- Dropdown menu with the same interface as Cycler (value, SetValue, Refresh).
-- Items: { value=, label= } or { header=true, label= } for a section title.
-- Uses the game's current dropdown (WowStyle1DropdownTemplate); falls back to the
-- classic UIDropDownMenu, and to the arrow picker only if neither exists.
local dropdownCount = 0
local function Dropdown(parent, w, getItems, onChange)
    local function firstValue(items)
        for _, it in ipairs(items) do if not it.header then return it.value end end
    end
    local function labelOf(v)
        for _, it in ipairs(getItems()) do
            if not it.header and it.value == v then return it.label end
        end
    end

    local dd
    local ok, f = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if ok and f and f.SetupMenu then
        dd = f
        dd:SetWidth(w)
        dd:SetupMenu(function(_, root)
            local items = getItems()
            if root.SetScrollMode and #items > 18 then root:SetScrollMode(18 * 20) end
            for _, it in ipairs(items) do
                if it.header then
                    root:CreateTitle(it.label)
                else
                    root:CreateRadio(it.label,
                        function(v) return dd.value == v end,
                        function(v) dd:Select(v, true) end,
                        it.value)
                end
            end
        end)
        function dd:ShowLabel(text)
            if self.OverrideText then self:OverrideText(text)
            elseif self.Text then self.Text:SetText(text) end
        end
    else
        dropdownCount = dropdownCount + 1
        local okU, u = pcall(CreateFrame, "Frame", "MOODropDown" .. dropdownCount, parent, "UIDropDownMenuTemplate")
        if not okU or not u or not UIDropDownMenu_Initialize then
            return Cycler(parent, w, getItems, onChange)
        end
        dd = u
        UIDropDownMenu_SetWidth(dd, w - 20)
        UIDropDownMenu_Initialize(dd, function(_, level)
            for _, it in ipairs(getItems()) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = it.label
                if it.header then
                    info.isTitle = true
                    info.notCheckable = true
                else
                    info.checked = (dd.value == it.value)
                    info.func = function() dd:Select(it.value, true); CloseDropDownMenus() end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        function dd:ShowLabel(text) UIDropDownMenu_SetText(self, text) end
    end

    function dd:SetValue(v)
        self.value = v
        self:ShowLabel(labelOf(v) or "-")
    end
    function dd:Refresh()
        if not self.value or not labelOf(self.value) then self.value = firstValue(getItems()) end
        self:ShowLabel(labelOf(self.value) or "-")
    end
    function dd:Select(v, fire)
        self:SetValue(v)
        if fire and onChange then onChange(v) end
    end
    dd:Refresh()
    return dd
end

-- Dropdown with checkboxes (pick several). Items: { value=, label=, exclusive=true }.
-- An "exclusive" item (like "Anything") clears the others, and picking another clears it.
-- dd.selected is a set { [value] = true }; onChange(selected) fires on every change.
local function MultiDropdown(parent, w, getItems, onChange, opts)
    opts = opts or {}
    local dd

    local function summary()
        local names, n = {}, 0
        for _, it in ipairs(getItems()) do
            if not it.header and dd.selected[it.value] then
                n = n + 1
                table.insert(names, it.short or it.label)
            end
        end
        if n == 0 then return opts.none or "None" end
        if n <= (opts.showNames or 2) then return table.concat(names, ", ") end
        return n .. " " .. (opts.plural or "selected")
    end

    local function toggle(v)
        local items = getItems()
        local exclusive, count = false, 0
        for _, it in ipairs(items) do
            if it.value == v then exclusive = it.exclusive end
            if dd.selected[it.value] then count = count + 1 end
        end
        if dd.selected[v] then
            dd.selected[v] = nil
        else
            if exclusive then
                wipe(dd.selected)
            else
                for _, it in ipairs(items) do
                    if it.exclusive and dd.selected[it.value] then dd.selected[it.value] = nil; count = count - 1 end
                end
                if opts.max and count >= opts.max then
                    ns.Print("You can pick up to " .. opts.max .. ".")
                    return
                end
            end
            dd.selected[v] = true
        end
        dd:ShowLabel(summary())
        if onChange then onChange(dd.selected) end
    end

    local ok, f = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    if ok and f and f.SetupMenu then
        dd = f
        dd.selected = {}            -- must exist before SetupMenu: it builds the menu right away
        dd:SetWidth(w)
        dd:SetupMenu(function(_, root)
            local items = getItems()
            if root.SetScrollMode and #items > 18 then root:SetScrollMode(18 * 20) end
            for _, it in ipairs(items) do
                if it.header then
                    root:CreateTitle(it.label)
                else
                    root:CreateCheckbox(it.label,
                        function(v) return dd.selected ~= nil and dd.selected[v] == true end,
                        function(v)
                            toggle(v)
                            return MenuResponse and MenuResponse.Refresh   -- keep the menu open
                        end,
                        it.value)
                end
            end
        end)
        function dd:ShowLabel(text)
            if self.OverrideText then self:OverrideText(text)
            elseif self.Text then self.Text:SetText(text) end
        end
    else
        dropdownCount = dropdownCount + 1
        local okU, u = pcall(CreateFrame, "Frame", "MOODropDown" .. dropdownCount, parent, "UIDropDownMenuTemplate")
        if not okU or not u or not UIDropDownMenu_Initialize then
            -- last resort: a single-choice picker that still reports a set
            local c
            c = Dropdown(parent, w, getItems, function(v)
                c.selected = { [v] = true }
                if onChange then onChange(c.selected) end
            end)
            c.selected = {}
            function c:SetSelected(set)
                for v in pairs(set or {}) do self:SetValue(v) break end
                self.selected = {}
                if self.value then self.selected[self.value] = true end
            end
            return c
        end
        dd = u
        dd.selected = {}
        UIDropDownMenu_SetWidth(dd, w - 20)
        UIDropDownMenu_Initialize(dd, function(_, level)
            for _, it in ipairs(getItems()) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = it.label
                if it.header then
                    info.isTitle = true
                    info.notCheckable = true
                else
                    info.isNotRadio = true
                    info.keepShownOnClick = true
                    info.checked = dd.selected[it.value] == true
                    info.func = function()
                        toggle(it.value)
                        if UIDropDownMenu_Refresh then UIDropDownMenu_Refresh(dd) end
                    end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        function dd:ShowLabel(text) UIDropDownMenu_SetText(self, text) end
    end

    dd.selected = dd.selected or {}
    function dd:SetSelected(set)
        self.selected = {}
        for v, on in pairs(set or {}) do if on then self.selected[v] = true end end
        self:Refresh()
    end
    -- drop picks that no longer exist (e.g. after changing category)
    function dd:Refresh()
        local valid = {}
        for _, it in ipairs(getItems()) do if not it.header then valid[it.value] = true end end
        for v in pairs(self.selected) do if not valid[v] then self.selected[v] = nil end end
        if not next(self.selected) and opts.default then
            local d = opts.default()
            if d then self.selected[d] = true end
        end
        self:ShowLabel(summary())
    end
    dd:Refresh()
    return dd
end

-- "- n +" number stepper
local function Stepper(parent, label, value, onChange)
    local s = CreateFrame("Frame", nil, parent)
    s.value = value or 0
    local l = Text(s, "GameFontNormalSmall")
    l:SetPoint("LEFT")
    l:SetText(label)
    local minus = Button(s, "-", 20, 20)
    minus:SetPoint("LEFT", l, "RIGHT", 4, 0)
    s.num = Text(s, "GameFontHighlight", "CENTER")
    s.num:SetWidth(18)
    s.num:SetPoint("LEFT", minus, "RIGHT", 1, 0)
    local plus = Button(s, "+", 20, 20)
    plus:SetPoint("LEFT", s.num, "RIGHT", 1, 0)
    s:SetSize(math.max(30, l:GetStringWidth()) + 66, 22)
    function s:Set(v) self.value = math.max(0, math.min(39, v)); self.num:SetText(self.value) end
    minus:SetScript("OnClick", function() s:Set(s.value - 1); if onChange then onChange() end end)
    plus:SetScript("OnClick", function() s:Set(s.value + 1); if onChange then onChange() end end)
    s:Set(s.value)
    return s
end

-- Scrollable list with fixed rows (mouse wheel)
local function List(parent, rowH, nRows, buildRow, fillRow)
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.data, list.offset = {}, {}, 0
    list:SetHeight(rowH * nRows)
    for i = 1, nRows do
        local r = CreateFrame("Button", nil, list)
        r:SetHeight(rowH)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        r:SetPoint("RIGHT", list, "RIGHT", 0, 0)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.08)
        buildRow(r)
        list.rows[i] = r
    end
    list.empty = Text(list, "GameFontDisable", "CENTER")
    list.empty:SetPoint("TOP", 0, -30)
    list.pos = Text(list, "GameFontDisableSmall", "RIGHT")
    list.pos:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -2)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, #self.data - nRows)
        self.offset = math.max(0, math.min(max, self.offset - delta))
        self:Refresh()
    end)
    function list:SetData(data, emptyText)
        self.data = data
        self.empty:SetText(emptyText or "")
        self.offset = math.max(0, math.min(self.offset, #data - nRows))
        self:Refresh()
    end
    function list:Refresh()
        for i, r in ipairs(self.rows) do
            local item = self.data[self.offset + i]
            if item then r.item = item; r:Show(); fillRow(r, item) else r.item = nil; r:Hide() end
        end
        self.empty:SetShown(#self.data == 0)
        if #self.data > nRows then
            self.pos:SetText((self.offset + 1) .. "-" .. math.min(#self.data, self.offset + nRows) .. " of " .. #self.data .. "  (scroll)")
        else
            self.pos:SetText("")
        end
    end
    return list
end

local function Header(parent, cols)
    for _, c in ipairs(cols) do
        local t = Text(parent, "GameFontNormalSmall")
        t:SetPoint("TOPLEFT", c[2], 0)
        t:SetText(c[1])
    end
end

local function Section(parent, title)
    local t = Text(parent, "GameFontNormal")
    t:SetText(title)
    return t
end

-- Shared with other UI files (UI_Coach.lua)
ns.UI = { Text = Text, Button = Button, EditBox = EditBox, Dropdown = Dropdown, MultiDropdown = MultiDropdown, List = List, Header = Header, Section = Section }

local function roleItems()
    local out = {}
    for _, r in ipairs(ns.ROLES) do table.insert(out, { value = r, label = "I play: " .. ns.ROLE_LABEL[r] }) end
    return out
end

local function nameText(name, class, lvl)
    local s = ns.ClassColor(class, ns.ShortName(name)) .. ns.GuildMark(name)
    if lvl and lvl > 0 then s = "|cffaaaaaa" .. lvl .. "|r " .. s end
    return s
end

------------------------------------------------------------------------
-- Group finder page (Dungeons, Raids, PvP)
------------------------------------------------------------------------
local function catLabel(key)
    for _, c in ipairs(ns.CATEGORIES) do if c.key == key then return c.label end end
    return "?"
end

local function noRatings(cat) return cat == "WPVP" end

local function GroupPage(parent, cats, title)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local function instItems()
        local out = {}
        for _, cat in ipairs(cats) do
            if #cats > 1 then table.insert(out, { header = true, label = catLabel(cat) }) end
            for _, inst in ipairs(ns.INSTANCES_BY_CAT[cat] or {}) do
                table.insert(out, { value = inst.key, label = inst.name })
            end
        end
        return out
    end

    -- Post form, row 1: where + roles needed
    local form = Section(p, "List a group")
    form:SetPoint("TOPLEFT", 4, -4)
    p.inst = Dropdown(p, 220, instItems)
    p.inst:SetPoint("TOPLEFT", 4, -22)
    p.t = Stepper(p, "Tank", 1);   p.t:SetPoint("LEFT", p.inst, "RIGHT", 16, 0)
    p.h = Stepper(p, "Healer", 1); p.h:SetPoint("LEFT", p.t, "RIGHT", 10, 0)
    p.d = Stepper(p, "DPS", 3);    p.d:SetPoint("LEFT", p.h, "RIGHT", 10, 0)
    if cats[1] == "RAID" then p.t:Set(2); p.h:Set(8); p.d:Set(28) end
    if cats[1] == "BG" then p.t:Set(0); p.h:Set(2); p.d:Set(7) end

    -- Row 2: min level, note, buttons, my role
    local minL = Text(p, "GameFontNormalSmall"); minL:SetText("Min level")
    minL:SetPoint("TOPLEFT", 4, -56)
    p.min = EditBox(p, 30, 2); p.min:SetPoint("LEFT", minL, "RIGHT", 8, 0); p.min:SetNumeric(true)
    local noteL = Text(p, "GameFontNormalSmall"); noteL:SetText("Note")
    noteL:SetPoint("LEFT", p.min, "RIGHT", 10, 0)
    p.note = EditBox(p, 200, 60); p.note:SetPoint("LEFT", noteL, "RIGHT", 8, 0)

    p.post = Button(p, "List group", 90, 22, function()
        local inst = ns.INSTANCE_BY_KEY[p.inst.value]
        if not inst then return end
        ns.PostListing(inst.cat, inst.key, p.t.value, p.h.value, p.d.value,
            tonumber(p.min:GetText()) or inst.min, p.note:GetText())
    end)
    p.post:SetPoint("LEFT", p.note, "RIGHT", 10, 0)
    p.delist = Button(p, "Delist", 64, 22, function() ns.Delist() end)
    p.delist:SetPoint("LEFT", p.post, "RIGHT", 4, 0)

    p.role = Dropdown(p, 150, roleItems, function(v)
        MOO_CharDB.role = v
        ns.Fire("STATE_CHANGED")
    end)
    p.role:SetPoint("TOPRIGHT", -4, -52)

    -- Listings
    local lt = Section(p, title)
    lt:SetPoint("TOPLEFT", 4, -88)
    local hdr = CreateFrame("Frame", nil, p)
    hdr:SetPoint("TOPLEFT", 4, -106); hdr:SetPoint("RIGHT", -4, 0); hdr:SetHeight(14)
    local X = { 0, 130, 300, 450, 575 }
    Header(hdr, { { "Leader", X[1] }, { "Where", X[2] }, { "Needs", X[3] }, { "Group ratings", X[4] }, { "Note", X[5] } })

    p.list = List(p, 24, 14,
        function(r)
            r.c = {}
            for i = 1, 5 do
                r.c[i] = Text(r)
                r.c[i]:SetPoint("LEFT", X[i] + 2, 0)
            end
            r.c[2]:SetWidth(165)
            r.c[5]:SetWidth(76)
            r.btn = Button(r, "Apply", 64, 20)
            r.btn:SetPoint("RIGHT", -2, 0)
            r:SetScript("OnClick", function(self) if self.item then ns.ShowGroup(self.item.leader) end end)
            r:SetScript("OnEnter", function(self)
                local l = self.item
                if not l then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ns.ShortName(l.leader) .. "'s group - " .. ns.InstanceName(l.inst))
                GameTooltip:AddLine(ns.GuildTooltipLine(l.leader))
                if l.note ~= "" then GameTooltip:AddLine(l.note, 1, 1, 1, true) end
                GameTooltip:AddLine("Min level " .. l.min, 0.7, 0.7, 0.7)
                GameTooltip:AddLine(" ")
                for _, m in ipairs(ns.ListingMembers(l)) do
                    local right = noRatings(l.cat) and "" or ns.RatingSummary(m.name, m.role)
                    GameTooltip:AddDoubleLine(ns.ClassColor(m.class, ns.ShortName(m.name)) .. ns.GuildMark(m.name) ..
                        (m.role and ("  " .. ns.RoleText(m.role)) or ""), right)
                end
                GameTooltip:AddLine("Click to see the whole group.", 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", GameTooltip_Hide)
        end,
        function(r, l)
            r.c[1]:SetText(nameText(l.leader, l.class, l.lvl))
            r.c[2]:SetText(ns.InstanceName(l.inst))
            r.c[3]:SetText(ns.NeedsText(l))
            r.c[4]:SetText(noRatings(l.cat) and "|cff888888-|r" or ns.GroupRatingSummary(l))
            r.c[5]:SetText(l.note)
            local app = ns.myApplications[l.leader]
            r.btn:Enable()
            if app and app.id == l.id and app.state == "sent" then
                r.btn:SetText("Cancel")
                r.btn:SetScript("OnClick", function() ns.CancelApplication(l.leader) end)
            elseif app and app.id == l.id and app.state ~= "closed" then
                r.btn:SetText(app.state == "invited" and "Invited" or "Declined")
                r.btn:Disable()
            else
                r.btn:SetText("Apply")
                r.btn:SetScript("OnClick", function() ns.Apply(l.leader, MOO_CharDB.role, "") end)
                if UnitLevel("player") < l.min then r.btn:Disable() end
            end
        end)
    p.list:SetPoint("TOPLEFT", 4, -122)
    p.list:SetPoint("RIGHT", -4, 0)

    function p:Refresh()
        self.inst:Refresh()
        self.role:SetValue(MOO_CharDB.role)
        local mine = ns.myListing
        local mineHere = false
        if mine then
            for _, c in ipairs(cats) do if mine.cat == c then mineHere = true end end
        end
        self.post:SetText(mineHere and "Update" or "List group")
        self.delist:SetShown(mineHere)
        local data = {}
        for _, c in ipairs(cats) do
            for _, l in ipairs(ns.SortedListings(c)) do table.insert(data, l) end
        end
        self.list:SetData(data, "No " .. title:lower() .. " right now. List one above!")
    end
    return p
end

------------------------------------------------------------------------
-- Players page: who is available, invite them
------------------------------------------------------------------------
local function setToList(set, order)
    local out = {}
    for _, v in ipairs(order) do if set[v] then table.insert(out, v) end end
    return out
end

local function PlayersPage(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    MOO_CharDB.avail = MOO_CharDB.avail or {}
    local saved = MOO_CharDB.avail

    local function catItems()
        local out = {}
        for _, c in ipairs(ns.CATEGORIES) do table.insert(out, { value = c.key, label = c.label }) end
        return out
    end
    local function instItems()
        local cat = p.cat and p.cat.value or "DUNGEON"
        local out = { { value = "ANY", label = "Anything (" .. catLabel(cat):lower() .. ")", short = "Anything", exclusive = true } }
        for _, inst in ipairs(ns.INSTANCES_BY_CAT[cat] or {}) do
            table.insert(out, { value = inst.key, label = inst.name })
        end
        return out
    end
    local function roleChoices()
        local out = {}
        for _, r in ipairs(ns.ROLES) do table.insert(out, { value = r, label = ns.ROLE_LABEL[r] }) end
        return out
    end
    local function instOrder()
        local order = { "ANY" }
        for _, it in ipairs(instItems()) do if it.value ~= "ANY" then table.insert(order, it.value) end end
        return order
    end

    local s = Section(p, "Mark yourself available (leaders can invite you)")
    s:SetPoint("TOPLEFT", 4, -4)
    p.cat = Dropdown(p, 150, catItems, function(v)
        saved.cat = v
        p.inst:Refresh()
        saved.insts = p.inst.selected
    end)
    p.cat:SetPoint("TOPLEFT", 4, -22)
    p.inst = MultiDropdown(p, 230, instItems, function(sel) saved.insts = sel end,
        { none = "Pick instances", plural = "instances", max = 12, default = function() return "ANY" end })
    p.inst:SetPoint("LEFT", p.cat, "RIGHT", 8, 0)
    p.roles = MultiDropdown(p, 170, roleChoices, function(sel) saved.roles = sel end,
        { none = "Pick roles", plural = "roles", showNames = 3, default = function() return MOO_CharDB.role end })
    p.roles:SetPoint("LEFT", p.inst, "RIGHT", 8, 0)

    local noteL = Text(p, "GameFontNormalSmall"); noteL:SetText("Note")
    noteL:SetPoint("TOPLEFT", 4, -56)
    p.note = EditBox(p, 300, 60); p.note:SetPoint("LEFT", noteL, "RIGHT", 8, 0)
    p.go = Button(p, "List me", 90, 22, function()
        local insts = setToList(p.inst.selected, instOrder())
        local roles = setToList(p.roles.selected, ns.ROLES)
        if #roles == 0 then ns.Print("Pick at least one role.") return end
        ns.SetAvailable(p.cat.value, insts, roles, p.note:GetText())
    end)
    p.go:SetPoint("LEFT", p.note, "RIGHT", 10, 0)
    p.stop = Button(p, "Remove me", 90, 22, function() ns.ClearAvailable() end)
    p.stop:SetPoint("LEFT", p.go, "RIGHT", 4, 0)

    if saved.cat then p.cat:SetValue(saved.cat) end
    if saved.insts then p.inst:SetSelected(saved.insts) end
    if saved.roles then p.roles:SetSelected(saved.roles) end
    saved.insts, saved.roles = p.inst.selected, p.roles.selected

    local lt = Section(p, "Available players")
    lt:SetPoint("TOPLEFT", 4, -88)
    p.filter = Dropdown(p, 200, function()
        local out = { { value = "ALL", label = "Show: everything" } }
        if ns.myListing then table.insert(out, { value = "MATCH", label = "Show: fits my listing" }) end
        for _, c in ipairs(ns.CATEGORIES) do table.insert(out, { value = c.key, label = "Show: " .. c.label }) end
        return out
    end, function() p:Refresh() end)
    p.filter:SetPoint("TOPRIGHT", -4, -84)

    local hdr = CreateFrame("Frame", nil, p)
    hdr:SetPoint("TOPLEFT", 4, -108); hdr:SetPoint("RIGHT", -4, 0); hdr:SetHeight(14)
    local X = { 0, 135, 305, 410, 510 }
    Header(hdr, { { "Player", X[1] }, { "Wants", X[2] }, { "Roles", X[3] }, { "Rating", X[4] }, { "Note", X[5] } })

    local function bestRating(a)
        if noRatings(a.cat) then return "|cff888888-|r" end
        local best, bestRole
        local prof = ns.GetProfile(a.name)
        for _, r in ipairs(a.roles) do
            local pr = prof.roles[r]
            if pr and pr.shown and (not best or pr.avg > best) then best, bestRole = pr.avg, r end
        end
        if bestRole then return ns.RatingSummary(a.name, bestRole) .. (#a.roles > 1 and (" " .. ns.ROLE_LABEL[bestRole]:sub(1, 1)) or "") end
        return ns.RatingSummary(a.name, a.roles[1])
    end

    p.list = List(p, 24, 14,
        function(r)
            r.c = {}
            for i = 1, 5 do r.c[i] = Text(r); r.c[i]:SetPoint("LEFT", X[i] + 2, 0) end
            r.c[2]:SetWidth(165)
            r.c[5]:SetWidth(90)
            r.inv = Button(r, "Invite", 60, 20)
            r.inv:SetPoint("RIGHT", -2, 0)
            r.gear = Button(r, "Gear", 50, 20)
            r.gear:SetPoint("RIGHT", r.inv, "LEFT", -2, 0)
            r:SetScript("OnClick", function(self) if self.item then ns.ShowProfile(self.item.name) end end)
            r:SetScript("OnEnter", function(self)
                local a = self.item
                if not a then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ns.ClassColor(a.class, ns.ShortName(a.name)) .. "  |cffaaaaaa" .. a.lvl .. "|r")
                GameTooltip:AddLine(ns.GuildTooltipLine(a.name))
                if a.insts[1] == "ANY" then
                    GameTooltip:AddLine("Wants: " .. ns.AvailableWhereText(a.cat, a.insts), 1, 1, 1)
                else
                    GameTooltip:AddLine("Wants:", 1, 0.82, 0)
                    for _, k in ipairs(a.insts) do GameTooltip:AddLine("  " .. ns.InstanceName(k), 1, 1, 1) end
                end
                if not noRatings(a.cat) then
                    GameTooltip:AddLine("Ratings:", 1, 0.82, 0)
                    for _, ro in ipairs(a.roles) do
                        GameTooltip:AddDoubleLine("  " .. ns.RoleText(ro), ns.RatingSummary(a.name, ro))
                    end
                end
                if a.note ~= "" then GameTooltip:AddLine(a.note, 0.8, 0.8, 0.8, true) end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", GameTooltip_Hide)
        end,
        function(r, a)
            r.c[1]:SetText(nameText(a.name, a.class, a.lvl))
            r.c[2]:SetText(ns.AvailableWhereText(a.cat, a.insts))
            r.c[3]:SetText(ns.RolesText(a.roles))
            r.c[4]:SetText(bestRating(a))
            r.c[5]:SetText(a.note)
            r.inv:SetScript("OnClick", function() ns.InviteName(a.name) end)
            r.gear:SetScript("OnClick", function()
                if not ns.myListing then
                    ns.Print("List a group first: players share gear only with leaders who have a listing.")
                    return
                end
                ns.RequestGear(a.name)
                ns.ShowProfile(a.name)
            end)
        end)
    p.list:SetPoint("TOPLEFT", 4, -124)
    p.list:SetPoint("RIGHT", -4, 0)

    function p:Refresh()
        self.cat:Refresh(); self.inst:Refresh(); self.roles:Refresh(); self.filter:Refresh()
        self.go:SetText(ns.myAvailable and "Update" or "List me")
        self.stop:SetShown(ns.myAvailable ~= nil)
        local f = self.filter.value
        self.list:SetData(ns.SortedAvailable(f ~= "ALL" and f or nil),
            f == "MATCH" and "Nobody available fits your listing right now." or "Nobody is marked available right now.")
    end
    return p
end

------------------------------------------------------------------------
-- My Group page: applicants + ready check
------------------------------------------------------------------------
local function MyGroupPage(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    p.status = Text(p, "GameFontNormal")
    p.status:SetPoint("TOPLEFT", 4, -4)
    local function pushNeeds() ns.UpdateNeeds(p.t.value, p.h.value, p.d.value) end
    p.d = Stepper(p, "DPS", 0, pushNeeds);    p.d:SetPoint("TOPRIGHT", -4, -2)
    p.h = Stepper(p, "Healer", 0, pushNeeds); p.h:SetPoint("RIGHT", p.d, "LEFT", -10, 0)
    p.t = Stepper(p, "Tank", 0, pushNeeds);   p.t:SetPoint("RIGHT", p.h, "LEFT", -10, 0)

    local hdr = CreateFrame("Frame", nil, p)
    hdr:SetPoint("TOPLEFT", 4, -28); hdr:SetPoint("RIGHT", -4, 0); hdr:SetHeight(14)
    local X = { 0, 140, 200, 240, 330, 440 }
    Header(hdr, { { "Applicant", X[1] }, { "Role", X[2] }, { "iLvl", X[3] }, { "Rating", X[4] }, { "Gear", X[5] }, { "Note", X[6] } })

    p.apps = List(p, 24, 8,
        function(r)
            r.c = {}
            for i = 1, 6 do r.c[i] = Text(r); r.c[i]:SetPoint("LEFT", X[i] + 2, 0) end
            r.c[6]:SetWidth(90)
            r.dec = Button(r, "Decline", 64, 20); r.dec:SetPoint("RIGHT", -2, 0)
            r.inv = Button(r, "Invite", 56, 20); r.inv:SetPoint("RIGHT", r.dec, "LEFT", -2, 0)
            r.gear = Button(r, "Details", 60, 20); r.gear:SetPoint("RIGHT", r.inv, "LEFT", -2, 0)
            r:SetScript("OnEnter", function(self)
                if not self.item then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ns.ShortName(self.item.name))
                GameTooltip:AddLine(ns.GuildTooltipLine(self.item.name))
                if self.item.note ~= "" then GameTooltip:AddLine(self.item.note, 1, 1, 1, true) end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", GameTooltip_Hide)
        end,
        function(r, a)
            r.c[1]:SetText(nameText(a.name, a.class, a.lvl))
            r.c[2]:SetText(ns.RoleText(a.role))
            r.c[3]:SetText(a.ilvl > 0 and a.ilvl or "-")
            local wpvp = ns.myListing and noRatings(ns.myListing.cat)
            r.c[4]:SetText(wpvp and "|cff888888-|r" or ns.RatingSummary(a.name, a.role))
            r.c[5]:SetText(ns.GearStatusText(ns.gearSeen[a.name]))
            local stateText = { invited = "|cffffd100invited|r", joined = "|cff33ff33joined|r", declined = "|cff888888declined|r" }
            r.c[6]:SetText(stateText[a.state] or a.note)
            r.gear:SetScript("OnClick", function() ns.ShowProfile(a.name) end)
            r.inv:SetScript("OnClick", function() ns.InviteApplicant(a.name) end)
            r.dec:SetScript("OnClick", function() ns.DeclineApplicant(a.name) end)
            r.inv:SetEnabled(a.state == "new")
            r.dec:SetEnabled(a.state == "new")
        end)
    p.apps:SetPoint("TOPLEFT", 4, -44)
    p.apps:SetPoint("RIGHT", -4, 0)

    -- Ready check section
    local rc = Section(p, "Group & ready check")
    rc:SetPoint("TOPLEFT", 4, -250)
    p.counts = Text(p, "GameFontHighlightSmall")
    p.counts:SetPoint("LEFT", rc, "RIGHT", 16, 0)
    p.rcBtn = Button(p, "Ready check", 110, 22, function() ns.StartReadyCheck() end)
    p.rcBtn:SetPoint("TOPRIGHT", -4, -246)
    p.raidBtn = Button(p, "Convert to raid", 120, 22, function()
        if C_PartyInfo and C_PartyInfo.ConvertToRaid then C_PartyInfo.ConvertToRaid() elseif ConvertToRaid then ConvertToRaid() end
    end)
    p.raidBtn:SetPoint("RIGHT", p.rcBtn, "LEFT", -4, 0)
    p.rateBtn = Button(p, "Rate last run", 110, 22, function() ns.ShowRatingPrompt() end)
    p.rateBtn:SetPoint("RIGHT", p.raidBtn, "LEFT", -4, 0)

    local X2 = { 0, 26, 190, 260, 370, 470 }
    local hdr2 = CreateFrame("Frame", nil, p)
    hdr2:SetPoint("TOPLEFT", 4, -274); hdr2:SetPoint("RIGHT", -4, 0); hdr2:SetHeight(14)
    Header(hdr2, { { "", X2[1] }, { "Member", X2[2] }, { "Role", X2[3] }, { "Rating", X2[4] }, { "Gear", X2[5] }, { "MOO", X2[6] } })

    p.roster = List(p, 20, 9,
        function(r)
            r.c = {}
            for i = 1, 6 do r.c[i] = Text(r); r.c[i]:SetPoint("LEFT", X2[i] + 2, 0) end
            r:SetScript("OnClick", function(self) if self.item then ns.ShowProfile(self.item.name) end end)
        end,
        function(r, m)
            r.c[1]:SetText(m.state and ns.READY_ICON[m.state] or "")
            local n = nameText(m.name, m.class, m.level)
            if not m.online then n = n .. " |cff888888(offline)|r" end
            r.c[2]:SetText(n)
            r.c[3]:SetText(m.role and ns.RoleText(m.role) or "|cff888888?|r")
            local wpvp = ns.myListing and noRatings(ns.myListing.cat)
            r.c[4]:SetText(wpvp and "|cff888888-|r" or ns.RatingSummary(m.name, m.role))
            local g = ns.gearSeen[m.name]
            r.c[5]:SetText(g and ns.GearStatusText(g) or "")
            r.c[6]:SetText(m.aol and "|cff33ff33yes|r" or "|cff888888no|r")
        end)
    p.roster:SetPoint("TOPLEFT", 4, -290)
    p.roster:SetPoint("RIGHT", -4, 0)

    function p:Refresh()
        local l = ns.myListing
        if l then
            self.status:SetText("Your listing: |cffffffff" .. ns.InstanceName(l.inst) .. "|r   still need:")
            self.t:Set(l.t); self.h:Set(l.h); self.d:Set(l.d)
            self.t:Show(); self.h:Show(); self.d:Show()
        else
            self.status:SetText("You have no listing. List a group from Dungeons, Raids or PvP.")
            self.t:Hide(); self.h:Hide(); self.d:Hide()
        end
        self.apps:SetData(ns.SortedApplicants(), l and "No applicants yet." or "")
        local roster = ns.GroupRoster()
        local c = ns.RoleCounts(roster)
        self.counts:SetText(IsInGroup() and string.format("%s %d   %s %d   %s %d%s",
            ns.RoleText("TANK"), c.TANK, ns.RoleText("HEAL"), c.HEAL, ns.RoleText("DPS"), c.DPS,
            c.unknown > 0 and ("   |cff888888? " .. c.unknown .. "|r") or "") or "")
        self.roster:SetData(roster, "You are not in a group.")
        self.rcBtn:SetEnabled(ns.CanReadyCheck())
        self.raidBtn:SetShown(IsInGroup() and not IsInRaid() and UnitIsGroupLeader("player"))
        self.rateBtn:SetEnabled(MOO_CharDB.pending and #MOO_CharDB.pending > 0)
    end
    return p
end

------------------------------------------------------------------------
-- Ratings page
------------------------------------------------------------------------
function ns.ProfileText(name)
    local p = ns.GetProfile(name)
    local lines = {}
    local any = false
    for _, role in ipairs(ns.ROLES) do
        local pr = p.roles[role]
        if pr then
            any = true
            if pr.shown then
                table.insert(lines, ns.RoleText(role) .. ":  " .. ns.StarsText(pr.avg) ..
                    "  |cffaaaaaa" .. pr.count .. " ratings from " .. pr.nRaters .. " players|r")
            else
                table.insert(lines, ns.RoleText(role) .. ":  |cff888888hidden until " .. ns.MIN_RATERS ..
                    " players rate (" .. pr.nRaters .. " so far)|r")
            end
        end
    end
    if not any then return "|cff888888No ratings yet.|r" end
    local tags = ns.TopTags(p, 4)
    if tags ~= "" then table.insert(lines, "|cffffd100Known for:|r " .. tags) end
    local instLines = {}
    for instKey, roles in pairs(p.inst) do
        for role, pi in pairs(roles) do
            local pr = p.roles[role]
            if pr and pr.shown then
                table.insert(instLines, string.format("  %s (%s): %s |cff888888x%d|r",
                    ns.InstanceName(instKey), ns.ROLE_LABEL[role], ns.StarsText(pi.avg), pi.count))
            end
        end
    end
    if #instLines > 0 then
        table.sort(instLines)
        table.insert(lines, "|cffffd100By instance:|r")
        for i = 1, math.min(10, #instLines) do table.insert(lines, instLines[i]) end
    end
    return table.concat(lines, "\n")
end

local function RatingsPage(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()
    local s = Section(p, "Look up a player")
    s:SetPoint("TOPLEFT", 4, -4)
    p.search = EditBox(p, 200, 40)
    p.search:SetPoint("TOPLEFT", 10, -24)
    local go = Button(p, "Show", 70, 22, function()
        local n = strtrim(p.search:GetText() or "")
        if n ~= "" then ns.ShowProfile(ns.FullName(n:sub(1, 1):upper() .. n:sub(2))) end
    end)
    go:SetPoint("LEFT", p.search, "RIGHT", 6, 0)
    p.search:SetScript("OnEnterPressed", function(self) self:ClearFocus(); go:Click() end)
    local tgt = Button(p, "My target", 90, 22, function()
        local n = UnitIsPlayer("target") and ns.UnitFullName("target")
        if n then ns.ShowProfile(n) else ns.Print("Target a player first.") end
    end)
    tgt:SetPoint("LEFT", go, "RIGHT", 4, 0)

    local mine = Section(p, "Your ratings")
    mine:SetPoint("TOPLEFT", 4, -60)
    p.mine = Text(p, "GameFontHighlight")
    p.mine:SetPoint("TOPLEFT", 10, -82)
    p.mine:SetPoint("RIGHT", -10, 0)
    p.mine:SetWordWrap(true)
    p.mine:SetJustifyV("TOP")
    p.mine:SetSpacing(3)

    local how = Text(p, "GameFontDisableSmall")
    how:SetPoint("BOTTOMLEFT", 6, 4)
    how:SetPoint("RIGHT", -6, 0)
    how:SetWordWrap(true)
    how:SetText("Ratings count only between players who were in the same dungeon or raid group and both have MOO. " ..
        "The role comes from the rated player. Scores show after " .. ns.MIN_RATERS ..
        " different players rate a role. Ratings older than 180 days drop off.")

    function p:Refresh()
        self.mine:SetText(ns.ProfileText(ns.Me()))
    end
    return p
end

------------------------------------------------------------------------
-- Opt-in overlay
------------------------------------------------------------------------
local function OptInOverlay(parent)
    local o = CreateFrame("Frame", nil, parent)
    o:SetAllPoints()
    o:SetFrameLevel(parent:GetFrameLevel() + 20)
    o:EnableMouse(true)
    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)
    o.title = Text(o, "GameFontNormalHuge", "CENTER")
    o.title:SetPoint("TOP", 0, -50)
    o.body = Text(o, "GameFontHighlight", "LEFT")
    o.body:SetPoint("TOP", 0, -100)
    o.body:SetWidth(560)
    o.body:SetWordWrap(true)
    o.body:SetSpacing(4)
    o.btn = Button(o, "Opt in", 140, 26, function() ns.SetOptIn(true) end)
    o.btn:SetPoint("BOTTOM", 0, 50)
    function o:Refresh()
        if not ns.InOlympus() then
            self.title:SetText("Olympus only")
            self.body:SetText("MOO works only for members of an Olympus guild. Join one (the Olympus addon's " ..
                "Join screen can help) and MOO opens up.")
            self.btn:Hide()
            self:Show()
        elseif not ns.IsOptedIn() then
            self.title:SetText("Welcome to Muster Of Olympus")
            self.body:SetText(
                "To list groups, apply, or mark yourself available, you opt in to ratings:\n\n" ..
                "- After a dungeon or raid, groupmates who also use MOO can give you 1-5 stars and positive tags for the role you played.\n" ..
                "- A rating only counts if you were really grouped together (both your addons confirm it).\n" ..
                "- Scores show only once 3 different players have rated you in a role.\n" ..
                "- When you apply, your gear and basic stats go to that group's leader only.\n" ..
                "- MOO never invites, accepts or queues for you. Everything is a click.\n\n" ..
                "You can opt out any time with /moo optout. New runs stop counting right away.")
            self.btn:Show()
            self:Show()
        else
            self:Hide()
        end
    end
    return o
end

------------------------------------------------------------------------
-- Main window
------------------------------------------------------------------------
local TAB_DEFS = {
    { label = "Dungeons", build = function(c) return GroupPage(c, { "DUNGEON" }, "Dungeon groups") end },
    { label = "Raids",    build = function(c) return GroupPage(c, { "RAID" }, "Raid groups") end },
    { label = "PvP",      build = function(c) return GroupPage(c, { "BG", "WPVP" }, "PvP groups") end },
    { label = "Players",  build = PlayersPage },
    { label = "My Group", build = MyGroupPage },
    { label = "Ratings",  build = RatingsPage },
}

local function selectTab(i)
    main.selected = i
    if PanelTemplates_SetTab then PanelTemplates_SetTab(main, i) end
    for j, page in ipairs(pages) do page:SetShown(j == i) end
    if pages[i].Refresh then pages[i]:Refresh() end
end

local function makeMain()
    local ok, f = pcall(CreateFrame, "Frame", "MOOMainFrame", UIParent, "PortraitFrameTemplate")
    if not ok or not f then
        f = CreateFrame("Frame", "MOOMainFrameBasic", UIParent, "BasicFrameTemplateWithInset")
    end
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, f:GetName())

    local title = "Muster Of Olympus  |cff888888(MOO " .. ns.VERSION .. ")|r"
    if f.SetTitle then f:SetTitle(title)
    elseif f.TitleText then f.TitleText:SetText(title) end
    if f.SetPortraitToAsset then
        pcall(f.SetPortraitToAsset, f, "Interface\\Icons\\INV_Misc_GroupNeedMore")
    end

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", 14, -64)
    content:SetPoint("BOTTOMRIGHT", -14, 14)
    f.content = content

    -- Olympus link in the header
    f.oly = Button(f, "Olympus", 80, 20, ns.OpenOlympus)
    f.oly:SetPoint("TOPRIGHT", -30, -32)
    f.themeBtn = Button(f, "Dark mode", 86, 20, function()
        ns.SetTheme(ns.IsDark() and "classic" or "dark")
    end)
    f.themeBtn:SetPoint("RIGHT", f.oly, "LEFT", -6, 0)
    f.status = Text(f, "GameFontDisableSmall", "RIGHT")
    f.status:SetPoint("RIGHT", f.themeBtn, "LEFT", -8, 0)

    for _, extra in ipairs(ns.EXTRA_TABS or {}) do table.insert(TAB_DEFS, extra) end
    for i, def in ipairs(TAB_DEFS) do
        local page = def.build(content)
        page:Hide()
        pages[i] = page
        local tab
        for _, tmpl in ipairs({ "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate", "UIPanelButtonTemplate" }) do
            local okT, t = pcall(CreateFrame, "Button", f:GetName() .. "Tab" .. i, f, tmpl)
            if okT and t then tab = t break end
        end
        tab:SetID(i)
        tab:SetText(def.label)
        if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
        if i == 1 then tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
        else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -14, 0) end
        tab:SetScript("OnClick", function() selectTab(i); PlaySound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB or 841) end)
        tabs[i] = tab
    end
    f.numTabs = #TAB_DEFS
    if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(f, #TAB_DEFS) end

    f.overlay = OptInOverlay(content)
    ns.Themed(f, content, -6, 6, 6, -6)
    f:SetScript("OnShow", function() ns.RefreshUI() end)
    f:Hide()
    main = f
    selectTab(1)
end

function ns.RefreshUI()
    if not main or not main:IsShown() then return end
    main.overlay:Refresh()
    local cross
    if not ns.CROSS_GUILD then cross = "|cffaaaaaaYour guild only|r"
    elseif ns.CrossGuildOn() then
        cross = MOO_DB.channelKey and "|cff33ff33Cross-guild: on (sealed)|r" or "|cff33ff33Cross-guild: on|r"
    else cross = "|cffffaa00Your guild only (no officer key)|r" end
    local oly = ns.OlympusAddonLoaded() and "|cff33ff33Olympus addon loaded|r" or "|cffffaa00Olympus addon not found|r"
    main.status:SetText(cross .. "   " .. oly)
    main.oly:SetShown(ns.OlympusAddonLoaded())
    main.themeBtn:SetText(ns.IsDark() and "Classic" or "Dark mode")
    main.themeBtn:ClearAllPoints()
    if main.oly:IsShown() then main.themeBtn:SetPoint("RIGHT", main.oly, "LEFT", -6, 0)
    else main.themeBtn:SetPoint("TOPRIGHT", -30, -32) end
    local page = pages[main.selected or 1]
    if page and page.Refresh then page:Refresh() end
end

function ns.ToggleMain(tab)
    if not main then makeMain() end
    if main:IsShown() and not tab then main:Hide() return end
    main:Show()
    if tab then selectTab(tab) end
    ns.RefreshUI()
end

for _, ev in ipairs({ "LISTINGS_UPDATED", "APPLICANTS_UPDATED", "GROUP_INFO", "STATE_CHANGED",
                      "READY_CHECK_UPDATED", "RATINGS_UPDATED", "GEAR_UPDATED", "INSTANCES_CHANGED",
                      "COACH_UPDATED" }) do
    ns.Listen(ev, function() ns.RefreshUI(); if ns.RefreshDetail then ns.RefreshDetail() end end)
end
ns.On("GROUP_ROSTER_UPDATE", function() ns.RefreshUI() end)
ns.Listen("APPLICANTS_UPDATED", function()
    -- jump to My Group when the first applicant arrives while the window is open
    if main and main:IsShown() and main.selected ~= 5 then
        for _, a in pairs(ns.applicants) do
            if a.state == "new" then tabs[5]:SetText("My Group (!)") return end
        end
    end
    if tabs[5] then tabs[5]:SetText("My Group") end
end)

------------------------------------------------------------------------
-- Player detail card: ratings + gear + stats
------------------------------------------------------------------------
local detail

local function makeDetail()
    local ok, f = pcall(CreateFrame, "Frame", "MOODetailFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "MOODetailFrame2", UIParent, "BackdropTemplate") end
    f:SetSize(520, 440)
    f:SetPoint("CENTER", 300, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, f:GetName())

    f.title = Text(f, "GameFontNormal", "CENTER")
    f.title:SetPoint("TOP", 0, -6)

    f.rating = Text(f, "GameFontHighlightSmall")
    f.rating:SetPoint("TOPLEFT", 14, -34)
    f.rating:SetWidth(240)
    f.rating:SetWordWrap(true)
    f.rating:SetJustifyV("TOP")
    f.rating:SetSpacing(3)

    f.gearTitle = Text(f, "GameFontNormal")
    f.gearTitle:SetPoint("TOPLEFT", 270, -34)
    f.gearRows = {}
    for i, s in ipairs(ns.SLOTS) do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(236, 15)
        r:SetPoint("TOPLEFT", 270, -52 - (i - 1) * 15)
        r.slot = Text(r, "GameFontDisableSmall")
        r.slot:SetPoint("LEFT")
        r.slot:SetWidth(62)
        r.slot:SetText(s.label)
        r.item = Text(r, "GameFontHighlightSmall")
        r.item:SetPoint("LEFT", 64, 0)
        r.item:SetWidth(172)
        r:SetScript("OnEnter", function(self)
            if self.id and self.id > 0 then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.id)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        f.gearRows[i] = r
    end
    f.stats = Text(f, "GameFontHighlightSmall")
    f.stats:SetPoint("TOPLEFT", 270, -52 - #ns.SLOTS * 15 - 8)
    f.stats:SetWidth(236)
    f.stats:SetWordWrap(true)
    f.stats:SetJustifyV("TOP")
    f.stats:SetSpacing(2)

    f.note = Text(f, "GameFontDisableSmall")
    f.note:SetPoint("BOTTOMLEFT", 14, 10)
    f.note:SetPoint("RIGHT", -14, 0)
    f.note:SetWordWrap(true)
    ns.Themed(f)
    f:Hide()
    detail = f
end

local function itemText(id)
    if not id or id == 0 then return "|cff555555-|r" end
    local name, _, quality
    if C_Item and C_Item.GetItemInfo then name, _, quality = C_Item.GetItemInfo(id)
    else name, _, quality = GetItemInfo(id) end
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return "|cff888888item " .. id .. "|r"
    end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return color and (color.hex .. name .. "|r") or name
end

function ns.RefreshDetail()
    if not detail or not detail:IsShown() or not detail.name then return end
    local name = detail.name
    local gl, gr, gg, gb = ns.GuildTooltipLine(name)
    detail.title:SetText(ns.ShortName(name) .. "  |cff888888" .. name .. "|r")
    detail.rating:SetTextColor(1, 1, 1)
    detail.guildLine = detail.guildLine or Text(detail, "GameFontHighlightSmall")
    detail.guildLine:SetPoint("TOPLEFT", 14, -24)
    detail.guildLine:SetText(gl)
    detail.guildLine:SetTextColor(gr, gg, gb)
    detail.rating:SetText("|cffffd100Ratings|r\n" .. ns.ProfileText(name))
    local g = ns.gearSeen[name]
    if name == ns.Me() then
        g = { gear = ns.GearSnapshot(), stats = ns.StatSnapshot(), status = "verified" }
        g.ilvl = ns.AverageItemLevel()
    end
    local ids = {}
    if g and g.gear then
        local i = 0
        for id in g.gear:gmatch("[^,]+") do i = i + 1; ids[i] = tonumber(id) end
        detail.gearTitle:SetText("Gear  |cffaaaaaaavg iLvl " .. (ns.AverageItemLevel(g.gear) or "?") .. "|r  " .. ns.GearStatusText(g))
    else
        detail.gearTitle:SetText("Gear  |cff888888(not shared with you)|r")
    end
    for i, r in ipairs(detail.gearRows) do
        r.id = ids[i]
        r.item:SetText(g and g.gear and itemText(ids[i]) or "")
    end
    if g and g.stats then
        local v = { strsplit(",", g.stats) }
        local parts = {}
        for i, label in ipairs(ns.STAT_LABELS) do
            if v[i] and v[i] ~= "0" and v[i] ~= "0.0" then table.insert(parts, label .. " |cffffffff" .. v[i] .. "|r") end
        end
        detail.stats:SetText(table.concat(parts, "   "))
    else
        detail.stats:SetText("")
    end
    detail.note:SetText("Gear is sent by the player's own addon when they apply. \"Verified\" means MOO inspected " ..
        "them in your group and it matched; \"changed\" means it didn't (they may simply have swapped items).")
end

function ns.ShowProfile(name)
    if not name then return end
    if not detail then makeDetail() end
    detail.name = name
    detail:Show()
    ns.RefreshDetail()
end

------------------------------------------------------------------------
-- Group card: every member of a listed group with their rating for their role
------------------------------------------------------------------------
local groupFrame

local function makeGroupFrame()
    local ok, f = pcall(CreateFrame, "Frame", "MOOGroupFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "MOOGroupFrame2", UIParent) end
    f:SetSize(500, 400)
    f:SetPoint("CENTER", -250, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, f:GetName())

    f.title = Text(f, "GameFontNormal", "CENTER")
    f.title:SetPoint("TOP", 0, -6)
    f.sub = Text(f, "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", 14, -32)
    f.sub:SetPoint("RIGHT", -14, 0)
    f.sub:SetWordWrap(true)

    local X = { 0, 150, 220, 330 }
    local hdr = CreateFrame("Frame", nil, f)
    hdr:SetPoint("TOPLEFT", 14, -62); hdr:SetPoint("RIGHT", -14, 0); hdr:SetHeight(14)
    Header(hdr, { { "Member", X[1] }, { "Role", X[2] }, { "Rating", X[3] }, { "Known for", X[4] } })

    f.list = List(f, 20, 13,
        function(r)
            r.c = {}
            for i = 1, 4 do r.c[i] = Text(r); r.c[i]:SetPoint("LEFT", X[i] + 2, 0) end
            r.c[4]:SetWidth(140)
            r:SetScript("OnClick", function(self) if self.item then ns.ShowProfile(self.item.name) end end)
        end,
        function(r, m)
            local leader = groupFrame.listing and m.name == groupFrame.listing.leader
            r.c[1]:SetText(ns.ClassColor(m.class, ns.ShortName(m.name)) .. ns.GuildMark(m.name) ..
                (leader and " |cffffd100(leader)|r" or ""))
            r.c[2]:SetText(m.role and ns.RoleText(m.role) or "|cff888888?|r")
            if groupFrame.noRatings then
                r.c[3]:SetText("|cff888888-|r"); r.c[4]:SetText("")
            else
                r.c[3]:SetText(ns.RatingSummary(m.name, m.role))
                r.c[4]:SetText("|cffaaaaaa" .. ns.TopTags(ns.GetProfile(m.name), 2) .. "|r")
            end
        end)
    f.list:SetPoint("TOPLEFT", 14, -78)
    f.list:SetPoint("RIGHT", -14, 0)

    f.apply = Button(f, "Apply", 90, 22)
    f.apply:SetPoint("BOTTOMRIGHT", -14, 12)
    f.hint = Text(f, "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", 14, 16)
    f.hint:SetText("Click a member for their full ratings and gear.")
    ns.Themed(f)
    f:Hide()
    groupFrame = f
end

function ns.RefreshGroupFrame()
    local f = groupFrame
    if not f or not f:IsShown() then return end
    local l = ns.listings[f.leader] or (ns.myListing and f.leader == ns.Me() and ns.myListing)
    if not l then
        f.title:SetText(ns.ShortName(f.leader) .. "'s group")
        f.sub:SetText("|cff888888This listing is gone.|r")
        f.list:SetData({}, "")
        f.apply:Hide()
        return
    end
    if l == ns.myListing then l.leader = ns.Me() end
    f.listing = l
    f.noRatings = (l.cat == "WPVP")
    f.title:SetText(ns.ShortName(l.leader) .. "'s group - " .. ns.InstanceName(l.inst))
    f.sub:SetText("Needs: " .. ns.NeedsText(l) .. (l.note ~= "" and ("   |cffffffff" .. l.note .. "|r") or "") ..
        (f.noRatings and "\n|cff888888World PvP groups aren't rated.|r" or ("\nGroup: " .. ns.GroupRatingSummary(l))))
    local members = ns.ListingMembers(l)
    f.list:SetData(members, "")
    local app = ns.myApplications[l.leader]
    f.apply:SetShown(l ~= ns.myListing)
    f.apply:SetEnabled(not (app and app.id == l.id) and UnitLevel("player") >= (l.min or 1))
    f.apply:SetScript("OnClick", function() ns.Apply(l.leader, MOO_CharDB.role, "") end)
end

function ns.ShowGroup(leader)
    if not leader then return end
    if not groupFrame then makeGroupFrame() end
    groupFrame.leader = leader
    groupFrame:Show()
    ns.RefreshGroupFrame()
end

ns.Listen("LISTINGS_UPDATED", function() ns.RefreshGroupFrame() end)
ns.Listen("RATINGS_UPDATED", function() ns.RefreshGroupFrame() end)

ns.On("GET_ITEM_INFO_RECEIVED", function()
    if detail and detail:IsShown() then
        C_Timer.After(0.2, ns.RefreshDetail)
    end
end)

------------------------------------------------------------------------
-- Minimap button
--
-- Uses LibDBIcon if another addon already loaded it (so MOO's button sits exactly where
-- every other addon's does). Otherwise MOO places its own button the same way LibDBIcon
-- does: on the minimap's edge, sized from the minimap itself, for round and square maps.
------------------------------------------------------------------------
local MINIMAP_SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}
local EDGE_OFFSET = 5      -- how far past the minimap's edge the button's center sits
local ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"
local minimapButton

local function onClick(button)
    if button == "RightButton" then ns.ToggleMain(5) else ns.ToggleMain() end
end

local function tooltip(tt)
    tt:AddLine("Muster Of Olympus")
    tt:AddLine("Left-click: open", 1, 1, 1)
    tt:AddLine("Right-click: My Group & ready check", 1, 1, 1)
    tt:AddLine("Drag to move around the minimap", 0.6, 0.6, 0.6)
end

local function placeButton()
    local b = minimapButton
    if not b then return end
    local angle = math.rad(MOO_DB.minimap.angle or 200)
    local x, y = math.cos(angle), math.sin(angle)
    local q = 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local quad = MINIMAP_SHAPES[shape] or MINIMAP_SHAPES.ROUND
    local w = (Minimap:GetWidth() / 2) + EDGE_OFFSET
    local h = (Minimap:GetHeight() / 2) + EDGE_OFFSET
    if quad[q] then
        x, y = x * w, y * h
    else
        local dw = math.sqrt(2 * w * w) - 10
        local dh = math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    end
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function tryLibDBIcon()
    if not LibStub then return false end
    local ldb = LibStub("LibDataBroker-1.1", true)
    local icon = LibStub("LibDBIcon-1.0", true)
    if not ldb or not icon then return false end
    local obj = ldb:NewDataObject("MOO", {
        type = "launcher", text = "MOO", icon = ICON,
        OnClick = function(_, button) onClick(button) end,
        OnTooltipShow = tooltip,
    })
    MOO_DB.minimap.libdbicon = MOO_DB.minimap.libdbicon or { hide = MOO_DB.minimap.hide }
    icon:Register("MOO", obj, MOO_DB.minimap.libdbicon)
    ns.minimapLib = icon
    return true
end

local function makeMinimapButton()
    if minimapButton or ns.minimapLib then return end
    if tryLibDBIcon() then return end

    local b = CreateFrame("Button", "MOOMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Same art layout as LibDBIcon so it matches the other buttons on the ring
    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(50, 50)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(ICON)
    icon:SetPoint("CENTER")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    minimapButton = b
    placeButton()
    -- Edit Mode and other addons can resize the minimap; stay on its edge
    Minimap:HookScript("OnSizeChanged", placeButton)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            MOO_DB.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            placeButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function(_, button) onClick(button) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        tooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetShown(not MOO_DB.minimap.hide)
end

function ns.SetMinimapButtonShown(show)
    MOO_DB.minimap.hide = not show
    if ns.minimapLib then
        MOO_DB.minimap.libdbicon.hide = not show
        if show then ns.minimapLib:Show("MOO") else ns.minimapLib:Hide("MOO") end
    else
        if show and not minimapButton then makeMinimapButton() end
        if minimapButton then minimapButton:SetShown(show) end
    end
    ns.Print(show and "Minimap button shown." or "Minimap button hidden. /moo minimap brings it back.")
end

ns.Listen("READY", function()
    if ns.InOlympus() then makeMinimapButton() end
end)
