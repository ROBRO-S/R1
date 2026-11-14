--!strict
-- Иконка предмета: rbxassetid из конфига или ViewportFrame по ассету.

local ItemIcon = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(script.Parent:WaitForChild("ItemCatalog") :: ModuleScript)

local function clearChildren(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") or child:IsA("ViewportFrame") or child:IsA("WorldModel") then
			child:Destroy()
		end
	end
end

local function assetsFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("assets")
end

local function prepareClone(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
end

local function makeStickPart(): BasePart
	-- Cylinder в Roblox вытянут по X: Size = (длина, диаметр, диаметр).
	local stick = Instance.new("Part")
	stick.Name = "StickPreview"
	stick.Size = Vector3.new(1.35, 0.42, 0.42)
	stick.Color = Color3.fromRGB(120, 85, 50)
	stick.Material = Enum.Material.Wood
	stick.Shape = Enum.PartType.Cylinder
	-- Чуть повернуть к камере, чтобы не выглядела точкой.
	stick.CFrame = CFrame.Angles(math.rad(25), math.rad(35), math.rad(55))
	prepareClone(stick)
	return stick
end

local function makeRockPart(): BasePart
	local assets = assetsFolder()
	local template = assets and assets:FindFirstChild("SmallRock")
	if template and template:IsA("BasePart") then
		local clone = template:Clone()
		prepareClone(clone)
		clone.Transparency = 0
		return clone
	end
	local rock = Instance.new("Part")
	rock.Name = "RockPreview"
	rock.Size = Vector3.new(1.4, 1.0, 1.6)
	rock.Color = Color3.fromRGB(90, 90, 95)
	rock.Material = Enum.Material.Slate
	prepareClone(rock)
	return rock
end

local function makeFistPart(): BasePart
	local assets = assetsFolder()
	local template = assets and assets:FindFirstChild("fistweapon_A")
	if template and template:IsA("BasePart") then
		local clone = template:Clone()
		prepareClone(clone)
		return clone
	end
	local part = Instance.new("Part")
	part.Name = "FistPreview"
	part.Size = Vector3.new(1, 0.45, 1)
	part.Color = Color3.fromRGB(40, 40, 45)
	part.Material = Enum.Material.Metal
	prepareClone(part)
	return part
end

local function makeToolPart(assetName: string, previewName: string): BasePart
	local assets = assetsFolder()
	local template = assets and assets:FindFirstChild(assetName)
	if template and template:IsA("BasePart") then
		local clone = template:Clone()
		prepareClone(clone)
		clone.Transparency = 0
		return clone
	end
	if template and template:IsA("Model") then
		local src = template.PrimaryPart or template:FindFirstChildWhichIsA("BasePart", true)
		if src then
			local clone = src:Clone()
			prepareClone(clone)
			clone.Transparency = 0
			return clone
		end
	end
	local part = Instance.new("Part")
	part.Name = previewName
	part.Size = Vector3.new(0.35, 2.2, 0.7)
	part.Color = Color3.fromRGB(120, 90, 55)
	part.Material = Enum.Material.Wood
	prepareClone(part)
	return part
end

local function previewPartFor(itemId: string): BasePart?
	if itemId == "Stick" then
		return makeStickPart()
	elseif itemId == "SmallRock" then
		return makeRockPart()
	elseif itemId == "FistWeapon" then
		return makeFistPart()
	elseif itemId == "Axe" then
		return makeToolPart("Axe", "AxePreview")
	elseif itemId == "Pickaxe" then
		return makeToolPart("Pickaxe", "PickaxePreview")
	end
	return nil
end

local function fillViewport(parent: GuiObject, itemId: string)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "IconViewport"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.Parent = parent

	local world = Instance.new("WorldModel")
	world.Parent = viewport

	local part = previewPartFor(itemId)
	if not part then
		viewport:Destroy()
		return
	end
	part.Parent = world

	local cam = Instance.new("Camera")
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	-- Камера по AABB модели (с учётом поворота), ближе — слот заполняется.
	local cf, size = part.CFrame, part.Size
	local corners = {
		Vector3.new(-1, -1, -1),
		Vector3.new(-1, -1, 1),
		Vector3.new(-1, 1, -1),
		Vector3.new(-1, 1, 1),
		Vector3.new(1, -1, -1),
		Vector3.new(1, -1, 1),
		Vector3.new(1, 1, -1),
		Vector3.new(1, 1, 1),
	}
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, c in ipairs(corners) do
		local p = cf:PointToWorldSpace(Vector3.new(c.X * size.X * 0.5, c.Y * size.Y * 0.5, c.Z * size.Z * 0.5))
		minV = Vector3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z))
		maxV = Vector3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z))
	end
	local center = (minV + maxV) * 0.5
	local extent = (maxV - minV).Magnitude
	local zoom = if itemId == "Stick" then 0.85 else 1.15
	local distance = math.max(extent * zoom, 1.2)
	cam.CFrame = CFrame.new(center + Vector3.new(distance * 0.55, distance * 0.35, distance * 0.55), center)
end

function ItemIcon.Apply(parent: GuiObject, itemId: string?)
	clearChildren(parent)
	if not itemId then
		return
	end

	local icon = ItemCatalog.Icon(itemId)
	if icon ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "IconImage"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = icon
		image.Parent = parent
		return
	end

	fillViewport(parent, itemId)
end

return ItemIcon
