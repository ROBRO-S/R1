--!strict
-- Хотбар + рюкзак из InvState. Стаки: "Stick x3". G / drag — дроп.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local HOTBAR_SLOTS = 9
local TOTAL_SLOTS = 20
local SLOT_SIZE = 56
local SLOT_GAP = 6
local GRID_COLS = 5
local ATTR_SLOT = "InvSlot"
local ATTR_COUNT = "Count"

local PAPER = Color3.fromRGB(232, 220, 196)
local PAPER_DARK = Color3.fromRGB(198, 178, 142)
local PAPER_EDGE = Color3.fromRGB(110, 88, 58)
local SELECTED = Color3.fromRGB(255, 236, 170)

local FALLBACK_NAMES: { [string]: string } = {
	FistWeapon = "Fist Weapon",
	Stick = "Stick",
	SmallRock = "Rock",
}

local selectedSlot = 1
local backpackOpen = false
local slotButtons: { [number]: { TextButton } } = {}
local slotItemIds: { [number]: string } = {}
local slotCounts: { [number]: number } = {}
local backpackFrame: Frame
local backpackButton: TextButton
local dragFrom: number? = nil
local dragGhost: Frame? = nil
local dragMoved = false

local ItemCatalog: any = nil
local ItemIcon: any = nil
local equipRemote: RemoteEvent? = nil
local dropRemote: RemoteEvent? = nil
local moveRemote: RemoteEvent? = nil
local invState: Folder? = nil
local backpack: Backpack? = nil

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

local function displayName(itemId: string): string
	if ItemCatalog and ItemCatalog.DisplayName then
		return ItemCatalog.DisplayName(itemId)
	end
	return FALLBACK_NAMES[itemId] or itemId
end

local function isMelee(itemId: string): boolean
	if ItemCatalog and ItemCatalog.IsMelee then
		return ItemCatalog.IsMelee(itemId)
	end
	return itemId == "FistWeapon"
end

local function slotLabelText(itemId: string?, count: number?): string
	if not itemId then
		return ""
	end
	local name = displayName(itemId)
	local n = count or 1
	if n > 1 then
		return name .. " x" .. tostring(n)
	end
	return name
end

local function applyIcon(holder: Frame, itemId: string?)
	if ItemIcon and ItemIcon.Apply then
		ItemIcon.Apply(holder, itemId)
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		child:Destroy()
	end
	if not itemId then
		return
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(60, 44, 28)
	label.Text = string.sub(displayName(itemId), 1, 1)
	label.Parent = holder
end

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true
gui.Parent = playerGui

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

local function refreshSlotVisuals()
	for index = 1, TOTAL_SLOTS do
		local itemId = slotItemIds[index]
		local count = slotCounts[index]
		local buttons = slotButtons[index]
		if buttons then
			for _, button in ipairs(buttons) do
				local iconHolder = button:FindFirstChild("Icon")
				local label = button:FindFirstChild("Item")
				local countBadge = button:FindFirstChild("Count")
				if iconHolder and iconHolder:IsA("Frame") then
					applyIcon(iconHolder, itemId)
				end
				if label and label:IsA("TextLabel") then
					label.Text = slotLabelText(itemId, count)
				end
				if countBadge and countBadge:IsA("TextLabel") then
					if itemId and (count or 1) > 1 then
						countBadge.Text = "x" .. tostring(count)
						countBadge.Visible = true
					else
						countBadge.Text = ""
						countBadge.Visible = false
					end
				end
			end
		end
	end
end

local function findToolForSlot(slot: number): Tool?
	local function scan(container: Instance?): Tool?
		if not container then
			return nil
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute(ATTR_SLOT) == slot then
				return child
			end
		end
		return nil
	end
	local pack = backpack or player:FindFirstChildOfClass("Backpack")
	return scan(pack) or scan(player.Character)
end

local function syncFromInvState()
	table.clear(slotItemIds)
	table.clear(slotCounts)
	if invState then
		for _, child in ipairs(invState:GetChildren()) do
			if child:IsA("StringValue") then
				local slot = tonumber(string.match(child.Name, "^Slot(%d+)$"))
				if slot and slot >= 1 and slot <= TOTAL_SLOTS and child.Value ~= "" then
					slotItemIds[slot] = child.Value
					local countAttr = child:GetAttribute(ATTR_COUNT)
					slotCounts[slot] = if typeof(countAttr) == "number" then math.max(1, countAttr) else 1
				end
			end
		end
		local equipped = invState:FindFirstChild("Equipped")
		if equipped and equipped:IsA("IntValue") and equipped.Value > 0 then
			selectedSlot = equipped.Value
		end
	end
	refreshSlotVisuals()
	refreshSelection()
