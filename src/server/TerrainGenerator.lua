-- Создай Script в ServerScriptService
-- Этот скрипт будет запускаться ТОЛЬКО когда ты явно его вызовешь

local Terrain = workspace.Terrain
local MapSize = 2000
local Resolution = 4
local BaseHeight = 10

local function getHeight(x, z)
	local scale1 = 0.008
	local scale2 = 0.03
	local amplitude1 = 15
	local amplitude2 = 5
	
	local noise1 = math.noise(x * scale1, 0, z * scale1) * amplitude1
	local noise2 = math.noise(x * scale2, 100, z * scale2) * amplitude2
	
	return BaseHeight + noise1 + noise2
end

local function getMaterial(x, z, height)
	local distFromCenter = math.sqrt(x^2 + z^2)
	
	if x > 600 and z > 600 then
		return Enum.Material.Sand
	end
	
	if height < BaseHeight - 3 then
		return Enum.Material.Mud
	elseif height > BaseHeight + 12 then
		return Enum.Material.Rock
	else
		return Enum.Material.Grass
	end
end

print("=== ГЕНЕРАЦИЯ ЛАНДШАФТА ===")
print("Размер: " .. MapSize .. "x" .. MapSize)

local startTime = tick()
local cellsGenerated = 0

for x = -MapSize/2, MapSize/2, Resolution do
	for z = -MapSize/2, MapSize/2, Resolution do
		local height = getHeight(x, z)
		local material = getMaterial(x, z, height)
		
		local region = Region3.new(
			Vector3.new(x, -50, z),
			Vector3.new(x + Resolution, height, z + Resolution)
		)
		
		Terrain:FillRegion(region, Resolution, material)
		cellsGenerated = cellsGenerated + 1
		
		if cellsGenerated % 5000 == 0 then
			print("Прогресс: " .. cellsGenerated .. " ячеек")
			wait() -- даем студии передохнуть
		end
	end
end

local endTime = tick()
print("✓ Генерация завершена!")
print("Время: " .. string.format("%.2f", endTime - startTime) .. " сек")
print("Ячеек: " .. cellsGenerated)
print("Не забудь сохранить Place (Ctrl+S)!")