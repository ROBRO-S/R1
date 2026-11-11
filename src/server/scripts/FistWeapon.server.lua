--!strict
-- Кастеты + слоты. Handle невидимый; кастеты Weld к рукам.
-- Стойка/блок/удары — клиентские анимации; сервер: IsBlocking, WalkSpeed, хитбокс.
-- Экип слота — RemoteEvent (клиентский EquipTool после Unequip глючит).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemsConfig = require(ServerScriptService:WaitForChild("ItemsConfig"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
type MeleeStats = ItemsConfig.MeleeStats

-- === Посадка на кулаки (можно чуть утопить внутрь руки) ===
local RIGHT_FIST_POSITION = Vector3.new(0, 0.1, 0)
local RIGHT_FIST_ROTATION_DEG = Vector3.new(0, 0, -90)

local LEFT_FIST_POSITION = Vector3.new(0, 0.1, 0)
local LEFT_FIST_ROTATION_DEG = Vector3.new(0, 90, -90)

local BLOCK_WALK_SPEED = 10
local DEFAULT_WALK_SPEED = 16
-- ===

local TOOL_NAME = "FistWeapon"
local ITEM_ID = "FistWeapon"
local TEMPLATE_NAME = "fistweapon_A"
local RIGHT_VISUAL = "FistWeapon_Right"
local LEFT_VISUAL = "FistWeapon_Left"
local SLOT_COUNT = InventoryService.SlotCount()
local ATTR_SLOT = InventoryService.AttrSlot()
local ATTR_ITEM = InventoryService.AttrItem()
-- Клиент читает тайминги комбо с Tool (из items_config).
local ATTR_COMBO_RESET = "ComboReset"
local ATTR_ATTACK_CD = "AttackCooldown"
local ATTR_FINISH_CD = "FinishCooldown"

local function anglesFromDeg(rot: Vector3): CFrame
	return CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
end

local function offsetCFrame(pos: Vector3, rotDeg: Vector3): CFrame
	return CFrame.new(pos) * anglesFromDeg(rotDeg)
end

local function preparePart(part: BasePart)
	part.CanCollide = false
	part.Anchored = false
	part.Massless = true
end

local function resolveTemplate(): BasePart?
	local assets = ReplicatedStorage:WaitForChild("assets", 30)
	if not assets then
		warn("FistWeapon: нет ReplicatedStorage.assets")
		return nil
	end
	local template = assets:WaitForChild(TEMPLATE_NAME, 30)
	if not template then
		warn("FistWeapon: нет assets." .. TEMPLATE_NAME)
		return nil
	end
	if template:IsA("BasePart") then
		return template
	end
	local nested = template:FindFirstChildWhichIsA("BasePart", true)
	if nested then
		return nested
	end
	warn("FistWeapon: шаблон не BasePart (" .. template.ClassName .. ")")
	return nil
end

local template = resolveTemplate()
if not template then
	return
end

local equipRemote = InventoryService.EnsureRemote("EquipSlot")
local blockRemote = InventoryService.EnsureRemote("FistBlock")
local attackRemote = InventoryService.EnsureRemote("FistAttack")

local attackState: { [Player]: { lastAttackAt: number, lastStep: number, cooldownUntil: number } } = {}

local function findArm(character: Model, side: "Left" | "Right"): BasePart?
	if side == "Left" then
		local hand = character:FindFirstChild("LeftHand")
		if hand and hand:IsA("BasePart") then
			return hand
		end
		local arm = character:FindFirstChild("Left Arm")
		if arm and arm:IsA("BasePart") then
			return arm
		end
	else
		local hand = character:FindFirstChild("RightHand")
		if hand and hand:IsA("BasePart") then
			return hand
		end
		local arm = character:FindFirstChild("Right Arm")
		if arm and arm:IsA("BasePart") then
			return arm
		end
	end
	return nil
end

local function clearVisuals(character: Model)
	for _, name in { RIGHT_VISUAL, LEFT_VISUAL } do
		local inst = character:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end
end

local function weldFist(character: Model, side: "Left" | "Right")
	local arm = findArm(character, side)
	if not arm then
		return
	end
	local name = if side == "Left" then LEFT_VISUAL else RIGHT_VISUAL
	local existing = character:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local fist = template:Clone()
	fist.Name = name
	preparePart(fist)
	fist.Parent = character

	local pos = if side == "Left" then LEFT_FIST_POSITION else RIGHT_FIST_POSITION
	local rot = if side == "Left" then LEFT_FIST_ROTATION_DEG else RIGHT_FIST_ROTATION_DEG

	local weld = Instance.new("Weld")
	weld.Name = name .. "Weld"
	weld.Part0 = arm
	weld.Part1 = fist
	weld.C0 = offsetCFrame(pos, rot)
	weld.C1 = CFrame.new()
	weld.Parent = fist
end

local function clearBlocking(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	character:SetAttribute("IsBlocking", false)
	if humanoid then
		local base = character:GetAttribute("BaseWalkSpeed")
		if typeof(base) == "number" then
			humanoid.WalkSpeed = base
		else
			humanoid.WalkSpeed = DEFAULT_WALK_SPEED
		end
	end
end

local function setBlocking(character: Model, active: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if active then
		if typeof(character:GetAttribute("BaseWalkSpeed")) ~= "number" then
			character:SetAttribute("BaseWalkSpeed", humanoid.WalkSpeed)
		end
		character:SetAttribute("IsBlocking", true)
		humanoid.WalkSpeed = BLOCK_WALK_SPEED
	else
		clearBlocking(character)
	end
end

local function hasFistEquipped(character: Model): boolean
	local tool = character:FindFirstChild(TOOL_NAME)
	return tool ~= nil and tool:IsA("Tool")
end

local function getRootPart(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isFacingAttacker(targetRoot: BasePart, attackerRoot: BasePart, blockDot: number): boolean
	local toAttacker = attackerRoot.Position - targetRoot.Position
	local flat = Vector3.new(toAttacker.X, 0, toAttacker.Z)
	if flat.Magnitude < 1e-3 then
		return true
	end
	return targetRoot.CFrame.LookVector:Dot(flat.Unit) > blockDot
end

local function applyKnockback(attackerRoot: BasePart, targetRoot: BasePart, force: number)
	local push = targetRoot.Position - attackerRoot.Position
	local flat = Vector3.new(push.X, 0, push.Z)
	if flat.Magnitude < 1e-3 then
		flat = attackerRoot.CFrame.LookVector
		flat = Vector3.new(flat.X, 0, flat.Z)
	end
	if flat.Magnitude < 1e-3 then
		return
	end
	targetRoot:ApplyImpulse(flat.Unit * force * targetRoot.AssemblyMass)
end

local function applyCombatAttrs(tool: Tool, stats: MeleeStats)
	tool:SetAttribute(ATTR_COMBO_RESET, stats.combo_reset)
	tool:SetAttribute(ATTR_ATTACK_CD, stats.attack_cooldown)
	tool:SetAttribute(ATTR_FINISH_CD, stats.finish_cooldown)
	if stats.display_name ~= "" then
		tool.ToolTip = stats.display_name
	end
end

local function resolveEquippedItemId(character: Model): string?
	local tool = character:FindFirstChild(TOOL_NAME)
	if not (tool and tool:IsA("Tool")) then
		return nil
	end
	local itemId = tool:GetAttribute(ATTR_ITEM)
	if typeof(itemId) == "string" and itemId ~= "" then
		return itemId
	end
	return ITEM_ID
end

local function resolveHit(attacker: Player, step: number, stats: MeleeStats)
	local character = attacker.Character
	if not character then
		return
	end
	if not hasFistEquipped(character) then
		return
	end
	if character:GetAttribute("IsBlocking") == true then
		return
	end

	local attackerHumanoid = character:FindFirstChildOfClass("Humanoid")
	local attackerRoot = getRootPart(character)
	if not attackerHumanoid or attackerHumanoid.Health <= 0 or not attackerRoot then
		return
	end

	local damage = stats.damages[step]
	if typeof(damage) ~= "number" then
		return
	end

	local hitbox = ItemsConfig.HitboxSize(stats)
	local comboLength = ItemsConfig.ComboLength(stats)
	local hitCFrame = attackerRoot.CFrame * CFrame.new(0, 0, -(hitbox.Z * 0.5))
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }
	overlap.RespectCanCollide = false

	local hitHumanoids: { [Humanoid]: boolean } = {}
	for _, part in ipairs(Workspace:GetPartBoundsInBox(hitCFrame, hitbox, overlap)) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= character then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not hitHumanoids[humanoid] then
				hitHumanoids[humanoid] = true

				local finalDamage = damage
				local targetRoot = getRootPart(model)
				local blocked = model:GetAttribute("IsBlocking") == true
					and targetRoot ~= nil
					and isFacingAttacker(targetRoot, attackerRoot, stats.block_dot)
				if blocked then
					finalDamage = 0
				end

				if finalDamage > 0 then
					humanoid:TakeDamage(finalDamage)
				end

				if step >= comboLength and not blocked and targetRoot then
					applyKnockback(attackerRoot, targetRoot, stats.knockback)
				end
			end
		end
	end
end

local function expectedComboStep(
	state: { lastAttackAt: number, lastStep: number },
	now: number,
	comboReset: number,
	comboLength: number
): number
	if state.lastAttackAt <= 0 or now - state.lastAttackAt > comboReset then
		return 1
	end
	if state.lastStep >= comboLength then
		return 1
	end
	return state.lastStep + 1
end

local function createTool(): Tool
	local stats = ItemsConfig.GetMelee(ITEM_ID)
	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = if stats then stats.display_name else "Fist Weapon"
	tool.Grip = CFrame.new()
	if stats then
		applyCombatAttrs(tool, stats)
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.CastShadow = false
	handle.Parent = tool

	local weldedCharacter: Model? = nil

	tool.Equipped:Connect(function()
		local character = tool.Parent
		if not character or not character:IsA("Model") then
			return
		end
		weldedCharacter = character
		weldFist(character, "Right")
		weldFist(character, "Left")

		local player = Players:GetPlayerFromCharacter(character)
		if player and InventoryService.GetSession(player) then
			local slot = tool:GetAttribute(ATTR_SLOT)
			if typeof(slot) == "number" then
				InventoryService.SetEquipped(player, slot)
			end
		end
	end)

	tool.Unequipped:Connect(function()
		-- Чистим weld даже если Tool уничтожили, а не положили в Backpack.
		local character = weldedCharacter
		weldedCharacter = nil
		if character then
			clearVisuals(character)
			clearBlocking(character)
		end

		local parent = tool.Parent
		local player: Player? = nil
		if parent and parent:IsA("Backpack") and parent.Parent and parent.Parent:IsA("Player") then
			player = parent.Parent
		elseif character then
			player = Players:GetPlayerFromCharacter(character)
		end
		if player and InventoryService.GetSession(player) then
			InventoryService.SetEquipped(player, 0)
		end
	end)

	return tool
end

local function findTool(player: Player, pred: (Tool) -> boolean): Tool?
	local function scan(container: Instance?): Tool?
		if not container then
			return nil
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and pred(child) then
				return child
			end
		end
		return nil
	end
	return scan(player:FindFirstChildOfClass("Backpack")) or scan(player.Character)
end

local function scalePartTo(part: BasePart, maxDim: number)
	local current = math.max(part.Size.X, part.Size.Y, part.Size.Z)
	if current <= 1e-3 or current <= maxDim then
		return
	end
	part.Size = part.Size * (maxDim / current)
end

local function hookHeldTool(tool: Tool)
	tool.Equipped:Connect(function()
		local character = tool.Parent
		if not character or not character:IsA("Model") then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player and InventoryService.GetSession(player) then
			local slot = tool:GetAttribute(ATTR_SLOT)
			if typeof(slot) == "number" then
				InventoryService.SetEquipped(player, slot)
			end
		end
	end)

	tool.Unequipped:Connect(function()
		local backpack = tool.Parent
		if not (backpack and backpack:IsA("Backpack")) then
			return
		end
		local player = backpack.Parent
		if not (player and player:IsA("Player")) then
			return
		end
		if InventoryService.GetSession(player) then
			InventoryService.SetEquipped(player, 0)
		end
	end)
end

-- Обычный предмет в руке (камень, ветка, будущие ресурсы).
local function createHeldTool(itemId: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = itemId
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = ItemsConfig.DisplayName(itemId)

	local handle: BasePart
	if itemId == "Stick" then
		handle = Instance.new("Part")
		handle.Shape = Enum.PartType.Cylinder
		handle.Size = Vector3.new(1.5, 0.22, 0.22)
		handle.Color = Color3.fromRGB(120, 85, 50)
		handle.Material = Enum.Material.Wood
		tool.Grip = CFrame.new(0, -0.05, 0) * CFrame.Angles(0, 0, math.rad(90))
	elseif itemId == "SmallRock" then
		local assets = ReplicatedStorage:FindFirstChild("assets")
		local template = assets and assets:FindFirstChild("SmallRock")
		if template and template:IsA("BasePart") then
			handle = template:Clone()
			handle.Transparency = 0
			scalePartTo(handle, 1.1)
		else
			handle = Instance.new("Part")
			handle.Size = Vector3.new(0.95, 0.7, 1.05)
			handle.Color = Color3.fromRGB(90, 90, 95)
			handle.Material = Enum.Material.Slate
		end
		tool.Grip = CFrame.new(0, -0.12, -0.25)
	else
		handle = Instance.new("Part")
		handle.Size = Vector3.new(0.7, 0.7, 0.7)
		handle.Color = Color3.fromRGB(180, 160, 120)
		handle.Material = Enum.Material.SmoothPlastic
		tool.Grip = CFrame.new(0, -0.1, -0.2)
	end

	handle.Name = "Handle"
	handle.Anchored = false
	handle.CanCollide = false
	handle.Massless = true
	handle.CastShadow = true
	handle.Parent = tool

	hookHeldTool(tool)
	return tool
end

local function createToolForItem(itemId: string): Tool
	if ItemsConfig.IsMelee(itemId) then
		local tool = createTool()
		tool.Name = itemId
		return tool
	end
	return createHeldTool(itemId)
end

local function ensureTools(player: Player)
	local data = InventoryService.GetSession(player)
	if not data then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	-- Убрать Tool'ы без слота / с другим ItemId.
	local function prune(container: Instance?)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				local slot = child:GetAttribute(ATTR_SLOT)
				local stack = if typeof(slot) == "number" then data.slots[slot] else nil
				local itemId = if stack then stack.id else nil
				local toolItem = child:GetAttribute(ATTR_ITEM)
				if typeof(slot) ~= "number"
					or not itemId
					or typeof(toolItem) ~= "string"
					or toolItem ~= itemId
				then
					child:Destroy()
				end
			end
		end
	end
	prune(backpack)
	prune(player.Character)

	for slot, stack in pairs(data.slots) do
		local itemId = stack.id
		local existing = findTool(player, function(tool)
			return tool:GetAttribute(ATTR_SLOT) == slot
		end)
		if existing then
			existing.Name = itemId
			existing:SetAttribute(ATTR_SLOT, slot)
			existing:SetAttribute(ATTR_ITEM, itemId)
			if ItemsConfig.IsMelee(itemId) then
				local stats = ItemsConfig.GetMelee(itemId)
				if stats then
					applyCombatAttrs(existing, stats)
				end
			end
		else
			local tool = createToolForItem(itemId)
			tool:SetAttribute(ATTR_SLOT, slot)
			tool:SetAttribute(ATTR_ITEM, itemId)
			if ItemsConfig.IsMelee(itemId) then
				local stats = ItemsConfig.GetMelee(itemId)
				if stats then
					applyCombatAttrs(tool, stats)
				end
			end
			tool.Parent = backpack
		end
	end
end

InventoryService.SetToolSync(ensureTools)

InventoryService.SetVisualCleanup(function(player: Player)
	local character = player.Character
	if character then
		clearVisuals(character)
		clearBlocking(character)
	end
end)

local function equipSlot(player: Player, slot: number)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local data = InventoryService.GetSession(player)
	if not data then
		return
	end

	if slot < 1 then
		humanoid:UnequipTools()
		InventoryService.SetEquipped(player, 0)
		return
	end

	local stack = data.slots[slot]
	if not stack then
		humanoid:UnequipTools()
		InventoryService.SetEquipped(player, 0)
		return
	end

	local tool = findTool(player, function(t)
		return t:GetAttribute(ATTR_SLOT) == slot
	end)
	if not tool then
		ensureTools(player)
		tool = findTool(player, function(t)
			return t:GetAttribute(ATTR_SLOT) == slot
		end)
	end
	if tool then
		humanoid:EquipTool(tool)
	else
		InventoryService.SetEquipped(player, slot)
	end
end

local function hookPlayer(player: Player)
	-- Сессия уже поднимается в InventoryService; здесь — Tool и экип.
	InventoryService.HookPlayer(player)

	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			if not player.Parent or player.Character ~= character then
				return
			end
			character:WaitForChild("Humanoid", 10)
			ensureTools(player)
			InventoryService.WriteState(player)
			local data = InventoryService.GetSession(player)
			if data and data.equipped > 0 then
				equipSlot(player, data.equipped)
			end
		end)

		character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				clearVisuals(character)
				clearBlocking(character)
			end
		end)
	end)

	if player.Character then
		task.defer(function()
			local character = player.Character
			if not character then
				return
			end
			ensureTools(player)
			InventoryService.WriteState(player)
			local data = InventoryService.GetSession(player)
			if data and data.equipped > 0 then
				equipSlot(player, data.equipped)
			end
		end)
	end
end

local function isHoldingSlot(player: Player, slot: number): boolean
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

equipRemote.OnServerEvent:Connect(function(player: Player, slot: any)
	if typeof(slot) ~= "number" then
		return
	end
	slot = math.floor(slot)
	if slot < 0 or slot > SLOT_COUNT then
		return
	end
	local data = InventoryService.GetSession(player)
	if not data then
		return
	end
	if slot >= 1 and not data.slots[slot] then
		-- Пустой слот → снять.
		equipSlot(player, 0)
		return
	end
	-- Повторный выбор того же слота → убрать из рук (не дроп).
	if slot >= 1 and (data.equipped == slot or isHoldingSlot(player, slot)) then
		equipSlot(player, 0)
		return
	end
	equipSlot(player, slot)
end)

blockRemote.OnServerEvent:Connect(function(player: Player, active: any)
	if typeof(active) ~= "boolean" then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	if active then
		if not hasFistEquipped(character) then
			return
		end
		setBlocking(character, true)
	else
		setBlocking(character, false)
	end
end)

attackRemote.OnServerEvent:Connect(function(player: Player, stepAny: any)
	if typeof(stepAny) ~= "number" then
		return
	end
	local step = math.floor(stepAny)

	local character = player.Character
	if not character then
		return
	end
	local itemId = resolveEquippedItemId(character)
	if not itemId then
		return
	end
	local stats = ItemsConfig.GetMelee(itemId)
	if not stats then
		return
	end

	local comboLength = ItemsConfig.ComboLength(stats)
	if step < 1 or step > comboLength then
		return
	end
	if character:GetAttribute("IsBlocking") == true then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local state = attackState[player]
	if not state then
		state = { lastAttackAt = 0, lastStep = 0, cooldownUntil = 0 }
		attackState[player] = state
	end

	if now < state.cooldownUntil then
		return
	end

	local expected = expectedComboStep(state, now, stats.combo_reset, comboLength)
	if step ~= expected then
		return
	end

	local hitDelay = stats.hit_delays[step]
	if typeof(hitDelay) ~= "number" then
		return
	end

	state.lastAttackAt = now
	state.lastStep = step
	local cooldown = if step >= comboLength then stats.finish_cooldown else stats.attack_cooldown
	state.cooldownUntil = now + cooldown

	task.delay(hitDelay, function()
		if not player.Parent then
			return
		end
		resolveHit(player, step, stats)
	end)
end)

Players.PlayerAdded:Connect(hookPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(hookPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	attackState[player] = nil
end)

print("FistWeapon: готов (" .. template:GetFullName() .. ")")
