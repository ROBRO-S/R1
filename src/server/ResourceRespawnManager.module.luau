--!strict
-- Общая очередь респавна ресурсов: 1 объект за тик, без спайков FPS.

local ResourceRespawnManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

ResourceRespawnManager.MEGA_TREE_RESPAWN_TIME = 90
ResourceRespawnManager.MEDIUM_ROCK_RESPAWN_TIME = 60
ResourceRespawnManager.BIG_TREE_RESPAWN_TIME = 60
ResourceRespawnManager.STICK_RESPAWN_TIME = 30

local TICK_INTERVAL = 2
local PLAYER_CLEAR_RADIUS = 6
local EMERGE_STUDS = 3
local EMERGE_TIME = 0.8
local FREE_SPOT_ATTEMPTS = 24
local FREE_SPOT_RADIUS = 80
local DEFAULT_MEGA_HP = 75
local DEFAULT_ROCK_HP = 60
local DEFAULT_MEGA_RADIUS = 9
local DEFAULT_THIN_RADIUS = 2.5
local DEFAULT_BOULDER_RADIUS = 3.5
local DEFAULT_EXCLUSION = 4
local DEFAULT_LIFT = -2
local DEFAULT_THIN_LIFT = 0
local DEFAULT_SCALE = 1
local DEFAULT_RAY_START = 200
local DEFAULT_RAY_DEPTH = 300
local DEFAULT_WATER_Y = 6
local DEFAULT_BOULDER_COLOR = Color3.fromRGB(80, 80, 80)

type QueueEntry = {
	assetName: string,
	originCFrame: CFrame,
	readyAt: number,
}

local queue: { QueueEntry } = {}
local started = false

local BLOCKING_NAMES: { [string]: number } = {
	MegaTree = 18,
	BigTree = 4,
	thin_tree = 4,
	MediumRock = 5,
	SmallRock = 2,
	Stick = 1.5,
}

local function configProps(): (any, any)
	local ok, cfg = pcall(function()
		local ConfigLoader = require(ServerScriptService:WaitForChild("ConfigLoader"))
		return ConfigLoader.Get()
	end)
	if ok and cfg then
		return cfg, cfg.props or {}
	end
	return nil, {}
end

local function megaTreeMaxHp(): number
	local _, props = configProps()
	local hp = props.mega_tree_hp
	if typeof(hp) == "number" and hp >= 1 then
		return hp
	end
	return DEFAULT_MEGA_HP
end

local function mediumRockMaxHp(): number
	local _, props = configProps()
	local hp = props.medium_rock_hp
	if typeof(hp) == "number" and hp >= 1 then
		return hp
	end
	return DEFAULT_ROCK_HP
end

local function colorFrom(raw: any, fallback: Color3): Color3
	if type(raw) == "table" then
		local r = tonumber(raw[1]) or 80
		local g = tonumber(raw[2]) or 80
		local b = tonumber(raw[3]) or 80
		return Color3.fromRGB(r, g, b)
	end
	return fallback
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function groundHit(x: number, z: number): RaycastResult?
	local _, props = configProps()
	local startY = if typeof(props.ray_start_y) == "number" then props.ray_start_y else DEFAULT_RAY_START
	local depth = if typeof(props.ray_depth) == "number" then props.ray_depth else DEFAULT_RAY_DEPTH
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.IgnoreWater = false
	return Workspace:Raycast(Vector3.new(x, startY, z), Vector3.new(0, -depth, 0), params)
end

local function waterPlane(): number
	local cfg = select(1, configProps())
	if cfg and typeof((cfg :: any).water_world_y) == "number" then
		return (cfg :: any).water_world_y
	end
	return DEFAULT_WATER_Y
end

local function playersNear(pos: Vector3, radius: number): boolean
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				if flatDist(root.Position, pos) <= radius then
					return true
				end
			end
		end
	end
	return false
end

local function propFootprint(name: string): number
	return BLOCKING_NAMES[name] or 0
end

local function spotClearOfProps(pos: Vector3, needRadius: number): boolean
	for _, child in ipairs(Workspace:GetChildren()) do
		local otherR = 0
		if child:IsA("Model") or child:IsA("BasePart") then
			otherR = propFootprint(child.Name)
		end
		if otherR > 0 then
			local otherPos: Vector3
			if child:IsA("Model") then
				otherPos = child:GetPivot().Position
			else
				otherPos = (child :: BasePart).Position
			end
			if flatDist(pos, otherPos) < needRadius + otherR then
				return false
			end
		end
	end
	return true
end

