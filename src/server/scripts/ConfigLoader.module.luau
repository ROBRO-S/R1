-- Загрузчик biome_config.json.
-- Rojo 7.7 по умолчанию кладёт обычный .json как ModuleScript с `return { ... }`.
-- Source такого модуля в игре не прочитать, поэтому JSONDecode к нему не применить.
-- В default.project.json для этого файла стоит syncRules use = "text":
-- в ReplicatedStorage появляется StringValue biome_config, а в Value — сырой JSON.
-- Если правило сняли и приехал ModuleScript, таблица всё равно прогоняется
-- через JSONEncode и JSONDecode, чтобы битые данные ловил тот же pcall.

local ConfigLoader = {}

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local cached = nil

-- Запасные числа. Совпадают с текущим JSON.
-- Сюда попадаем только если конфиг не найден или JSON сломан.
local function fallback()
	return {
		map_size = 2000,
		chunk_size = 256,
		voxel_res = 4,
		base_height = 10,
		-- Верхний предел зеркала. Выше — пруды крупнее.
		pond_level = 6,
		water_world_y = 6,
		probabilities = {
			-- Доля клеток 4×4, не накопленный порог.
			-- Суммы строго растут, пока каждое число больше нуля.
			thin_tree = 0.0008,
			mega_tree = 0.0004,
			stick = 0.0005,
			small_rock = 0.0005,
			boulder = 0.0005,
		},
		-- Клетка сетки занятости. В неё нельзя поставить второй объект.
		occupancy_cell_size = 4,
		-- Основание MegaTree. Площадка и проверка уклона считаются от этого радиуса.
		tree_base_radius = 18,
		-- Градусы. Круче — под деревом режется круглая площадка.
		-- 6° ловит уступ вокселя под широким основанием.
		max_slope_for_tree = 6,
		-- Градусы. Круче — под камнем выравнивается пятачок, чтобы он не висел над ямой.
		max_slope_for_prop = 8,
		-- Внешний радиус выравнивания. Внутренние flatten_flat_fraction — ровная земля.
		flatten_radius = 36,
		flatten_flat_fraction = 0.5,
		-- Зазор между основаниями любых объектов.
		exclusion_radius = 4,
		-- На сколько студов искать свободную точку, если место занято.
		spawn_search_radius = 40,
		near_water_radius_thin = 1.5,
		near_water_radius_mega = 3,
		-- Больше нуля — на чанк гарантируется минимум прудов.
		pond_density = 1,
		min_pond_size = 16,
		min_ponds_per_chunk = 1,
		terrain = {
			noise_scale_1 = 0.0035,
			noise_scale_2 = 0.012,
			-- Невысокие волны. Большие амплитуды дают горы, на которых объекты висят.
			noise_amplitude_1 = 5,
			noise_amplitude_2 = 1.2,
			noise_seed_y = 0,
			noise_offset_2 = 100,
			-- Раньше скала была выше BaseHeight + 12, то есть 22.
			rock_level = 22,
			bottom_y = -50,
			-- Запас за краем map_size, чтобы не было дыр и не светился Baseplate.
			edge_margin = 128,
			-- Доля суши с Terrain Decoration (материал Grass). Остальное — Ground без стеблей.
			grass_coverage = 0.7,
			-- Длина стеблей Terrain.GrassLength: 0.1 короткий … 1 длинный.
			grass_height = 0.25,
			-- Масштаб шума пятен травы. Меньше — крупные пятна.
			grass_noise_scale = 0.015,
			-- Насколько яма глубже обода, чтобы стать прудом. Больше — меньше и мельче.
			pond_depth = 1.6,
			-- На каком расстоянии мерить обод. Слишком маленький радиус на плавном шуме даёт 0 прудов.
			pond_rim = 16,
			-- Насколько зеркало ниже самой низкой точки берега.
			pond_shore = 1,
			-- Минимальная толщина воды. Раньше вместо неё было жёсткое «не меньше 1 студа».
			pond_min_fill = 0.6,
			pond_place_attempts = 12,
			progress_every = 400,
		},
		props = {
			ray_start_y = 200,
			ray_depth = 300,
			column_bottom_y = -50,
			column_top_y = 100,
			thin_tree_radius = 2.5,
			mega_tree_radius = 9,
			small_rock_radius = 1.2,
			boulder_radius = 3.5,
			thin_tree_scale = 1,
			thin_tree_lift = 0,
			stick_beside_chance = 0.6,
			stick_beside_dist_min = 2,
			stick_beside_dist_max = 4,
			stick_beside_size = { 0.8, 0.2, 0.2 },
			stick_beside_lift = 0.1,
			stick_beside_tilt = 25,
			stick_color = { 120, 80, 40 },
			mega_tree_scale = 1,
			-- Отрицательное — утопить ствол, чтобы корни не торчали.
			mega_tree_lift = -2,
			soil_size = 1,
			soil_transparency = 1,
			stick_size = { 2.4, 0.6, 0.6 },
			stick_lift = 0.3,
			stick_tilt = 30,
			ground_ray_up = 50,
			ground_ray_down = 100,
			small_rock_color = { 100, 100, 100 },
			rock_transparency = 0,
			boulder_tilt = 15,
			boulder_color = { 80, 80, 80 },
			chunk_log_every = 500,
		},
	}
