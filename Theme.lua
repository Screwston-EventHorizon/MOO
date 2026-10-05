-- MOO Theme: "classic" (the game's own window art, the default) or "dark".
-- Dark mode dims the window frame art and puts a near-black panel behind the content.
-- Text, buttons and dropdowns keep the game's style in both themes.
-- /moo theme dark | classic, or the button in the main window's header.

local _, ns = ...

local PANEL = { 0.04, 0.045, 0.055, 0.95 }   -- near-black content panel
local EDGE  = { 0.25, 0.22, 0.16, 1 }        -- thin bronze edge around it
local DIM   = { 0.45, 0.45, 0.5 }            -- frame art tint in dark mode

local targets = {}

function ns.IsDark()
    return MOO_DB ~= nil and MOO_DB.theme == "dark"
end

local function makePanel(owner, anchor, l, t, r, b)
    local p = { parts = {} }
    local bg = owner:CreateTexture(nil, "BACKGROUND", nil, 7)
    bg:SetColorTexture(unpack(PANEL))
    bg:SetPoint("TOPLEFT", anchor, "TOPLEFT", l, t)
    bg:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", r, b)
    table.insert(p.parts, bg)
    local function edge(p1, p2, w, h)
        local e = owner:CreateTexture(nil, "BORDER", nil, 7)
        e:SetColorTexture(unpack(EDGE))
        e:SetPoint(p1, bg, p1)
        e:SetPoint(p2, bg, p2)
        if w then e:SetWidth(w) end
        if h then e:SetHeight(h) end
        table.insert(p.parts, e)
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    return p
end

-- The frame's own template art: its textures and its NineSlice border pieces.
local function collectArt(frame, skip)
    local art = {}
    local function add(region)
        if region and region.IsObjectType and region:IsObjectType("Texture") and not skip[region] then
            table.insert(art, region)
        end
    end
    for _, r in ipairs({ frame:GetRegions() }) do add(r) end
    if type(frame.NineSlice) == "table" and frame.NineSlice.GetRegions then
        for _, r in ipairs({ frame.NineSlice:GetRegions() }) do add(r) end
    end
    if type(frame.TitleContainer) == "table" and frame.TitleContainer.GetRegions then
        for _, r in ipairs({ frame.TitleContainer:GetRegions() }) do add(r) end
    end
    return art
end

local function apply(t)
    local dark = ns.IsDark()
    for _, part in ipairs(t.panel.parts) do part:SetShown(dark) end
    for _, tex in ipairs(t.art) do
        if dark then tex:SetVertexColor(DIM[1], DIM[2], DIM[3]) else tex:SetVertexColor(1, 1, 1) end
    end
end

-- Register a MOO window for theming.
--   frame: the window; panelOwner: where the dark panel goes (default the window)
--   l, t, r, b: panel insets relative to panelOwner (defaults clear a standard title bar)
function ns.Themed(frame, panelOwner, l, t, r, b)
    panelOwner = panelOwner or frame
    local art = collectArt(frame, {})          -- collect before adding the panel
    local panel = makePanel(panelOwner, panelOwner, l or 6, t or -26, r or -6, b or 6)
    local entry = { frame = frame, art = art, panel = panel }
    table.insert(targets, entry)
    apply(entry)
end

function ns.SetTheme(name)
    if name ~= "dark" and name ~= "classic" then
        ns.Print("Use /moo theme dark or /moo theme classic")
        return
    end
    MOO_DB.theme = name
    for _, t in ipairs(targets) do apply(t) end
    ns.Fire("STATE_CHANGED")
end
