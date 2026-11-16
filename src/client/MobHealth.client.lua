--!strict
-- Шкала HP над мобами: появляется с первого удара + цифры урона.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HealthBar = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HealthBar"))

-- Как у игрока (сердце + цифры), чуть компактнее экранной шкалы.
local BAR_WIDTH = 96
local BAR_HEIGHT = 12
local BILLBOARD_OFFSET = Vector3.new(0, 2.6, 0)
local DAMAGE_FADE = 0.7

type MobEntry = {
	bar: any,
	billboard: BillboardGui,
	healthConn: RBXScriptConnection?,
	maxConn: RBXScriptConnection?,
	ancestryConn: RBXScriptConnection?,
	lastHealth: number,
	revealed: boolean,
}

local tracked: { [Model]: MobEntry } = {}

local function resolveAdornee(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

local function emitSparks(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		root = model.PrimaryPart
	end
	if not (root and root:IsA("BasePart")) then
		return
	end

	local att = root:FindFirstChild("DamageSparks")
	if not (att and att:IsA("Attachment")) then
		att = Instance.new("Attachment")
		att.Name = "DamageSparks"
		att.Parent = root

		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Sparks"
		pe.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 120)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 140, 40)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 30)),
		})
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.22),
			NumberSequenceKeypoint.new(1, 0.02),
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Speed = NumberRange.new(6, 12)
		pe.Lifetime = NumberRange.new(0.25, 0.45)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Acceleration = Vector3.new(0, -20, 0)
		pe.LightEmission = 0.6
		pe.Rate = 0
		pe.Parent = att
	end

	local pe = (att :: Attachment):FindFirstChildOfClass("ParticleEmitter")
	if pe then
		pe:Emit(10)
	end
end

local function spawnDamageNumber(model: Model, amount: number)
	local adornee = resolveAdornee(model)
	if not adornee then
		return
	end

	local dealt = math.max(1, math.floor(amount + 0.5))
	local gui = Instance.new("BillboardGui")
	gui.Name = "DamageNumber"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(72, 28)
	gui.MaxDistance = 90
	gui.Adornee = adornee
	gui.StudsOffsetWorldSpace = Vector3.new(
		(math.random() - 0.5) * 1.6,
		1.1 + math.random() * 0.4,
		(math.random() - 0.5) * 0.6
	)
	gui.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 230, 200)
	label.TextStrokeColor3 = Color3.fromRGB(40, 20, 10)
	label.TextStrokeTransparency = 0.45
	label.TextTransparency = 0.28
	label.Text = tostring(dealt)
	label.Parent = gui

	local startOffset = gui.StudsOffsetWorldSpace
	local goalOffset = startOffset + Vector3.new((math.random() - 0.5) * 0.5, 1.6, 0)

	local move = TweenService:Create(
		gui,
		TweenInfo.new(DAMAGE_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = goalOffset }
	)
	local fade = TweenService:Create(
		label,
		TweenInfo.new(DAMAGE_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	move:Play()
	fade:Play()
	fade.Completed:Connect(function()
		gui:Destroy()
	end)
end

local function untrack(model: Model)
	local entry = tracked[model]
	if not entry then
		return
	end
	tracked[model] = nil
	if entry.healthConn then
		entry.healthConn:Disconnect()
	end
	if entry.maxConn then
		entry.maxConn:Disconnect()
	end
	if entry.ancestryConn then
		entry.ancestryConn:Disconnect()
	end
	entry.bar.Destroy()
	entry.billboard:Destroy()
end

local function track(model: Model)
	if tracked[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local adornee = resolveAdornee(model)
	if not adornee then
		return
	end

	-- Прячем стандартный HP Roblox.
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MobHealthBar"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(BAR_WIDTH + 8, BAR_HEIGHT + 10)
	billboard.StudsOffsetWorldSpace = BILLBOARD_OFFSET
	billboard.MaxDistance = 80
	billboard.Adornee = adornee
	billboard.Enabled = false
	billboard.Parent = model

	local bar = HealthBar.Create(billboard, {
		Width = BAR_WIDTH,
		Height = BAR_HEIGHT,
		Icon = "heart",
		Palette = "health",
		ShowLabel = true,
		ZIndex = 5,
	})
	bar.Root.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Root.Position = UDim2.fromScale(0.5, 0.5)

	local entry: MobEntry = {
		bar = bar,
		billboard = billboard,
		healthConn = nil,
		maxConn = nil,
		ancestryConn = nil,
		lastHealth = humanoid.Health,
		revealed = false,
	}
	tracked[model] = entry

	local function sync()
		bar.SetHealth(humanoid.Health, humanoid.MaxHealth)
	end
	sync()

	entry.healthConn = humanoid.HealthChanged:Connect(function(hp)
		local dealt = entry.lastHealth - hp
		if dealt > 0.05 then
			if not entry.revealed then
				entry.revealed = true
			end
			billboard.Enabled = true
			emitSparks(model)
			spawnDamageNumber(model, dealt)
		end
		entry.lastHealth = hp
		bar.SetHealth(hp, humanoid.MaxHealth)
		if hp <= 0 then
			billboard.Enabled = false
		end
	end)
	entry.maxConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(sync)
	entry.ancestryConn = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			untrack(model)
		end
	end)
end

local function consider(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	if inst:GetAttribute("ShowMobHealthBar") ~= true then
		return
	end
	-- Не вешаем шкалу на локального игрока.
	if Players:GetPlayerFromCharacter(inst) then
		return
	end
	task.defer(track, inst)
end

for _, child in ipairs(Workspace:GetDescendants()) do
	consider(child)
end

Workspace.DescendantAdded:Connect(function(inst)
	consider(inst)
	if inst:IsA("Model") then
		inst:GetAttributeChangedSignal("ShowMobHealthBar"):Connect(function()
			if inst:GetAttribute("ShowMobHealthBar") == true then
				consider(inst)
			else
				untrack(inst)
			end
		end)
	end
end)
