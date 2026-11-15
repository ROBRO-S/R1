--!strict
-- Шкалы HP + Defence над хотбаром слева.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local SLOT_SIZE = 56
local SLOT_GAP = 6
local HOTBAR_SLOTS = 9
local HP_WIDTH = 105
local HP_HEIGHT = 13
local DEF_WIDTH = 88
local DEF_HEIGHT = 9
local BOTTOM_PAD = 18
local GAP_ABOVE_HOTBAR = 10
local GAP_BETWEEN = 4

local ATTR_DEFENCE = "Defence"
local ATTR_MAX_DEFENCE = "MaxDefence"

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local HealthBar = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HealthBar"))

local gui = Instance.new("ScreenGui")
gui.Name = "PlayerHealth"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0, 1)
holder.Parent = gui

local stack = Instance.new("Frame")
stack.Name = "Stack"
stack.BackgroundTransparency = 1
stack.Size = UDim2.fromScale(1, 1)
stack.Parent = holder

local stackLayout = Instance.new("UIListLayout")
stackLayout.FillDirection = Enum.FillDirection.Vertical
stackLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
stackLayout.Padding = UDim.new(0, GAP_BETWEEN)
stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
stackLayout.Parent = stack

local function layoutHolder()
	local hotbarWidth = HOTBAR_SLOTS * SLOT_SIZE + (HOTBAR_SLOTS - 1) * SLOT_GAP
	local backpackExtra = SLOT_SIZE + SLOT_GAP + 8
	local rootWidth = hotbarWidth + backpackExtra
	local left = -math.floor(rootWidth / 2)
	local totalH = HP_HEIGHT + 6 + DEF_HEIGHT + 4 + GAP_BETWEEN
	holder.Position = UDim2.new(0.5, left, 1, -(BOTTOM_PAD + SLOT_SIZE + GAP_ABOVE_HOTBAR))
	holder.Size = UDim2.fromOffset(math.max(HP_WIDTH, DEF_WIDTH), totalH)
end
layoutHolder()

local defBar = HealthBar.Create(stack, {
	Width = DEF_WIDTH,
	Height = DEF_HEIGHT,
	Icon = "shield",
	Palette = "defence",
	ShowLabel = true,
	ZIndex = 20,
	LayoutOrder = 1,
})
defBar.Root.Visible = false

local hpBar = HealthBar.Create(stack, {
	Width = HP_WIDTH,
	Height = HP_HEIGHT,
	Icon = "heart",
	Palette = "health",
	ShowLabel = true,
	ZIndex = 20,
	LayoutOrder = 2,
})

local healthConn: RBXScriptConnection? = nil
local maxConn: RBXScriptConnection? = nil
local defConn: RBXScriptConnection? = nil
local maxDefConn: RBXScriptConnection? = nil

local function syncDefence(character: Model)
	local maxD = character:GetAttribute(ATTR_MAX_DEFENCE)
	local cur = character:GetAttribute(ATTR_DEFENCE)
	local maxN = if typeof(maxD) == "number" then maxD else 0
	local curN = if typeof(cur) == "number" then cur else 0
	if maxN > 0 then
		defBar.Root.Visible = true
		defBar.SetHealth(curN, maxN)
	else
		defBar.Root.Visible = false
	end
end

local function bindHumanoid(character: Model, humanoid: Humanoid)
	if healthConn then
		healthConn:Disconnect()
		healthConn = nil
	end
	if maxConn then
		maxConn:Disconnect()
		maxConn = nil
	end
	if defConn then
		defConn:Disconnect()
		defConn = nil
	end
	if maxDefConn then
		maxDefConn:Disconnect()
		maxDefConn = nil
	end

	local function syncHp()
		hpBar.SetHealth(humanoid.Health, humanoid.MaxHealth)
	end
	syncHp()
	syncDefence(character)

	healthConn = humanoid.HealthChanged:Connect(function(hp)
		hpBar.SetHealth(hp, humanoid.MaxHealth)
	end)
	maxConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(syncHp)
	defConn = character:GetAttributeChangedSignal(ATTR_DEFENCE):Connect(function()
		syncDefence(character)
	end)
	maxDefConn = character:GetAttributeChangedSignal(ATTR_MAX_DEFENCE):Connect(function()
		syncDefence(character)
	end)
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		bindHumanoid(character, humanoid)
	end
end

if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)
