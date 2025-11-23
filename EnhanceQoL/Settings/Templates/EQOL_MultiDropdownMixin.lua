local addonName, addon = ...

EQOL_MultiDropdownMixin = CreateFromMixins(SettingsDropdownControlMixin)

local SUMMARY_CHAR_LIMIT = 80

function EQOL_MultiDropdownMixin:OnLoad()
    -- erzeugt self.Control, self.Control.Dropdown, Tooltip-Verhalten etc.
    SettingsDropdownControlMixin.OnLoad(self)

    if self.Summary then
        self.Summary:SetText("")
        self.Summary:Hide()
        self.Summary = nil
    end

    self:EnsureSummaryAnchors()
end

function EQOL_MultiDropdownMixin:Init(initializer)
    -- Unsere eigenen Daten zuerst setzen
    self.initializer = initializer

    local data = initializer:GetData()
    -- data = { var = "abc", label = "...", options = {...}, db = addon.db }

    self.var     = data.var
    self.options = data.options or {}
    self.db      = addon.db

    for _, option in ipairs(self.options) do
        option.value = option.value or option.text
        local fallback = option.text or tostring(option.value)
        option.label = option.label or fallback
        option.text = option.text or fallback
    end

    if not self.db then
        error("EQOL_MultiDropdownMixin: data.db fehlt")
    end

    -- Jetzt Basis-Init, das InitDropdown + EvaluateState ruft (unsere überschriebenen Versionen)
    SettingsDropdownControlMixin.Init(self, initializer)

    -- Label ggf. anpassen
    if data.label then
        self.Text:SetText(data.label)
    end

    -- Summary initial anzeigen
    self:RefreshSummary()
end

-- --- Auswahlmodell: Tabelle in addon.db[var] ---

function EQOL_MultiDropdownMixin:GetSelectionTable()
    self.db = self.db or addon.db
    local t = self.db[self.var]
    if type(t) ~= "table" then
        t = {}
        self.db[self.var] = t
    end
    return t
end

function EQOL_MultiDropdownMixin:IsSelected(key)
    return self:GetSelectionTable()[key] == true
end

function EQOL_MultiDropdownMixin:ToggleOption(key)
    local t = self:GetSelectionTable()
    if t[key] then
        t[key] = nil
    else
        t[key] = true
    end

    -- optional Setting synchronisieren (z.B. als "key1,key3")
    local setting = self:GetSetting()
    if setting then
        setting:SetValue(self:SerializeSelection(t))
    end

    self:RefreshSummary()
end

function EQOL_MultiDropdownMixin:SerializeSelection(tbl)
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

function EQOL_MultiDropdownMixin:RefreshSummary()
    if not self.Summary then return end

    self:EnsureSummaryAnchors()

    local t = self:GetSelectionTable()
    local texts = {}

    for _, opt in ipairs(self.options) do
        if t[opt.value] then
            table.insert(texts, opt.text or tostring(opt.value))
        end
    end

    local summary = self:FormatSummaryText(texts)
    self.Summary:SetText(summary)
end

function EQOL_MultiDropdownMixin:EnsureSummaryAnchors()
    if self.summaryAnchored then
        return
    end

    if not (self.Summary and self.Control and self.Control.Dropdown) then
        return
    end

    self.summaryAnchored = true
    self.Summary:ClearAllPoints()
    self.Summary:SetPoint("TOPLEFT", self.Control.Dropdown, "BOTTOMLEFT", 0, -2)
    self.Summary:SetPoint("TOPRIGHT", self.Control.Dropdown, "BOTTOMRIGHT", 0, -2)
    self.Summary:SetWidth(self.Control.Dropdown:GetWidth())
end

function EQOL_MultiDropdownMixin:GetSummaryWidthLimit()
    if self.Control and self.Control.Dropdown then
        return self.Control.Dropdown:GetWidth()
    end

    if self.Summary then
        return self.Summary:GetWidth()
    end
end

function EQOL_MultiDropdownMixin:GetSummaryMeasureFontString()
    if self.summaryMeasure and self.summaryMeasure:IsObjectType("FontString") then
        return self.summaryMeasure
    end

    if not self.Summary then
        return nil
    end

    local fs = self.Summary:GetParent():CreateFontString(nil, "OVERLAY")
    if not fs then
        return nil
    end

    fs:SetFontObject(self.Summary:GetFontObject())
    fs:Hide()
    fs:SetWordWrap(false)
    fs:SetNonSpaceWrap(false)
    fs:SetSpacing(0)
    self.summaryMeasure = fs
    return fs
