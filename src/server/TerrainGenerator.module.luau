local TerrainGenerator = {}

function TerrainGenerator.Generate()
	local Terrain = workspace.Terrain
	local MapSize = 2000
	local Resolution = 4
	local BaseHeight = 10

	-- НАСТРОЙКА ВОДОЕМОВ:
	-- PondLevel: все, что ниже этой высоты, - кандидат в пруд (меньше число = меньше прудов)
	-- WaterWorldY: плоский уровень воды, ОБЯЗАТЕЛЬНО минимум на 6 студиов ниже PondLevel
	local PondLevel = BaseHeight - 6
	local WaterWorldY = PondLevel - 6

	-- Удаляем Baseplate
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
		print("🗑️ Baseplate удален")
	end

	local function getHeight(x, z)
		local scale1 = 0.008
		local scale2 = 0.03
		local amplitude1 = 15
		local amplitude2 = 5

		local noise1 = math.noise(x * scale1, 0, z * scale1) * amplitude1
		local noise2 = math.noise(x * scale2, 100, z * scale2) * amplitude2

		return BaseHeight + noise1 + noise2
	end

	local function getMaterial(x, z, height)
		if x > 600 and z > 600 then
			return Enum.Material.Sand
		end

		if height > BaseHeight + 12 then
			return Enum.Material.Rock
		elseif height < BaseHeight - 12 then
			return Enum.Material.Mud
		else
			return Enum.Material.Grass
		end
	end

	-- ВЫРЕЗАНИЕ ПРУДОВ в самых глубоких низинах
	local function CarvePonds()
		print("💧 Вырезаю пруды в низинах...")
		local Chunk = 256
		local waterColumns = 0

		for startX = -MapSize/2, MapSize/2 - Chunk, Chunk do
			for startZ = -MapSize/2, MapSize/2 - Chunk, Chunk do

				local region = Region3.new(
					Vector3.new(startX, -50, startZ),
					Vector3.new(startX + Chunk, 100, startZ + Chunk)
				):ExpandToGrid(Resolution)

				local rMin = region.CFrame.Position - (region.Size / 2)
				local materials, occupancy = Terrain:ReadVoxels(region, Resolution)
				if not materials then continue end

				local sizeX = #materials
				local sizeY = #materials[1]
				local sizeZ = #materials[1][1]

				-- Плоский уровень воды в индексах вокселей этого чанка
				local waterLevel = math.floor((WaterWorldY - rMin.Y) / Resolution) + 1

				-- ПРОХОД 1: карта высот + маска пруда по ВЫСОТЕ ландшафта
				local surfaceGrid = {}
				local mask = {}
				for xi = 1, sizeX do
					surfaceGrid[xi] = {}
					mask[xi] = {}
					for zi = 1, sizeZ do
						local sY = 0
						for yi = sizeY, 1, -1 do
							local mat = materials[xi][yi][zi]
							if mat ~= Enum.Material.Air then
								sY = yi
								break
							end
						end
						surfaceGrid[xi][zi] = sY

						local m = false
						local worldX = rMin.X + (xi - 1) * Resolution
						local worldZ = rMin.Z + (zi - 1) * Resolution
						if not (worldX > 600 and worldZ > 600) then
							local h = getHeight(worldX, worldZ)
							if h < PondLevel and sY >= 4 then
								local topMat = materials[xi][sY][zi]
								if topMat ~= Enum.Material.Rock and topMat ~= Enum.Material.Sand then
									m = true
								end
							end
						end
						mask[xi][zi] = m
					end
				end

				-- ПРОХОД 2: связные области = отдельные пруды
				local visited = {}
				for xi = 1, sizeX do visited[xi] = {} end
				local changed = false

				for xi = 1, sizeX do
					for zi = 1, sizeZ do
						if mask[xi][zi] and not visited[xi][zi] then
							local stack = {{xi, zi}}
							visited[xi][zi] = true
							local cells = {}
							local rimMin = math.huge

							while #stack > 0 do
								local cur = table.remove(stack)
								local cx, cz = cur[1], cur[2]
								table.insert(cells, cur)

								for _, d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
									local nx, nz = cx + d[1], cz + d[2]
									if nx >= 1 and nx <= sizeX and nz >= 1 and nz <= sizeZ then
										if mask[nx][nz] then
											if not visited[nx][nz] then
												visited[nx][nz] = true
												table.insert(stack, {nx, nz})
											end
										else
											local ns = surfaceGrid[nx][nz]
											if ns > 0 and ns < rimMin then
												rimMin = ns
											end
										end
									end
								end
							end

							-- Пруд: не лужа и вода ниже кромки берега
							if #cells >= 6 and rimMin > waterLevel then
								for _, c in ipairs(cells) do
									local cx, cz = c[1], c[2]
									local sY = surfaceGrid[cx][cz]
									local worldX = rMin.X + (cx - 1) * Resolution
									local worldZ = rMin.Z + (cz - 1) * Resolution
									local h = getHeight(worldX, worldZ)

									-- Глубина чаши: ниже земля = глубже пруд
									local depthUnder = math.clamp(2 + math.floor((PondLevel - h) / 3), 2, 6)

									if depthUnder <= 2 then
										-- БЕРЕГ: песчаная полка в уровень воды
										for yi = waterLevel + 1, sY do
											materials[cx][yi][cz] = Enum.Material.Air
										end
										if waterLevel >= 1 and waterLevel <= sizeY then
											materials[cx][waterLevel][cz] = Enum.Material.Sand
										end
									else
										-- ВОДА: плоское зеркало + песчаное дно
										local bottom = waterLevel - depthUnder
										if bottom < 2 then bottom = 2 end

										for yi = waterLevel + 1, sY do
											materials[cx][yi][cz] = Enum.Material.Air
										end
										for yi = bottom + 1, waterLevel do
											materials[cx][yi][cz] = Enum.Material.Water
										end
										materials[cx][bottom][cz] = Enum.Material.Sand
										waterColumns += 1
									end
									changed = true
								end
							end
						end
					end
				end

				if changed then
					Terrain:WriteVoxels(region, Resolution, materials, occupancy)
				end
			end
		end

		print(string.format("✅ Колонок воды: %d", waterColumns))
	end

	print("=== ГЕНЕРАЦИЯ ЛАНДШАФТА ===")
	print("Размер: " .. MapSize .. "x" .. MapSize)

	local startTime = tick()
	local cellsGenerated = 0

	for x = -MapSize/2, MapSize/2, Resolution do
		for z = -MapSize/2, MapSize/2, Resolution do
			local height = getHeight(x, z)
			local material = getMaterial(x, z, height)

			local region = Region3.new(
				Vector3.new(x, -50, z),
				Vector3.new(x + Resolution, height, z + Resolution)
			)

			Terrain:FillRegion(region, Resolution, material)
			cellsGenerated = cellsGenerated + 1

			if cellsGenerated % 5000 == 0 then
				print("Прогресс: " .. cellsGenerated .. " ячеек")
				wait()
			end
		end
	end

	CarvePonds()

	local endTime = tick()
	print("✓ Генерация завершена!")
	print("Время: " .. string.format("%.2f", endTime - startTime) .. " сек")
	print("Ячеек: " .. cellsGenerated)
	print("Не забудь сохранить Place (Ctrl+S)!")
end

return TerrainGenerator