local TerrainGenerator = {}

function TerrainGenerator.Generate()
	-- Создай Script в ServerScriptService
	-- Этот скрипт будет запускаться ТОЛЬКО когда ты явно его вызовешь

	local ConfigLoader = require(script.Parent:WaitForChild("ConfigLoader"))
	local cfg = ConfigLoader.Get()
	local terrainCfg = cfg.terrain

	local Terrain = workspace.Terrain
	local MapSize = cfg.map_size
	local ChunkSize = cfg.chunk_size
	local Resolution = cfg.voxel_res
	local BaseHeight = cfg.base_height
	local PondLevel = cfg.pond_level
	local WaterWorldY = cfg.water_world_y
	-- Глобальный потолок. Раньше он резал любую яму выше base_height, и прудов выходило 0.
	local WaterCap = math.min(PondLevel, WaterWorldY)
	local PondDepth = terrainCfg.pond_depth
	local PondRim = terrainCfg.pond_rim
	local PondShore = terrainCfg.pond_shore
	local PondMinFill = terrainCfg.pond_min_fill
	local PondAttempts = terrainCfg.pond_place_attempts
	local PondDensity = cfg.pond_density
	local MinPondSize = cfg.min_pond_size
	local MinPondsPerChunk = cfg.min_ponds_per_chunk
	local Exclusion = cfg.exclusion_radius
	local MaxSlope = cfg.max_slope_for_tree
	local FlatFraction = cfg.flatten_flat_fraction

	if FlatFraction <= 0.05 or FlatFraction >= 1 then
		warn("⚠️ flatten_flat_fraction должен быть между 0 и 1. Беру 0.5.")
		FlatFraction = 0.5
	end
	if PondShore < 0 or PondMinFill < 0 or PondDepth < 0 or MinPondSize < 0 then
		warn("⚠️ Отрицательные параметры пруда в biome_config.")
	end
	if PondAttempts < 1 then
		PondAttempts = 1
	end

	local function getHeight(x, z)
		local scale1 = terrainCfg.noise_scale_1
		local scale2 = terrainCfg.noise_scale_2
		local amplitude1 = terrainCfg.noise_amplitude_1
		local amplitude2 = terrainCfg.noise_amplitude_2

		local noise1 = math.noise(x * scale1, terrainCfg.noise_seed_y, z * scale1) * amplitude1
		local noise2 = math.noise(x * scale2, terrainCfg.noise_offset_2, z * scale2) * amplitude2

		return BaseHeight + noise1 + noise2
	end

	local grassCoverage = terrainCfg.grass_coverage
	if type(grassCoverage) ~= "number" then
		grassCoverage = 0.7
	end
	grassCoverage = math.clamp(grassCoverage, 0, 1)
	local grassHeight = terrainCfg.grass_height
	if type(grassHeight) ~= "number" then
		grassHeight = 0.25
	end
	local grassNoiseScale = terrainCfg.grass_noise_scale
	if type(grassNoiseScale) ~= "number" or grassNoiseScale <= 0 then
		grassNoiseScale = 0.015
	end

	local function getMaterial(x, z, height)
		-- Скала выше порога. Стебли Decoration только на Grass — доля grass_coverage.
		if height > terrainCfg.rock_level then
			return Enum.Material.Rock
		end
		if grassCoverage >= 1 then
			return Enum.Material.Grass
		end
		if grassCoverage <= 0 then
			return Enum.Material.Ground
		end
		local n = math.noise(x * grassNoiseScale, 17.3, z * grassNoiseScale)
		local t = (n + 1) * 0.5
		if t < grassCoverage then
			return Enum.Material.Grass
		end
		return Enum.Material.Ground
	end

	local function bedMaterial(_x, _z)
		return Enum.Material.Mud
	end

	-- Пруд там, где точка заметно ниже обода.
	-- Зеркало больше не прижимается к water_world_y, если этот потолок ниже дна ямы:
	-- при base_height 10 и воде на 6 почти вся карта отбраковывалась.
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
		local surface = lip - PondShore
		if WaterCap > height + PondMinFill then
			surface = math.min(surface, WaterCap)
		end
		if surface - height < PondMinFill then
			return nil
		end
		return surface
	end

	print("=== ГЕНЕРАЦИЯ ЛАНДШАФТА ===")
	print("Размер: " .. MapSize .. "x" .. MapSize)
	print(string.format(
		"Яма: глубина %.1f | обод %.0f | берег %.1f | столб воды от %.1f",
		PondDepth, PondRim, PondShore, PondMinFill
	))
	print(string.format(
		"Пруды: плотность %.2f | минимум %d на чанк | радиус воды >= %.0f",
		PondDensity, MinPondsPerChunk, MinPondSize
	))
	print(string.format(
		"Трава: покрытие %.0f%% | высота %.2f | шум %.4f",
		grassCoverage * 100, grassHeight, grassNoiseScale
	))
	if WaterCap < BaseHeight then
		print(string.format(
			"Потолок воды %.1f ниже base_height %.1f — он больше не запрещает ямы на холмах.",
			WaterCap, BaseHeight
		))
	end

	-- Прошлый рельеф стираем, иначе новая вода не заменит старую землю.
	Terrain:Clear()
	-- Дать движку пережить Clear — иначе сразу после него легко поймать timeout.
	task.wait()

	local startTime = tick()
	local cellsGenerated = 0
	local waterCells = 0
	local half = MapSize / 2
	-- Игровой прямоугольник ±half; рельеф чуть шире, чтобы край и Baseplate не светились.
	local edgeMargin = terrainCfg.edge_margin or 0
	if edgeMargin < 0 then
		edgeMargin = 0
	end
	local minCoord = -half - edgeMargin
	local maxCoord = half + edgeMargin
	local span = math.floor((maxCoord - minCoord) / Resolution) + 1
	local waterMask = table.create(span * span, false)
	local surfaceAt = {}
	local progressEvery = terrainCfg.progress_every
	if type(progressEvery) ~= "number" or progressEvery < 100 then
		progressEvery = 400
	end

	local function maskIndex(x, z)
		local ix = math.floor((x - minCoord) / Resolution + 0.5)
		local iz = math.floor((z - minCoord) / Resolution + 0.5)
		if ix < 0 or iz < 0 or ix >= span or iz >= span then
			return nil
		end
		return iz * span + ix + 1, ix, iz
	end

	local function worldOf(index)
		local zero = index - 1
		local iz = math.floor(zero / span)
		local ix = zero - iz * span
		return minCoord + ix * Resolution, minCoord + iz * Resolution
	end

	local function chunkKeyAt(x, z)
		local ix = math.floor((x + half) / ChunkSize)
		local iz = math.floor((z + half) / ChunkSize)
		return ix .. ":" .. iz
	end

	local function fillBox(x, z, y0, y1, material)
		if y1 - y0 < 0.05 then
			return
		end
		-- FillRegion: быстрее и стабильнее на большой карте, чем сотни тысяч FillBlock.
		local region = Region3.new(
			Vector3.new(x, y0, z),
			Vector3.new(x + Resolution, y1, z + Resolution)
		):ExpandToGrid(Resolution)
		Terrain:FillRegion(region, Resolution, material)
	end

	-- maxCoord включительно; последняя колонка закрывает правый/дальний край.
	local columnIndex = 0
	for x = minCoord, maxCoord, Resolution do
		for z = minCoord, maxCoord, Resolution do
			local height = getHeight(x, z)
			local surface = bowlSurface(x, z, height)
			local material = getMaterial(x, z, height)

			fillBox(x, z, terrainCfg.bottom_y, height, material)

			if surface then
				local index = maskIndex(x, z)
				if index then
					waterMask[index] = true
					surfaceAt[index] = surface
				end
			end

			cellsGenerated += 1
			if cellsGenerated % progressEvery == 0 then
				print("Прогресс: " .. cellsGenerated .. " ячеек")
				task.wait()
			end
		end
		columnIndex += 1
		-- Периодический yield по столбцам — иначе Studio убивает скрипт по timeout.
		if columnIndex % 2 == 0 then
			task.wait()
		end
	end

	-- Decoration / GrassLength из обычного серверного скрипта часто нельзя писать
	-- (нужен PluginOrOpenCloud) — не валим всю генерацию из-за травы.
	local clampedGrass = math.clamp(grassHeight, 0.1, 1)
	local okDecor, decorErr = pcall(function()
		Terrain.Decoration = grassCoverage > 0
	end)
	if not okDecor then
		warn(string.format(
			"⚠️ Terrain.Decoration из скрипта недоступен. В Studio включи Terrain.Decoration вручную. (%s)",
			tostring(decorErr)
		))
	end
	local okGrassLen, grassLenErr = pcall(function()
		Terrain.GrassLength = clampedGrass
	end)
	if not okGrassLen then
		warn(string.format(
			"⚠️ GrassLength из скрипта не ставится. В Studio: Terrain.GrassLength = %.2f (%s)",
			clampedGrass,
			tostring(grassLenErr)
		))
	end

	local function collectPonds(mask)
		local seen = table.create(span * span, false)
		local ponds = {}

		for index = 1, span * span do
			if mask[index] and not seen[index] then
				local stack = { index }
				seen[index] = true
				local cells = {}
				local chunks = {}
				local sumX, sumZ = 0, 0

				while #stack > 0 do
					local current = stack[#stack]
					stack[#stack] = nil
					cells[#cells + 1] = current
					local wx, wz = worldOf(current)
					sumX += wx
					sumZ += wz
					chunks[chunkKeyAt(wx, wz)] = true

					local zero = current - 1
					local iz = math.floor(zero / span)
					local ix = zero - iz * span

					local function push(neighbor, ok)
						if ok and mask[neighbor] and not seen[neighbor] then
							seen[neighbor] = true
							stack[#stack + 1] = neighbor
						end
					end

					push(current - 1, ix > 0)
					push(current + 1, ix + 1 < span)
					push(current - span, iz > 0)
					push(current + span, iz + 1 < span)
				end

				local count = #cells
				ponds[#ponds + 1] = {
					count = count,
					cells = cells,
					chunks = chunks,
					x = sumX / count,
					z = sumZ / count,
				}
			end
		end

		return ponds
	end

	local minCells = math.max(1, math.ceil((math.pi * MinPondSize * MinPondSize) / (Resolution * Resolution)))
	local found = collectPonds(waterMask)
	local naturalLarge = 0
	local naturalSmall = 0
	local chunkCounts = {}
	local placed = {}
	local waterRadius = MinPondSize
	local bowlRadius = waterRadius / FlatFraction
	local bank = bowlRadius - waterRadius

	for _, pond in found do
		if pond.count < minCells then
			naturalSmall += 1
			for _, index in pond.cells do
				waterMask[index] = false
			end
		else
			naturalLarge += 1
			local area = pond.count * Resolution * Resolution
			local radius = math.sqrt(area / math.pi) + bank
			placed[#placed + 1] = { x = pond.x, z = pond.z, r = radius }
			for key in pond.chunks do
				chunkCounts[key] = (chunkCounts[key] or 0) + 1
			end
			for _, index in pond.cells do
				local x, z = worldOf(index)
				local height = getHeight(x, z)
				local surface = surfaceAt[index]
				fillBox(x, z, height - Resolution, height, bedMaterial(x, z))
				fillBox(x, z, height, surface, Enum.Material.Water)
				waterCells += 1
			end
		end
	end

	if naturalLarge == 0 then
		print(string.format(
			"Крупных естественных прудов 0. Шум слишком плавный для ямы %.1f на ободе %.0f, мелких ям отброшено: %d.",
			PondDepth, PondRim, naturalSmall
		))
	end

	local function separation(x, z, radius)
		local best = math.huge
		for _, pond in placed do
			local dx = pond.x - x
			local dz = pond.z - z
			local spare = math.sqrt(dx * dx + dz * dz) - pond.r - radius - Exclusion
			if spare < best then
				best = spare
			end
		end
		return best
	end

	local function maskWet(x, z, radius)
		local reach = radius + Resolution
		for sx = x - reach, x + reach, Resolution do
			for sz = z - reach, z + reach, Resolution do
				local dx = sx - x
				local dz = sz - z
				if dx * dx + dz * dz <= reach * reach then
					local index = maskIndex(sx, sz)
					if index and waterMask[index] then
						return true
					end
				end
			end
		end
		return false
	end

	local function slopeAt(x, z, radius)
		local h = getHeight(x, z)
		local worst = 0
		local dirs = { { radius, 0 }, { -radius, 0 }, { 0, radius }, { 0, -radius } }
		for _, dir in dirs do
			local drop = math.abs(getHeight(x + dir[1], z + dir[2]) - h)
			local angle = math.deg(math.atan(drop / radius))
			if angle > worst then
				worst = angle
			end
		end
		return worst
	end

	local verticalPad = terrainCfg.noise_amplitude_1 + terrainCfg.noise_amplitude_2 + PondRim + PondDepth
	local carved = 0
	local carveFailures = 0

	local function carvePond(cx, cz)
		if maskWet(cx, cz, bowlRadius) then
			return false
		end

		local yGuess = getHeight(cx, cz)
		local region = Region3.new(
			Vector3.new(cx - bowlRadius, yGuess - verticalPad, cz - bowlRadius),
			Vector3.new(cx + bowlRadius, yGuess + verticalPad, cz + bowlRadius)
		):ExpandToGrid(Resolution)
		local materials, occupancy = Terrain:ReadVoxels(region, Resolution)
		if not materials or not materials[1] or not materials[1][1] or not occupancy then
			return false
		end

		local rMin = region.CFrame.Position - (region.Size / 2)
		local sizeX, sizeY, sizeZ = #materials, #materials[1], #materials[1][1]
		local columns = {}
		local edgeMin = math.huge
		local edgeSum, edgeCount = 0, 0

		for xi = 1, sizeX do
			for zi = 1, sizeZ do
				local wx = rMin.X + (xi - 0.5) * Resolution
				local wz = rMin.Z + (zi - 0.5) * Resolution
				local dx = wx - cx
				local dz = wz - cz
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist <= bowlRadius + Resolution * 0.5 then
					local oldYi = nil
					for yi = sizeY, 1, -1 do
						local mat = materials[xi][yi][zi]
						if mat ~= Enum.Material.Air and mat ~= Enum.Material.Water then
							oldYi = yi
							break
						end
					end
					if oldYi then
						local oldY = rMin.Y + oldYi * Resolution
						columns[#columns + 1] = {
							xi = xi,
							zi = zi,
							x = wx,
							z = wz,
							dist = dist,
							oldY = oldY,
							oldYi = oldYi,
						}
						if dist >= bowlRadius - Resolution then
							edgeMin = math.min(edgeMin, oldY)
							edgeSum += oldY
							edgeCount += 1
						end
					end
				end
			end
		end

		if edgeMin == math.huge or edgeCount == 0 or #columns == 0 then
			return false
		end

		-- Зеркало почти у средней кромки. Раньше оно садилось на самый низкий берег
		-- минус целый воксель, и вода лежала на дне глубокой ямы.
		local lip = edgeSum / edgeCount
		local surfaceY = math.min(lip - PondShore, edgeMin)
		local surfaceVoxel = math.clamp(math.floor((surfaceY - rMin.Y - 0.001) / Resolution) + 1, 1, sizeY)
		local wetMarks = {}

		for _, column in columns do
			local dist = column.dist
			if dist <= bowlRadius then
				local inner = dist <= waterRadius
				local solidMat = inner and bedMaterial(column.x, column.z) or getMaterial(column.x, column.z, column.oldY)
				local solidTop, waterTop, wet
				if inner then
					-- Один воксель воды, верх зеркала у кромки, без глубокого котлована.
					solidTop = math.max(1, surfaceVoxel - 1)
					waterTop = surfaceVoxel
					wet = waterTop > solidTop
				elseif column.oldYi < surfaceVoxel then
					solidTop = surfaceVoxel
					waterTop = solidTop
					wet = false
				else
					solidTop = column.oldYi
					waterTop = solidTop
					wet = false
				end
				local clearTop = math.max(column.oldYi, waterTop, solidTop)

				for yi = 1, sizeY do
					if yi < solidTop then
						local mat = materials[column.xi][yi][column.zi]
						if mat == Enum.Material.Air or mat == Enum.Material.Water then
							materials[column.xi][yi][column.zi] = solidMat
							occupancy[column.xi][yi][column.zi] = 1
						end
					elseif yi == solidTop then
						materials[column.xi][yi][column.zi] = solidMat
						occupancy[column.xi][yi][column.zi] = 1
					elseif wet and yi <= waterTop then
						materials[column.xi][yi][column.zi] = Enum.Material.Water
						occupancy[column.xi][yi][column.zi] = 1
					elseif yi <= clearTop then
						materials[column.xi][yi][column.zi] = Enum.Material.Air
						occupancy[column.xi][yi][column.zi] = 0
					end
				end

				if wet then
					wetMarks[#wetMarks + 1] = { x = column.x, z = column.z }
				end
			end
		end

		if #wetMarks == 0 then
			return false
		end

		local ok, err = pcall(function()
			Terrain:WriteVoxels(region, Resolution, materials, occupancy)
		end)
		if not ok then
			warn("⚠️ Не удалось вырыть пруд: " .. tostring(err))
			return false
		end

		for _, mark in wetMarks do
			local index = maskIndex(mark.x, mark.z)
			if index then
				waterMask[index] = true
			end
			waterCells += 1
		end
		placed[#placed + 1] = { x = cx, z = cz, r = bowlRadius }
		local owner = chunkKeyAt(cx, cz)
		chunkCounts[owner] = (chunkCounts[owner] or 0) + 1
		carved += 1
		return true
	end

	local target = 0
	if PondDensity > 0 then
		target = math.max(MinPondsPerChunk, math.ceil(PondDensity - 1e-6))
	end

	if target > 0 and MinPondSize > 0 then
		local cursorX = -half
		local chunkIx = 0
		while cursorX < half - 0.001 do
			local chunkX = math.min(ChunkSize, half - cursorX)
			local cursorZ = -half
			local chunkIz = 0
			while cursorZ < half - 0.001 do
				local chunkZ = math.min(ChunkSize, half - cursorZ)
				local key = chunkIx .. ":" .. chunkIz
				local have = chunkCounts[key] or 0
				local fit = math.max(1, math.floor((chunkX * chunkZ) / (math.pi * (bowlRadius * 2) * (bowlRadius * 2))))
				local need = math.min(target, fit) - have

				while need > 0 do
					local placedHere = false
					local best = nil
					local function consider(x, z, allowSteep)
						if x - bowlRadius < minCoord or x + bowlRadius > maxCoord then
							return
						end
						if z - bowlRadius < minCoord or z + bowlRadius > maxCoord then
							return
						end
						local spare = separation(x, z, bowlRadius)
						if spare < 0 or maskWet(x, z, bowlRadius) then
							return
						end
						local slope = slopeAt(x, z, waterRadius)
						local flatEnough = slope <= MaxSlope
						if not best or spare > best.spare then
							best = { x = x, z = z, spare = spare, flat = flatEnough }
						end
						if allowSteep or flatEnough then
							if carvePond(x, z) then
								placedHere = true
							end
						end
					end

					for _ = 1, PondAttempts do
						if placedHere then
							break
						end
						local inset = math.min(bowlRadius, math.min(chunkX, chunkZ) * 0.5 - Resolution)
						if inset < Resolution then
							inset = 0
						end
						local spanX = chunkX - inset * 2
						local spanZ = chunkZ - inset * 2
						local x = cursorX + inset
						local z = cursorZ + inset
						if spanX > 0 then
							x += math.random() * spanX
						end
						if spanZ > 0 then
							z += math.random() * spanZ
						end
						consider(x, z, false)
					end

					if not placedHere then
						local steps = math.max(3, math.ceil(math.sqrt(PondAttempts)))
						for ix = 1, steps do
							if placedHere then
								break
							end
							for iz = 1, steps do
								if placedHere then
									break
								end
								consider(
									cursorX + chunkX * (ix / (steps + 1)),
									cursorZ + chunkZ * (iz / (steps + 1)),
									false
								)
							end
						end
					end

					if not placedHere and best and best.flat then
						placedHere = carvePond(best.x, best.z)
					elseif not placedHere and best then
						placedHere = carvePond(best.x, best.z)
					end

					if not placedHere then
						carveFailures += 1
						warn(string.format(
							"⚠️ Чанк [%.0f, %.0f] не вместил пруд радиуса %.0f.",
							cursorX, cursorZ, waterRadius
						))
						break
					end
					need -= 1
					task.wait()
				end

				cursorZ += ChunkSize
				chunkIz += 1
				task.wait()
			end
			cursorX += ChunkSize
			chunkIx += 1
		end
	end

	local endTime = tick()
	print("✓ Генерация завершена!")
	print("Время: " .. string.format("%.2f", endTime - startTime) .. " сек")
	print("Ячеек: " .. cellsGenerated)
	print(string.format(
		"Водоёмов: %d | естественных %d | вырыто %d | мелких отброшено %d | клеток воды: %d",
		naturalLarge + carved, naturalLarge, carved, naturalSmall, waterCells
	))
	if carveFailures > 0 then
		print("Чанков без гарантированного пруда: " .. carveFailures)
	end
	print("Не забудь сохранить Place (Ctrl+S)!")
end

return TerrainGenerator
