--!strict
-- Меню крафта: открывается вместе с рюкзаком. Категория Weapons + панель рецепта.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local PAPER = Color3.fromRGB(232, 220, 196)
local PAPER_DARK = Color3.fromRGB(198, 178, 142)
local PAPER_EDGE = Color3.fromRGB(110, 88, 58)
local SELECTED = Color3.fromRGB(255, 236, 170)
local TEXT = Color3.fromRGB(60, 44, 28)
local TEXT_LIGHT = Color3.fromRGB(245, 235, 210)
local GREEN = Color3.fromRGB(72, 150, 72)
local GREEN_HOVER = Color3.fromRGB(88, 170, 88)
local GREY = Color3.fromRGB(130, 118, 100)
local RED = Color3.fromRGB(190, 55, 45)

local CAT_W = 52
local LIST_W = 210
local DETAIL_W = 240
local PANEL_H = 320
local ROW_H = 40
local ATTR_COUNT = "Count"
local TOTAL_SLOTS = 20

local CraftCatalog: any = nil
local ItemCatalog: any = nil
local ItemIcon: any = nil
local craftRemote: RemoteEvent? = nil

local selectedCategory = "Weapons"
local selectedRecipe: string? = nil
local invCounts: { [string]: number } = {}

local craftRoot: Frame
local catRail: Frame
local listFrame: Frame
local detailFrame: Frame
local listButtons: { [string]: TextButton } = {}
local categoryButtons: { [string]: TextButton } = {}

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
	return itemId
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
	label.TextColor3 = TEXT
	label.Text = string.sub(displayName(itemId), 1, 1)
	label.Parent = holder
end

local function recountFromInvState(folder: Folder?)
	table.clear(invCounts)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("StringValue") then
			local slot = tonumber(string.match(child.Name, "^Slot(%d+)$"))
			if slot and slot >= 1 and slot <= TOTAL_SLOTS and child.Value ~= "" then
				local countAttr = child:GetAttribute(ATTR_COUNT)
				local n = if typeof(countAttr) == "number" then math.max(1, countAttr) else 1
				invCounts[child.Value] = (invCounts[child.Value] or 0) + n
			end
		end
	end
end

local function canCraft(recipe: any): boolean
	if not recipe then
		return false
	end
	for _, cost in ipairs(recipe.costs) do
		local have = invCounts[cost.id] or 0
		if have < cost.count then
			return false
		end
	end
	return true
end

local function clearFrame(frame: Frame)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function styleCategory(catId: string)
	for id, button in pairs(categoryButtons) do
		local on = id == selectedCategory
		button.BackgroundColor3 = if on then SELECTED else PAPER
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if on then 3 else 2
			stroke.Color = if on then SELECTED else PAPER_EDGE
		end
	end
end

local function styleRecipeRows()
	for id, button in pairs(listButtons) do
		local on = id == selectedRecipe
		button.BackgroundColor3 = if on then SELECTED else PAPER
	end
end