end

local function findConfigInstance()
	local containers = { ReplicatedStorage, ServerScriptService }
	local names = { "biome_config", "BiomeConfig" }

	for _, container in containers do
		for _, name in names do
			local inst = container:FindFirstChild(name)
			if inst then
				return inst
			end
		end
	end

	return nil
end

-- Ставит пропущенную запятую между соседними полями, иначе JSONDecode
-- выбрасывает весь файл и генератор молча берёт старые шансы.
local function relaxJson(text)
	if type(text) ~= "string" then
		return text, false
	end
	local fixed, inserted = string.gsub(text, "([%w%d}%]])%s*\n(%s*\")", "%1,\n%2")
	return fixed, inserted > 0
end

local function decodeJson(text)
	local fixed, repaired = relaxJson(text)
	if repaired then
		warn("⚠️ В biome_config.json не хватало запятых между полями. Для чтения поставил их сам — в файле лучше дописать.")
	end
	return HttpService:JSONDecode(fixed)
end

local function describe(cfg)
	local probs = cfg.probabilities or {}
	return string.format(
		"вода %.2f | берег %.2f | пруды %.2f/чанк мин %d размер %.0f | дерево R %.0f уклон %.0f° | шансы thin %.4f mega %.4f stick %.4f rock %.4f boulder %.4f",
		tonumber(cfg.water_world_y) or -1,
		tonumber(cfg.pond_level) or -1,
		tonumber(cfg.pond_density) or -1,
		tonumber(cfg.min_ponds_per_chunk) or -1,
		tonumber(cfg.min_pond_size) or -1,
		tonumber(cfg.tree_base_radius) or -1,
		tonumber(cfg.max_slope_for_tree) or -1,
		tonumber(probs.thin_tree) or -1,
		tonumber(probs.mega_tree) or -1,
		tonumber(probs.stick) or -1,
		tonumber(probs.small_rock) or -1,
		tonumber(probs.boulder) or -1
	)
end

local function readConfig(inst)
	if inst:IsA("StringValue") then
		return pcall(decodeJson, inst.Value)
	end

	if inst:IsA("ModuleScript") then
		local okRequire, required = pcall(require, inst)
		if not okRequire then
			return false, required
		end
		if type(required) ~= "table" then
			return false, "ModuleScript biome_config вернул не таблицу"
		end

		local okEncode, encoded = pcall(function()
			return HttpService:JSONEncode(required)
		end)
		if not okEncode then
			return false, encoded
		end

		return pcall(decodeJson, encoded)
	end

	return false, "biome_config должен быть StringValue или ModuleScript, пришло " .. inst.ClassName
end

-- Дописывает только отсутствующие поля. Уже заданные числа не трогает.
local function fillMissing(data, backup)
	for key, value in backup do
		if type(value) == "table" then
			if type(data[key]) ~= "table" then
				data[key] = value
			else
				fillMissing(data[key], value)
			end
		elseif data[key] == nil then
			warn("⚠️ В biome_config нет поля " .. tostring(key) .. ". Беру запасное значение.")
			data[key] = value
		end
	end
end

function ConfigLoader.Get()
	if cached then
		return cached
	end

	local backup = fallback()
	local inst = findConfigInstance()
	if not inst then
		warn("⚠️ biome_config не найден. Шансы из JSON не применились, беру запасные: " .. describe(backup))
		cached = backup
		return cached
	end

	local ok, data = readConfig(inst)
	if not ok or type(data) ~= "table" then
		warn("⚠️ Битый biome_config.json, шансы из файла НЕ применились: " .. tostring(data))
		warn("Запасные значения: " .. describe(backup))
		cached = backup
		return cached
	end

	fillMissing(data, backup)
	print("biome_config прочитан | " .. describe(data))
	cached = data
	return cached
end

-- Копит вероятности в пороги для if/elseif.
-- Каждый следующий порог строго больше предыдущего, пока все вероятности > 0.
function ConfigLoader.SpawnThresholds(cfg)
	local probs = cfg.probabilities
	local thin = probs.thin_tree
	local mega = thin + probs.mega_tree
	local stick = mega + probs.stick
	local rock = stick + probs.small_rock
	local boulder = rock + probs.boulder

	if not (thin < mega and mega < stick and stick < rock and rock < boulder) then
		warn("⚠️ Пороги спавна должны строго возрастать: thin < mega < stick < small_rock < boulder")
	end

	return {
		thin_tree = thin,
		mega_tree = mega,
		stick = stick,
		small_rock = rock,
		boulder = boulder,
	}
end

return ConfigLoader
