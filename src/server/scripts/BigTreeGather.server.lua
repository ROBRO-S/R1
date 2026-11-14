--!strict
-- Тонкий вход: логика в BigTreeGather ModuleScript.

local ServerScriptService = game:GetService("ServerScriptService")

print("BigTreeGather.server: boot")

local ok, modOrErr = pcall(function()
	return require(ServerScriptService:WaitForChild("BigTreeGather"))
end)
if not ok then
	warn("BigTreeGather.server: require failed:", modOrErr)
	return
end

local BigTreeGather = modOrErr
if type(BigTreeGather) == "table" and type(BigTreeGather.Start) == "function" then
	BigTreeGather.Start()
else
	warn("BigTreeGather.server: модуль без Start()")
end
