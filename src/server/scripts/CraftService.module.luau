--!strict
-- Крафт: проверка рецепта, списание ресурсов, выдача результата.

local CraftService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local ItemsConfig = require(ServerScriptService:WaitForChild("ItemsConfig"))
local CraftCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CraftCatalog"))

local RATE_LIMIT = 0.35
local lastCraftAt: { [Player]: number } = {}

local function canAfford(player: Player, recipe: CraftCatalog.Recipe): boolean
	for _, cost in ipairs(recipe.costs) do
		if InventoryService.CountItem(player, cost.id) < cost.count then
			return false
		end
	end
	return true
end

function CraftService.Craft(player: Player, recipeId: string): boolean
	if typeof(recipeId) ~= "string" or recipeId == "" then
		return false
	end

	local now = os.clock()
	local last = lastCraftAt[player]
	if last and now - last < RATE_LIMIT then
		return false
	end

	local recipe = CraftCatalog.GetRecipe(recipeId)
	if not recipe then
		return false
	end
	if not ItemsConfig.IsKnown(recipe.result) then
		return false
	end
	if not canAfford(player, recipe) then
		return false
	end
	if not InventoryService.FindFreeSlot(player) then
		return false
	end

	for _, cost in ipairs(recipe.costs) do
		if not InventoryService.ConsumeItem(player, cost.id, cost.count) then
			return false
		end
	end

	local slot = InventoryService.AddItem(player, recipe.result, recipe.count)
	if not slot then
		-- Откат ресурсов, если слот внезапно заняли.
		for _, cost in ipairs(recipe.costs) do
			InventoryService.AddItem(player, cost.id, cost.count)
		end
		return false
	end

	lastCraftAt[player] = now
	return true
end

function CraftService.Start()
	local craftRemote = InventoryService.EnsureRemote("CraftItem")
	craftRemote.OnServerEvent:Connect(function(player: Player, recipeAny: any)
		if typeof(recipeAny) ~= "string" then
			return
		end
		CraftService.Craft(player, recipeAny)
	end)
end

return CraftService
