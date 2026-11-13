--!strict
-- Загрузчик items_config.json: статы оружия/инструментов/ресурсов по ItemId.
-- Новый предмет = новый ключ в JSON (FistWeapon_gold, WoodenAxe, Stick, ...).
-- Rojo syncRules use=text → ReplicatedStorage.items_config (StringValue).

local ItemsConfig = {}

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

export type MeleeStats = {
	kind: string,
	display_name: string,
	icon: string,
	combo_reset: number,
	attack_cooldown: number,
	finish_cooldown: number,
	hit_delays: { number },
	damages: { number },
	-- Урон по MegaTree (если нет — берём damages[1]). Разные топоры = разный tree_damage.
	tree_damage: number?,
	-- Урон по MediumRock (кирка). Если нет — damages[1].
	rock_damage: number?,
	-- Клиентская анимация удара (rbxassetid://…).
	swing_animation: string?,
	hitbox: { number },
	knockback: number,
	block_dot: number,
}

export type ItemInfo = {
	kind: string,
	display_name: string,
	icon: string,
	world_name: string?,
	max_stack: number,
}

local cached: { [string]: any }? = nil

local function meleeFallback(): MeleeStats
	return {
		kind = "melee",
		display_name = "Fist Weapon",
		icon = "",
		combo_reset = 1.3,
		attack_cooldown = 0.38,
		finish_cooldown = 0.8,
		hit_delays = { 0.15, 0.15, 0.22 },
		damages = { 12, 14, 22 },
		hitbox = { 4.5, 4.5, 4.5 },
		knockback = 40,
		block_dot = 0.2,
	}
end

local function resourceFallback(displayName: string, worldName: string, maxStack: number): ItemInfo
	return {
		kind = "resource",
		display_name = displayName,
		icon = "",
		world_name = worldName,
		max_stack = maxStack,
	}
end

local function axeMeleeFallback(): MeleeStats
	return {
		kind = "melee",
		display_name = "Axe",
		icon = "",
		combo_reset = 0.5,
		attack_cooldown = 0.5,
		finish_cooldown = 0.5,
		hit_delays = { 0.17 },
		-- Урон по манекену/мобам (слабее кастетов).
		damages = { 8 },
		-- Урон по MegaTree: при mega_tree_hp=75 → 5 ударов.
		tree_damage = 15,
		hitbox = { 10, 20, 10 },
		knockback = 0,
		block_dot = 0.2,
	}
end

local function pickaxeMeleeFallback(): MeleeStats
	return {
		kind = "melee",
		display_name = "Pickaxe",
		icon = "",
		swing_animation = "rbxassetid://117674721132335",
		combo_reset = 0.55,
		attack_cooldown = 0.55,
		finish_cooldown = 0.55,
		hit_delays = { 0.20 },
		damages = { 8 },
		rock_damage = 15,
		hitbox = { 10, 20, 10 },
		knockback = 0,
		block_dot = 0.2,
	}
end

local function fallback(): { [string]: any }
	local fists = meleeFallback()
	local fistInfo: any = fists
	fistInfo.max_stack = 1
	local axe = axeMeleeFallback()
	local axeInfo: any = axe
	axeInfo.max_stack = 1
	axeInfo.world_name = "Axe"
	local pickaxe = pickaxeMeleeFallback()
	local pickaxeInfo: any = pickaxe
	pickaxeInfo.max_stack = 1
	pickaxeInfo.world_name = "Pickaxe"
	return {
		FistWeapon = fistInfo,
		Axe = axeInfo,
		Pickaxe = pickaxeInfo,
		Stick = resourceFallback("Stick", "Stick", 99),
		SmallRock = resourceFallback("Rock", "SmallRock", 99),
	}
end

local function findConfigInstance(): Instance?
	for _, container in { ReplicatedStorage, ServerScriptService } do
		local inst = container:FindFirstChild("items_config")
		if inst and inst:IsA("StringValue") then
			return inst
		end
	end
	return nil
end

local function relaxJson(text: string): (string, boolean)
	local fixed, inserted = string.gsub(text, "([%w%d}%]])%s*\n(%s*\")", "%1,\n%2")
	return fixed, inserted > 0
end

local function decodeJson(text: string): any
	local fixed, repaired = relaxJson(text)
	if repaired then
		warn("⚠️ В items_config.json не хватало запятых. Для чтения поставил их сам — в файле лучше дописать.")
	end
	return HttpService:JSONDecode(fixed)
end

local function readConfig(inst: Instance): (boolean, any)
	if inst:IsA("StringValue") then
		return pcall(decodeJson, inst.Value)
	end
	return false, "items_config должен быть StringValue, пришло " .. inst.ClassName
end

local function isArrayLike(t: { [any]: any }): boolean
	local n = 0
	for key in t do
		if typeof(key) ~= "number" then
			return false
		end
		n += 1
	end
	return n > 0
end

local function fillMissing(data: { [any]: any }, backup: { [any]: any })
	for key, value in backup do
		if type(value) == "table" then
			if type(data[key]) ~= "table" then
				data[key] = value
			elseif not isArrayLike(value) and not isArrayLike(data[key]) then
				-- Не дополняем JSON-массивы (hit_delays/damages) индексами из другого оружия.
				fillMissing(data[key], value)
			end
		elseif data[key] == nil then
			warn("⚠️ В items_config нет поля " .. tostring(key) .. ". Беру запасное значение.")
			data[key] = value
		end
	end
end

local function asMelee(raw: any): MeleeStats?
	if type(raw) ~= "table" then
		return nil
	end
	-- Только скалярные поля; массивы damages/hit_delays/hitbox не трогаем.
	local base = meleeFallback()
	for key, value in base do
		if raw[key] == nil and type(value) ~= "table" then
			raw[key] = value
		end
	end
	if type(raw.damages) ~= "table" or type(raw.hit_delays) ~= "table" or type(raw.hitbox) ~= "table" then
		return nil
	end
	return raw :: MeleeStats
end

local function asItemInfo(itemId: string, raw: any): ItemInfo?
	if type(raw) ~= "table" then
		return nil
	end
	local kind = raw.kind
	if type(kind) ~= "string" or kind == "" then
		kind = "resource"
	end
	local display = raw.display_name
	if type(display) ~= "string" or display == "" then
		display = itemId
	end
	local icon = raw.icon
	if type(icon) ~= "string" then
		icon = ""
	end
	local worldName = raw.world_name
	if type(worldName) ~= "string" or worldName == "" then
		worldName = itemId
	end
	local maxStack = tonumber(raw.max_stack)
	if not maxStack or maxStack < 1 then
		maxStack = if kind == "melee" then 1 else 99
	end
	return {
		kind = kind,
		display_name = display,
		icon = icon,
		world_name = worldName,
		max_stack = math.floor(maxStack),
	}
end

function ItemsConfig.Get(): { [string]: any }
	if cached then
		return cached
	end

	local backup = fallback()
	local inst = findConfigInstance()
	if not inst then
		warn("⚠️ items_config не найден. Беру запасные статы предметов.")
		cached = backup
		return cached
	end

	local ok, data = readConfig(inst)
	if not ok or type(data) ~= "table" then
		warn("⚠️ Битый items_config.json: " .. tostring(data))
		cached = backup
		return cached
	end

	fillMissing(data, backup)
	for itemId, backupItem in backup do
		if type(data[itemId]) == "table" and type(backupItem) == "table" then
			fillMissing(data[itemId], backupItem)
		end
	end

	local names = {}
	for id in data do
		table.insert(names, tostring(id))
	end
	table.sort(names)
	print("items_config прочитан | " .. table.concat(names, ", "))

	cached = data
	return cached
end

function ItemsConfig.GetItem(itemId: string): ItemInfo?
	local all = ItemsConfig.Get()
	local raw = all[itemId]
	if raw == nil then
		return nil
	end
	return asItemInfo(itemId, raw)
end

function ItemsConfig.IsKnown(itemId: string): boolean
	return ItemsConfig.GetItem(itemId) ~= nil
end

function ItemsConfig.IsMelee(itemId: string): boolean
	local info = ItemsConfig.GetItem(itemId)
	return info ~= nil and info.kind == "melee"
end

function ItemsConfig.DisplayName(itemId: string): string
	local info = ItemsConfig.GetItem(itemId)
	if info then
		return info.display_name
	end
	return itemId
end

function ItemsConfig.Icon(itemId: string): string
	local info = ItemsConfig.GetItem(itemId)
	if info and info.icon ~= "" then
		return info.icon
	end
	return ""
end

function ItemsConfig.WorldName(itemId: string): string
	local info = ItemsConfig.GetItem(itemId)
	if info and info.world_name and info.world_name ~= "" then
		return info.world_name
	end
	return itemId
end

function ItemsConfig.MaxStack(itemId: string): number
	local info = ItemsConfig.GetItem(itemId)
	if info then
		return math.max(1, info.max_stack)
	end
	return 1
end

function ItemsConfig.ItemIdFromWorldName(worldName: string): string?
	local all = ItemsConfig.Get()
	for itemId, raw in pairs(all) do
		local info = asItemInfo(itemId, raw)
		if info and info.world_name == worldName then
			return itemId
		end
	end
	if ItemsConfig.IsKnown(worldName) then
		return worldName
	end
	return nil
end

-- Статы melee-предмета по ItemId (FistWeapon, FistWeapon_gold, ...).
function ItemsConfig.GetMelee(itemId: string): MeleeStats?
	local all = ItemsConfig.Get()
	local raw = all[itemId]
	if raw == nil then
		warn("⚠️ items_config: нет предмета " .. itemId)
		if itemId == "FistWeapon" then
			return meleeFallback()
		end
		return nil
	end
	local kind = (raw :: any).kind
	if kind ~= nil and kind ~= "melee" then
		warn("⚠️ items_config: " .. itemId .. " не melee (kind=" .. tostring(kind) .. ")")
		return nil
	end
	local stats = asMelee(raw)
	if not stats then
		warn("⚠️ items_config: битые melee-статы у " .. itemId)
		return if itemId == "FistWeapon" then meleeFallback() else nil
	end
	return stats
end

function ItemsConfig.HitboxSize(stats: MeleeStats): Vector3
	local box = stats.hitbox
	local x = tonumber(box[1]) or 4.5
	local y = tonumber(box[2]) or 4.5
	local z = tonumber(box[3]) or 4.5
	return Vector3.new(x, y, z)
end

function ItemsConfig.ComboLength(stats: MeleeStats): number
	return math.max(1, math.min(#stats.damages, #stats.hit_delays))
end

-- Урон топора/инструмента по деревьям. Нет tree_damage → damages[1].
function ItemsConfig.TreeDamage(stats: MeleeStats): number
	local td = (stats :: any).tree_damage
	if typeof(td) == "number" and td > 0 then
		return td
	end
	local d = stats.damages[1]
	if typeof(d) == "number" and d > 0 then
		return d
	end
	return 15
end

-- Урон кирки по MediumRock. Нет rock_damage → damages[1].
function ItemsConfig.RockDamage(stats: MeleeStats): number
	local rd = (stats :: any).rock_damage
	if typeof(rd) == "number" and rd > 0 then
		return rd
	end
	local d = stats.damages[1]
	if typeof(d) == "number" and d > 0 then
		return d
	end
	return 15
end

function ItemsConfig.SwingAnimation(stats: MeleeStats): string
	local anim = (stats :: any).swing_animation
	if typeof(anim) == "string" and anim ~= "" then
		return anim
	end
	return ""
end

return ItemsConfig
