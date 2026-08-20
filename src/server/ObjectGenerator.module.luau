local ObjectGenerator = {}

function ObjectGenerator.Generate()

	-- 2. Настройки генерации
	local Terrain = workspace.Terrain
	local RepStorage = game:GetService("ReplicatedStorage")
	local MapSize = 2000
	local ChunkSize = 256
	local VoxelRes = 4

	-- Функция ТОЧНОГО поиска поверхности через Raycast
	local function getExactSurfaceY(x, z)
		local startPos = Vector3.new(x, 200, z)
		local direction = Vector3.new(0, -300, 0)

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = {Terrain}

		local result = workspace:Raycast(startPos, direction, rayParams)

		if result then
			return result.Position.Y
		else
			return nil
		end
	end

	-- Ищем шаблоны деревьев
	local assetsFolder = RepStorage:FindFirstChild("assets")
	local ThinTreeTemplate = assetsFolder and assetsFolder:FindFirstChild("BigTree")
	local MegaTreeTemplate = assetsFolder and assetsFolder:FindFirstChild("MegaTree")

	if not ThinTreeTemplate then
		warn("⚠️ НЕ НАШЕЛ BigTree В assets!")
		return
	end

	print("🌲 Начинаю генерацию с Raycast...")
	local startTime = tick()
	local ThinTreeCount = 0
	local MegaTreeCount = 0
	local StickCount = 0

	local ALLOWED = {
		[Enum.Material.Grass] = true,
		[Enum.Material.Mud] = true,
		[Enum.Material.LeafyGrass] = true,
		[Enum.Material.Sand] = true
	}

	for startX = -MapSize/2, MapSize/2 - ChunkSize, ChunkSize do
		for startZ = -MapSize/2, MapSize/2 - ChunkSize, ChunkSize do

			local region = Region3.new(
				Vector3.new(startX, -50, startZ),
				Vector3.new(startX + ChunkSize, 100, startZ + ChunkSize)
			):ExpandToGrid(VoxelRes)

			local rMin = region.CFrame.Position - (region.Size / 2)
			local materials = Terrain:ReadVoxels(region, VoxelRes)

			if materials then
				local sizeX = #materials
				local sizeY = #materials[1]
				local sizeZ = #materials[1][1]

				for xi = 1, sizeX do
					for zi = 1, sizeZ do

						-- Базовая высота для деревьев (через воксели)
						local baseY = nil
						for yi = sizeY, 1, -1 do
							local mat = materials[xi][yi][zi]
							if mat ~= Enum.Material.Air and mat ~= Enum.Material.Water then
								if ALLOWED[mat] then
									baseY = rMin.Y + (yi - 1) * VoxelRes
									break
								else
									break
								end
							end
						end

						if baseY then
							local worldX = rMin.X + (xi - 1) * VoxelRes
							local worldZ = rMin.Z + (zi - 1) * VoxelRes
							local rand = math.random()

							-- 1. ТОНКИЕ ДЕРЕВЬЯ (0.4%)
							if rand < 0.004 then
								local newTree = ThinTreeTemplate:Clone()
								
								-- Страховка PrimaryPart
								if not newTree.PrimaryPart then
									newTree.PrimaryPart = newTree:FindFirstChildWhichIsA("BasePart")
								end
								
								pcall(function() newTree:ScaleTo(Vector3.new(0.35, 0.35, 0.35)) end)
								
								if newTree.PrimaryPart then
									newTree:SetPrimaryPartCFrame(CFrame.new(worldX, baseY + 20, worldZ))
									newTree.Parent = workspace
									ThinTreeCount += 1

									-- Ветка рядом
									if math.random() < 0.6 then
										local angle = math.random() * math.pi * 2
										local dist = math.random(2, 4)
										local sx = worldX + math.cos(angle) * dist
										local sz = worldZ + math.sin(angle) * dist

										local sy = getExactSurfaceY(sx, sz)
										if sy then
											local stick = Instance.new("Part")
											stick.Size = Vector3.new(0.8, 0.2, 0.2)
											stick.Anchored = true
											stick.Color = Color3.fromRGB(120, 80, 40)
											stick.Shape = Enum.PartType.Cylinder
											stick.CanCollide = false
											stick.Name = "Stick"
											stick.CFrame = CFrame.new(sx, sy + 0.1, sz) * CFrame.Angles(0, 0, math.rad(math.random(-25, 25)))
											stick.Parent = workspace
											StickCount += 1
										end
									end
								end

							-- 2. МЕГА-ДЕРЕВЬЯ (0.5% - с программным якорем Soil)
							elseif rand < 0.005 then
								if MegaTreeTemplate then
									local megaTree = MegaTreeTemplate:Clone()
									
									-- Создаем невидимый якорь Soil
									local soil = Instance.new("Part")
									soil.Name = "Soil"
									soil.Size = Vector3.new(1, 1, 1)
									soil.Transparency = 1
									soil.Anchored = true
									soil.CanCollide = false
									soil.Parent = megaTree
									
									megaTree.PrimaryPart = soil
									
									-- Масштабируем до гигантских размеров
									pcall(function() megaTree:ScaleTo(Vector3.new(2.5, 2.5, 2.5)) end)
									
									-- Ставим якорь ровно на землю (+0.5 чтобы не провалился)
									megaTree:SetPrimaryPartCFrame(CFrame.new(worldX, baseY + 0.5, worldZ))
									megaTree.Parent = workspace
									MegaTreeCount += 1
								else
									warn("⚠️ НЕ НАШЕЛ MegaTree В assets!")
								end

							-- 3. ОТДЕЛЬНЫЕ ВЕТКИ (1.5%)
							elseif rand < 0.019 then
								local sy = getExactSurfaceY(worldX, worldZ)
								if sy then
									local stick = Instance.new("Part")
									stick.Size = Vector3.new(0.8, 0.2, 0.2)
									stick.Anchored = true
									stick.Color = Color3.fromRGB(120, 80, 40)
									stick.Shape = Enum.PartType.Cylinder
									stick.CanCollide = false
									stick.Name = "Stick"
									stick.CFrame = CFrame.new(worldX, sy + 0.1, worldZ) * CFrame.Angles(0, 0, math.rad(math.random(-30, 30)))
									stick.Parent = workspace
									StickCount += 1
								end
							end
						end
					end
				end
			end

			if startX % 500 == 0 and startZ % 500 == 0 then
				print(string.format("Чанк [%.0f, %.0f] | Тонких: %d Мега: %d Веток: %d", 
					startX, startZ, ThinTreeCount, MegaTreeCount, StickCount))
				wait()
			end
		end
	end

	print("✅ ВСЁ ГОТОВО!")
	print(string.format(" Время: %.2f сек | 🌱 Тонких: %d | 🌳 Мега: %d | 🥢 Веток: %d", 
		tick() - startTime, ThinTreeCount, MegaTreeCount, StickCount))
end

return ObjectGenerator