local function refreshDetail()
	clearFrame(detailFrame)
	detailFrame.Visible = selectedRecipe ~= nil
	if not selectedRecipe or not CraftCatalog then
		return
	end

	local recipe = CraftCatalog.GetRecipe(selectedRecipe)
	if not recipe then
		detailFrame.Visible = false
		return
	end

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = detailFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = detailFrame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 56)
	header.LayoutOrder = 1
	header.Parent = detailFrame

	local iconBox = Instance.new("Frame")
	iconBox.Name = "Icon"
	iconBox.BackgroundColor3 = PAPER
	iconBox.BorderSizePixel = 0
	iconBox.Size = UDim2.fromOffset(52, 52)
	iconBox.Parent = header
	makeCorner(iconBox, 6)
	makeStroke(iconBox, PAPER_EDGE, 2)
	applyIcon(iconBox, recipe.result)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(60, 4)
	title.Size = UDim2.new(1, -64, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = TEXT_LIGHT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = displayName(recipe.result)
	title.Parent = header

	if recipe.count > 1 then
		local qty = Instance.new("TextLabel")
		qty.BackgroundTransparency = 1
		qty.Position = UDim2.fromOffset(60, 28)
		qty.Size = UDim2.new(1, -64, 0, 18)
		qty.Font = Enum.Font.GothamBold
		qty.TextSize = 14
		qty.TextColor3 = PAPER
		qty.TextXAlignment = Enum.TextXAlignment.Left
		qty.Text = "x" .. tostring(recipe.count)
		qty.Parent = header
	end

	if recipe.description ~= "" then
		local desc = Instance.new("TextLabel")
		desc.Name = "Desc"
		desc.BackgroundTransparency = 1
		desc.Size = UDim2.new(1, 0, 0, 36)
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 13
		desc.TextColor3 = PAPER
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextWrapped = true
		desc.Text = recipe.description
		desc.LayoutOrder = 2
		desc.Parent = detailFrame
	end

	local preview = if CraftCatalog.GetMeleePreview then CraftCatalog.GetMeleePreview(recipe.result) else nil
	if preview then
		local stats = Instance.new("Frame")
		stats.Name = "Stats"
		stats.BackgroundTransparency = 1
		stats.Size = UDim2.new(1, 0, 0, 40)
		stats.LayoutOrder = 3
		stats.Parent = detailFrame

		local dmg = Instance.new("TextLabel")
		dmg.BackgroundTransparency = 1
		dmg.Size = UDim2.new(0.5, -4, 1, 0)
		dmg.Font = Enum.Font.GothamBold
		dmg.TextSize = 14
		dmg.TextColor3 = TEXT_LIGHT
		dmg.TextXAlignment = Enum.TextXAlignment.Left
		dmg.TextYAlignment = Enum.TextYAlignment.Top
		dmg.Text = "Damage\n" .. tostring(preview.damage)
		dmg.Parent = stats

		local spd = Instance.new("TextLabel")
		spd.BackgroundTransparency = 1
		spd.Position = UDim2.new(0.5, 4, 0, 0)
		spd.Size = UDim2.new(0.5, -4, 1, 0)
		spd.Font = Enum.Font.GothamBold
		spd.TextSize = 14
		spd.TextColor3 = TEXT_LIGHT
		spd.TextXAlignment = Enum.TextXAlignment.Left
		spd.TextYAlignment = Enum.TextYAlignment.Top
		spd.Text = "Attack Speed\n" .. string.format("%.1f", preview.attack_speed)
		spd.Parent = stats
	end

	local reqTitle = Instance.new("TextLabel")
	reqTitle.BackgroundTransparency = 1
	reqTitle.Size = UDim2.new(1, 0, 0, 18)
	reqTitle.Font = Enum.Font.GothamBold
	reqTitle.TextSize = 14
	reqTitle.TextColor3 = TEXT_LIGHT
	reqTitle.TextXAlignment = Enum.TextXAlignment.Left
	reqTitle.Text = "Required"
	reqTitle.LayoutOrder = 4
	reqTitle.Parent = detailFrame

	local reqList = Instance.new("Frame")
	reqList.Name = "Costs"
	reqList.BackgroundTransparency = 1
	reqList.Size = UDim2.new(1, 0, 0, #recipe.costs * 34)
	reqList.LayoutOrder = 5
	reqList.Parent = detailFrame

	local reqLayout = Instance.new("UIListLayout")
	reqLayout.FillDirection = Enum.FillDirection.Vertical
	reqLayout.Padding = UDim.new(0, 4)
	reqLayout.Parent = reqList

	local affordable = true
	for i, cost in ipairs(recipe.costs) do
		local have = invCounts[cost.id] or 0
		local ok = have >= cost.count
		if not ok then
			affordable = false
		end

		local row = Instance.new("Frame")
		row.BackgroundColor3 = PAPER
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 30)
		row.LayoutOrder = i
		row.Parent = reqList
		makeCorner(row, 4)

		local costIcon = Instance.new("Frame")
		costIcon.Name = "Icon"
		costIcon.BackgroundTransparency = 1
		costIcon.Position = UDim2.fromOffset(4, 2)
		costIcon.Size = UDim2.fromOffset(26, 26)
		costIcon.Parent = row
		applyIcon(costIcon, cost.id)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.fromOffset(34, 0)
		nameLabel.Size = UDim2.new(1, -90, 1, 0)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 13
		nameLabel.TextColor3 = TEXT
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = displayName(cost.id)
		nameLabel.Parent = row

		local ratio = Instance.new("TextLabel")
		ratio.BackgroundTransparency = 1
		ratio.AnchorPoint = Vector2.new(1, 0.5)
		ratio.Position = UDim2.new(1, -8, 0.5, 0)
		ratio.Size = UDim2.fromOffset(56, 20)
		ratio.Font = Enum.Font.GothamBold
		ratio.TextSize = 14
		ratio.TextColor3 = if ok then TEXT else RED
		ratio.TextXAlignment = Enum.TextXAlignment.Right
		ratio.Text = string.format("%d/%d", have, cost.count)
		ratio.Parent = row
	end

	local craftBtn = Instance.new("TextButton")
	craftBtn.Name = "Craft"
	craftBtn.Size = UDim2.new(1, 0, 0, 36)
	craftBtn.BorderSizePixel = 0
	craftBtn.Font = Enum.Font.GothamBold
	craftBtn.TextSize = 16
	craftBtn.Text = "Craft"
	craftBtn.AutoButtonColor = affordable
	craftBtn.LayoutOrder = 6
	craftBtn.Parent = detailFrame
	makeCorner(craftBtn, 6)

	if affordable then
		craftBtn.BackgroundColor3 = GREEN
		craftBtn.TextColor3 = Color3.new(1, 1, 1)
		craftBtn.MouseEnter:Connect(function()
			if craftBtn.Parent then
				craftBtn.BackgroundColor3 = GREEN_HOVER
			end
		end)
		craftBtn.MouseLeave:Connect(function()
			if craftBtn.Parent then
				craftBtn.BackgroundColor3 = GREEN
			end
		end)
		craftBtn.MouseButton1Click:Connect(function()
			if craftRemote and selectedRecipe and canCraft(recipe) then
				craftRemote:FireServer(selectedRecipe)
			end
		end)
	else
		craftBtn.BackgroundColor3 = GREY
		craftBtn.TextColor3 = Color3.fromRGB(210, 200, 180)
		craftBtn.Active = false
	end
end

local function rebuildList()
	clearFrame(listFrame)
	table.clear(listButtons)
	if not CraftCatalog then
		return
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -16, 0, 28)
	title.Position = UDim2.fromOffset(8, 6)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = TEXT_LIGHT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Weapons"
	title.Parent = listFrame

	local cats = CraftCatalog.GetCategories()
	for _, cat in ipairs(cats) do
		if cat.id == selectedCategory then
			title.Text = cat.display_name
			break
		end
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(8, 36)
	scroll.Size = UDim2.new(1, -16, 1, -44)
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = listFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local recipes = CraftCatalog.GetRecipesForCategory(selectedCategory)
	if selectedRecipe == nil and #recipes > 0 then
		selectedRecipe = recipes[1].id
	end

	for i, recipe in ipairs(recipes) do
		local row = Instance.new("TextButton")
		row.Name = recipe.id
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		row.BorderSizePixel = 0
		row.AutoButtonColor = true
		row.Text = ""
		row.BackgroundColor3 = if recipe.id == selectedRecipe then SELECTED else PAPER
		row.Parent = scroll
		makeCorner(row, 6)

		local icon = Instance.new("Frame")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Position = UDim2.fromOffset(6, 4)
		icon.Size = UDim2.fromOffset(ROW_H - 8, ROW_H - 8)
		icon.Parent = row
		applyIcon(icon, recipe.result)

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(ROW_H, 0)
		name.Size = UDim2.new(1, -(ROW_H + 8), 1, 0)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 14
		name.TextColor3 = TEXT
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = displayName(recipe.result)
		name.Parent = row

		row.MouseButton1Click:Connect(function()
			selectedRecipe = recipe.id
			styleRecipeRows()
			refreshDetail()
		end)

		listButtons[recipe.id] = row
	end

	refreshDetail()
