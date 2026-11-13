--!strict
-- Клиентское чтение items_config (имена, иконки, kind).

local ItemCatalog = {}

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type ItemInfo = {
	kind: string,
	display_name: string,
	icon: string,
}

local cached: { [string]: ItemInfo }? = nil

local FALLBACK: { [string]: ItemInfo } = {
	FistWeapon = { kind = "melee", display_name = "Fist Weapon", icon = "" },
	Axe = { kind = "melee", display_name = "Axe", icon = "" },
	Pickaxe = { kind = "melee", display_name = "Pickaxe", icon = "" },
	Stick = { kind = "resource", display_name = "Stick", icon = "" },
	SmallRock = { kind = "resource", display_name = "Rock", icon = "" },
}

local function relaxJson(text: string): string
	local fixed = string.gsub(text, "([%w%d}%]])%s*\n(%s*\")", "%1,\n%2")
	return fixed
end

local function load(): { [string]: ItemInfo }
	if cached then
		return cached
	end
	local result: { [string]: ItemInfo } = {}
	for id, info in pairs(FALLBACK) do
		result[id] = table.clone(info)
	end

	local inst = ReplicatedStorage:FindFirstChild("items_config")
	if inst and inst:IsA("StringValue") and inst.Value ~= "" then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(relaxJson(inst.Value))
		end)
		if ok and type(data) == "table" then
			for itemId, raw in pairs(data) do
				if type(itemId) == "string" and type(raw) == "table" then
					local kind = raw.kind
					if type(kind) ~= "string" then
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
					result[itemId] = {
						kind = kind,
						display_name = display,
						icon = icon,
					}
				end
			end
		end
	end

	cached = result
	return result
end

function ItemCatalog.Get(itemId: string): ItemInfo?
	return load()[itemId]
end

function ItemCatalog.DisplayName(itemId: string): string
	local info = ItemCatalog.Get(itemId)
	if info then
		return info.display_name
	end
	return itemId
end

function ItemCatalog.Icon(itemId: string): string
	local info = ItemCatalog.Get(itemId)
	if info and info.icon ~= "" then
		return info.icon
	end
	return ""
end

function ItemCatalog.IsMelee(itemId: string): boolean
	local info = ItemCatalog.Get(itemId)
	return info ~= nil and info.kind == "melee"
end

return ItemCatalog
