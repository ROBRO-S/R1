--!strict
-- Мировые подбираемые: Stick / SmallRock (+ дроп любых ItemId).
-- ProximityPrompt (E). Сессия — InventoryService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemsConfig = require(ServerScriptService:WaitForChild("ItemsConfig"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))

local ATTR_ITEM = "ItemId"
local ATTR_WORLD_LOOT = "WorldLoot"
local PROMPT_NAME = "PickupPrompt"
local MAX_PICK_DIST = 12
local DROP_FORWARD = 4

local PICKABLE_NAMES: { [string]: string } = {
	Stick = "Stick",
	SmallRock = "SmallRock",
	FistWeapon = "FistWeapon",
	Axe = "Axe",
	Pickaxe = "Pickaxe",
}

local stickColor = Color3.fromRGB(120, 85, 50)

local setupLoot: (Instance, string?) -> ()

local function assetsFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("assets")
end

local function findBasePart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function anchorAll(inst: Instance)
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.CanTouch = true
		inst.CanQuery = true
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = true
			d.CanQuery = true
		end
	end
end

local function yawOnNormal(normal: Vector3, yaw: number): CFrame
	local up = normal.Unit
	local axis = Vector3.yAxis
	if math.abs(up:Dot(axis)) > 0.98 then
		axis = Vector3.xAxis
	end
	local right = up:Cross(axis)
	if right.Magnitude < 1e-4 then
		right = up:Cross(Vector3.zAxis)
	end
	right = right.Unit
	local forward = right:Cross(up).Unit
	return CFrame.fromMatrix(Vector3.zero, right, up, -forward) * CFrame.Angles(0, yaw, 0)
end

