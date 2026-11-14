--!strict
-- Общий hold-E сбор: анимация рук + лёгкий sway цели через TweenService.
-- Переиспользуется для BigTree → Stick и позже кустов ягод.

local HoldGather = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Зацикленная анимация сбора руками (Action3).
HoldGather.GATHER_ANIM_ID = "rbxassetid://125088678950361"
HoldGather.DEFAULT_HOLD_DURATION = 1.2

export type AttachConfig = {
	actionText: string,
	objectText: string,
	holdDuration: number?,
	maxActivationDistance: number?,
	requiresLineOfSight: boolean?,
	promptName: string?,
	keyboardKeyCode: Enum.KeyCode?,
	animationId: string?,
	swayDegrees: number?,
	swayPeriod: number?,
	onHoldBegan: ((player: Player, target: Instance) -> ())?,
	onHoldEnded: ((player: Player, target: Instance) -> ())?,
	onTriggered: (player: Player, target: Instance) -> (),
}

type PlayerHoldState = {
	track: AnimationTrack?,
	swayStop: (() -> ())?,
}

local playerState: { [Player]: PlayerHoldState } = {}

local function ensureState(player: Player): PlayerHoldState
	local state = playerState[player]
	if not state then
		state = {}
		playerState[player] = state
	end
	return state
end

-- Якорь у основания: иначе prompt на кроне/центре модели и MaxActivationDistance не дотягивается с земли.
local ATTACH_NAME = "HoldGatherAttach"

local function lowestPart(model: Model): BasePart?
	local best: BasePart? = nil
	local bestY = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local bottom = d.Position.Y - d.Size.Y * 0.5
			if bottom < bestY then
				bestY = bottom
				best = d
			end
		end
	end
	return best
end

local function ensurePromptAnchor(target: Instance): Instance?
	local existing = target:FindFirstChild(ATTACH_NAME, true)
	if existing and existing:IsA("Attachment") then
		return existing
	end

	if target:IsA("BasePart") then
		local att = Instance.new("Attachment")
		att.Name = ATTACH_NAME
		att.Position = Vector3.new(0, -target.Size.Y * 0.5 + 1.5, 0)
		att.Parent = target
		return att
	end

	if target:IsA("Model") then
		local host = lowestPart(target)
		if not host then
			return nil
		end
		local pivot = target:GetPivot().Position
		local bottomY = host.Position.Y - host.Size.Y * 0.5
		local att = Instance.new("Attachment")
		att.Name = ATTACH_NAME
		att.Parent = host
		att.WorldPosition = Vector3.new(pivot.X, bottomY + 2, pivot.Z)
		return att
	end

	return nil
end

local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	local created = Instance.new("Animator")
	created.Parent = humanoid
	return created
end

local function stopTrack(state: PlayerHoldState)
	local track = state.track
	if track then
		track:Stop(0)
		track:Destroy()
		state.track = nil
	end
end

local function stopSway(state: PlayerHoldState)
	local stop = state.swayStop
	if stop then
		state.swayStop = nil
		stop()
	end
end

function HoldGather.StopPlayer(player: Player)
	local state = playerState[player]
	if not state then
		return
	end
	stopTrack(state)
	stopSway(state)
end

local function playGatherAnim(player: Player, animId: string)
	local state = ensureState(player)
	stopTrack(state)

	local character = player.Character
	if not character then
		return
	end
	local animator = getAnimator(character)
	if not animator then
		return
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if not ok or typeof(trackOrErr) ~= "Instance" then
		return
	end

	local track = trackOrErr :: AnimationTrack
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Action3
	track:Play(0.05)
	state.track = track
end

local function readPivot(target: Instance): CFrame?
	if target:IsA("Model") then
		return target:GetPivot()
	end
	if target:IsA("BasePart") then
		return target.CFrame
	end
	return nil
end

local function writePivot(target: Instance, cf: CFrame)
	if target:IsA("Model") then
		target:PivotTo(cf)
	elseif target:IsA("BasePart") then
		target.CFrame = cf
	end
end

local function startSway(target: Instance, degrees: number, period: number): () -> ()
	local start = readPivot(target)
	if not start then
		return function() end
	end

	local stopped = false
	local alpha = Instance.new("NumberValue")
	alpha.Value = 0
	local tween = TweenService:Create(
		alpha,
		TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Value = 1 }
	)
	local angle = math.rad(degrees)
	local conn = alpha.Changed:Connect(function(v: number)
		if stopped or not target.Parent then
			return
		end
		writePivot(target, start * CFrame.Angles(angle * v * 0.55, 0, angle * v))
	end)
	tween:Play()

	return function()
		if stopped then
			return
		end
		stopped = true
		tween:Cancel()
		conn:Disconnect()
		alpha:Destroy()
		if target.Parent then
			writePivot(target, start)
		end
	end
end

function HoldGather.Attach(target: Instance, config: AttachConfig): ProximityPrompt?
	local host = ensurePromptAnchor(target)
	if not host then
		warn("HoldGather: нет якоря у", target:GetFullName())
		return nil
	end

	local promptName = config.promptName or "GatherPrompt"
	local old = host:FindFirstChild(promptName)
	if old then
		old:Destroy()
	end

	local holdDuration = if typeof(config.holdDuration) == "number"
		then config.holdDuration
		else HoldGather.DEFAULT_HOLD_DURATION
	local animId = if typeof(config.animationId) == "string" and config.animationId ~= ""
		then config.animationId
		else HoldGather.GATHER_ANIM_ID
	local maxDist = if typeof(config.maxActivationDistance) == "number"
		then config.maxActivationDistance
		else 7
	local swayDeg = if typeof(config.swayDegrees) == "number" then config.swayDegrees else 2.2
	local swayPeriod = if typeof(config.swayPeriod) == "number" then config.swayPeriod else 0.28
	local los = if config.requiresLineOfSight == nil then false else config.requiresLineOfSight

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = promptName
	prompt.ActionText = config.actionText
	prompt.ObjectText = config.objectText
	prompt.KeyboardKeyCode = config.keyboardKeyCode or Enum.KeyCode.E
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = maxDist
	prompt.RequiresLineOfSight = los
	prompt.Parent = host

	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		if not player or not player:IsA("Player") then
			return
		end
		if not target.Parent then
			return
		end
		playGatherAnim(player, animId)
		local state = ensureState(player)
		stopSway(state)
		state.swayStop = startSway(target, swayDeg, swayPeriod)
		if config.onHoldBegan then
			config.onHoldBegan(player, target)
		end
	end)

	prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		if not player or not player:IsA("Player") then
			return
		end
		-- Отпустил раньше времени — мгновенно стоп анимации и sway.
		HoldGather.StopPlayer(player)
		if config.onHoldEnded then
			config.onHoldEnded(player, target)
		end
	end)

	prompt.Triggered:Connect(function(player: Player)
		if not player or not player:IsA("Player") then
			return
		end
		HoldGather.StopPlayer(player)
		if not target.Parent then
			return
		end
		config.onTriggered(player, target)
	end)

	return prompt
end

Players.PlayerRemoving:Connect(function(player: Player)
	HoldGather.StopPlayer(player)
	playerState[player] = nil
end)

return HoldGather
