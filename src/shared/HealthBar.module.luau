--!strict
-- Пиксельная шкала HP/Defence: овал + иконка + цифры + ghost-deplete (без чёрной обводки бара).

local TweenService = game:GetService("TweenService")

local HealthBar = {}

export type IconKind = "heart" | "shield" | "none"
export type PaletteKind = "health" | "defence"

export type CreateOptions = {
	Width: number?,
	Height: number?,
	Icon: IconKind?,
	Palette: PaletteKind?,
	ShowLabel: boolean?,
	ZIndex: number?,
	LayoutOrder: number?,
}

export type HealthBarHandle = {
	Root: Frame,
	SetHealth: (current: number, maxHealth: number) -> (),
	Destroy: () -> (),
}

local TRACK = Color3.fromRGB(255, 255, 255)
local GHOST = Color3.fromRGB(255, 230, 200)
local TEXT = Color3.fromRGB(255, 255, 255)
local TEXT_STROKE = Color3.fromRGB(0, 0, 0)

local HEART_MAIN = Color3.fromRGB(220, 45, 55)
local HEART_SHADE = Color3.fromRGB(150, 20, 35)
local HEART_SHINE = Color3.fromRGB(255, 255, 255)
local HEART_OUTLINE = Color3.fromRGB(20, 20, 20)

local SHIELD_MAIN = Color3.fromRGB(90, 160, 230)
local SHIELD_SHADE = Color3.fromRGB(40, 90, 170)
local SHIELD_SHINE = Color3.fromRGB(210, 235, 255)
local SHIELD_OUTLINE = Color3.fromRGB(20, 20, 20)

local DEPLETE_TIME = 0.45

local function healthPair(ratio: number): (Color3, Color3)
	if ratio > 0.7 then
		return Color3.fromRGB(90, 215, 75), Color3.fromRGB(45, 155, 45)
	elseif ratio > 0.4 then
		return Color3.fromRGB(255, 175, 55), Color3.fromRGB(215, 115, 25)
	elseif ratio > 0.2 then
		return Color3.fromRGB(255, 105, 65), Color3.fromRGB(200, 55, 35)
	else
		return Color3.fromRGB(175, 35, 55), Color3.fromRGB(115, 18, 35)
	end
end

local function defencePair(ratio: number): (Color3, Color3)
	if ratio > 0.7 then
		return Color3.fromRGB(110, 190, 255), Color3.fromRGB(50, 120, 210)
	elseif ratio > 0.4 then
		return Color3.fromRGB(90, 160, 235), Color3.fromRGB(40, 95, 180)
	elseif ratio > 0.2 then
		return Color3.fromRGB(70, 130, 210), Color3.fromRGB(35, 75, 150)
	else
		return Color3.fromRGB(55, 90, 160), Color3.fromRGB(30, 55, 110)
	end
end

local function makeCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function paintCells(
	parent: Frame,
	cells: { { number } },
	size: number,
	z: number,
	main: Color3,
	shade: Color3,
	shine: Color3,
	outline: Color3
)
	local cols = #cells[1]
	local rows = #cells
	local cell = math.max(1, math.floor(size / math.max(cols, rows)))
	local ox = math.floor((size - cell * cols) / 2)
	local oy = math.floor((size - cell * rows) / 2)

	local outlineFrame = Instance.new("Frame")
	outlineFrame.Name = "IconOutline"
	outlineFrame.BackgroundTransparency = 1
	outlineFrame.Size = UDim2.fromOffset(size, size)
	outlineFrame.Position = UDim2.fromOffset(0, 0)
	outlineFrame.ZIndex = z - 1
	outlineFrame.Parent = parent

	for row = 1, rows do
		for col = 1, cols do
			if cells[row][col] == 1 then
				for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
					local nr, nc = row + d[2], col + d[1]
					local outside = nr < 1 or nr > rows or nc < 1 or nc > cols or cells[nr][nc] == 0
					if outside then
						local edge = Instance.new("Frame")
						edge.BorderSizePixel = 0
						edge.BackgroundColor3 = outline
						edge.Size = UDim2.fromOffset(cell, cell)
						edge.Position = UDim2.fromOffset(
							ox + (col - 1) * cell + d[1] * cell,
							oy + (row - 1) * cell + d[2] * cell
						)
						edge.ZIndex = z - 1
						edge.Parent = outlineFrame
					end
				end
			end
		end
	end

	for row = 1, rows do
		for col = 1, cols do
			if cells[row][col] == 1 then
				local px = Instance.new("Frame")
				px.Name = "P"
				px.BorderSizePixel = 0
				px.Size = UDim2.fromOffset(cell, cell)
				px.Position = UDim2.fromOffset(ox + (col - 1) * cell, oy + (row - 1) * cell)
				px.ZIndex = z
				if row >= rows - 1 or (row >= 4 and col >= 4) then
					px.BackgroundColor3 = shade
				elseif row <= 2 and col <= 3 then
					px.BackgroundColor3 = if (row == 1 and col == 2) or (row == 2 and col == 2)
						then shine
						else main
				else
					px.BackgroundColor3 = main
				end
				px.Parent = parent
			end
		end
	end