end

function EQOL_MultiDropdownMixin:WouldExceedSummaryWidth(text, widthLimit)
    if not text or text == "" then
        return false
    end

    if not widthLimit then
        return #text > SUMMARY_CHAR_LIMIT
    end

    local measure = self:GetSummaryMeasureFontString()
    if not measure then
        return #text > SUMMARY_CHAR_LIMIT
    end

    measure:SetFontObject(self.Summary:GetFontObject())
    measure:SetText(text)
    local getWidth = measure.GetUnboundedStringWidth or measure.GetStringWidth
    return getWidth(measure) > widthLimit
end

function EQOL_MultiDropdownMixin:FormatSummaryText(texts)
    if #texts == 0 then
        return "–"
    end

    local widthLimit = self:GetSummaryWidthLimit()
    local summary = ""
    local overflow = 0

    for index, text in ipairs(texts) do
        local candidate = (summary == "") and text or (summary .. ", " .. text)
        if widthLimit and summary ~= "" and self:WouldExceedSummaryWidth(candidate, widthLimit) then
            overflow = #texts - index + 1
            break
        elseif widthLimit and summary == "" and self:WouldExceedSummaryWidth(candidate, widthLimit) then
            summary = text
            overflow = #texts - index
            break
        else
            summary = candidate
        end
    end

    if overflow > 0 then
        local overflowText = (" … (+%d)"):format(overflow)
        local candidate = summary .. overflowText
        if widthLimit and self:WouldExceedSummaryWidth(candidate, widthLimit) then
            candidate = summary .. " …"
        end
        summary = candidate
    end

    if not widthLimit and #summary > SUMMARY_CHAR_LIMIT then
        summary = summary:sub(1, SUMMARY_CHAR_LIMIT) .. " …"
    end

    return summary
end

-- Wir ersetzen komplett die Dropdown-Initialisierung des Basis-Mixins
function EQOL_MultiDropdownMixin:InitDropdown()
    local setting     = self:GetSetting()
    local initializer = self:GetElementData()

    -- Wir bauen unsere eigene optionsFunc auf Basis self.options
    local function optionsFunc()
        return self.options
    end

    -- Tooltip wie beim Original bauen
    local initTooltip = Settings.CreateOptionsInitTooltip(
        setting,
        initializer:GetName(),
        initializer:GetTooltip(),
        optionsFunc
    )

    -- Unsere Multi-Checkbox-Variante des Dropdown-Menüs
    self:SetupDropdownMenu(self.Control.Dropdown, setting, optionsFunc, initTooltip)

    -- Steppers brauchst du bei Multi-Select i.d.R. nicht
    if self.Control and self.Control.SetSteppersShown then
        self.Control:SetSteppersShown(false)
    end
end

-- OVERRIDE: kein Settings.InitDropdown mehr, wir bauen das Menü selbst
function EQOL_MultiDropdownMixin:SetupDropdownMenu(button, setting, optionsFunc, initTooltip)
    local dropdown = button or self.Control.Dropdown

    dropdown:SetDefaultText(CUSTOM)

    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetGridMode(MenuConstants.VerticalGridDirection)

        local opts = optionsFunc() or {}

        for _, opt in ipairs(opts) do
            if opt.value ~= nil then
                local label = opt.label or opt.text or tostring(opt.value)

                rootDescription:CreateCheckbox(
                    label,
                    function()
                        return self:IsSelected(opt.value)
                    end,
                    function()
                        self:ToggleOption(opt.value)
                    end,
                    opt
                )
            end
        end
    end)

    if initTooltip then
        dropdown:SetTooltipFunc(initTooltip)
        dropdown:SetDefaultTooltipAnchors()
    end

    dropdown:SetScript("OnEnter", function()
        ButtonStateBehaviorMixin.OnEnter(dropdown)
        DefaultTooltipMixin.OnEnter(dropdown)
    end)

    dropdown:SetScript("OnLeave", function()
        ButtonStateBehaviorMixin.OnLeave(dropdown)
        DefaultTooltipMixin.OnLeave(dropdown)
    end)
end
