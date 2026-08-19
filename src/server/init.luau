print("🚀 Сервер R1 запускается...")

-- Подключаем модули
local SSS = game:GetService("ServerScriptService")
local TerrainGen = require(SSS.TerrainGenerator)
local ObjectGen = require(SSS.ObjectGenerator)

-- Проверяем флаг мира
local WorldFlag = workspace:FindFirstChild("WorldGenerated_v1")

if not WorldFlag then
    warn("⚠️ Мир не найден. Начинаю полную генерацию...")
    
    -- 1. Очищаем старые объекты (если они остались с прошлых тестов)
    print(" Очищаю карту от старых объектов...")
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "BigTree" or obj.Name == "thin_tree" or obj.Name == "Stick" then
            obj:Destroy()
        end
    end
    
    -- 2. Генерируем ландшафт
    TerrainGen.Generate()
    
    -- 3. Генерируем деревья и ветки
    ObjectGen.Generate()
    
    -- 4. Ставим флаг
    local flag = Instance.new("BoolValue")
    flag.Name = "WorldGenerated_v1"
    flag.Parent = workspace
    
    print("✨ Мир успешно создан!")
else
    print("ℹ️ Мир уже существует. Пропускаю генерацию.")
end