end

local function buildHeart(parent: Frame, size: number, z: number)
	local heart = Instance.new("Frame")
	heart.Name = "Heart"
	heart.BackgroundTransparency = 1
	heart.Size = UDim2.fromOffset(size, size)
	heart.Position = UDim2.fromOffset(0, math.floor((parent.Size.Y.Offset - size) / 2))
	heart.ZIndex = z
	heart.Parent = parent

	local cells: { { number } } = {
		{ 0, 0, 1, 1, 0, 1, 1 },
		{ 0, 1, 1, 1, 1, 1, 1 },
		{ 1, 1, 1, 1, 1, 1, 1 },
		{ 0, 1, 1, 1, 1, 1, 0 },
		{ 0, 0, 1, 1, 1, 0, 0 },
		{ 0, 0, 0, 1, 0, 0, 0 },
	}
	paintCells(heart, cells, size, z, HEART_MAIN, HEART_SHADE, HEART_SHINE, HEART_OUTLINE)
	return heart
end

local function buildShield(parent: Frame, size: number, z: number)
	local shield = Instance.new("Frame")
	shield.Name = "Shield"
	shield.BackgroundTransparency = 1
	shield.Size = UDim2.fromOffset(size, size)
	shield.Position = UDim2.fromOffset(0, math.floor((parent.Size.Y.Offset - size) / 2))
	shield.ZIndex = z
	shield.Parent = parent

	local cells: { { number } } = {
		{ 0, 1, 1, 1, 1, 1, 0 },
		{ 1, 1, 1, 1, 1, 1, 1 },
		{ 1, 1, 1, 1, 1, 1, 1 },
		{ 1, 1, 1, 1, 1, 1, 1 },
		{ 0, 1, 1, 1, 1, 1, 0 },
		{ 0, 0, 1, 1, 1, 0, 0 },
		{ 0, 0, 0, 1, 0, 0, 0 },
	}
	paintCells(shield, cells, size, z, SHIELD_MAIN, SHIELD_SHADE, SHIELD_SHINE, SHIELD_OUTLINE)
	return shield
end

