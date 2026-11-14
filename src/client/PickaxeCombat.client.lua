--!strict
-- Удар Pickaxe: анимация Action3 из items_config + PickaxeAttack.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DEFAULT_ANIM_ID = "rbxassetid://117674721132335"
local SWING_PRIORITY = Enum.AnimationPriority.Action3
local DEFAULT_ATTACK_COOLDOWN = 0.55
local ATTR_ATTACK_CD = "AttackCooldown"
local ATTR_SWING_ANIM = "SwingAnimation"
local TOOL_NAME = "Pickaxe"

local player = Players.LocalPlayer

local attackRemote: RemoteEvent? = nil

local function getAttackRemote(): RemoteEvent?
	if attackRemote and attackRemote.Parent then
		return attackRemote
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = ReplicatedStorage:WaitForChild("Remotes", 60)
	end
	if not remotes then
		warn("PickaxeCombat client: нет Remotes")
		return nil
	end
	local remote = remotes:FindFirstChild("PickaxeAttack")
	if not (remote and remote:IsA("RemoteEvent")) then
		remote = remotes:WaitForChild("PickaxeAttack", 60)
	end
	if remote and remote:IsA("RemoteEvent") then
		attackRemote = remote
		return attackRemote
	end
	warn("PickaxeCombat client: нет PickaxeAttack")
	return nil
end

task.spawn(getAttackRemote)

local swingTrack: AnimationTrack? = nil
local loadedAnimId: string? = nil
local equippedTool: Tool? = nil
local cooldownUntil = 0
local characterConns: { RBXScriptConnection } = {}
local toolConns: { RBXScriptConnection } = {}

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

local function animIdFor(tool: Tool): string
	local attr = tool:GetAttribute(ATTR_SWING_ANIM)
	if typeof(attr) == "string" and attr ~= "" then
		return attr
	end
	return DEFAULT_ANIM_ID
end

local function ensureTrack(character: Model, tool: Tool): AnimationTrack?
	local wantId = animIdFor(tool)
	if swingTrack and swingTrack.Parent and loadedAnimId == wantId then
		swingTrack.Priority = SWING_PRIORITY
		swingTrack.Looped = false
		return swingTrack
	end
	if swingTrack then
		swingTrack:Stop(0)
		swingTrack = nil
		loadedAnimId = nil
	end
	local animator = getAnimator(character)
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = wantId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or typeof(track) ~= "Instance" then
		warn("PickaxeCombat client: анимация не загрузилась")
		return nil
	end
	local animTrack = track :: AnimationTrack
	animTrack.Priority = SWING_PRIORITY
	animTrack.Looped = false
	swingTrack = animTrack
	loadedAnimId = wantId
	return animTrack
end

local function clearToolConns()
	for _, conn in ipairs(toolConns) do
		conn:Disconnect()
	end
	table.clear(toolConns)
end

local function clearCharacterConns()
	for _, conn in ipairs(characterConns) do
		conn:Disconnect()
	end
	table.clear(characterConns)
end

local function onUnequipped()
	equippedTool = nil
	clearToolConns()
	if swingTrack then
		swingTrack:Stop(0.05)
	end
	swingTrack = nil
	loadedAnimId = nil
	cooldownUntil = 0
end

local function tryAttack()
	local character = player.Character
	if not character then
		return
	end
	local tool = equippedTool
	if not tool or tool.Parent ~= character then
		local inHand = character:FindFirstChild(TOOL_NAME)
		if inHand and inHand:IsA("Tool") then
			tool = inHand
			equippedTool = tool
		else
			return
		end
	end

	local now = os.clock()
	if now < cooldownUntil then
		return
	end
	local cdAttr = tool:GetAttribute(ATTR_ATTACK_CD)
	local cooldown = if typeof(cdAttr) == "number" then cdAttr else DEFAULT_ATTACK_COOLDOWN
	cooldownUntil = now + cooldown

	local track = ensureTrack(character, tool)
	if track then
		track.Priority = SWING_PRIORITY
		track.Looped = false
		track:Stop(0)
		track:Play(0.05)
	end

	local remote = getAttackRemote()
	if remote then
		remote:FireServer()
	end
end

local function onEquipped(tool: Tool, character: Model)
	onUnequipped()
	equippedTool = tool
	ensureTrack(character, tool)
	getAttackRemote()

	table.insert(toolConns, tool.Activated:Connect(tryAttack))
	table.insert(toolConns, tool.Unequipped:Connect(function()
		if equippedTool == tool then
			onUnequipped()
		end
	end))
end

local function hookCharacter(character: Model)
	clearCharacterConns()
	onUnequipped()

	table.insert(characterConns, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			onEquipped(child, character)
		end
	end))
	table.insert(characterConns, character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child.Name == TOOL_NAME and equippedTool == child then
			onUnequipped()
		end
	end))

	local already = character:FindFirstChild(TOOL_NAME)
	if already and already:IsA("Tool") then
		onEquipped(already, character)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local character = player.Character
	if not character or not character:FindFirstChild(TOOL_NAME) then
		return
	end
	tryAttack()
end)

player.CharacterAdded:Connect(hookCharacter)
if player.Character then
	hookCharacter(player.Character)
end

print("PickaxeCombat client: готов")
