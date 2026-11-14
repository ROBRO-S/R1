--!strict
-- Pickaxe: удар правой. Урон манекену + добыча MediumRock.
-- Стартует из FistWeapon (Script PickaxeCombat.server.lua мог не подниматься в Studio).

local PickaxeCombat = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ItemsConfig = require(ServerScriptService:WaitForChild("ItemsConfig"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local ResourceRespawnManager = require(ServerScriptService:WaitForChild("ResourceRespawnManager"))
local ToolHints = require(ServerScriptService:WaitForChild("ToolHints"))

local TOOL_NAME = "Pickaxe"
local ITEM_ID = "Pickaxe"
local ATTR_ITEM = InventoryService.AttrItem()

local DEFAULT_COOLDOWN = 0.55
local DEFAULT_HIT_DELAY = 0.20
local DEFAULT_MOB_DAMAGE = 8
local DEFAULT_ROCK_DAMAGE = 15
local DEFAULT_ROCK_HP = 60

local MOB_RANGE = 12
local ROCK_HIT_RANGE = 10
-- Подсказка Use an Axe: только у основания MegaTree (не крона / не BigTree).
local TREE_HINT_FLAT = 14
local ROCK_SHAKE_STUDS = 0.18
local ROCK_SHAKE_TIME = 0.08
local SHARD_COUNT_MIN = 5
local SHARD_COUNT_MAX = 7
local SHARD_LIFE = 0.8
local LOOT_COUNT_MIN = 3
local LOOT_COUNT_MAX = 5
local LOOT_SCATTER = 2.8

local ATTR_ROCK_HP = "HP"
local ATTR_ROCK_BUSY = "PickaxeMineBusy"

local started = false
local pickaxeCooldown: { [Player]: number } = {}
local rockShakeToken: { [BasePart]: number } = {}

local function getRootPart(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function findPickaxeTool(character: Model): Tool?
	local tool = character:FindFirstChild(TOOL_NAME)
	if tool and tool:IsA("Tool") then
		return tool
	end
	return nil
end

local function readPickaxeStats(tool: Tool): (number, number, number, number)
	local itemId = tool:GetAttribute(ATTR_ITEM)
	if typeof(itemId) ~= "string" or itemId == "" then
		itemId = ITEM_ID
	end
	local stats = ItemsConfig.GetMelee(itemId)
	local mobDamage = DEFAULT_MOB_DAMAGE
	local rockDamage = DEFAULT_ROCK_DAMAGE
	local cooldown = DEFAULT_COOLDOWN
	local hitDelay = DEFAULT_HIT_DELAY
	if stats then
		local d = stats.damages[1]
		if typeof(d) == "number" then
			mobDamage = d
		end
		rockDamage = ItemsConfig.RockDamage(stats)
		if typeof(stats.attack_cooldown) == "number" then
			cooldown = stats.attack_cooldown
		end
		local hd = stats.hit_delays[1]
		if typeof(hd) == "number" then
			hitDelay = hd
		end
	end
	return mobDamage, rockDamage, cooldown, hitDelay
end

local function mediumRockMaxHp(): number
	local ok, cfg = pcall(function()
		local ConfigLoader = require(ServerScriptService:WaitForChild("ConfigLoader"))
		return ConfigLoader.Get()
	end)
	if ok and cfg and cfg.props then
		local hp = cfg.props.medium_rock_hp
		if typeof(hp) == "number" and hp >= 1 then
			return hp
		end
	end
	return DEFAULT_ROCK_HP
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function inFront(attackerRoot: BasePart, targetPos: Vector3, minDot: number): boolean
	local look = attackerRoot.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 1e-3 then
		return true
	end
	flatLook = flatLook.Unit
	local delta = targetPos - attackerRoot.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 0.5 then
		return true
	end
	return flat.Unit:Dot(flatLook) >= minDot
end

local function resolveSpawnLoot(): BindableFunction?
	local found = ServerScriptService:FindFirstChild("SpawnWorldLoot")
	if found and found:IsA("BindableFunction") then
		return found
	end
	return nil
end

local function ensureRockHp(rock: BasePart): number
	local hp = rock:GetAttribute(ATTR_ROCK_HP)
	if typeof(hp) ~= "number" then
		local maxHp = mediumRockMaxHp()
		rock:SetAttribute(ATTR_ROCK_HP, maxHp)
		return maxHp
	end
	return hp
end

local function closestPointOnPart(part: BasePart, worldPos: Vector3): (number, Vector3)
	local localPos = part.CFrame:PointToObjectSpace(worldPos)
	local half = part.Size * 0.5
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	local world = part.CFrame:PointToWorldSpace(clamped)
	return (world - worldPos).Magnitude, world
end

-- Без Soil: PrimaryPart часто съезжает от визуала.
local function megaVisualAxis(tree: Model): Vector3
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxZ = -math.huge, -math.huge
	local any = false
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Soil" and d.Transparency < 1 then
			any = true
			local p = d.Position
			local h = d.Size * 0.5
			minX = math.min(minX, p.X - h.X)
			minY = math.min(minY, p.Y - h.Y)
			minZ = math.min(minZ, p.Z - h.Z)
			maxX = math.max(maxX, p.X + h.X)
			maxZ = math.max(maxZ, p.Z + h.Z)
		end
	end
	if not any then
		local cf, size = tree:GetBoundingBox()
		return Vector3.new(cf.Position.X, cf.Position.Y - size.Y * 0.5, cf.Position.Z)
	end
	return Vector3.new((minX + maxX) * 0.5, minY, (minZ + maxZ) * 0.5)
end

local function findMegaTreeAncestor(inst: Instance?): Model?
	local node: Instance? = inst
	while node and node ~= Workspace do
		if node:IsA("Model") and node.Name == "MegaTree" then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function findMediumRockAncestor(inst: Instance?): BasePart?
	local node: Instance? = inst
	while node and node ~= Workspace do
		if node:IsA("BasePart") and node.Name == "MediumRock" then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function hitDummy(attackerRoot: BasePart, mobDamage: number): boolean
	local dummy = Workspace:FindFirstChild("TrainingDummy")
	if not (dummy and dummy:IsA("Model")) then
		return false
	end
	local dummyRoot = getRootPart(dummy)
	local targetPos = if dummyRoot then dummyRoot.Position else dummy:GetPivot().Position
	if flatDist(attackerRoot.Position, targetPos) > MOB_RANGE then
		return false
	end
	local humanoid = dummy:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	humanoid:TakeDamage(mobDamage)
	print(string.format("PickaxeCombat: манекен −%d (HP теперь %.0f)", mobDamage, humanoid.Health))
	return true
end

local function hintWrongTree(player: Player, attackerRoot: BasePart, character: Model)
	local rootPos = attackerRoot.Position
	local box = Vector3.new(12, 20, 12)
	local hitCFrame = attackerRoot.CFrame * CFrame.new(0, 3, -5)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = false
	for _, part in ipairs(Workspace:GetPartBoundsInBox(hitCFrame, box, overlap)) do
		local tree = findMegaTreeAncestor(part)
		if tree and part.Name ~= "Soil" and flatDist(rootPos, megaVisualAxis(tree)) <= TREE_HINT_FLAT then
			ToolHints.NeedAxe(player)
			return
		end
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child.Name == "MegaTree" then
			local axis = megaVisualAxis(child)
			if flatDist(rootPos, axis) <= TREE_HINT_FLAT and inFront(attackerRoot, axis, -0.35) then
				ToolHints.NeedAxe(player)
				return
			end
		end
	end
end

local function shakeRock(rock: BasePart)
	if rock:GetAttribute(ATTR_ROCK_BUSY) == true then
		return
	end
	local token = (rockShakeToken[rock] or 0) + 1
	rockShakeToken[rock] = token
	local origin = rock.CFrame
	local offset = Vector3.new(
		(math.random() - 0.5) * 2 * ROCK_SHAKE_STUDS,
		(math.random() - 0.5) * ROCK_SHAKE_STUDS,
		(math.random() - 0.5) * 2 * ROCK_SHAKE_STUDS
	)
	local info = TweenInfo.new(ROCK_SHAKE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(rock, info, { CFrame = origin + offset }):Play()
	task.delay(ROCK_SHAKE_TIME, function()
		if rockShakeToken[rock] ~= token or not rock.Parent then
			return
		end
		TweenService:Create(rock, info, { CFrame = origin }):Play()
	end)
end

local function spawnShards(at: Vector3, color: Color3)
	local count = math.random(SHARD_COUNT_MIN, SHARD_COUNT_MAX)
	for _ = 1, count do
		local shard = Instance.new("Part")
		shard.Name = "RockShard"
		shard.Size = Vector3.new(
			0.25 + math.random() * 0.45,
			0.2 + math.random() * 0.35,
			0.25 + math.random() * 0.45
		)
		shard.Color = color
		shard.Material = Enum.Material.Slate
		shard.Anchored = false
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.Massless = true
		shard.CastShadow = false
		shard.CFrame = CFrame.new(at + Vector3.new(0, 0.6, 0))
			* CFrame.Angles(math.random() * math.pi, math.random() * math.pi, math.random() * math.pi)
		shard.Parent = Workspace
		local dir = Vector3.new(math.random() - 0.5, 0.35 + math.random() * 0.55, math.random() - 0.5)
		if dir.Magnitude < 1e-3 then
			dir = Vector3.new(0, 1, 0)
		end
		shard.AssemblyLinearVelocity = dir.Unit * (10 + math.random() * 10)
		shard.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 12,
			(math.random() - 0.5) * 12,
			(math.random() - 0.5) * 12
		)
		local fadeInfo = TweenInfo.new(SHARD_LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(shard, fadeInfo, { Transparency = 1 }):Play()
		task.delay(SHARD_LIFE + 0.05, function()
			if shard.Parent then
				shard:Destroy()
			end
		end)
	end
end

local function dropSmallRocks(at: Vector3)
	local binder = resolveSpawnLoot()
	if not binder then
		warn("PickaxeCombat: нет SpawnWorldLoot")
		return
	end
	local count = math.random(LOOT_COUNT_MIN, LOOT_COUNT_MAX)
	for _ = 1, count do
		local ang = math.random() * math.pi * 2
		local dist = math.random() * LOOT_SCATTER
		local pos = at + Vector3.new(math.cos(ang) * dist, 0.4, math.sin(ang) * dist)
		binder:Invoke("SmallRock", pos)
	end
	print("PickaxeCombat: дроп SmallRock x", count)
end

local function destroyRock(rock: BasePart)
	if rock:GetAttribute(ATTR_ROCK_BUSY) == true then
		return
	end
	rock:SetAttribute(ATTR_ROCK_BUSY, true)
	rockShakeToken[rock] = (rockShakeToken[rock] or 0) + 1

	local originCF = rock.CFrame
	local center = rock.Position
	local color = rock.Color

	rock.CanCollide = false
	rock.CanQuery = false
	rock.Transparency = 1
	rock.Parent = nil

	spawnShards(center, color)
	dropSmallRocks(center)
	ResourceRespawnManager.Enqueue(
		"MediumRock",
		originCF,
		ResourceRespawnManager.MEDIUM_ROCK_RESPAWN_TIME
	)

	rock:Destroy()
	rockShakeToken[rock] = nil
end

local function hitMediumRock(attackerRoot: BasePart, character: Model, rockDamage: number): boolean
	local best: BasePart? = nil
	local bestDist = ROCK_HIT_RANGE

	local box = Vector3.new(14, 12, 14)
	local hitCFrame = attackerRoot.CFrame * CFrame.new(0, 2, -(box.Z * 0.35))
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = false
	for _, part in ipairs(Workspace:GetPartBoundsInBox(hitCFrame, box, overlap)) do
		local rock = findMediumRockAncestor(part)
		if rock then
			local dist = closestPointOnPart(rock, attackerRoot.Position)
			if dist < bestDist then
				bestDist = dist
				best = rock
			end
		end
	end

	if not best then
		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("BasePart") and child.Name == "MediumRock" then
				local dist, closest = closestPointOnPart(child, attackerRoot.Position)
				if dist < bestDist and inFront(attackerRoot, closest, -0.25) then
					bestDist = dist
					best = child
				end
			end
		end
	end

	if not best then
		return false
	end
	if best:GetAttribute(ATTR_ROCK_BUSY) == true then
		return false
	end

	local maxHp = mediumRockMaxHp()
	local hp = ensureRockHp(best)
	hp = math.max(0, hp - rockDamage)
	best:SetAttribute(ATTR_ROCK_HP, hp)
	print(string.format("PickaxeCombat: MediumRock −%d → HP %d/%d (dist %.1f)", rockDamage, hp, maxHp, bestDist))

	if hp <= 0 then
		task.spawn(destroyRock, best)
	else
		task.spawn(shakeRock, best)
	end
	return true
end

local function resolvePickaxeHit(player: Player, mobDamage: number, rockDamage: number)
	local character = player.Character
	if not character or not findPickaxeTool(character) then
		return
	end
	local attackerRoot = getRootPart(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not attackerRoot or not humanoid or humanoid.Health <= 0 then
		return
	end

	hintWrongTree(player, attackerRoot, character)

	local hitMob = hitDummy(attackerRoot, mobDamage)
	local hitRock = hitMediumRock(attackerRoot, character, rockDamage)
	if not hitMob and not hitRock then
		print("PickaxeCombat: промах (нет манекена/MediumRock рядом)")
	end
end

function PickaxeCombat.Start()
	if started then
		return
	end
	started = true

	ToolHints.Start()
	ResourceRespawnManager.Start()

	local attackRemote = InventoryService.EnsureRemote("PickaxeAttack")
	print("PickaxeCombat: remote →", attackRemote:GetFullName())

	attackRemote.OnServerEvent:Connect(function(player: Player)
		local character = player.Character
		if not character then
			return
		end
		local tool = findPickaxeTool(character)
		if not tool then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		local mobDamage, rockDamage, cooldown, hitDelay = readPickaxeStats(tool)
		local now = os.clock()
		local untilCd = pickaxeCooldown[player] or 0
		if now < untilCd then
			return
		end
		pickaxeCooldown[player] = now + cooldown

		task.delay(hitDelay, function()
			if not player.Parent then
				return
			end
			resolvePickaxeHit(player, mobDamage, rockDamage)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		pickaxeCooldown[player] = nil
	end)

	print("PickaxeCombat: Start() готов")
end

return PickaxeCombat