function HealthBar.Create(parent: Instance, opts: CreateOptions?): HealthBarHandle
	local width = (opts and opts.Width) or 100
	local height = (opts and opts.Height) or 13
	local iconKind: IconKind = if opts and opts.Icon then opts.Icon else "heart"
	local palette: PaletteKind = if opts and opts.Palette then opts.Palette else "health"
	local showLabel = if opts and opts.ShowLabel ~= nil then opts.ShowLabel else true
	local z = (opts and opts.ZIndex) or 10
	local iconSize = height + 4
	local barLeft = if iconKind ~= "none" then math.floor(iconSize * 0.55) else 0
	local barWidth = math.max(8, width - barLeft)
	local radius = math.max(1, math.floor(height / 2))

	local root = Instance.new("Frame")
	root.Name = if palette == "defence" then "DefenceBar" else "HealthBar"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(width, math.max(height, iconSize))
	root.ZIndex = z
	if opts and opts.LayoutOrder then
		root.LayoutOrder = opts.LayoutOrder
	end
	root.Parent = parent

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = TRACK
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, barLeft, 0.5, 0)
	track.Size = UDim2.fromOffset(barWidth, height)
	track.ZIndex = z
	track.ClipsDescendants = true
	track.Parent = root
	makeCorner(track, radius)

	local ghost = Instance.new("Frame")
	ghost.Name = "Ghost"
	ghost.BackgroundColor3 = GHOST
	ghost.BorderSizePixel = 0
	ghost.Size = UDim2.fromScale(1, 1)
	ghost.ZIndex = z + 1
	ghost.Parent = track
	makeCorner(ghost, radius)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(90, 215, 75)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = z + 2
	fill.ClipsDescendants = true
	fill.Parent = track
	makeCorner(fill, radius)

	local fillTop = Instance.new("Frame")
	fillTop.Name = "FillTop"
	fillTop.BackgroundColor3 = Color3.fromRGB(90, 215, 75)
	fillTop.BorderSizePixel = 0
	fillTop.Size = UDim2.new(1, 0, 0.5, 0)
	fillTop.ZIndex = z + 3
	fillTop.Parent = fill

	local fillBot = Instance.new("Frame")
	fillBot.Name = "FillBot"
	fillBot.BackgroundColor3 = Color3.fromRGB(45, 155, 45)
	fillBot.BorderSizePixel = 0
	fillBot.Position = UDim2.new(0, 0, 0.5, 0)
	fillBot.Size = UDim2.new(1, 0, 0.5, 0)
	fillBot.ZIndex = z + 3
	fillBot.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = math.clamp(height - 2, 8, 14)
	label.TextColor3 = TEXT
	label.TextStrokeColor3 = TEXT_STROKE
	label.TextStrokeTransparency = 0.15
	label.Text = "0/0"
	label.Visible = showLabel
	label.ZIndex = z + 5
	label.Parent = track

	if iconKind == "heart" then
		buildHeart(root, iconSize, z + 6)
	elseif iconKind == "shield" then
		buildShield(root, iconSize, z + 6)
	end

	local ghostTween: Tween? = nil
	local displayRatio = 1

	local function pairFor(ratio: number): (Color3, Color3)
		if palette == "defence" then
			return defencePair(ratio)
		end
		return healthPair(ratio)
	end

	local function applyFill(ratio: number)
		local r = math.clamp(ratio, 0, 1)
		fill.Size = UDim2.new(r, 0, 1, 0)
		local top, bot = pairFor(r)
		fill.BackgroundColor3 = top
		fillTop.BackgroundColor3 = top
		fillBot.BackgroundColor3 = bot
		displayRatio = r
	end

	local function setHealth(current: number, maxHealth: number)
		local maxH = math.max(1, maxHealth)
		local cur = math.clamp(current, 0, maxH)
		local newRatio = cur / maxH
		local oldRatio = displayRatio

		label.Text = string.format("%d/%d", math.floor(cur + 0.5), math.floor(maxH + 0.5))

		if newRatio < oldRatio - 0.001 then
			if ghostTween then
				ghostTween:Cancel()
				ghostTween = nil
			end
			ghost.Size = UDim2.new(oldRatio, 0, 1, 0)
			ghost.BackgroundColor3 = GHOST
			applyFill(newRatio)
			local tw = TweenService:Create(
				ghost,
				TweenInfo.new(DEPLETE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.new(newRatio, 0, 1, 0) }
			)
			ghostTween = tw
			tw:Play()
		else
			if ghostTween then
				ghostTween:Cancel()
				ghostTween = nil
			end
			ghost.Size = UDim2.new(newRatio, 0, 1, 0)
			applyFill(newRatio)
		end
	end

	applyFill(1)

	return {
		Root = root,
		SetHealth = setHealth,
		Destroy = function()
			if ghostTween then
				ghostTween:Cancel()
			end
			root:Destroy()
		end,
	}
end

return HealthBar
