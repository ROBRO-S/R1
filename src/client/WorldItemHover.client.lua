--!strict
-- При наведении на ветку/камень — маленькая подсказка с иконкой и названием.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local mouse = player:GetMouse()

local ATTR_ITEM = "ItemId"
local ATTR_WORLD_LOOT = "WorldLoot"

local FALLBACK_NAMES: { [string]: string } = {
	FistWeapon = "Fist Weapon",
	Axe = "Axe",
	Stick = "Stick",
	SmallRock = "Rock",
}

local ItemCatalog: any = nil
local ItemIcon: any = nil

local gui = Instance.new("ScreenGui")
gui.Name = "WorldItemHoverGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 80
gui.Parent = playerGui

local tip = Instance.new("Frame")
tip.Name = "Tip"
tip.Visible = false
tip.BackgroundColor3 = Color3.fromRGB(232, 220, 196)
tip.BorderSizePixel = 0
tip.Size = UDim2.fromOffset(120, 36)
tip.Parent = gui

local tipCorner = Instance.new("UICorner")
tipCorner.CornerRadius = UDim.new(0, 6)
tipCorner.Parent = tip

local tipStroke = Instance.new("UIStroke")
tipStroke.Color = Color3.fromRGB(110, 88, 58)
tipStroke.Thickness = 2
tipStroke.Parent = tip

local iconHolder = Instance.new("Frame")
iconHolder.Name = "Icon"
iconHolder.BackgroundTransparency = 1
iconHolder.Position = UDim2.fromOffset(6, 4)
iconHolder.Size = UDim2.fromOffset(28, 28)
iconHolder.Parent = tip

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "Name"
nameLabel.BackgroundTransparency = 1
nameLabel.Position = UDim2.fromOffset(38, 0)
nameLabel.Size = UDim2.new(1, -44, 1, 0)
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextSize = 13
nameLabel.TextColor3 = Color3.fromRGB(60, 44, 28)
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
nameLabel.Text = ""
nameLabel.Parent = tip

local currentId: string? = nil

local function displayName(itemId: string): string
	if ItemCatalog and ItemCatalog.DisplayName then
		return ItemCatalog.DisplayName(itemId)
	end
	return FALLBACK_NAMES[itemId] or itemId
end

local function applyIcon(itemId: string)
	if ItemIcon and ItemIcon.Apply then
		ItemIcon.Apply(iconHolder, itemId)
		return
	end
	for _, child in ipairs(iconHolder:GetChildren()) do
		child:Destroy()
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(60, 44, 28)
	label.Text = string.sub(displayName(itemId), 1, 1)
	label.Parent = iconHolder
end

local function resolveItemId(inst: Instance?): string?
	local node: Instance? = inst
	while node and node ~= Workspace do
		if node:GetAttribute(ATTR_WORLD_LOOT) == true then
			local id = node:GetAttribute(ATTR_ITEM)
			if typeof(id) == "string" and id ~= "" then
				return id
			end
		end
		if node.Name == "Stick" or node.Name == "SmallRock" or node.Name == "FistWeapon" or node.Name == "Axe" then
			return node.Name
		end
		node = node.Parent
	end
	return nil
end

local function setTip(itemId: string?)
	if itemId == currentId then
		return
	end
	currentId = itemId
	if not itemId then
		tip.Visible = false
		return
	end
	nameLabel.Text = displayName(itemId)
	applyIcon(itemId)
	tip.Visible = true
end

task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 30)
	if not shared then
		return
	end
	local catalogInst = shared:FindFirstChild("ItemCatalog")
	local iconInst = shared:FindFirstChild("ItemIcon")
	if catalogInst and catalogInst:IsA("ModuleScript") then
		local ok, result = pcall(require, catalogInst)
		if ok then
			ItemCatalog = result
		end
	end
	if iconInst and iconInst:IsA("ModuleScript") then
		local ok, result = pcall(require, iconInst)
		if ok then
			ItemIcon = result
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if UserInputService:GetFocusedTextBox() then
		setTip(nil)
		return
	end

	local screenPos = UserInputService:GetMouseLocation()
	local camera = Workspace.CurrentCamera
	if not camera then
		setTip(nil)
		return
	end

	local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { gui }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 40, params)
	local itemId = if result then resolveItemId(result.Instance) else nil
	if not itemId and mouse.Target then
		itemId = resolveItemId(mouse.Target)
	end

	setTip(itemId)
	if tip.Visible then
		local pos = UserInputService:GetMouseLocation()
		tip.Position = UDim2.fromOffset(pos.X + 16, pos.Y + 16)
	end
end)
