--!strict
-- Сбор веток (Stick) с тонких деревьев BigTree удержанием E.
-- Анимация/prompt — HoldGather (тот же каркас потом для кустов ягод).

local BigTreeGather = {}

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local HoldGather = require(ServerScriptService:WaitForChild("HoldGather"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local ResourceRespawnManager = require(ServerScriptService:WaitForChild("ResourceRespawnManager"))

local HOLD_DURATION = 1.2
local MIN_STICKS = 2
local MAX_STICKS = 3
-- Считается от якоря у основания ствола (HoldGatherAttach), не от кроны/pivot.
local MAX_ACTIVATION_DISTANCE = 8
local TARGET_NAME = "BigTree"
local PROMPT_NAME = "GatherPrompt"
local ATTR_BUSY = "GatherBusy"
local ATTR_ATTACHED = "HoldGatherAttached"
local ATTACH_NAME = "HoldGatherAttach"

local started = false

local function gatherAnchorPos(target: Instance): Vector3
	local att = target:FindFirstChild(ATTACH_NAME, true)
	if att and att:IsA("Attachment") then
		return att.WorldPosition
	end
	if target:IsA("Model") then
		local cf, size = target:GetBoundingBox()
		return Vector3.new(cf.Position.X, cf.Position.Y - size.Y * 0.5 + 2, cf.Position.Z)
	end
	if target:IsA("BasePart") then
		return target.Position
	end
	return Vector3.zero
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function targetCFrame(target: Instance): CFrame
	if target:IsA("Model") then
		return target:GetPivot()
	end
	if target:IsA("BasePart") then
		return target.CFrame
	end
	return CFrame.new()
end

local function onGatherComplete(player: Player, target: Instance)
	if target:GetAttribute(ATTR_BUSY) == true then
		return
	end
	if not target.Parent then
		return
	end
	target:SetAttribute(ATTR_BUSY, true)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		target:SetAttribute(ATTR_BUSY, nil)
		warn("BigTreeGather: нет персонажа у", player.Name)
		return
	end

	-- Только XZ до якоря у основания — 3D до pivot раньше отбрасывал высокие деревья.
	local anchor = gatherAnchorPos(target)
	if flatDist(root.Position, anchor) > MAX_ACTIVATION_DISTANCE + 3 then
		target:SetAttribute(ATTR_BUSY, nil)
		warn(string.format(
			"BigTreeGather: слишком далеко от основания (%.1f > %.1f)",
			flatDist(root.Position, anchor),
			MAX_ACTIVATION_DISTANCE + 3
		))
		return
	end

	local count = math.random(MIN_STICKS, MAX_STICKS)
	local slot = InventoryService.AddItem(player, "Stick", count)
	if not slot then
		target:SetAttribute(ATTR_BUSY, nil)
		warn("BigTreeGather: не удалось добавить Stick (инвентарь полон?) у", player.Name)
		return
	end

	local originCF = targetCFrame(target)
	target:Destroy()
	ResourceRespawnManager.Enqueue(
		"BigTree",
		originCF,
		ResourceRespawnManager.BIG_TREE_RESPAWN_TIME
	)
	print(string.format("BigTreeGather: %s собрал Stick x%d", player.Name, count))
end

local function clearOldGatherPrompts(inst: Instance)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Name == PROMPT_NAME then
			d:Destroy()
		end
	end
end

local function setupTree(inst: Instance)
	if inst.Parent ~= Workspace then
		return
	end
	if inst.Name ~= TARGET_NAME then
		return
	end
	if not (inst:IsA("Model") or inst:IsA("BasePart")) then
		return
	end
	if inst:GetAttribute(ATTR_ATTACHED) == true then
		return
	end

	clearOldGatherPrompts(inst)

	local prompt = HoldGather.Attach(inst, {
		promptName = PROMPT_NAME,
		actionText = "Gather",
		objectText = "Branches",
		holdDuration = HOLD_DURATION,
		maxActivationDistance = MAX_ACTIVATION_DISTANCE,
		requiresLineOfSight = false,
		keyboardKeyCode = Enum.KeyCode.E,
		animationId = HoldGather.GATHER_ANIM_ID,
		swayDegrees = 2.2,
		swayPeriod = 0.28,
		onTriggered = onGatherComplete,
	})
	if prompt then
		inst:SetAttribute(ATTR_ATTACHED, true)
	else
		warn("BigTreeGather: не удалось повесить prompt на", inst:GetFullName())
	end
end

function BigTreeGather.Start()
	if started then
		return
	end
	started = true

	ResourceRespawnManager.Start()

	for _, child in ipairs(Workspace:GetChildren()) do
		setupTree(child)
	end
	Workspace.ChildAdded:Connect(function(child)
		task.defer(setupTree, child)
	end)

	print("BigTreeGather: готов (hold E → Stick x2–3, респавн 60с)")
end

return BigTreeGather
