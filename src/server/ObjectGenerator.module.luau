local ObjectGenerator = {}

function ObjectGenerator.Generate()
    local Terrain = workspace.Terrain
    local RepStorage = game:GetService("ReplicatedStorage")
    local MapSize = 2000
    local ChunkSize = 256
    local VoxelRes = 4

    -- Функция ТОЧНОГО поиска поверхности через Raycast
    local function getExactSurfaceY(x, z)
        local startPos = Vector3.new(x, 200, z)
        local direction = Vector3.new(0, -300, 0)
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Include
        rayParams.FilterDescendantsInstances = {Terrain}
        local result = workspace:Raycast(startPos, direction, rayParams)
        if result then return result.Position.Y else return nil end
    end

    -- ВЫРАВНИВАНИЕ ПЛОЩАДКИ под крупным объектом
    local function flattenPad(x, z, levelY, radius)
        local region = Region3.new(
            Vector3.new(x - radius, levelY - 20, z - radius),
            Vector3.new(x + radius, levelY + 20, z + radius)
        ):ExpandToGrid(VoxelRes)

        local rMin = region.CFrame.Position - (region.Size / 2)
        local materials, occupancy = Terrain:ReadVoxels(region, VoxelRes)
        if not materials then return end

        local sizeX, sizeY, sizeZ = #materials, #materials[1], #materials[1][1]
        local t = math.floor((levelY - rMin.Y) / VoxelRes) + 1
        if t < 3 or t > sizeY - 1 then return end

        for xi = 1, sizeX do
            for zi = 1, sizeZ do
                for yi = t + 1, sizeY do
                    materials[xi][yi][zi] = Enum.Material.Air
                end
                for yi = t - 2, t do
                    materials[xi][yi][zi] = Enum.Material.Grass
                end
            end
        end

        Terrain:WriteVoxels(region, VoxelRes, materials, occupancy)
    end

    -- СЕТКА ЗАНЯТОСТИ: крупные объекты не спавнятся вплотную
    local placed = {}
    local function isCrowded(x, z)
        local cx, cz = math.floor(x / 12), math.floor(z / 12)
        for dx = -1, 1 do
            for dz = -1, 1 do
                if placed[(cx + dx) .. "," .. (cz + dz)] then
                    return true
                end
            end
        end
        return false
    end
    local function markPlaced(x, z)
        placed[math.floor(x / 12) .. "," .. math.floor(z / 12)] = true
    end

    -- Ищем шаблоны
    local assetsFolder = RepStorage:FindFirstChild("assets")
    local ThinTreeTemplate = assetsFolder and assetsFolder:FindFirstChild("BigTree")
    local MegaTreeTemplate = assetsFolder and assetsFolder:FindFirstChild("MegaTree")
    local SmallRockTemplate = assetsFolder and assetsFolder:FindFirstChild("SmallRock")
    local MediumRockTemplate = assetsFolder and assetsFolder:FindFirstChild("MediumRock")

    if not ThinTreeTemplate then
        warn("⚠️ НЕ НАШЕЛ BigTree В assets!")
        return
    end

    print("🌲 Начинаю генерацию объектов...")
    local startTime = tick()
    local ThinTreeCount, MegaTreeCount, StickCount = 0, 0, 0
    local RockCount, BoulderCount = 0, 0

    -- Деревья и камни растут ТОЛЬКО на траве
    local ALLOWED = {
        [Enum.Material.Grass] = true,
        [Enum.Material.LeafyGrass] = true
    }

    for startX = -MapSize/2, MapSize/2 - ChunkSize, ChunkSize do
        for startZ = -MapSize/2, MapSize/2 - ChunkSize, ChunkSize do
            
            local region = Region3.new(
                Vector3.new(startX, -50, startZ),
                Vector3.new(startX + ChunkSize, 100, startZ + ChunkSize)
            ):ExpandToGrid(VoxelRes)

            local rMin = region.CFrame.Position - (region.Size / 2)
            local materials = Terrain:ReadVoxels(region, VoxelRes)

            if materials then
                local sizeX, sizeY, sizeZ = #materials, #materials[1], #materials[1][1]

                -- ПРОВЕРКА ВОДЫ ВОКРУГ: деревья не спавнятся у берегов
                -- radiusCells: 3 ячейки по 4 студия = 12 студиов радиус
                local function nearWater(xi, zi, radiusCells)
                    for dx = -radiusCells, radiusCells do
                        for dz = -radiusCells, radiusCells do
                            local nx, nz = xi + dx, zi + dz
                            if nx >= 1 and nx <= sizeX and nz >= 1 and nz <= sizeZ then
                                for yi = sizeY, 1, -1 do
                                    local m = materials[nx][yi][nz]
                                    if m ~= Enum.Material.Air then
                                        if m == Enum.Material.Water then
                                            return true
                                        end
                                        break
                                    end
                                end
                            end
                        end
                    end
                    return false
                end

                for xi = 1, sizeX do
                    for zi = 1, sizeZ do
                        
                        -- Базовая высота
                        local baseY = nil
                        for yi = sizeY, 1, -1 do
                            local mat = materials[xi][yi][zi]
                            if mat ~= Enum.Material.Air and mat ~= Enum.Material.Water then
                                if ALLOWED[mat] then
                                    baseY = rMin.Y + (yi - 1) * VoxelRes
                                    break
                                else 
                                    break 
                                end
                            end
                        end

                        if baseY then
                            local worldX = rMin.X + (xi - 1) * VoxelRes
                            local worldZ = rMin.Z + (zi - 1) * VoxelRes
                            local rand = math.random()

                            -- ТОЧНАЯ высота земли для посадки
                            local exactY = getExactSurfaceY(worldX, worldZ) or (baseY + 4)

                            -- 1. ТОНКИЕ ДЕРЕВЬЯ (полоса 0..0.25%)
                            if rand < 0.0025 then
                                if not isCrowded(worldX, worldZ) and not nearWater(xi, zi, 2) then
                                    local newTree = ThinTreeTemplate:Clone()
                                    if not newTree.PrimaryPart then 
                                        newTree.PrimaryPart = newTree:FindFirstChildWhichIsA("BasePart") 
                                    end
                                    pcall(function() newTree:ScaleTo(Vector3.new(0.35, 0.35, 0.35)) end)
                                    if newTree.PrimaryPart then
                                        -- Заглубляем на 2 студия: на склонах не светит корнями
                                        newTree:SetPrimaryPartCFrame(CFrame.new(worldX, exactY + 14, worldZ))
                                        newTree.Parent = workspace
                                        ThinTreeCount += 1
                                        markPlaced(worldX, worldZ)
                                        
                                        -- Ветка рядом (дроп с дерева)
                                        if math.random() < 0.6 then
                                            local angle = math.random() * math.pi * 2
                                            local dist = math.random(2, 4)
                                            local sx = worldX + math.cos(angle) * dist
                                            local sz = worldZ + math.sin(angle) * dist
                                            local sy = getExactSurfaceY(sx, sz)
                                            if sy then
                                                local stick = Instance.new("Part")
                                                stick.Size = Vector3.new(2.4, 0.6, 0.6)
                                                stick.Anchored = true
                                                stick.Color = Color3.fromRGB(120, 80, 40)
                                                stick.Shape = Enum.PartType.Cylinder
                                                stick.CanCollide = false
                                                stick.Name = "Stick"
                                                stick.CFrame = CFrame.new(sx, sy + 0.3, sz) * CFrame.Angles(0, 0, math.rad(math.random(-25, 25)))
                                                stick.Parent = workspace
                                                StickCount += 1
                                            end
                                        end
                                    end
                                end

                            -- 2. МЕГА-ДЕРЕВЬЯ (полоса 0.25..0.5%) + ровная площадка
                            elseif rand < 0.005 then
                                if MegaTreeTemplate and not isCrowded(worldX, worldZ) and not nearWater(xi, zi, 4) then
                                    -- Сначала выравниваем полянку под деревом
                                    flattenPad(worldX, worldZ, exactY, 10)
                                    local padY = getExactSurfaceY(worldX, worldZ) or exactY

                                    local megaTree = MegaTreeTemplate:Clone()
                                    local soil = Instance.new("Part")
                                    soil.Name = "Soil"; soil.Size = Vector3.new(1,1,1)
                                    soil.Transparency = 1; soil.Anchored = true; soil.CanCollide = false
                                    soil.Parent = megaTree
                                    megaTree.PrimaryPart = soil
                                    pcall(function() megaTree:ScaleTo(Vector3.new(2.5, 2.5, 2.5)) end)
                                    megaTree:SetPrimaryPartCFrame(CFrame.new(worldX, padY - 2, worldZ))
                                    megaTree.Parent = workspace
                                    MegaTreeCount += 1
                                    markPlaced(worldX, worldZ)
                                end

                            -- 3. ОТДЕЛЬНЫЕ ВЕТКИ (полоса 0.5..0.8%)
                            elseif rand < 0.008 then
                                local sy = getExactSurfaceY(worldX, worldZ)
                                if sy then
                                    local stick = Instance.new("Part")
                                    stick.Size = Vector3.new(2.4, 0.6, 0.6)
                                    stick.Anchored = true
                                    stick.Color = Color3.fromRGB(120, 80, 40)
                                    stick.Shape = Enum.PartType.Cylinder
                                    stick.CanCollide = false
                                    stick.Name = "Stick"
                                    stick.CFrame = CFrame.new(worldX, sy + 0.3, worldZ) * CFrame.Angles(0, 0, math.rad(math.random(-30, 30)))
                                    stick.Parent = workspace
                                    StickCount += 1
                                end
                            
                            -- 4. МЕЛКИЕ КАМНИ (полоса 0.8..2%)
                            elseif rand < 0.02 then
                                if SmallRockTemplate and not isCrowded(worldX, worldZ) then
                                    local rock = SmallRockTemplate:Clone()
                                    local rot = CFrame.Angles(0, math.random() * math.pi * 2, 0)
                                    
                                    local halfHeight = rock.Size.Y / 2
                                    rock.CFrame = CFrame.new(worldX, exactY + halfHeight - 0.3, worldZ) * rot
                                    rock.Anchored = true
                                    rock.Color = Color3.fromRGB(100, 100, 100) 
                                    rock.Transparency = 0
                                    
                                    rock.Parent = workspace
                                    RockCount += 1
                                    markPlaced(worldX, worldZ)
                                end

                            -- 5. ВАЛУНЫ (полоса 2..2.5%)
                            elseif rand < 0.025 then
                                if MediumRockTemplate and not isCrowded(worldX, worldZ) then
                                    local boulder = MediumRockTemplate:Clone()
                                    local rotX = math.rad(math.random(-15, 15))
                                    local rotY = math.random() * math.pi * 2
                                    local rot = CFrame.Angles(rotX, rotY, 0)
                                    
                                    local halfHeight = boulder.Size.Y / 2
                                    boulder.CFrame = CFrame.new(worldX, exactY + halfHeight - 0.5, worldZ) * rot
                                    boulder.Anchored = true
                                    boulder.Color = Color3.fromRGB(80, 80, 80)
                                    boulder.Transparency = 0
                                    
                                    boulder.Parent = workspace
                                    BoulderCount += 1
                                    markPlaced(worldX, worldZ)
                                end
                            end
                        end -- Конец if baseY
                    end -- Конец for zi
                end -- Конец for xi
            end -- Конец if materials
            
            if startX % 500 == 0 and startZ % 500 == 0 then
                print(string.format("Чанк [%.0f, %.0f] | Деревья: %d Мега: %d Камни: %d Валуны: %d", 
                    startX, startZ, ThinTreeCount, MegaTreeCount, RockCount, BoulderCount))
                wait()
            end
        end -- Конец for startZ
    end -- Конец for startX

    print("✅ ВСЁ ГОТОВО!")
    print(string.format("⏱️ Время: %.2f сек | 🌱 Деревья: %d | 🌳 Мега: %d | 🪨 Камни: %d | 🗿 Валуны: %d", 
        tick() - startTime, ThinTreeCount, MegaTreeCount, RockCount, BoulderCount))
end

return ObjectGenerator