local function pickSpawnXZ(origin: CFrame, needRadius: number): (number, number, boolean)
	local ox = origin.Position.X
	local oz = origin.Position.Z
	local cfg = select(1, configProps())
	local searchR = FREE_SPOT_RADIUS
	local exclusion = DEFAULT_EXCLUSION
	if cfg then
		local c = cfg :: any
		if typeof(c.spawn_search_radius) == "number" then
			searchR = math.max(c.spawn_search_radius, 20)
		end
		if typeof(c.exclusion_radius) == "number" then
			exclusion = c.exclusion_radius
		end
	end
	local claimR = needRadius + exclusion * 0.5
	local waterY = waterPlane()

	for _ = 1, FREE_SPOT_ATTEMPTS do
		local ang = math.random() * math.pi * 2
		local dist = 8 + math.random() * searchR
		local x = ox + math.cos(ang) * dist
		local z = oz + math.sin(ang) * dist
		local hit = groundHit(x, z)
		if hit
			and hit.Material ~= Enum.Material.Water
			and hit.Position.Y >= waterY - 0.05
			and hit.Normal.Y > 0.55
			and spotClearOfProps(Vector3.new(x, hit.Position.Y, z), claimR)
		then
			return x, z, true
		end
	end
	return ox, oz, false
end

local function opaqueParts(inst: Instance): { BasePart }
	local parts: { BasePart } = {}
	if inst:IsA("BasePart") and inst.Transparency < 1 then
		table.insert(parts, inst)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Soil" then
			table.insert(parts, d)
		end
	end
	return parts
end

local function minPartY(inst: Instance): number
	local minY = math.huge
	for _, part in ipairs(opaqueParts(inst)) do
		local hx = part.Size.X * 0.5
		local hy = part.Size.Y * 0.5
		local hz = part.Size.Z * 0.5
		local cf = part.CFrame
		for _, sx in { -hx, hx } do
			for _, sy in { -hy, hy } do
				for _, sz in { -hz, hz } do
					local p = cf:PointToWorldSpace(Vector3.new(sx, sy, sz))
					minY = math.min(minY, p.Y)
				end
			end
		end
	end
	return minY
end

local function anchorAll(inst: Instance)
	if inst:IsA("BasePart") then
		inst.Anchored = true
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

local function setCollide(inst: Instance, enabled: boolean)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Soil" then
			d.CanCollide = enabled
		end
	end
	if inst:IsA("BasePart") then
		inst.CanCollide = enabled
	end
end

local function prepareMega(model: Model)
	local _, props = configProps()
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Transparency = 0
			child.CanCollide = true
			child.CanQuery = true
		end
	end
	local soil = model:FindFirstChild("Soil")
	if not (soil and soil:IsA("BasePart")) then
		local soilSize = props.soil_size
		if typeof(soilSize) ~= "number" then
			soilSize = 1
		end
		local part = Instance.new("Part")
		part.Name = "Soil"
		part.Size = Vector3.new(soilSize, soilSize, soilSize)
		part.Transparency = if typeof(props.soil_transparency) == "number" then props.soil_transparency else 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Parent = model
		soil = part
	end
	model.PrimaryPart = soil :: BasePart
	model:SetAttribute("HP", megaTreeMaxHp())
	model:SetAttribute("AxeChopBusy", nil)
	model.Name = "MegaTree"
end

local function tweenEmerge(model: Model, finalPivot: CFrame)
	setCollide(model, false)
	local buried = finalPivot - Vector3.new(0, EMERGE_STUDS, 0)
	model:PivotTo(buried)
	local alpha = Instance.new("NumberValue")
	alpha.Value = 0
	TweenService:Create(
		alpha,
		TweenInfo.new(EMERGE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = 1 }
	):Play()
	local t0 = os.clock()
	while model.Parent and os.clock() - t0 < EMERGE_TIME + 0.35 do
		local t = alpha.Value
		model:PivotTo(buried:Lerp(finalPivot, t))
		if t >= 0.999 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	alpha:Destroy()
	if model.Parent then
		model:PivotTo(finalPivot)
		setCollide(model, true)
	end
end

