--!strict
-- Манекен у спавна: стоит на месте, держит топор, бьёт при сближении.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local CombatDefence = require(ServerScriptService:WaitForChild("CombatDefence"))

local TrainingDummy = {}

local AGGRO_RANGE = 12
local ATTACK_RANGE = 6.5
local ATTACK_COOLDOWN = 1.35
local ATTACK_DAMAGE = 12
local HIT_DELAY = 0.18
local SWING_TIME = 0.16
local RECOVER_TIME = 0.22
local DUMMY_MAX_HP = 200

local started = false
local activeModel: Model? = nil
local aiToken = 0

local function flatDist(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function preparePart(part: BasePart)
	part.CanCollide = false
	part.Anchored = false
	part.Massless = true
	part.CanQuery = true
	part.CanTouch = false
end

local function attachAxe(model: Model, rightArm: BasePart)
	local assets = ReplicatedStorage:FindFirstChild("assets")
	local template = assets and assets:FindFirstChild("Axe")
	local visual: BasePart? = nil
	if template and template:IsA("BasePart") then
		visual = template:Clone()
	elseif template and template:IsA("Model") then
		local src = template:FindFirstChildWhichIsA("BasePart", true)
		if src then
			visual = src:Clone()
		end
	end
	if not visual then
		visual = Instance.new("Part")
		visual.Size = Vector3.new(0.35, 2.2, 0.7)
		visual.Color = Color3.fromRGB(120, 90, 55)
		visual.Material = Enum.Material.Wood
	end
	visual.Name = "HeldAxe"
	visual.Transparency = 0
	preparePart(visual)
	visual.Parent = model

	local weld = Instance.new("Weld")
	weld.Name = "HeldAxeWeld"
	weld.Part0 = rightArm
	weld.Part1 = visual
	-- Грубая посадка в руке манекена (не игрок — Grip не трогаем).
	weld.C0 = CFrame.new(0, -1.05, -0.15) * CFrame.Angles(math.rad(-20), math.rad(-90), math.rad(10))
	weld.C1 = CFrame.new()
	weld.Parent = visual
end

local function nearestPlayerRoot(origin: Vector3): (Player?, BasePart?)
	local bestPlayer: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDist = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				local d = flatDist(origin, root.Position)
				if d < bestDist then
					bestDist = d
					bestPlayer = player
					bestRoot = root
				end
			end
		end
	end
	return bestPlayer, bestRoot
end

local function faceToward(model: Model, root: BasePart, target: Vector3)
	local pos = root.Position
	local flat = Vector3.new(target.X, pos.Y, target.Z)
	if (flat - pos).Magnitude < 0.05 then
		return
	end
	model:PivotTo(CFrame.lookAt(pos, flat))
end

local function swingArm(rightArm: BasePart, root: BasePart, onHit: (() -> ())?)
	local armLocal = root.CFrame:ToObjectSpace(rightArm.CFrame)
	local windup = root.CFrame * armLocal * CFrame.Angles(math.rad(-25), 0, math.rad(-15))
	local strike = root.CFrame * armLocal * CFrame.Angles(math.rad(-95), 0, math.rad(-10))
	local rest = root.CFrame * armLocal

	local t1 = TweenService:Create(
		rightArm,
		TweenInfo.new(SWING_TIME * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = windup }
	)
	t1:Play()
	t1.Completed:Wait()
	if not rightArm.Parent then
		return
	end
	local t2 = TweenService:Create(
		rightArm,
		TweenInfo.new(SWING_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = strike }
	)
	t2:Play()
	t2.Completed:Wait()
	if onHit then
		onHit()
	end
	task.wait(HIT_DELAY * 0.35)
	if not rightArm.Parent then
		return
	end
	local t3 = TweenService:Create(
		rightArm,
		TweenInfo.new(RECOVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = rest }
	)
	t3:Play()
	t3.Completed:Wait()
end

local function runAi(model: Model, surfaceY: (number, number) -> number)
	aiToken += 1
	local token = aiToken
	local root = model:FindFirstChild("HumanoidRootPart")
	local rightArm = model:FindFirstChild("Right Arm")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and rightArm and rightArm:IsA("BasePart") and humanoid) then
		return
	end

	local lastAttack = 0
	local attacking = false
	local home = Vector3.new(root.Position.X, root.Position.Y, root.Position.Z)

	task.spawn(function()
		while token == aiToken and model.Parent and humanoid.Health > 0 do
			local _, targetRoot = nearestPlayerRoot(root.Position)
			if targetRoot and not attacking then
				local dist = flatDist(root.Position, targetRoot.Position)
				if dist <= AGGRO_RANGE then
					faceToward(model, root, targetRoot.Position)
					-- Держим точку на земле (на случай PivotTo).
					local ground = surfaceY(home.X, home.Z)
					local pos = root.Position
					if math.abs(pos.X - home.X) > 0.05 or math.abs(pos.Z - home.Z) > 0.05 then
						model:PivotTo(CFrame.new(home.X, ground + 3, home.Z) * (root.CFrame - root.CFrame.Position))
					end

					local now = os.clock()
					if dist <= ATTACK_RANGE and now - lastAttack >= ATTACK_COOLDOWN then
						lastAttack = now
						attacking = true
						task.spawn(function()
							faceToward(model, root, targetRoot.Position)
							swingArm(rightArm, root, function()
								if token ~= aiToken or not model.Parent or humanoid.Health <= 0 then
									return
								end
								local _, stillNear = nearestPlayerRoot(root.Position)
								if stillNear and flatDist(root.Position, stillNear.Position) <= ATTACK_RANGE + 1.5 then
									local victimModel = stillNear.Parent
									if victimModel and victimModel:IsA("Model") then
										-- Обычный моб: при блоке урон в defence, иначе в HP.
										CombatDefence.ApplyDamage(victimModel, ATTACK_DAMAGE)
									end
								end
							end)
							attacking = false
						end)
					end
				end
			end
			task.wait(0.12)
		end
	end)
