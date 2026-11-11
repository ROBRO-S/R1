--!strict
-- Загрузчик items_config.json: статы оружия/инструментов по ItemId.
-- Новый предмет = новый ключ в JSON (FistWeapon_gold, WoodenAxe, ...).
-- Rojo syncRules use=text → ReplicatedStorage.items_config (StringValue).

local ItemsConfig = {}

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

export type MeleeStats = {
	kind: string,
	display_name: string,
	combo_reset: number,
	attack_cooldown: number,
	finish_cooldown: number,
	hit_delays: { number },
	damages: { number },
	hitbox: { number },
	knockback: number,
	block_dot: number,
}

local cached: { [string]: any }? = nil

local function meleeFallback(): MeleeStats
	return {
		kind = "melee",
		display_name = "Fists",
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

local function fallback(): { [string]: any }
	return {
		FistWeapon = meleeFallback(),
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

local function fillMissing(data: { [any]: any }, backup: { [any]: any })
	for key, value in backup do
		if type(value) == "table" then
			if type(data[key]) ~= "table" then
				data[key] = value
			else
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
	local base = meleeFallback()
	fillMissing(raw, base)
	if type(raw.damages) ~= "table" or type(raw.hit_delays) ~= "table" or type(raw.hitbox) ~= "table" then
		return nil
	end
	return raw :: MeleeStats
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

return ItemsConfig