end

local backpackRef: GuiObject? = nil

local function layoutPanels(height: number)
	catRail.Size = UDim2.fromOffset(CAT_W, height)
	listFrame.Size = UDim2.fromOffset(LIST_W, height)
	detailFrame.Size = UDim2.fromOffset(DETAIL_W, height)
end

local function dockBesideBackpack()
	local pack = backpackRef
	local width = CAT_W + 8 + LIST_W + 8 + DETAIL_W
	if not pack then
		craftRoot.AnchorPoint = Vector2.new(1, 0.5)
		craftRoot.Position = UDim2.new(1, -360, 0.5, -20)
		craftRoot.Size = UDim2.fromOffset(width, PANEL_H)
		layoutPanels(PANEL_H)
		return
	end
	-- Привязка к левому краю инвентаря (Absolute* — экранные координаты с IgnoreGuiInset).
	local gap = 16
	local height = math.max(PANEL_H, pack.AbsoluteSize.Y)
	craftRoot.AnchorPoint = Vector2.new(1, 0)
	craftRoot.Position = UDim2.fromOffset(pack.AbsolutePosition.X - gap, pack.AbsolutePosition.Y)
	craftRoot.Size = UDim2.fromOffset(width, height)
	layoutPanels(height)
end

local function setCraftVisible(visible: boolean)
	craftRoot.Visible = visible
	if visible then
		dockBesideBackpack()
		rebuildList()
	end