local function spawnMegaTree(origin: CFrame): boolean
	local assets = ReplicatedStorage:FindFirstChild("assets")
	local template = assets and assets:FindFirstChild("MegaTree")
	if not (template and template:IsA("Model")) then
		warn("ResourceRespawnManager: нет assets.MegaTree")
		return false
	end

	local cfg, props = configProps()
	local needRadius = DEFAULT_MEGA_RADIUS
	if typeof(props.mega_tree_radius) == "number" then
		needRadius = props.mega_tree_radius
	elseif cfg and typeof(cfg.tree_base_radius) == "number" then
		needRadius = cfg.tree_base_radius
	end
	local scale = if typeof(props.mega_tree_scale) == "number" then props.mega_tree_scale else DEFAULT_SCALE
	local lift = if typeof(props.mega_tree_lift) == "number" then props.mega_tree_lift else DEFAULT_LIFT

	local x, z, foundFree = pickSpawnXZ(origin, needRadius)
	local hit = groundHit(x, z)
	local groundY = if hit then hit.Position.Y else origin.Position.Y
	local spawnPos = Vector3.new(x, groundY, z)

	if playersNear(spawnPos, PLAYER_CLEAR_RADIUS) then
		return false
	end

	local model = template:Clone()
	if not model.PrimaryPart then
		local part = model:FindFirstChildWhichIsA("BasePart", true)
		if part then
			model.PrimaryPart = part
		end
	end
	if scale ~= 1 then
		pcall(function()
			model:ScaleTo(scale)
		end)
	end
	prepareMega(model)

	local yaw = if foundFree then math.random() * math.pi * 2 else select(2, origin:ToOrientation())

	model.Parent = Workspace
	model:PivotTo(CFrame.new(x, groundY, z) * CFrame.Angles(0, yaw, 0))
	local minY = minPartY(model)
	if minY < math.huge then
		model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - minY, 0))
	end
	if lift ~= 0 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
	end
	anchorAll(model)

	local finalPivot = model:GetPivot()
	if playersNear(finalPivot.Position, PLAYER_CLEAR_RADIUS) then
		model:Destroy()
		return false
	end

	tweenEmerge(model, finalPivot)
	print(string.format(
		"ResourceRespawnManager: MegaTree респавн%s (%.0f, %.0f)",
		if foundFree then " на новом месте" else " на старом месте",
		x,
		z
	))
	return true
end

local function seatPartOnGround(part: BasePart, position: Vector3, rot: CFrame)
	local hit = groundHit(position.X, position.Z)
	local ground = if hit then hit.Position else position
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

local function tweenEmergePart(part: BasePart, finalCF: CFrame)
	part.CanCollide = false
	local buried = finalCF - Vector3.new(0, EMERGE_STUDS, 0)
	part.CFrame = buried
	local alpha = Instance.new("NumberValue")
	alpha.Value = 0
	TweenService:Create(
		alpha,
		TweenInfo.new(EMERGE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = 1 }
	):Play()
	local t0 = os.clock()
	while part.Parent and os.clock() - t0 < EMERGE_TIME + 0.35 do
		local t = alpha.Value
		part.CFrame = buried:Lerp(finalCF, t)
		if t >= 0.999 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	alpha:Destroy()
	if part.Parent then
		part.CFrame = finalCF
		part.CanCollide = true
		part.CanQuery = true
	end
end

local function prepareBigTree(model: Model)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			child.Transparency = 0
			child.CanCollide = true
			child.CanQuery = true
		end
	end
	if not model.PrimaryPart then
		local part = model:FindFirstChildWhichIsA("BasePart", true)
		if part then
			model.PrimaryPart = part
		end
	end
	model.Name = "BigTree"
	model:SetAttribute("GatherBusy", nil)
	model:SetAttribute("HoldGatherAttached", nil)
end

local function spawnBigTree(origin: CFrame): boolean
	local assets = ReplicatedStorage:FindFirstChild("assets")
	local template = assets and assets:FindFirstChild("BigTree")
	if not (template and template:IsA("Model")) then
		warn("ResourceRespawnManager: нет assets.BigTree")
		return false
	end

	local _, props = configProps()
	local needRadius = DEFAULT_THIN_RADIUS
	if typeof(props.thin_tree_radius) == "number" then
		needRadius = props.thin_tree_radius
	end
	local scale = if typeof(props.thin_tree_scale) == "number" then props.thin_tree_scale else DEFAULT_SCALE
	local lift = if typeof(props.thin_tree_lift) == "number" then props.thin_tree_lift else DEFAULT_THIN_LIFT

	local x, z, foundFree = pickSpawnXZ(origin, needRadius)
	local hit = groundHit(x, z)
	local groundY = if hit then hit.Position.Y else origin.Position.Y
	local spawnPos = Vector3.new(x, groundY, z)

	if playersNear(spawnPos, PLAYER_CLEAR_RADIUS) then
		return false
	end

	local model = template:Clone()
	if scale ~= 1 then
		pcall(function()
			model:ScaleTo(scale)
		end)
	end
	prepareBigTree(model)

	local yaw = if foundFree then math.random() * math.pi * 2 else select(2, origin:ToOrientation())

	model.Parent = Workspace
	model:PivotTo(CFrame.new(x, groundY, z) * CFrame.Angles(0, yaw, 0))
	local minY = minPartY(model)
	if minY < math.huge then
		model:PivotTo(model:GetPivot() + Vector3.new(0, groundY - minY, 0))
	end
	if lift ~= 0 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
	end
	anchorAll(model)

	local finalPivot = model:GetPivot()
	if playersNear(finalPivot.Position, PLAYER_CLEAR_RADIUS) then
		model:Destroy()
		return false
	end

	tweenEmerge(model, finalPivot)
	print(string.format(
		"ResourceRespawnManager: BigTree респавн%s (%.0f, %.0f)",
		if foundFree then " на новом месте" else " на старом месте",
		x,
		z
	))
	return true
