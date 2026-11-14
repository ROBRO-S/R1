--!strict
-- Тонкий вход: логика в PickaxeCombat ModuleScript (его же стартует FistWeapon).

print("PickaxeCombat.server: boot")

local ServerScriptService = game:GetService("ServerScriptService")

local ok, modOrErr = pcall(function()
	return require(ServerScriptService:WaitForChild("PickaxeCombat"))
end)
if not ok then
	warn("PickaxeCombat.server: require failed:", modOrErr)
	return
end

local PickaxeCombat = modOrErr
if type(PickaxeCombat) == "table" and type(PickaxeCombat.Start) == "function" then
	PickaxeCombat.Start()
else
	warn("PickaxeCombat.server: модуль без Start()")
end