end

-- UI shell
local gui = Instance.new("ScreenGui")
gui.Name = "CraftGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 99
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = true
gui.Parent = playerGui

craftRoot = Instance.new("Frame")
craftRoot.Name = "CraftRoot"
craftRoot.Visible = false
craftRoot.AnchorPoint = Vector2.new(1, 0.5)
craftRoot.Position = UDim2.new(1, -360, 0.5, -20)
craftRoot.Size = UDim2.fromOffset(CAT_W + 8 + LIST_W + 8 + DETAIL_W, PANEL_H)
craftRoot.BackgroundTransparency = 1
craftRoot.Parent = gui

catRail = Instance.new("Frame")
catRail.Name = "Categories"
catRail.BackgroundColor3 = PAPER_DARK
catRail.BorderSizePixel = 0
catRail.Size = UDim2.fromOffset(CAT_W, PANEL_H)
catRail.Parent = craftRoot
makeCorner(catRail, 10)
makeStroke(catRail, PAPER_EDGE, 2)

local catLayout = Instance.new("UIListLayout")
catLayout.FillDirection = Enum.FillDirection.Vertical
catLayout.Padding = UDim.new(0, 6)
catLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
catLayout.SortOrder = Enum.SortOrder.LayoutOrder
catLayout.Parent = catRail

local catPad = Instance.new("UIPadding")
catPad.PaddingTop = UDim.new(0, 8)
catPad.Parent = catRail

listFrame = Instance.new("Frame")
listFrame.Name = "RecipeList"
listFrame.BackgroundColor3 = PAPER_DARK
listFrame.BorderSizePixel = 0
listFrame.Position = UDim2.fromOffset(CAT_W + 8, 0)
listFrame.Size = UDim2.fromOffset(LIST_W, PANEL_H)
listFrame.Parent = craftRoot
makeCorner(listFrame, 10)
makeStroke(listFrame, PAPER_EDGE, 2)

