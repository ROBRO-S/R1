local TerrainGenerator = {}

function TerrainGenerator.Generate()
	-- Создай Script в ServerScriptService
	-- Этот скрипт будет запускаться ТОЛЬКО когда ты явно его вызовешь

	local ConfigLoader = require(script.Parent:WaitForChild("ConfigLoader"))
	local cfg = ConfigLoader.Get()
	local terrainCfg = cfg.terrain

	local Terrain = workspace.Terrain
	local MapSize = cfg.map_size
	local Resolution = cfg.voxel_res
	local BaseHeight = cfg.base_height
	local PondLevel = cfg.pond_level
	local WaterWorldY = cfg.water_world_y
	-- Зеркало не выше обоих порогов. pond_depth и pond_rim режут широкие озёра до ям.
	local WaterCap = math.min(PondLevel, WaterWorldY)
	local PondDepth = terrainCfg.pond_depth
	local PondRim = terrainCfg.pond_rim

	local function getHeight(x, z)
		local scale1 = terrainCfg.noise_scale_1
		local scale2 = terrainCfg.noise_scale_2
		local amplitude1 = terrainCfg.noise_amplitude_1
		local amplitude2 = terrainCfg.noise_amplitude_2

		local noise1 = math.noise(x * scale1, terrainCfg.noise_seed_y, z * scale1) * amplitude1
		local noise2 = math.noise(x * scale2, terrainCfg.noise_offset_2, z * scale2) * amplitude2

		return BaseHeight + noise1 + noise2
	end

	local function getMaterial(x, z, height)
		if x > terrainCfg.sand_min_x and z > terrainCfg.sand_min_z then
			return Enum.Material.Sand
		end

		-- Скала выше порога, остальное трава. Грязь только у настоящей ямы.
		if height > terrainCfg.rock_level then
			return Enum.Material.Rock
		else
			return Enum.Material.Grass
		end
	end

	-- Пруд только там, где точка заметно ниже обода. Ровная низина водой не заливается.
	local function bowlSurface(x, z, height)
		local rim = PondRim
		local surround = (
			getHeight(x - rim, z) + getHeight(x + rim, z)
			+ getHeight(x, z - rim) + getHeight(x, z + rim)
		) / 4
		local half = rim * 0.5
		local close = (
			getHeight(x - half, z) + getHeight(x + half, z)
			+ getHeight(x, z - half) + getHeight(x, z + half)
		) / 4
		local lip = math.min(surround, close)
		if lip - height < PondDepth then
			return nil
		end
		local surface = math.min(WaterCap, lip - 0.5)
		if surface - height < 1 then
			return nil
		end
		return surface
	end

	local function countPonds(mask, span)
		local seen = table.create(span * span, false)
		local ponds = 0

		for index = 1, span * span do
			if mask[index] and not seen[index] then
				ponds += 1
				local stack = { index }
				seen[index] = true

				while #stack > 0 do
					local current = stack[#stack]
					stack[#stack] = nil
					local zero = current - 1
					local iz = math.floor(zero / span)
					local ix = zero - iz * span

					if ix > 0 then
						local neighbor = current - 1
						if mask[neighbor] and not seen[neighbor] then
							seen[neighbor] = true
							stack[#stack + 1] = neighbor
						end
					end
					if ix + 1 < span then
						local neighbor = current + 1
						if mask[neighbor] and not seen[neighbor] then
							seen[neighbor] = true
							stack[#stack + 1] = neighbor
						end
					end
					if iz > 0 then
						local neighbor = current - span
						if mask[neighbor] and not seen[neighbor] then
							seen[neighbor] = true
							stack[#stack + 1] = neighbor
						end
					end
					if iz + 1 < span then
						local neighbor = current + span
						if mask[neighbor] and not seen[neighbor] then
							seen[neighbor] = true
							stack[#stack + 1] = neighbor
						end
					end
				end
			end
		end

		return ponds
	end

	print("=== ГЕНЕРАЦИЯ ЛАНДШАФТА ===")
	print("Размер: " .. MapSize .. "x" .. MapSize)
	print(string.format(
		"Вода не выше %.1f | глубина ямы %.1f | обод %.0f",
		WaterCap, PondDepth, PondRim
	))
	if WaterCap >= terrainCfg.rock_level then
		warn("⚠️ water_world_y или pond_level не ниже rock_level.")
	end

	-- Прошлый рельеф стираем, иначе новая вода не заменит старую землю.
	Terrain:Clear()

	local startTime = tick()
	local cellsGenerated = 0
	local waterCells = 0
	local minCoord = -MapSize / 2
	local maxCoord = MapSize / 2
	local span = math.floor((maxCoord - minCoord) / Resolution) + 1
	local waterMask = table.create(span * span, false)

	local function maskIndex(x, z)
		local ix = math.floor((x - minCoord) / Resolution + 0.5)
		local iz = math.floor((z - minCoord) / Resolution + 0.5)
		if ix < 0 or iz < 0 or ix >= span or iz >= span then
			return nil
		end
		return iz * span + ix + 1
	end

	local function fillBox(x, z, y0, y1, material)
		if y1 - y0 < 0.05 then
			return
		end
		local region = Region3.new(
			Vector3.new(x, y0, z),
			Vector3.new(x + Resolution, y1, z + Resolution)
		):ExpandToGrid(Resolution)
		Terrain:FillRegion(region, Resolution, material)
	end

	for x = minCoord, maxCoord, Resolution do
		for z = minCoord, maxCoord, Resolution do
			local height = getHeight(x, z)
			local surface = bowlSurface(x, z, height)
			local material = getMaterial(x, z, height)
			if surface then
				if not (x > terrainCfg.sand_min_x and z > terrainCfg.sand_min_z) then
					material = Enum.Material.Mud
				end
			end

			fillBox(x, z, terrainCfg.bottom_y, height, material)

			-- Вода только в яме и не выше обода, поэтому пруд не расползается в озеро.
			if surface then
				fillBox(x, z, height, surface, Enum.Material.Water)
				local index = maskIndex(x, z)
				if index then
					waterMask[index] = true
					waterCells += 1
				end
			end

			cellsGenerated += 1
			if cellsGenerated % terrainCfg.progress_every == 0 then
				print("Прогресс: " .. cellsGenerated .. " ячеек")
				wait() -- даем студии передохнуть
			end
		end
	end

	local ponds = countPonds(waterMask, span)
	local endTime = tick()
	print("✓ Генерация завершена!")
	print("Время: " .. string.format("%.2f", endTime - startTime) .. " сек")
	print("Ячеек: " .. cellsGenerated)
	print(string.format("Водоёмов: %d | клеток воды: %d", ponds, waterCells))
	print("Не забудь сохранить Place (Ctrl+S)!")
end

return TerrainGenerator
