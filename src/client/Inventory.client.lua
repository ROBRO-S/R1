--!strict
-- Хотбар + рюкзак (пустые ячейки). Клик / цифры 1–9, иконка рюкзака открывает полный инвентарь.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local HOTBAR_SLOTS = 9
local TOTAL_SLOTS = 20
local SLOT_SIZE = 52
local SLOT_GAP = 6
local GRID_COLS = 5

local PAPER = Color3.fromRGB(232, 220, 196)
local PAPER_DARK = Color3.fromRGB(198, 178, 142)
local PAPER_EDGE = Color3.fromRGB(110, 88, 58)
local SELECTED = Color3.fromRGB(255, 236, 170)

local selectedSlot = 1
local backpackOpen = false

-- Несколько кнопок на один слот (хотбар + сетка рюкзака).
local slotButtons: { [number]: { TextButton } } = {}
local backpackFrame: Frame
local backpackButton: TextButton

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local function makeCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function makeStroke(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function styleSlot(button: TextButton, index: number)
	local selected = index == selectedSlot
	button.BackgroundColor3 = if selected then SELECTED else PAPER
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if selected then SELECTED else PAPER_EDGE
		stroke.Thickness = if selected then 3 else 2
	end
end

local function refreshSelection()
	for index, buttons in pairs(slotButtons) do
		for _, button in ipairs(buttons) do
			styleSlot(button, index)
		end
	end
end

local function selectSlot(index: number)
	if index < 1 or index > TOTAL_SLOTS then
		return
	end
	selectedSlot = index
	refreshSelection()
end

local function setBackpackOpen(open: boolean)
	backpackOpen = open
	backpackFrame.Visible = open
	backpackButton.BackgroundColor3 = if open then SELECTED else PAPER
end

local function createSlot(index: number, parent: Instance, layoutOrder: number, showHotkey: boolean): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	button.BackgroundColor3 = PAPER
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = ""
	button.Parent = parent
	makeCorner(button, 6)
	makeStroke(button, PAPER_EDGE, 2)

	if showHotkey and index <= HOTBAR_SLOTS then
		local number = Instance.new("TextLabel")
		number.Name = "Index"
		number.BackgroundTransparency = 1
		number.Position = UDim2.fromOffset(4, 2)
		number.Size = UDim2.fromOffset(16, 14)
		number.Font = Enum.Font.GothamBold
		number.TextSize = 11
		number.TextColor3 = PAPER_DARK
		number.TextXAlignment = Enum.TextXAlignment.Left
		number.Text = tostring(index)
		number.Parent = button
	end

	button.MouseButton1Click:Connect(function()
		selectSlot(index)
	end)

	local list = slotButtons[index]
	if not list then
		list = {}
		slotButtons[index] = list
	end
	table.insert(list, button)
	return button
end

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.AnchorPoint = Vector2.new(0.5, 1)
root.Position = UDim2.new(0.5, 0, 1, -18)
root.Size = UDim2.fromOffset(
	HOTBAR_SLOTS * SLOT_SIZE + (HOTBAR_SLOTS - 1) * SLOT_GAP + SLOT_SIZE + SLOT_GAP + 8,
	SLOT_SIZE
)
root.Parent = gui

local hotbar = Instance.new("Frame")
hotbar.Name = "Hotbar"
hotbar.BackgroundTransparency = 1
hotbar.Size = UDim2.fromOffset(
	HOTBAR_SLOTS * SLOT_SIZE + (HOTBAR_SLOTS - 1) * SLOT_GAP,
	SLOT_SIZE
)
hotbar.Parent = root

local hotbarLayout = Instance.new("UIListLayout")
hotbarLayout.FillDirection = Enum.FillDirection.Horizontal
hotbarLayout.Padding = UDim.new(0, SLOT_GAP)
hotbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
hotbarLayout.Parent = hotbar

for i = 1, HOTBAR_SLOTS do
	createSlot(i, hotbar, i, true)
end

backpackButton = Instance.new("TextButton")
backpackButton.Name = "BackpackButton"
backpackButton.AnchorPoint = Vector2.new(1, 0.5)
backpackButton.Position = UDim2.new(1, 0, 0.5, 0)
backpackButton.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
backpackButton.BackgroundColor3 = PAPER
backpackButton.BorderSizePixel = 0
backpackButton.Text = "🎒"
backpackButton.TextSize = 26
backpackButton.Font = Enum.Font.GothamBold
backpackButton.Parent = root
makeCorner(backpackButton, 6)
makeStroke(backpackButton, PAPER_EDGE, 2)

backpackButton.MouseButton1Click:Connect(function()
	setBackpackOpen(not backpackOpen)
end)

local rows = math.ceil(TOTAL_SLOTS / GRID_COLS)
local panelWidth = GRID_COLS * SLOT_SIZE + (GRID_COLS - 1) * SLOT_GAP + 16
local panelHeight = rows * SLOT_SIZE + (rows - 1) * SLOT_GAP + 16

backpackFrame = Instance.new("Frame")
backpackFrame.Name = "Backpack"
backpackFrame.Visible = false
backpackFrame.AnchorPoint = Vector2.new(0.5, 1)
backpackFrame.Position = UDim2.new(0.5, 0, 1, -(SLOT_SIZE + 28))
backpackFrame.Size = UDim2.fromOffset(panelWidth, panelHeight)
backpackFrame.BackgroundColor3 = PAPER_DARK
backpackFrame.BorderSizePixel = 0
backpackFrame.Parent = gui
makeCorner(backpackFrame, 10)
makeStroke(backpackFrame, PAPER_EDGE, 2)

local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromOffset(8, 8)
grid.Size = UDim2.new(1, -16, 1, -16)
grid.Parent = backpackFrame

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
gridLayout.CellPadding = UDim2.fromOffset(SLOT_GAP, SLOT_GAP)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

for i = 1, TOTAL_SLOTS do
	createSlot(i, grid, i, true)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	local keyMap: { [Enum.KeyCode]: number } = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
		[Enum.KeyCode.Five] = 5,
		[Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.Seven] = 7,
		[Enum.KeyCode.Eight] = 8,
		[Enum.KeyCode.Nine] = 9,
	}

	local slot = keyMap[input.KeyCode]
	if slot then
		selectSlot(slot)
		return
	end

	if input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.E then
		setBackpackOpen(not backpackOpen)
	end
end)

refreshSelection()