detailFrame = Instance.new("Frame")
detailFrame.Name = "Detail"
detailFrame.BackgroundColor3 = PAPER_DARK
detailFrame.BorderSizePixel = 0
detailFrame.Position = UDim2.fromOffset(CAT_W + 8 + LIST_W + 8, 0)
detailFrame.Size = UDim2.fromOffset(DETAIL_W, PANEL_H)
detailFrame.Visible = false
detailFrame.Parent = craftRoot
makeCorner(detailFrame, 10)
makeStroke(detailFrame, PAPER_EDGE, 2)

local function buildCategories()
	for _, child in ipairs(catRail:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	table.clear(categoryButtons)

	local cats = if CraftCatalog then CraftCatalog.GetCategories() else {
		{ id = "Weapons", display_name = "Weapons", icon = "⚔" },
	}

	for i, cat in ipairs(cats) do
		local btn = Instance.new("TextButton")
		btn.Name = cat.id
		btn.LayoutOrder = i
		btn.Size = UDim2.fromOffset(40, 40)
		btn.BackgroundColor3 = if cat.id == selectedCategory then SELECTED else PAPER
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 20
		btn.Text = cat.icon or "⚔"
		btn.TextColor3 = TEXT
		btn.Parent = catRail
		makeCorner(btn, 6)
		makeStroke(btn, PAPER_EDGE, 2)

		btn.MouseButton1Click:Connect(function()
			selectedCategory = cat.id
			selectedRecipe = nil
			styleCategory(cat.id)
			rebuildList()
		end)

		categoryButtons[cat.id] = btn
	end
end

task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 30)
	if shared then
		local craftInst = shared:FindFirstChild("CraftCatalog")
		local catalogInst = shared:FindFirstChild("ItemCatalog")
		local iconInst = shared:FindFirstChild("ItemIcon")
		if craftInst and craftInst:IsA("ModuleScript") then
			local ok, result = pcall(require, craftInst)
			if ok then
				CraftCatalog = result
			else
				warn("Craft: CraftCatalog require failed:", result)
			end
		end
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
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	if remotes then
		local craft = remotes:WaitForChild("CraftItem", 10)
		if craft and craft:IsA("RemoteEvent") then
			craftRemote = craft
		end
	end

	buildCategories()

	local function hookInv(folder: Folder)
		local function sync()
			recountFromInvState(folder)
			if craftRoot.Visible then
				refreshDetail()
			end
		end
		local function hookValue(child: Instance)
			if child:IsA("StringValue") then
				child.Changed:Connect(sync)
				child:GetAttributeChangedSignal(ATTR_COUNT):Connect(sync)
			end
		end
		folder.ChildAdded:Connect(function(child)
			hookValue(child)
			task.defer(sync)
		end)
		folder.ChildRemoved:Connect(function()
			task.defer(sync)
		end)
		for _, child in ipairs(folder:GetChildren()) do
			hookValue(child)
		end
		sync()
	end

	local invState = player:FindFirstChild("InvState")
	if not (invState and invState:IsA("Folder")) then
		invState = player:WaitForChild("InvState", 60)
	end
	if invState and invState:IsA("Folder") then
		hookInv(invState)
	end

	local invGui = playerGui:WaitForChild("InventoryGui", 60)
	if invGui then
		local backpack = invGui:WaitForChild("Backpack", 30)
		if backpack and backpack:IsA("GuiObject") then
			backpackRef = backpack
			backpack:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				if craftRoot.Visible then
					dockBesideBackpack()
				end
			end)
			backpack:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				if craftRoot.Visible then
					dockBesideBackpack()
				end
			end)
			setCraftVisible(backpack.Visible)
			backpack:GetPropertyChangedSignal("Visible"):Connect(function()
				setCraftVisible(backpack.Visible)
			end)
		end
	end
end)

print("Craft: UI готов")