local function groundHit(position: Vector3): (Vector3, Vector3)
	local origin = position + Vector3.new(0, 8, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(origin, Vector3.new(0, -40, 0), params)
	if hit then
		return hit.Position, hit.Normal
	end
	return position, Vector3.yAxis
end

local function seatOnGround(part: BasePart, position: Vector3, rot: CFrame)
	local ground, _normal = groundHit(position)
	part.CFrame = CFrame.new(ground) * rot
	local cf = part.CFrame
	local size = part.Size
	local minY = math.huge
	for _, sx in { -0.5, 0.5 } do
		for _, sy in { -0.5, 0.5 } do
			for _, sz in { -0.5, 0.5 } do
				local p = cf:PointToWorldSpace(Vector3.new(size.X * sx, size.Y * sy, size.Z * sz))
				minY = math.min(minY, p.Y)
			end
		end
	end
	part.CFrame = part.CFrame + Vector3.new(0, ground.Y - minY, 0)
end

local function makeStickAt(position: Vector3): BasePart
	-- Cylinder вдоль X: (длина, диаметр, диаметр).
	local stick = Instance.new("Part")
	stick.Name = "Stick"
	stick.Size = Vector3.new(2.2, 0.35, 0.35)
	stick.Color = stickColor
	stick.Shape = Enum.PartType.Cylinder
	stick.CanCollide = false
	stick.Material = Enum.Material.Wood
	local yaw = math.random() * math.pi * 2
	stick.Parent = Workspace
	seatOnGround(stick, position, CFrame.Angles(0, yaw, 0))
	anchorAll(stick)
	return stick
end

local function makeSmallRockAt(position: Vector3): Instance
	local assets = assetsFolder()
	local template = assets and assets:FindFirstChild("SmallRock")
	local ground, normal = groundHit(position)
	local rot = yawOnNormal(normal, math.random() * math.pi * 2)
	if template and template:IsA("BasePart") then
		local part = template:Clone()
		part.Name = "SmallRock"
		part.Transparency = 0
		part.CanCollide = false
		part.Parent = Workspace
		seatOnGround(part, ground, rot)
		anchorAll(part)
		return part
	end
	local rock = Instance.new("Part")
	rock.Name = "SmallRock"
	rock.Size = Vector3.new(1.4, 1.0, 1.6)
	rock.Color = Color3.fromRGB(90, 90, 95)
	rock.Material = Enum.Material.Slate
	rock.CanCollide = false
	rock.Parent = Workspace
	seatOnGround(rock, ground, rot)
	anchorAll(rock)
	return rock
end

local function makeFistDropAt(position: Vector3): Instance
	-- Временный вид на земле; позже заменится моделькой игрока.
	local assets = assetsFolder()
	local template = assets and assets:FindFirstChild("fistweapon_A")
	local yaw = math.random() * math.pi * 2
	if template and template:IsA("BasePart") then
		local part = template:Clone()
		part.Name = "FistWeapon"
		part.CanCollide = false
		part.Massless = true
		part.Parent = Workspace
		seatOnGround(part, position, CFrame.Angles(0, yaw, math.rad(15)))
		anchorAll(part)
		return part
	end
	local part = Instance.new("Part")
	part.Name = "FistWeapon"
	part.Size = Vector3.new(1.2, 0.5, 1.2)
	part.Color = Color3.fromRGB(40, 40, 45)
	part.Material = Enum.Material.Metal
	part.CanCollide = false
	part.Parent = Workspace
	seatOnGround(part, position, CFrame.Angles(0, yaw, 0))
	anchorAll(part)
	return part
end

local function makeToolDropAt(itemId: string, assetName: string, position: Vector3): Instance
	local assets = assetsFolder()
	local template = assets and assets:FindFirstChild(assetName)
	local yaw = math.random() * math.pi * 2
	local rot = CFrame.Angles(0, yaw, math.rad(90))
	if template and template:IsA("BasePart") then
		local part = template:Clone()
		part.Name = itemId
		part.Transparency = 0
		part.CanCollide = false
		part.Massless = true
		part.Parent = Workspace
		seatOnGround(part, position, rot)
		anchorAll(part)
		return part
	end
	if template and template:IsA("Model") then
		local model = template:Clone()
		model.Name = itemId
		local host = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		model.Parent = Workspace
		if host then
			seatOnGround(host, position, rot)
		end
		anchorAll(model)
		return model
	end
	local part = Instance.new("Part")
	part.Name = itemId
	part.Size = Vector3.new(0.35, 2.2, 0.7)
	part.Color = Color3.fromRGB(120, 90, 55)
	part.Material = Enum.Material.Wood
	part.CanCollide = false
	part.Parent = Workspace
	seatOnGround(part, position, rot)
	anchorAll(part)
	return part
end

local function spawnWorldItem(itemId: string, position: Vector3): Instance?
	if itemId == "Stick" then
		return makeStickAt(position)
	elseif itemId == "SmallRock" then
		return makeSmallRockAt(position)
	elseif itemId == "FistWeapon" then
		return makeFistDropAt(position)
	elseif itemId == "Axe" then
		return makeToolDropAt("Axe", "Axe", position)
	elseif itemId == "Pickaxe" then
		return makeToolDropAt("Pickaxe", "Pickaxe", position)
	end
	local part = Instance.new("Part")
	part.Name = ItemsConfig.WorldName(itemId)
	part.Size = Vector3.new(1, 1, 1)
	part.Color = Color3.fromRGB(180, 160, 120)
	part.CanCollide = false
	part.Parent = Workspace
	seatOnGround(part, position, CFrame.Angles(0, math.random() * math.pi * 2, 0))
	anchorAll(part)
	return part
end

setupLoot = function(inst: Instance, itemId: string?)
	if inst:GetAttribute(ATTR_WORLD_LOOT) == true then
		return
	end

	local resolved = itemId
	if not resolved then
		local attr = inst:GetAttribute(ATTR_ITEM)
		if typeof(attr) == "string" and attr ~= "" then
			resolved = attr
		else
			resolved = PICKABLE_NAMES[inst.Name]
		end
	end
	if not resolved or not ItemsConfig.IsKnown(resolved) then
		return
	end

	local host = findBasePart(inst)
	if not host then
		return
	end

	inst:SetAttribute(ATTR_ITEM, resolved)
	inst:SetAttribute(ATTR_WORLD_LOOT, true)
	host:SetAttribute(ATTR_ITEM, resolved)
	host:SetAttribute(ATTR_WORLD_LOOT, true)

	local existing = host:FindFirstChild(PROMPT_NAME)
	if existing then
		existing:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Pick up"
	prompt.ObjectText = ItemsConfig.DisplayName(resolved)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = MAX_PICK_DIST
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = host

	prompt.Triggered:Connect(function(player: Player)
		if not player or not player:IsA("Player") then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		if (root.Position - host.Position).Magnitude > MAX_PICK_DIST + 4 then
			return
		end
		if not inst.Parent then
			return
		end
		local id = inst:GetAttribute(ATTR_ITEM)
		if typeof(id) ~= "string" or not ItemsConfig.IsKnown(id) then
			return
		end
		local slot = InventoryService.AddItem(player, id)
		if not slot then
			return
		end
		inst:Destroy()
	end)
end

local function dropInFront(player: Player, itemId: string): boolean
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	local pos = root.Position + root.CFrame.LookVector * DROP_FORWARD
	local spawned = spawnWorldItem(itemId, pos)
	if not spawned then
		return false
	end
	setupLoot(spawned, itemId)
	return true
end

InventoryService.SetDropSpawner(dropInFront)

-- Серверный спавн лута (рубка MegaTree → Stick и т.п.).
local spawnBinder = Instance.new("BindableFunction")
spawnBinder.Name = "SpawnWorldLoot"
spawnBinder.Parent = ServerScriptService
spawnBinder.OnInvoke = function(itemId: any, position: any): boolean
	if typeof(itemId) ~= "string" or typeof(position) ~= "Vector3" then
		return false
	end
	if not ItemsConfig.IsKnown(itemId) then
		return false
	end
	local spawned = spawnWorldItem(itemId, position)
	if not spawned then
		return false
	end
	setupLoot(spawned, itemId)
	return true
end

local function trySetup(inst: Instance)
	if inst.Parent ~= Workspace then
		return
	end
	local itemId = PICKABLE_NAMES[inst.Name]
	if itemId then
		setupLoot(inst, itemId)
	end
end

for _, child in ipairs(Workspace:GetChildren()) do
	trySetup(child)
end

Workspace.ChildAdded:Connect(function(child)
	task.defer(trySetup, child)
end)

print("WorldLoot: готов (Stick / SmallRock / FistWeapon / Axe / Pickaxe / дроп)")
