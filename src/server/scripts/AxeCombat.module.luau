--!strict
-- Axe: удар правой. Урон манекену + рубка MegaTree.
-- Стартует из FistWeapon (Script AxeCombat.server.lua мог не подниматься в Studio).

local AxeCombat = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ItemsConfig = require(ServerScriptService:WaitForChild("ItemsConfig"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local ResourceRespawnManager = require(ServerScriptService:WaitForChild("ResourceRespawnManager"))
local ToolHints = require(ServerScriptService:WaitForChild("ToolHints"))

local TOOL_NAME = "Axe"
local ITEM_ID = "Axe"
local ATTR_ITEM = InventoryService.AttrItem()

local DEFAULT_COOLDOWN = 0.5
local DEFAULT_HIT_DELAY = 0.17
local DEFAULT_MOB_DAMAGE = 8
local DEFAULT_TREE_DAMAGE = 15
local DEFAULT_TREE_HP = 75

local MOB_RANGE = 12
-- Хит MegaTree: часть меша в overlap / рядом со стволом (Soil PrimaryPart НЕ использовать — он часто съезжает).
local TREE_PART_HIT_RANGE = 12
local TREE_AXIS_FLAT_RANGE = 16
local TREE_SWAY_DEG = 3.5
local TREE_SWAY_TIME = 0.14
-- Падение вокруг основания (не вокруг pivot — иначе «ракета»).
local TREE_FALL_DEG = 88
local TREE_FALL_TIME = 2.6
local TREE_FADE_TIME = 0.55
local STICK_DROP_MIN = 5
local STICK_DROP_MAX = 8
local STICK_SCATTER = 3.5

local ATTR_TREE_HP = "HP"
local ATTR_TREE_BUSY = "AxeChopBusy"

local started = false
local axeCooldown: { [Player]: number } = {}
local treeSwayToken: { [Model]: number } = {}

local function getRootPart(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function findAxeTool(character: Model): Tool?
	local tool = character:FindFirstChild(TOOL_NAME)
	if tool and tool:IsA("Tool") then
		return tool
	end
	return nil
end

local function readAxeStats(tool: Tool): (number, number, number, number)
	local itemId = tool:GetAttribute(ATTR_ITEM)
	if typeof(itemId) ~= "string" or itemId == "" then
		itemId = ITEM_ID
	end
	local stats = ItemsConfig.GetMelee(itemId)
	local mobDamage = DEFAULT_MOB_DAMAGE
	local treeDamage = DEFAULT_TREE_DAMAGE
	local cooldown = DEFAULT_COOLDOWN
	local hitDelay = DEFAULT_HIT_DELAY
	if stats then
		local d = stats.damages[1]
		if typeof(d) == "number" then
			mobDamage = d
		end
		treeDamage = ItemsConfig.TreeDamage(stats)
		if typeof(stats.attack_cooldown) == "number" then
			cooldown = stats.attack_cooldown
		end
		local hd = stats.hit_delays[1]
		if typeof(hd) == "number" then
			hitDelay = hd
		end
	end
	return mobDamage, treeDamage, cooldown, hitDelay
end

local function megaTreeMaxHp(): number
	local ok, cfg = pcall(function()
		local ConfigLoader = require(ServerScriptService:WaitForChild("ConfigLoader"))
		return ConfigLoader.Get()
	end)
	if ok and cfg and cfg.props then
		local hp = cfg.props.mega_tree_hp
		if typeof(hp) == "number" and hp >= 1 then
			return hp
		end
	end
	return DEFAULT_TREE_HP
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

local function ensureTreeHp(tree: Model): number
	local hp = tree:GetAttribute(ATTR_TREE_HP)
	if typeof(hp) ~= "number" then
		local maxHp = megaTreeMaxHp()
		tree:SetAttribute(ATTR_TREE_HP, maxHp)
		return maxHp
	end
	return hp
end

local function setTreeCollide(tree: Model, enabled: boolean)
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = enabled
		end
	end
end

-- Нижняя точка bounding box — «корни»; вокруг неё валим ствол.
local function treeBasePosition(tree: Model): Vector3
	local cf, size = tree:GetBoundingBox()
	return Vector3.new(cf.Position.X, cf.Position.Y - size.Y * 0.5, cf.Position.Z)
end

-- Падение от игрока: ось перпендикулярна направлению «игрок → дерево».
local function fallAxisAway(tree: Model, attackerRoot: BasePart): (Vector3, Vector3)
	local base = treeBasePosition(tree)
	local toTree = base - attackerRoot.Position
	local away = Vector3.new(toTree.X, 0, toTree.Z)
	if away.Magnitude < 1e-3 then
		local look = attackerRoot.CFrame.LookVector
		away = Vector3.new(look.X, 0, look.Z)
		if away.Magnitude < 1e-3 then
			away = Vector3.new(0, 0, -1)
		end
	end
	away = away.Unit
	-- up × away: положительный угол валит крону от игрока.
	local axis = Vector3.new(away.Z, 0, -away.X)
	return axis, away
end

local function animatePivotAroundHinge(
	tree: Model,
	startPivot: CFrame,
	hingePos: Vector3,
	axis: Vector3,
	angleRad: number,
	duration: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection
)
	local hinge = CFrame.new(hingePos)
	local relative = hinge:ToObjectSpace(startPivot)
	local alpha = Instance.new("NumberValue")
	alpha.Value = 0
	TweenService:Create(alpha, TweenInfo.new(duration, style, direction), { Value = 1 }):Play()
	local t0 = os.clock()
	while tree.Parent and os.clock() - t0 < duration + 0.35 do
		local ang = angleRad * alpha.Value
		tree:PivotTo(hinge * CFrame.fromAxisAngle(axis, ang) * relative)
		if alpha.Value >= 0.999 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	alpha:Destroy()
end

local function dropSticksAtStump(stumpPos: Vector3)
	local binder = resolveSpawnLoot()
	if not binder then
		warn("AxeCombat: нет SpawnWorldLoot")
		return
	end
	local count = math.random(STICK_DROP_MIN, STICK_DROP_MAX)
	for _ = 1, count do
		local ang = math.random() * math.pi * 2
		local dist = math.random() * STICK_SCATTER
		local pos = stumpPos + Vector3.new(math.cos(ang) * dist, 0.5, math.sin(ang) * dist)
		binder:Invoke("Stick", pos)
	end
	print("AxeCombat: дроп Stick x", count, "у пня")
end

local function fadeAndDestroyTree(tree: Model)
	local fadeInfo = TweenInfo.new(TREE_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, fadeInfo, { Transparency = 1 }):Play()
		elseif d:IsA("Decal") or d:IsA("Texture") then
			TweenService:Create(d, fadeInfo, { Transparency = 1 }):Play()
		end
	end
	task.wait(TREE_FADE_TIME)
	if tree.Parent then
		tree:Destroy()
	end
end

local function fallTree(tree: Model, attackerRoot: BasePart)
	if tree:GetAttribute(ATTR_TREE_BUSY) == true then
		return
	end
	tree:SetAttribute(ATTR_TREE_BUSY, true)
	treeSwayToken[tree] = (treeSwayToken[tree] or 0) + 1

	local originCF = tree:GetPivot()
	local hingePos = treeBasePosition(tree)
	local stumpPos = hingePos
	setTreeCollide(tree, false)

	local axis, _fallDir = fallAxisAway(tree, attackerRoot)
	local startPivot = tree:GetPivot()
	animatePivotAroundHinge(
		tree,
		startPivot,
		hingePos,
		axis,
		math.rad(TREE_FALL_DEG),
		TREE_FALL_TIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)

	dropSticksAtStump(stumpPos)
	ResourceRespawnManager.Enqueue(
		"MegaTree",
		originCF,
		ResourceRespawnManager.MEGA_TREE_RESPAWN_TIME
	)

	if tree.Parent then
		fadeAndDestroyTree(tree)
	end
	treeSwayToken[tree] = nil
end

local function swayTree(tree: Model, attackerRoot: BasePart)
	if tree:GetAttribute(ATTR_TREE_BUSY) == true then
		return
	end
	local token = (treeSwayToken[tree] or 0) + 1
	treeSwayToken[tree] = token
	local axis = select(1, fallAxisAway(tree, attackerRoot))
	local hingePos = treeBasePosition(tree)
	local startPivot = tree:GetPivot()
	local angle = math.rad(TREE_SWAY_DEG)
	animatePivotAroundHinge(
		tree,
		startPivot,
		hingePos,
		axis,
		angle,
		TREE_SWAY_TIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	if treeSwayToken[tree] ~= token or not tree.Parent then
		return
	end
	local midPivot = tree:GetPivot()
	animatePivotAroundHinge(
		tree,
		midPivot,
		hingePos,
		axis,
		-angle,
		TREE_SWAY_TIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	if treeSwayToken[tree] == token and tree.Parent then
		tree:PivotTo(startPivot)
	end
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
	print(string.format("AxeCombat: манекен −%d (HP теперь %.0f)", mobDamage, humanoid.Health))
	return true
end

-- Ось/низ визуала без Soil: PrimaryPart=Soil часто далеко от меша и ломал хит (~50 студов).
local function megaVisualAxis(tree: Model): Vector3
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
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
			maxY = math.max(maxY, p.Y + h.Y)
			maxZ = math.max(maxZ, p.Z + h.Z)
		end
	end
	if not any then
		return treeBasePosition(tree)
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

local function findThinTreeAncestor(inst: Instance?): Model?
	local node: Instance? = inst
	while node and node ~= Workspace do
		if node:IsA("Model") and (node.Name == "BigTree" or node.Name == "thin_tree") then
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

local function hintWrongRock(player: Player, attackerRoot: BasePart, character: Model)
	local rockRange = 10
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
			if dist <= rockRange then
				ToolHints.NeedPickaxe(player)
				return
			end
		end
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "MediumRock" then
			local dist, closest = closestPointOnPart(child, attackerRoot.Position)
			if dist <= rockRange and inFront(attackerRoot, closest, -0.25) then
				ToolHints.NeedPickaxe(player)
				return
			end
		end
	end
end

local function hitMegaTree(attackerRoot: BasePart, character: Model, treeDamage: number): boolean
	local best: Model? = nil
	local bestDist = TREE_PART_HIT_RANGE
	local otherTree: Model? = nil
	local rootPos = attackerRoot.Position

	-- 1) Часть меша MegaTree в боксе удара (Soil игнорируем).
	local box = Vector3.new(12, 20, 12)
	local hitCFrame = attackerRoot.CFrame * CFrame.new(0, 3, -5)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = false
	for _, part in ipairs(Workspace:GetPartBoundsInBox(hitCFrame, box, overlap)) do
		if part.Name ~= "Soil" then
			local mega = findMegaTreeAncestor(part)
			if mega then
				local dist = closestPointOnPart(part, rootPos)
				local axisFlat = flatDist(rootPos, megaVisualAxis(mega))
				-- Рядом с мешем + не под дальним краем кроны (ось по визуалу, не Soil).
				if dist < bestDist and axisFlat <= TREE_AXIS_FLAT_RANGE then
					bestDist = dist
					best = mega
				end
			elseif not otherTree then
				otherTree = findThinTreeAncestor(part)
			end
		end
	end

	-- 2) Запас: у визуальной оси дерева.
	if not best then
		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("Model") and child.Name == "MegaTree" then
				local axis = megaVisualAxis(child)
				local flat = flatDist(rootPos, axis)
				if flat < bestDist and flat <= TREE_AXIS_FLAT_RANGE and inFront(attackerRoot, axis, -0.35) then
					bestDist = flat
					best = child
				end
			end
		end
	end

	if not best then
		if otherTree then
			print("AxeCombat: удар по", otherTree.Name, "— рубка только MegaTree (сбор веток: E)")
			return true
		end
		local nearestFlat = math.huge
		local count = 0
		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("Model") and child.Name == "MegaTree" then
				count += 1
				local flat = flatDist(rootPos, megaVisualAxis(child))
				if flat < nearestFlat then
					nearestFlat = flat
				end
			end
		end
		print(string.format(
			"AxeCombat: MegaTree не в досягаемости (найдено %d, до оси визуала %.1f, лимит %.0f)",
			count,
			if nearestFlat < math.huge then nearestFlat else -1,
			TREE_AXIS_FLAT_RANGE
		))
		return false
	end

	if best:GetAttribute(ATTR_TREE_BUSY) == true then
		return false
	end

	local maxHp = megaTreeMaxHp()
	local hp = ensureTreeHp(best)
	hp = math.max(0, hp - treeDamage)
	best:SetAttribute(ATTR_TREE_HP, hp)
	print(string.format(
		"AxeCombat: MegaTree −%d → HP %d/%d (part %.1f, axisFlat %.1f)",
		treeDamage,
		hp,
		maxHp,
		bestDist,
		flatDist(rootPos, megaVisualAxis(best))
	))

	if hp <= 0 then
		task.spawn(fallTree, best, attackerRoot)
	else
		task.spawn(swayTree, best, attackerRoot)
	end
	return true
end

local function resolveAxeHit(player: Player, mobDamage: number, treeDamage: number)
	local character = player.Character
	if not character or not findAxeTool(character) then
		return
	end
	local attackerRoot = getRootPart(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not attackerRoot or not humanoid or humanoid.Health <= 0 then
		return
	end

	hintWrongRock(player, attackerRoot, character)

	local hitMob = hitDummy(attackerRoot, mobDamage)
	local hitTree = hitMegaTree(attackerRoot, character, treeDamage)
	if not hitMob and not hitTree then
		print("AxeCombat: промах (нет манекена/MegaTree рядом)")
	end
end

function AxeCombat.Start()
	if started then
		return
	end
	started = true

	ToolHints.Start()
	ResourceRespawnManager.Start()

	local attackRemote = InventoryService.EnsureRemote("AxeAttack")
	print("AxeCombat: remote →", attackRemote:GetFullName())

	attackRemote.OnServerEvent:Connect(function(player: Player)
		print("AxeCombat: получил AxeAttack от", player.Name)

		local character = player.Character
		if not character then
			return
		end
		local tool = findAxeTool(character)
		if not tool then
			warn("AxeCombat: нет Tool Axe у", player.Name)
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		local mobDamage, treeDamage, cooldown, hitDelay = readAxeStats(tool)
		local now = os.clock()
		local untilCd = axeCooldown[player] or 0
		if now < untilCd then
			return
		end
		axeCooldown[player] = now + cooldown

		task.delay(hitDelay, function()
			if not player.Parent then
				return
			end
			resolveAxeHit(player, mobDamage, treeDamage)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		axeCooldown[player] = nil
	end)

	print("AxeCombat: Start() готов")
end

return AxeCombat