end

local function isHoldingSlot(slot: number): boolean
	local character = player.Character
	if not character then
		return false
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute(ATTR_SLOT) == slot then
			return true
		end
	end
	return false
end

local function selectSlot(index: number)
	if index < 1 or index > TOTAL_SLOTS then
		return
	end
	selectedSlot = index
	refreshSelection()

	local itemId = slotItemIds[index]
	-- Сервер сам снимет с рук при повторном выборе того же слота.
	if equipRemote then
		equipRemote:FireServer(if itemId then index else 0)
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if not itemId then
		humanoid:UnequipTools()
		return
	end
	if isHoldingSlot(index) then
		humanoid:UnequipTools()
		return
	end
	local tool = findToolForSlot(index)
	if tool then
		humanoid:EquipTool(tool)
	else
		humanoid:UnequipTools()
	end
end

local function requestDrop(slot: number)
	if not slotItemIds[slot] then
		return
	end
	if dropRemote then
		dropRemote:FireServer(slot)
	end
end

local function requestMove(fromSlot: number, toSlot: number)
	if moveRemote then
		moveRemote:FireServer(fromSlot, toSlot)
	end
end

local function setBackpackOpen(open: boolean)
	backpackOpen = open
	backpackFrame.Visible = open
	backpackButton.BackgroundColor3 = if open then SELECTED else PAPER
end

local function destroyGhost()
	if dragGhost then
		dragGhost:Destroy()
		dragGhost = nil
	end
end

local function beginDrag(slot: number)
	local itemId = slotItemIds[slot]
	if not itemId then
		return
	end
	dragFrom = slot
	dragMoved = false
	destroyGhost()

	local ghost = Instance.new("Frame")
	ghost.Name = "DragGhost"
	ghost.BackgroundColor3 = PAPER
	ghost.BorderSizePixel = 0
	ghost.Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
	ghost.ZIndex = 50
	ghost.Parent = gui
	makeCorner(ghost, 6)
	makeStroke(ghost, PAPER_EDGE, 2)

	local icon = Instance.new("Frame")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(6, 2)
	icon.Size = UDim2.new(1, -12, 1, -20)
	icon.ZIndex = 51
	icon.Parent = ghost
	applyIcon(icon, itemId)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -3)
	label.Size = UDim2.new(1, -6, 0, 14)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 10
	label.TextColor3 = Color3.fromRGB(60, 44, 28)
	label.Text = slotLabelText(itemId, slotCounts[slot])
	label.ZIndex = 51
	label.Parent = ghost

	dragGhost = ghost
end

local function slotAtScreenPos(screenPos: Vector2): number?
	for index, buttons in pairs(slotButtons) do
		for _, button in ipairs(buttons) do
			if button.Visible and button.AbsoluteSize.X > 0 then
				local pos = button.AbsolutePosition
				local size = button.AbsoluteSize
				if screenPos.X >= pos.X
					and screenPos.X <= pos.X + size.X
					and screenPos.Y >= pos.Y
					and screenPos.Y <= pos.Y + size.Y
				then
					return index
				end
			end
		end
	end
	return nil
end

