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

    print("🌲 Начинаю генерацию с Raycast...")
    local startTime = tick()
    local ThinTreeCount, MegaTreeCount, StickCount = 0, 0, 0
    local RockCount, BoulderCount = 0, 0

    local ALLOWED = {
        [Enum.Material.Grass] = true,
        [Enum.Material.Mud] = true,
        [Enum.Material.LeafyGrass] = true,
        [Enum.Material.Sand] = true
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
                                else break end
                            end
                        end

                        if baseY then
                            local worldX = rMin.X + (xi - 1) * VoxelRes
                            local worldZ = rMin.Z + (zi - 1) * VoxelRes
                            local rand = math.random()

                            -- 1. ТОНКИЕ ДЕРЕВЬЯ (0.4%)
                            if rand < 0.004 then
                                local newTree = ThinTreeTemplate:Clone()
                                if not newTree.PrimaryPart then 
                                    newTree.PrimaryPart = newTree:FindFirstChildWhichIsA("BasePart") 
                                end
                                pcall(function() newTree:ScaleTo(Vector3.new(0.35, 0.35, 0.35)) end)
                                if newTree.PrimaryPart then
                                    newTree:SetPrimaryPartCFrame(CFrame.new(worldX, baseY + 20, worldZ))
                                    newTree.Parent = workspace
                                    ThinTreeCount += 1
                                    
                                    -- Ветка рядом
                                    if math.random() < 0.6 then
                                        local angle = math.random() * math.pi * 2
                                        local dist = math.random(2, 4)
                                        local sx = worldX + math.cos(angle) * dist
                                        local sz = worldZ + math.sin(angle) * dist
                                        local sy = getExactSurfaceY(sx, sz)
                                        if sy then
                                            local stick = Instance.new("Part")
                                            stick.Size = Vector3.new(0.8, 0.2, 0.2)
                                            stick.Anchored = true
                                            stick.Color = Color3.fromRGB(120, 80, 40)
                                            stick.Shape = Enum.PartType.Cylinder
                                            stick.CanCollide = false
                                            stick.Name = "Stick"
                                            stick.CFrame = CFrame.new(sx, sy + 0.1, sz) * CFrame.Angles(0, 0, math.rad(math.random(-25, 25)))
                                            stick.Parent = workspace
                                            StickCount += 1
                                        end
                                    end
                                end

                            -- 2. МЕГА-ДЕРЕВЬЯ (0.5%)
                            elseif rand < 0.005 then
                                if MegaTreeTemplate then
                                    local megaTree = MegaTreeTemplate:Clone()
                                    local soil = Instance.new("Part")
                                    soil.Name = "Soil"; soil.Size = Vector3.new(1,1,1)
                                    soil.Transparency = 1; soil.Anchored = true; soil.CanCollide = false
                                    soil.Parent = megaTree
                                    megaTree.PrimaryPart = soil
                                    pcall(function() megaTree:ScaleTo(Vector3.new(2.5, 2.5, 2.5)) end)
                                    megaTree:SetPrimaryPartCFrame(CFrame.new(worldX, baseY + 0.5, worldZ))
                                    megaTree.Parent = workspace
                                    MegaTreeCount += 1
                                end

                            -- 3. ОТДЕЛЬНЫЕ ВЕТКИ (1.5%)
                            elseif rand < 0.019 then
                                local sy = getExactSurfaceY(worldX, worldZ)
                                if sy then
                                    local stick = Instance.new("Part")
                                    stick.Size = Vector3.new(0.8, 0.2, 0.2)
                                    stick.Anchored = true
                                    stick.Color = Color3.fromRGB(120, 80, 40)
                                    stick.Shape = Enum.PartType.Cylinder
                                    stick.CanCollide = false
                                    stick.Name = "Stick"
                                    stick.CFrame = CFrame.new(worldX, sy + 0.1, worldZ) * CFrame.Angles(0, 0, math.rad(math.random(-30, 30)))
                                    stick.Parent = workspace
                                    StickCount += 1
                                end
                            
                            -- 4. МЕЛКИЕ КАМНИ (3%) - НОРМАЛЬНЫЙ ЦВЕТ + ФИКС ПОЗИЦИИ
                            elseif rand < 0.03 then
                                if SmallRockTemplate then
                                    local rock = SmallRockTemplate:Clone()
                                    
                                    -- Рандомный поворот
                                    local rot = CFrame.Angles(0, math.random() * math.pi * 2, 0)
                                    
                                    -- Страховка: проверяем точную высоту земли через Raycast
                                    local rayStart = Vector3.new(worldX, baseY + 50, worldZ)
                                    local rayDir = Vector3.new(0, -100, 0)
                                    local params = RaycastParams.new()
                                    params.FilterType = Enum.RaycastFilterType.Include
                                    params.FilterDescendantsInstances = {Terrain}
                                    local result = workspace:Raycast(rayStart, rayDir, params)
                                    
                                    local groundY = result and result.Position.Y or baseY
                                    
                                    -- Ставим камень НА землю (центр + половина высоты)
                                    local halfHeight = rock.Size.Y / 2
                                    rock.CFrame = CFrame.new(worldX, groundY + halfHeight, worldZ) * rot
                                    
                                    rock.Anchored = true
                                    rock.Color = Color3.fromRGB(100, 100, 100) 
                                    rock.Transparency = 0
                                    
                                    rock.Parent = workspace
                                    RockCount += 1
                                end

                            -- 5. ВАЛУНЫ (0.5%) - НОРМАЛЬНЫЙ ЦВЕТ + ФИКС ПОЗИЦИИ
                            elseif rand < 0.035 then
                                if MediumRockTemplate then
                                    local boulder = MediumRockTemplate:Clone()
                                    
                                    -- Наклон + поворот
                                    local rotX = math.rad(math.random(-15, 15))
                                    local rotY = math.random() * math.pi * 2
                                    local rot = CFrame.Angles(rotX, rotY, 0)
                                    
                                    -- Точная высота земли
                                    local rayStart = Vector3.new(worldX, baseY + 50, worldZ)
                                    local rayDir = Vector3.new(0, -100, 0)
                                    local params = RaycastParams.new()
                                    params.FilterType = Enum.RaycastFilterType.Include
                                    params.FilterDescendantsInstances = {Terrain}
                                    local result = workspace:Raycast(rayStart, rayDir, params)
                                    
                                    local groundY = result and result.Position.Y or baseY
                                    
                                    local halfHeight = boulder.Size.Y / 2
                                    boulder.CFrame = CFrame.new(worldX, groundY + halfHeight, worldZ) * rot
                                    
                                    boulder.Anchored = true
                                    boulder.Color = Color3.fromRGB(80, 80, 80)
                                    boulder.Transparency = 0
                                    
                                    boulder.Parent = workspace
                                    BoulderCount += 1
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
    print(string.format(" Время: %.2f сек | 🌱 Деревья: %d | 🌳 Мега: %d | 🪨 Камни: %d |  Валуны: %d", 
        tick() - startTime, ThinTreeCount, MegaTreeCount, RockCount, BoulderCount))
end

return ObjectGenerator