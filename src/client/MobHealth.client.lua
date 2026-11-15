--!strict
-- Шкала HP над обычными мобами (атрибут ShowMobHealthBar) + искры при уроне.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local HealthBar = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HealthBar"))

local BAR_WIDTH = 80
local BAR_HEIGHT = 11
local BILLBOARD_OFFSET = Vector3.new(0, 2.8, 0)

type MobEntry = {
	bar: any,
	billboard: BillboardGui,
	healthConn: RBXScriptConnection?,
	maxConn: RBXScriptConnection?,
	ancestryConn: RBXScriptConnection?,
	lastHealth: number,
}

local tracked: { [Model]: MobEntry } = {}

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

	local adornee: BasePart? = nil
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		adornee = head
	else
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			adornee = root
		else
			adornee = model.PrimaryPart
		end
	end
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
	billboard.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT + 6)
	billboard.StudsOffsetWorldSpace = BILLBOARD_OFFSET
	billboard.MaxDistance = 80
	billboard.Adornee = adornee
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
	}
	tracked[model] = entry

	local function sync()
		bar.SetHealth(humanoid.Health, humanoid.MaxHealth)
	end
	sync()

	entry.healthConn = humanoid.HealthChanged:Connect(function(hp)
		if hp < entry.lastHealth - 0.05 then
			emitSparks(model)
		end
		entry.lastHealth = hp
		bar.SetHealth(hp, humanoid.MaxHealth)
		if hp <= 0 then
			billboard.Enabled = false
		else
			billboard.Enabled = true
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
