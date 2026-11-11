--!strict
-- Тонкий вход: логика в AxeCombat ModuleScript (его же стартует FistWeapon).

local ServerScriptService = game:GetService("ServerScriptService")

print("AxeCombat.server: boot")

local ok, modOrErr = pcall(function()
	return require(ServerScriptService:WaitForChild("AxeCombat"))
end)
if not ok then
	warn("AxeCombat.server: require failed:", modOrErr)
	return
end

local AxeCombat = modOrErr
if type(AxeCombat) == "table" and type(AxeCombat.Start) == "function" then
	AxeCombat.Start()
else
	warn("AxeCombat.server: модуль без Start()")
end
