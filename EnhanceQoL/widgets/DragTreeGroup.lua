local AceGUI = LibStub("AceGUI-3.0")
local GetMouseFocus = _G.GetMouseFoci

--[[ DragTreeGroup - simple TreeGroup extension with drag-and-drop
     Dragging is started with a left-click while holding ALT.
     When the mouse is released over another entry, the widget fires
     an "OnDragDrop" callback with the source and target unique values.
]]

local Type, Version = "EQOL_DragTreeGroup", 3

local function Constructor()
	local tree = AceGUI:Create("TreeGroup")
	tree.type = Type

	if not tree.origCreateButton then tree.origCreateButton = tree.CreateButton end

	function tree:CreateButton()
		local btn = self:origCreateButton()

		local oldMouseDown = btn:GetScript("OnMouseDown")
		local oldMouseUp = btn:GetScript("OnMouseUp")
		local oldEnter = btn:GetScript("OnEnter")
		local oldLeave = btn:GetScript("OnLeave")

		btn:SetScript("OnMouseDown", function(frame, button)
			if button == "LeftButton" and IsAltKeyDown() then
				frame.obj.dragSource = frame.uniquevalue
				frame.obj.dragging = true
				frame.obj.dragButton = frame
				frame:LockHighlight()
			elseif oldMouseDown then
				oldMouseDown(frame, button)
			end
		end)

		local function findTarget(obj)
			local focus = GetMouseFocus()
			if focus and focus[1] and focus[1].obj == obj and focus[1].uniquevalue then return focus[1].uniquevalue end
		end

		btn:SetScript("OnMouseUp", function(frame, button)
			local obj = frame.obj
			if obj.dragging then
				obj.dragging = nil
				if obj.dragButton then
					obj.dragButton:UnlockHighlight()
					obj.dragButton = nil
				end
				local src = obj.dragSource
				obj.dragSource = nil
				local target = findTarget(obj)
				if src and target and src ~= target then obj:Fire("OnDragDrop", src, target) end
			end
			if oldMouseUp then oldMouseUp(frame, button) end
		end)

		btn:SetScript("OnEnter", function(frame)
			if frame.obj.dragging then frame:LockHighlight() end
			if oldEnter then oldEnter(frame) end
		end)

		btn:SetScript("OnLeave", function(frame)
			if frame.obj.dragging and not frame.selected then frame:UnlockHighlight() end
			if oldLeave then oldLeave(frame) end
		end)

		return btn
	end

	return tree
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
