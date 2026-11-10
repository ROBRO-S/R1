--!strict
-- Стойка и блок FistWeapon: клиентские анимации + RemoteEvent блока на сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- === ID анимаций ===
local STANCE_ANIM_ID = "rbxassetid://108577822156162"
local STANCE_PRIORITY = Enum.AnimationPriority.Action

local BLOCK_ANIM_ID = "rbxassetid://132899316313297"
local BLOCK_PRIORITY = Enum.AnimationPriority.Action2
-- ===

local TOOL_NAME = "FistWeapon"

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local blockRemote = if remotes then remotes:WaitForChild("FistBlock", 30) else nil

local stanceTrack: AnimationTrack? = nil
local blockTrack: AnimationTrack? = nil
local equippedTool: Tool? = nil
local blocking = false
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

local function loadTrack(animator: Animator, animId: string, priority: Enum.AnimationPriority): AnimationTrack?
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
	animTrack.Looped = true
	return animTrack
end

local function stopTrack(track: AnimationTrack?)
	if track then
		track:Stop(0.15)
	end
end

local function setBlocking(active: boolean)
	if blocking == active then
		return
	end
	blocking = active

	if active then
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
	stopTrack(stanceTrack)
	stopTrack(blockTrack)
	stanceTrack = nil
	blockTrack = nil
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
end

local function onEquipped(tool: Tool, character: Model)
	equippedTool = tool
	stopStanceAndBlock()

	local animator = getAnimator(character)
	if not animator then
		return
	end

	stanceTrack = loadTrack(animator, STANCE_ANIM_ID, STANCE_PRIORITY)
	blockTrack = loadTrack(animator, BLOCK_ANIM_ID, BLOCK_PRIORITY)

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

local function hookCharacter(character: Model)
	clearCharacterConns()
	stopStanceAndBlock()
	equippedTool = nil

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