end

function TrainingDummy.Ensure(surfaceY: (number, number) -> number)
	local old = workspace:FindFirstChild("TrainingDummy")
	if old then
		old:Destroy()
	end
	activeModel = nil
	aiToken += 1

	local x, z = 14, 0
	local ground = surfaceY(x, z)

	local model = Instance.new("Model")
	model.Name = "TrainingDummy"
	model:SetAttribute("ShowMobHealthBar", true)
	model:SetAttribute("MobKind", "normal")

	local function addPart(name: string, size: Vector3, offset: Vector3, color: Color3): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Anchored = true
		part.CanCollide = true
		part.Massless = true
		part.Material = Enum.Material.SmoothPlastic
		part.Color = color
		part.CFrame = CFrame.new(x, ground, z) * CFrame.new(offset)
		part.Parent = model
		return part
	end

	local root = addPart("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), Color3.fromRGB(190, 150, 110))
	addPart("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), Color3.fromRGB(220, 180, 140))
	addPart("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), Color3.fromRGB(190, 150, 110))
	local rightArm = addPart("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), Color3.fromRGB(190, 150, 110))
	addPart("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), Color3.fromRGB(80, 90, 120))
	addPart("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), Color3.fromRGB(80, 90, 120))

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.MaxHealth = DUMMY_MAX_HP
	humanoid.Health = DUMMY_MAX_HP
	humanoid.DisplayName = "Dummy"
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.Parent = model

	model.PrimaryPart = root
	attachAxe(model, rightArm)
	model.Parent = workspace
	activeModel = model

	humanoid.Died:Connect(function()
		task.delay(1.5, function()
			TrainingDummy.Ensure(surfaceY)
		end)
	end)

	runAi(model, surfaceY)
end

function TrainingDummy.Start(surfaceY: (number, number) -> number)
	if started then
		return
	end
	started = true
	TrainingDummy.Ensure(surfaceY)
end

return TrainingDummy
