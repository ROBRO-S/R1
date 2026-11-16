--!strict
-- Клиент/сервер: рецепты крафта из craft_config + статы для UI.

local CraftCatalog = {}

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Cost = {
	id: string,
	count: number,
}

export type Recipe = {
	id: string,
	result: string,
	count: number,
	description: string,
	costs: { Cost },
}

export type Category = {
	id: string,
	display_name: string,
	icon: string,
	recipes: { string },
}

export type MeleePreview = {
	damage: number,
	attack_speed: number,
}

type CraftData = {
	categories: { Category },
	recipes: { [string]: Recipe },
}

local cached: CraftData? = nil
local meleeCache: { [string]: MeleePreview }? = nil

local FALLBACK: CraftData = {
	categories = {
		{
			id = "Weapons",
			display_name = "Weapons",
			icon = "⚔",
			recipes = { "Axe", "Pickaxe", "FistWeapon" },
		},
	},
	recipes = {
		Axe = {
			id = "Axe",
			result = "Axe",
			count = 1,
			description = "Stone axe for chopping trees.",
			costs = {
				{ id = "Stick", count = 2 },
				{ id = "SmallRock", count = 2 },
			},
		},
		Pickaxe = {
			id = "Pickaxe",
			result = "Pickaxe",
			count = 1,
			description = "Stone pickaxe for breaking rocks.",
			costs = {
				{ id = "Stick", count = 2 },
				{ id = "SmallRock", count = 3 },
			},
		},
		FistWeapon = {
			id = "FistWeapon",
			result = "FistWeapon",
			count = 1,
			description = "Paired knuckles for close combat.",
			costs = {
				{ id = "MetalPiece", count = 2 },
			},
		},
	},
}

local function relaxJson(text: string): string
	local fixed = string.gsub(text, "([%w%d}%]])%s*\n(%s*\")", "%1,\n%2")
	return fixed
end

local function parseCosts(raw: any): { Cost }
	local costs: { Cost } = {}
	if type(raw) ~= "table" then
		return costs
	end
	for _, entry in ipairs(raw) do
		if type(entry) == "table" and type(entry.id) == "string" then
			local n = tonumber(entry.count)
			if n and n > 0 then
				table.insert(costs, {
					id = entry.id,
					count = math.floor(n),
				})
			end
		end
	end
	return costs
end

local function parseRecipe(recipeId: string, raw: any): Recipe?
	if type(raw) ~= "table" then
		return nil
	end
	local result = raw.result
	if type(result) ~= "string" or result == "" then
		result = recipeId
	end
	local count = tonumber(raw.count) or 1
	local description = raw.description
	if type(description) ~= "string" then
		description = ""
	end
	local costs = parseCosts(raw.costs)
	if #costs == 0 then
		return nil
	end
	return {
		id = recipeId,
		result = result,
		count = math.max(1, math.floor(count)),
		description = description,
		costs = costs,
	}
end

local function loadCraft(): CraftData
	if cached then
		return cached
	end

	local result: CraftData = {
		categories = table.clone(FALLBACK.categories),
		recipes = {},
	}
	for id, recipe in pairs(FALLBACK.recipes) do
		result.recipes[id] = {
			id = recipe.id,
			result = recipe.result,
			count = recipe.count,
			description = recipe.description,
			costs = table.clone(recipe.costs),
		}
	end

	local inst = ReplicatedStorage:FindFirstChild("craft_config")
	if inst and inst:IsA("StringValue") and inst.Value ~= "" then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(relaxJson(inst.Value))
		end)
		if ok and type(data) == "table" then
			if type(data.recipes) == "table" then
				for recipeId, raw in pairs(data.recipes) do
					if type(recipeId) == "string" then
						local parsed = parseRecipe(recipeId, raw)
						if parsed then
							result.recipes[recipeId] = parsed
						end
					end
				end
			end
			if type(data.categories) == "table" then
				local cats: { Category } = {}
				for _, raw in ipairs(data.categories) do
					if type(raw) == "table" and type(raw.id) == "string" then
						local display = raw.display_name
						if type(display) ~= "string" or display == "" then
							display = raw.id
						end
						local icon = raw.icon
						if type(icon) ~= "string" then
							icon = "⚔"
						end
						local recipeIds: { string } = {}
						if type(raw.recipes) == "table" then
							for _, rid in ipairs(raw.recipes) do
								if type(rid) == "string" and result.recipes[rid] then
									table.insert(recipeIds, rid)
								end
							end
						end
						table.insert(cats, {
							id = raw.id,
							display_name = display,
							icon = icon,
							recipes = recipeIds,
						})
					end
				end
				if #cats > 0 then
					result.categories = cats
				end
			end
		end
	end

	cached = result
	return result
end

local function loadMeleePreviews(): { [string]: MeleePreview }
	if meleeCache then
		return meleeCache
	end
	local result: { [string]: MeleePreview } = {
		FistWeapon = { damage = 50, attack_speed = 2.6 },
		Axe = { damage = 8, attack_speed = 2.0 },
		Pickaxe = { damage = 8, attack_speed = 1.8 },
	}

	local inst = ReplicatedStorage:FindFirstChild("items_config")
	if inst and inst:IsA("StringValue") and inst.Value ~= "" then
		local ok, data = pcall(function()
			return HttpService:JSONDecode(relaxJson(inst.Value))
		end)
		if ok and type(data) == "table" then
			for itemId, raw in pairs(data) do
				if type(itemId) == "string" and type(raw) == "table" and raw.kind == "melee" then
					local damage = 0
					if type(raw.damages) == "table" then
						damage = tonumber(raw.damages[1]) or 0
					end
					local cd = tonumber(raw.attack_cooldown) or 0.5
					if cd <= 0 then
						cd = 0.5
					end
					local speed = math.floor((1 / cd) * 10 + 0.5) / 10
					result[itemId] = {
						damage = damage,
						attack_speed = speed,
					}
				end
			end
		end
	end

	meleeCache = result
	return result
end

function CraftCatalog.GetCategories(): { Category }
	return loadCraft().categories
end

function CraftCatalog.GetRecipe(recipeId: string): Recipe?
	return loadCraft().recipes[recipeId]
end

function CraftCatalog.GetRecipesForCategory(categoryId: string): { Recipe }
	local data = loadCraft()
	local list: { Recipe } = {}
	for _, cat in ipairs(data.categories) do
		if cat.id == categoryId then
			for _, recipeId in ipairs(cat.recipes) do
				local recipe = data.recipes[recipeId]
				if recipe then
					table.insert(list, recipe)
				end
			end
			break
		end
	end
	return list
end

function CraftCatalog.GetMeleePreview(itemId: string): MeleePreview?
	return loadMeleePreviews()[itemId]
end

return CraftCatalog
