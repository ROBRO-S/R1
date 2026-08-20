print("🚀 Сервер R1 запускается...")

local SSS = game:GetService("ServerScriptService")
local TerrainGen = require(SSS.TerrainGenerator)
local ObjectGen = require(SSS.ObjectGenerator)

local WorldFlag = workspace:FindFirstChild("WorldGenerated_v1")

if not WorldFlag then
    warn("⚠️ Мир не найден. Начинаю полную генерацию...")
    
    print(" Очищаю карту от старых объектов...")
    for _, obj in ipairs(workspace:GetChildren()) do
        -- Добавил SmallRock и MediumRock в список очистки
        if obj.Name == "BigTree" or obj.Name == "thin_tree" or obj.Name == "Stick" 
           or obj.Name == "SmallRock" or obj.Name == "MediumRock" or obj.Name == "MegaTree" then
            obj:Destroy()
        end
    end
    
    TerrainGen.Generate()
    ObjectGen.Generate()
    
    local flag = Instance.new("BoolValue")
    flag.Name = "WorldGenerated_v1"
    flag.Parent = workspace
    
    print("✨ Мир успешно создан!")
else
    print("ℹ️ Мир уже существует. Пропускаю генерацию.")
end