local function endDrag()
	local from = dragFrom
	dragFrom = nil
	destroyGhost()
	if not from then
		return
	end

	local inset = GuiService:GetGuiInset()
	local mousePos = UserInputService:GetMouseLocation() - inset
	local over = slotAtScreenPos(mousePos)

	if not dragMoved then
		selectSlot(from)
		return
	end

	if over and over ~= from then
		requestMove(from, over)
		return
	end

	if not over then
		requestDrop(from)
	end
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
		number.ZIndex = 3
		number.Parent = button
	end

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"
	iconHolder.BackgroundTransparency = 1
	iconHolder.Position = UDim2.fromOffset(6, 4)
	iconHolder.Size = UDim2.new(1, -12, 1, -22)
	iconHolder.Parent = button

	local countBadge = Instance.new("TextLabel")
	countBadge.Name = "Count"
	countBadge.BackgroundTransparency = 1
	countBadge.AnchorPoint = Vector2.new(1, 0)
	countBadge.Position = UDim2.new(1, -4, 0, 2)
	countBadge.Size = UDim2.fromOffset(28, 14)
	countBadge.Font = Enum.Font.GothamBold
	countBadge.TextSize = 11
	countBadge.TextColor3 = Color3.fromRGB(60, 44, 28)
	countBadge.TextXAlignment = Enum.TextXAlignment.Right
	countBadge.Text = ""
	countBadge.Visible = false
	countBadge.ZIndex = 4
	countBadge.Parent = button

	local item = Instance.new("TextLabel")
	item.Name = "Item"
	item.BackgroundTransparency = 1
	item.AnchorPoint = Vector2.new(0.5, 1)
	item.Position = UDim2.new(0.5, 0, 1, -3)
	item.Size = UDim2.new(1, -6, 0, 14)
	item.Font = Enum.Font.GothamBold
	item.TextSize = 10
	item.TextColor3 = Color3.fromRGB(60, 44, 28)
	item.TextTruncate = Enum.TextTruncate.AtEnd
	item.Text = ""
	item.ZIndex = 2
	item.Parent = button

	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if slotItemIds[index] then
				beginDrag(index)
			else
				selectSlot(index)
			end
		end
	end)

	local list = slotButtons[index]
	if not list then
		list = {}
		slotButtons[index] = list
	end
	table.insert(list, button)
	return button
end

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

refreshSelection()

UserInputService.InputChanged:Connect(function(input: InputObject)
	if not dragFrom or not dragGhost then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
	then
		dragMoved = true
		local pos = UserInputService:GetMouseLocation()
		dragGhost.Position = UDim2.fromOffset(pos.X - SLOT_SIZE / 2, pos.Y - SLOT_SIZE / 2)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		if dragFrom then
			endDrag()
		end
	end
end)

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

	if input.KeyCode == Enum.KeyCode.B then
		setBackpackOpen(not backpackOpen)
		return
	end

	if input.KeyCode == Enum.KeyCode.G then
		requestDrop(selectedSlot)
	end
end)

local function hookInvState(folder: Folder)
	invState = folder
	local function hookValue(child: Instance)
		if child:IsA("StringValue") then
			child.Changed:Connect(syncFromInvState)
			child:GetAttributeChangedSignal(ATTR_COUNT):Connect(syncFromInvState)
		elseif child:IsA("IntValue") and child.Name == "Equipped" then
			child.Changed:Connect(syncFromInvState)
		end
	end
	folder.ChildAdded:Connect(function(child)
		hookValue(child)
		task.defer(syncFromInvState)
	end)
	folder.ChildRemoved:Connect(function()
		task.defer(syncFromInvState)
	end)
	for _, child in ipairs(folder:GetChildren()) do
		hookValue(child)
	end
	syncFromInvState()
end

-- Сервисы/модули — после появления UI, чтобы хотбар не пропадал при ошибке.
task.spawn(function()
	backpack = player:WaitForChild("Backpack") :: Backpack

	local shared = ReplicatedStorage:WaitForChild("Shared", 30)
	if shared then
		local catalogInst = shared:FindFirstChild("ItemCatalog")
		local iconInst = shared:FindFirstChild("ItemIcon")
		if catalogInst and catalogInst:IsA("ModuleScript") then
			local ok, result = pcall(require, catalogInst)
			if ok then
				ItemCatalog = result
			else
				warn("Inventory: ItemCatalog require failed:", result)
			end
		end
		if iconInst and iconInst:IsA("ModuleScript") then
			local ok, result = pcall(require, iconInst)
			if ok then
				ItemIcon = result
			else
				warn("Inventory: ItemIcon require failed:", result)
			end
		end
	else
		warn("Inventory: нет ReplicatedStorage.Shared — текстовые иконки")
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	if remotes then
		local eq = remotes:WaitForChild("EquipSlot", 10)
		local drop = remotes:WaitForChild("DropSlot", 10)
		local move = remotes:WaitForChild("MoveSlot", 10)
		if eq and eq:IsA("RemoteEvent") then
			equipRemote = eq
		end
		if drop and drop:IsA("RemoteEvent") then
			dropRemote = drop
		end
		if move and move:IsA("RemoteEvent") then
			moveRemote = move
		end
	end

	local folder = player:FindFirstChild("InvState")
	if not (folder and folder:IsA("Folder")) then
		folder = player:WaitForChild("InvState", 60)
	end
	if folder and folder:IsA("Folder") then
		hookInvState(folder)
	else
		warn("Inventory: InvState не пришёл с сервера")
	end

	refreshSlotVisuals()
end)

print("Inventory: UI готов")
