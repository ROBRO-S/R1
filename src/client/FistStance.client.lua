--!strict
-- Стойка, блок и комбо-удары FistWeapon: клиентские анимации + remotes на сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- === ID анимаций ===
local STANCE_ANIM_ID = "rbxassetid://108577822156162"
local STANCE_PRIORITY = Enum.AnimationPriority.Action

local BLOCK_ANIM_ID = "rbxassetid://132899316313297"
local BLOCK_PRIORITY = Enum.AnimationPriority.Action2

local PUNCH_ANIM_IDS = {
	"rbxassetid://105005161184569", -- 1-й удар
	"rbxassetid://103017786529440", -- 2-й удар
	"rbxassetid://129682755455617", -- 3-й тяжёлый удар
}
local PUNCH_PRIORITY = Enum.AnimationPriority.Action3

-- Запасные тайминги, если на Tool ещё нет атрибутов из items_config.
local DEFAULT_COMBO_RESET = 1.3
local DEFAULT_ATTACK_COOLDOWN = 0.38
local DEFAULT_FINISH_COOLDOWN = 0.8
local ATTR_COMBO_RESET = "ComboReset"
local ATTR_ATTACK_CD = "AttackCooldown"
local ATTR_FINISH_CD = "FinishCooldown"
-- ===

local TOOL_NAME = "FistWeapon"
local COMBO_LENGTH = #PUNCH_ANIM_IDS

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local blockRemote = if remotes then remotes:WaitForChild("FistBlock", 30) else nil
local attackRemote = if remotes then remotes:WaitForChild("FistAttack", 30) else nil

local stanceTrack: AnimationTrack? = nil
local blockTrack: AnimationTrack? = nil
local punchTrack: AnimationTrack? = nil
local punchTracks: { AnimationTrack? } = {}
local equippedTool: Tool? = nil
local blocking = false
local nextComboStep = 1
local lastAttackAt = 0
local cooldownUntil = 0
local characterConns: { RBXScriptConnection } = {}

local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function loadTrack(
	animator: Animator,
	animId: string,
	priority: Enum.AnimationPriority,
	looped: boolean
): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or typeof(track) ~= "Instance" then
		warn("FistStance: не загрузил анимацию " .. animId)
		return nil
	end
	local animTrack = track :: AnimationTrack
	animTrack.Priority = priority
	animTrack.Looped = looped
	return animTrack
end

local function stopTrack(track: AnimationTrack?, fadeTime: number?)
	if track then
		track:Stop(fadeTime or 0.15)
	end
end

local function stopPunch(fadeTime: number?)
	stopTrack(punchTrack, fadeTime)
	punchTrack = nil
end

local function setBlocking(active: boolean)
	if blocking == active then
		return
	end
	blocking = active

	if active then
		stopPunch(0.05)
		if blockTrack and not blockTrack.IsPlaying then
			blockTrack:Play(0.1)
		end
	else
		stopTrack(blockTrack)
	end

	if blockRemote and blockRemote:IsA("RemoteEvent") then
		blockRemote:FireServer(active)
	end
end

local function stopStanceAndBlock()
	setBlocking(false)
	stopPunch(0.05)
	stopTrack(stanceTrack)
	stopTrack(blockTrack)
	stanceTrack = nil
	blockTrack = nil
	table.clear(punchTracks)
end

local function clearCharacterConns()
	for _, conn in ipairs(characterConns) do
		conn:Disconnect()
	end
	table.clear(characterConns)
end

local function onUnequipped()
	equippedTool = nil
	stopStanceAndBlock()
	nextComboStep = 1
	lastAttackAt = 0
	cooldownUntil = 0
end

local function onEquipped(tool: Tool, character: Model)
	equippedTool = tool
	stopStanceAndBlock()
	nextComboStep = 1
	lastAttackAt = 0
	cooldownUntil = 0

	local animator = getAnimator(character)
	if not animator then
		return
	end

	stanceTrack = loadTrack(animator, STANCE_ANIM_ID, STANCE_PRIORITY, true)
	blockTrack = loadTrack(animator, BLOCK_ANIM_ID, BLOCK_PRIORITY, true)
	for i, animId in ipairs(PUNCH_ANIM_IDS) do
		punchTracks[i] = loadTrack(animator, animId, PUNCH_PRIORITY, false)
	end

	if stanceTrack then
		stanceTrack:Play(0.15)
	end
end

local function isFistEquipped(character: Model): Tool?
	local tool = character:FindFirstChild(TOOL_NAME)
	if tool and tool:IsA("Tool") then
		return tool
	end
	return nil
end

local function readNumberAttr(tool: Tool, name: string, fallback: number): number
	local value = tool:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return fallback
end

local function tryAttack()
	if blocking then
		return
	end
	if not equippedTool or equippedTool.Parent ~= player.Character then
		return
	end

	local comboReset = readNumberAttr(equippedTool, ATTR_COMBO_RESET, DEFAULT_COMBO_RESET)
	local attackCooldown = readNumberAttr(equippedTool, ATTR_ATTACK_CD, DEFAULT_ATTACK_COOLDOWN)
	local finishCooldown = readNumberAttr(equippedTool, ATTR_FINISH_CD, DEFAULT_FINISH_COOLDOWN)

	local now = os.clock()
	if now < cooldownUntil then
		return
	end

	local step = nextComboStep
	if now - lastAttackAt > comboReset then
		step = 1
	end

	local track = punchTracks[step]
	if not track then
		return
	end

	stopPunch(0.05)
	punchTrack = track
	track:Play(0.05)

	if attackRemote and attackRemote:IsA("RemoteEvent") then
		attackRemote:FireServer(step)
	end

	lastAttackAt = now
	local cooldown = if step >= COMBO_LENGTH then finishCooldown else attackCooldown
	cooldownUntil = now + cooldown
	nextComboStep = if step >= COMBO_LENGTH then 1 else step + 1
end

local function hookCharacter(character: Model)
	clearCharacterConns()
	stopStanceAndBlock()
	equippedTool = nil
	nextComboStep = 1
	lastAttackAt = 0
	cooldownUntil = 0

	local function tryEquip(tool: Instance)
		if tool:IsA("Tool") and tool.Name == TOOL_NAME then
			onEquipped(tool, character)
		end
	end

	table.insert(characterConns, character.ChildAdded:Connect(tryEquip))
	table.insert(characterConns, character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			onUnequipped()
		end
	end))

	local already = isFistEquipped(character)
	if already then
		onEquipped(already, character)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not equippedTool or equippedTool.Parent ~= player.Character then
			return
		end
		tryAttack()
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
		return
	end
	if not equippedTool or equippedTool.Parent ~= player.Character then
		return
	end
	setBlocking(true)
end)

UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
		return
	end
	if blocking then
		setBlocking(false)
	end
end)

player.CharacterAdded:Connect(hookCharacter)
if player.Character then
	hookCharacter(player.Character)
end