end

local function spawnMediumRock(origin: CFrame): boolean
	local assets = ReplicatedStorage:FindFirstChild("assets")
	local template = assets and assets:FindFirstChild("MediumRock")
	if not (template and template:IsA("BasePart")) then
		warn("ResourceRespawnManager: нет assets.MediumRock")
		return false
	end

	local _, props = configProps()
	local needRadius = DEFAULT_BOULDER_RADIUS
	if typeof(props.boulder_radius) == "number" then
		needRadius = props.boulder_radius
	end
	local color = colorFrom(props.boulder_color, DEFAULT_BOULDER_COLOR)
	local transparency = if typeof(props.rock_transparency) == "number" then props.rock_transparency else 0

	local x, z, foundFree = pickSpawnXZ(origin, needRadius)
	local hit = groundHit(x, z)
	local groundY = if hit then hit.Position.Y else origin.Position.Y
	local spawnPos = Vector3.new(x, groundY, z)
	if playersNear(spawnPos, PLAYER_CLEAR_RADIUS) then
		return false
	end

	local part = template:Clone()
	part.Name = "MediumRock"
	part.Color = color
	part.Transparency = transparency
	part.CanCollide = true
	part.CanQuery = true
	part:SetAttribute("HP", mediumRockMaxHp())
	part:SetAttribute("PickaxeMineBusy", nil)
	part.Parent = Workspace

	local yaw = if foundFree then math.random() * math.pi * 2 else select(2, origin:ToOrientation())
	local tilt = if typeof(props.boulder_tilt) == "number" then props.boulder_tilt else 0
	local rotX = if tilt > 0 then math.rad(math.random(-tilt, tilt)) else 0
	seatPartOnGround(part, spawnPos, CFrame.Angles(rotX, yaw, 0))
	anchorAll(part)

	local finalCF = part.CFrame
	if playersNear(finalCF.Position, PLAYER_CLEAR_RADIUS) then
		part:Destroy()
		return false
	end

	tweenEmergePart(part, finalCF)
	print(string.format(
		"ResourceRespawnManager: MediumRock респавн%s (%.0f, %.0f)",
		if foundFree then " на новом месте" else " на старом месте",
		x,
		z
	))
	return true
end

local function trySpawn(entry: QueueEntry): boolean
	if entry.assetName == "MegaTree" then
		return spawnMegaTree(entry.originCFrame)
	end
	if entry.assetName == "BigTree" then
		return spawnBigTree(entry.originCFrame)
	end
	if entry.assetName == "MediumRock" then
		return spawnMediumRock(entry.originCFrame)
	end
	-- Позже: Stick / SmallRock.
	warn("ResourceRespawnManager: неизвестный ассет", entry.assetName)
	return true
end

local function processTick()
	local now = os.clock()
	for index, entry in ipairs(queue) do
		if entry.readyAt <= now then
			local ok = trySpawn(entry)
			if ok then
				table.remove(queue, index)
			end
			-- Не больше 1 спавна за тик (успех или отложен из‑за игрока).
			return
		end
	end
end

function ResourceRespawnManager.Enqueue(assetName: string, originCFrame: CFrame, delaySec: number)
	table.insert(queue, {
		assetName = assetName,
		originCFrame = originCFrame,
		readyAt = os.clock() + math.max(0, delaySec),
	})
	ResourceRespawnManager.Start()
end

function ResourceRespawnManager.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(TICK_INTERVAL)
			processTick()
		end
	end)
	print("ResourceRespawnManager: цикл респавна каждые", TICK_INTERVAL, "с")
end

return ResourceRespawnManager
