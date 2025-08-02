local parentAddonName = "EnhanceQoL"
local addonName, addon = ...
if _G[parentAddonName] then
	addon = _G[parentAddonName]
else
	error(parentAddonName .. " is not loaded")
end

addon.SharedMedia = addon.SharedMedia or {}
addon.SharedMedia.functions = addon.SharedMedia.functions or {}

local function addSoundFrame(container)
	local scroll = addon.functions.createContainer("ScrollFrame", "Flow")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	container:AddChild(scroll)

	local wrapper = addon.functions.createContainer("SimpleGroup", "List")
	wrapper:SetFullWidth(true)
	scroll:AddChild(wrapper)

	for _, sound in ipairs(addon.SharedMedia.sounds or {}) do
		local row = addon.functions.createContainer("SimpleGroup", "Flow")
		row:SetFullWidth(true)

		local cb = addon.functions.createCheckboxAce(sound.label, addon.db.sharedMediaSounds[sound.key], function(self, _, value) addon.SharedMedia.functions.UpdateSound(sound.key, value) end)
		cb:SetRelativeWidth(0.8)
		row:AddChild(cb)

		local btn = addon.functions.createButtonAce("Play", 80, function() PlaySoundFile(sound.path) end)
		btn:SetRelativeWidth(0.2)
		row:AddChild(btn)

		wrapper:AddChild(row)
	end
end

function addon.SharedMedia.functions.treeCallback(container, group)
	container:ReleaseChildren()
	addSoundFrame(container)
end
