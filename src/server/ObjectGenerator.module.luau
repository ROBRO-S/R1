local ObjectGenerator = {}

function ObjectGenerator.Generate()
    local ConfigLoader = require(script.Parent:WaitForChild("ConfigLoader"))
    local cfg = ConfigLoader.Get()
    local props = cfg.props
    -- Пороги строго растут: тонкое < мега < ветка < камень < валун.
    local spawn = ConfigLoader.SpawnThresholds(cfg)

    local Terrain = workspace.Terrain
    local RepStorage = game:GetService("ReplicatedStorage")
    local MapSize = cfg.map_size
    local ChunkSize = cfg.chunk_size
    local VoxelRes = cfg.voxel_res
    local occupancyCell = cfg.occupancy_cell_size
    local flattenRadius = cfg.flatten_radius
    local nearWaterThin = cfg.near_water_radius_thin
    local nearWaterMega = cfg.near_water_radius_mega

    if occupancyCell <= 0 or flattenRadius < 0 or nearWaterThin < 0 or nearWaterMega < 0 then
        warn("⚠️ Некорректные occupancy/flatten/near_water в biome_config")
    end
    if occupancyCell <= 0 then
        occupancyCell = VoxelRes
    end

    -- Вода и скала сюда не входят: на них объекты не ставятся.
    local ALLOWED = {
        [Enum.Material.Grass] = true,
        [Enum.Material.Mud] = true,
        [Enum.Material.LeafyGrass] = true,
        [Enum.Material.Sand] = true,
    }

    local function colorFrom(rgb)
        return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Include
    rayParams.FilterDescendantsInstances = { Terrain }
    rayParams.IgnoreWater = false

    -- Луч с высокой точки, а не от грубого вокселя: так низ объекта совпадает с землёй.
    local function groundHit(x, z)
        return workspace:Raycast(
            Vector3.new(x, props.ray_start_y, z),
            Vector3.new(0, -props.ray_depth, 0),
            rayParams
        )
    end

    local occupied = {}

    local function forEachCell(x, z, radius, callback)
        local minX = math.floor((x - radius) / occupancyCell)
        local maxX = math.floor((x + radius) / occupancyCell)
        local minZ = math.floor((z - radius) / occupancyCell)
        local maxZ = math.floor((z + radius) / occupancyCell)
        for ix = minX, maxX do
            for iz = minZ, maxZ do
                if callback(ix, iz) then
                    return true
                end
            end
        end
        return false
    end

    local function areaFree(x, z, radius)
        local blocked = forEachCell(x, z, radius, function(ix, iz)
            return occupied[ix .. ":" .. iz] == true
        end)
        return not blocked
    end

    local function claim(x, z, radius)
        forEachCell(x, z, radius, function(ix, iz)
            occupied[ix .. ":" .. iz] = true
            return false
        end)
    end

    local waterPlane = cfg.water_world_y

    -- Луч часто пролетает воду и бьёт в дно. Дно ниже зеркала и воксель с водой — это пруд.
    local function pointIsWet(x, z, groundY)
        if groundY < waterPlane - 0.05 then
            return true
        end
        local y0 = math.min(groundY, waterPlane) - VoxelRes
        local y1 = math.max(groundY, waterPlane) + VoxelRes
        if y1 - y0 < 0.2 then
            y1 = y0 + VoxelRes
        end
        local region = Region3.new(
            Vector3.new(x, y0, z),
            Vector3.new(x + 0.25, y1, z + 0.25)
        ):ExpandToGrid(VoxelRes)
        local mats = Terrain:ReadVoxels(region, VoxelRes)
        if not mats then
            return false
        end
        for xi = 1, #mats do
            local column = mats[xi]
            for yi = 1, #column do
                local row = column[yi]
                for zi = 1, #row do
                    if row[zi] == Enum.Material.Water then
                        return true
                    end
                end
            end
        end
        return false
    end

    -- Суша только под основанием. Радиус кроны занятость не путает с проверкой воды.
    local function usableGround(x, z, occupyRadius, waterRadius)
        if not areaFree(x, z, occupyRadius) then
            return nil
        end
        local foot = waterRadius or 0
        if foot <= 0 then
            foot = math.min(occupyRadius or 1, 2)
        end
        if foot > 3 then
            foot = 3
        end
        if foot < 1 then
            foot = 1
        end
        local offsets = {
            { 0, 0 },
            { foot, 0 },
            { -foot, 0 },
            { 0, foot },
            { 0, -foot },
        }
        local center = nil
        for index, off in offsets do
            local hit = groundHit(x + off[1], z + off[2])
            if not hit or hit.Normal.Y < 0.45 then
                return nil
            end
            if hit.Material == Enum.Material.Water or not ALLOWED[hit.Material] then
                return nil
            end
            if pointIsWet(x + off[1], z + off[2], hit.Position.Y) then
                return nil
            end
            if index == 1 then
                center = hit
            end
        end
        return center
    end

    local function opaqueParts(root)
        local list = {}
        local function consider(inst)
            if inst:IsA("BasePart") and inst.Transparency < 1 then
                table.insert(list, inst)
            end
        end
        consider(root)
        for _, child in root:GetDescendants() do
            consider(child)
        end
        return list
    end

    local function boundsOf(parts)
        local minX, minY, minZ = math.huge, math.huge, math.huge
        local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
        for _, part in parts do
            local hx = part.Size.X * 0.5
            local hy = part.Size.Y * 0.5
            local hz = part.Size.Z * 0.5
            local cf = part.CFrame
            for _, sx in { -hx, hx } do
                for _, sy in { -hy, hy } do
                    for _, sz in { -hz, hz } do
                        local point = cf:PointToWorldSpace(Vector3.new(sx, sy, sz))
                        if point.X < minX then minX = point.X end
                        if point.Y < minY then minY = point.Y end
                        if point.Z < minZ then minZ = point.Z end
                        if point.X > maxX then maxX = point.X end
                        if point.Y > maxY then maxY = point.Y end
                        if point.Z > maxZ then maxZ = point.Z end
                    end
                end
            end
        end
        return minX, minY, minZ, maxX, maxY, maxZ
    end

    -- Сажает самую нижнюю точку сетки на луч. Центр кроны для этого не используется:
    -- иначе ствол уезжает в сторону и оказывается в воде или над пустотой.
    local function seatInstance(inst, x, z, rot, groundY)
        local placed = CFrame.new(x, groundY, z) * rot
        if inst:IsA("Model") then
            inst:PivotTo(placed)
            local parts = opaqueParts(inst)
            if #parts == 0 then
                return false
            end
            local baseX, baseZ, minY = nil, nil, math.huge
            for _, part in parts do
                local hx = part.Size.X * 0.5
                local hy = part.Size.Y * 0.5
                local hz = part.Size.Z * 0.5
                local cf = part.CFrame
                for _, sx in { -hx, hx } do
                    for _, sy in { -hy, hy } do
                        for _, sz in { -hz, hz } do
                            local point = cf:PointToWorldSpace(Vector3.new(sx, sy, sz))
                            if point.Y < minY then
                                minY = point.Y
                                baseX = point.X
                                baseZ = point.Z
                            end
                        end
                    end
                end
            end
            inst:PivotTo(inst:GetPivot() + Vector3.new(x - baseX, groundY - minY, z - baseZ))
            return true
        end

        inst.CFrame = placed
        local _, minY = boundsOf({ inst })
        inst.CFrame = inst.CFrame + Vector3.new(0, groundY - minY, 0)
        return true
    end

    local function anchorAll(inst)
        if inst:IsA("BasePart") then
            inst.Anchored = true
        end
        for _, child in inst:GetDescendants() do
            if child:IsA("BasePart") then
                child.Anchored = true
            end
        end
    end

    local function flattenUnder(x, z, groundY, material)
        if flattenRadius <= 0 or material == Enum.Material.Water then
            return
        end
        local region = Region3.new(
            Vector3.new(x - flattenRadius, groundY - VoxelRes, z - flattenRadius),
            Vector3.new(x + flattenRadius, groundY, z + flattenRadius)
        ):ExpandToGrid(VoxelRes)
        Terrain:FillRegion(region, VoxelRes, material)
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

    local stickColor = colorFrom(props.stick_color)
    local smallRockColor = colorFrom(props.small_rock_color)
    local boulderColor = colorFrom(props.boulder_color)
    local besideSize = props.stick_beside_size
    local looseStickSize = props.stick_size

    local function scaleModel(model, scale)
        if scale == 1 or not model:IsA("Model") then
            return
        end
        -- UnionOperation (камни) сюда не попадают: ScaleTo только у Model.
        pcall(function()
            model:ScaleTo(Vector3.new(scale, scale, scale))
        end)
    end

    local function spawnModel(template, scale, x, z, rot, occupyRadius, waterExtra, prepare)
        if not template or not template:IsA("Model") then
            return nil
        end
        -- Радиус берём из конфига, а не из кроны: иначе мега-дерево
        -- требует пустую поляну размером с листву и не ставится вообще.
        local hit = usableGround(x, z, occupyRadius, waterExtra or 0)
        if not hit then
            return nil
        end

        local model = template:Clone()
        if not model.PrimaryPart then
            local part = model:FindFirstChildWhichIsA("BasePart", true)
            if part then
                model.PrimaryPart = part
            end
        end
        if prepare then
            prepare(model)
        end
        scaleModel(model, scale)
        model.Parent = workspace
        if not seatInstance(model, x, z, rot, hit.Position.Y) then
            model:Destroy()
            return nil
        end
        anchorAll(model)
        claim(x, z, occupyRadius)
        flattenUnder(x, z, hit.Position.Y, hit.Material)
        return model, occupyRadius
    end

    local function spawnPart(template, x, z, rot, color, occupyRadius)
        if not template or not template:IsA("BasePart") then
            return nil
        end
        local hit = usableGround(x, z, occupyRadius, math.min(occupyRadius, 3))
        if not hit then
            return nil
        end

        local part = template:Clone()
        part.Color = color
        part.Transparency = props.rock_transparency
        part.Parent = workspace
        if not seatInstance(part, x, z, rot, hit.Position.Y) then
            part:Destroy()
            return nil
        end
        anchorAll(part)
        claim(x, z, occupyRadius)
        flattenUnder(x, z, hit.Position.Y, hit.Material)
        return part
    end

    local function makeStick(x, z, size, tilt, hit, radius)
        local stick = Instance.new("Part")
        stick.Name = "Stick"
        stick.Size = Vector3.new(size[1], size[2], size[3])
        stick.Color = stickColor
        stick.Shape = Enum.PartType.Cylinder
        stick.CanCollide = false
        stick.Parent = workspace
        local rot = CFrame.Angles(0, 0, math.rad(math.random(-tilt, tilt)))
        if not seatInstance(stick, x, z, rot, hit.Position.Y) then
            stick:Destroy()
            return false
        end
        anchorAll(stick)
        claim(x, z, radius)
        return true
    end

    local function placeBesideStick(x, z, treeRadius)
        if math.random() >= props.stick_beside_chance then
            return false
        end
        local stickRadius = math.max(besideSize[1], besideSize[3]) * 0.5
        local minDist = math.max(props.stick_beside_dist_min, treeRadius + stickRadius + 1)
        local maxDist = math.max(props.stick_beside_dist_max, minDist)
        for _ = 1, 6 do
            local angle = math.random() * math.pi * 2
            local dist = minDist
            if maxDist > minDist then
                dist = minDist + math.random() * (maxDist - minDist)
            end
            local sx = x + math.cos(angle) * dist
            local sz = z + math.sin(angle) * dist
            local hit = usableGround(sx, sz, stickRadius, stickRadius)
            if hit and makeStick(sx, sz, besideSize, props.stick_beside_tilt, hit, stickRadius) then
                return true
            end
        end
        return false
    end

    local function prepareMega(model)
        local soil = Instance.new("Part")
        local soilSize = props.soil_size
        soil.Name = "Soil"
        soil.Size = Vector3.new(soilSize, soilSize, soilSize)
        soil.Transparency = props.soil_transparency
        soil.Anchored = true
        soil.CanCollide = false
        soil.Parent = model
        model.PrimaryPart = soil
    end

    local thinRadius = props.thin_tree_radius
    local megaRadius = props.mega_tree_radius
    local smallRockRadius = props.small_rock_radius
    local boulderRadius = props.boulder_radius

    print("🌲 Начинаю генерацию с Raycast...")
    print(string.format(
        "Шансы клеток: thin %.4f | mega %.4f | stick %.4f | rock %.4f | boulder %.4f",
        cfg.probabilities.thin_tree,
        cfg.probabilities.mega_tree,
        cfg.probabilities.stick,
        cfg.probabilities.small_rock,
        cfg.probabilities.boulder
    ))
    print(string.format(
        "Занятость: %.0f | выравнивание: %.0f | у воды тонкие/мега: %.0f / %.0f",
        occupancyCell, flattenRadius, nearWaterThin, nearWaterMega
    ))
    local startTime = tick()
    local ThinTreeCount, MegaTreeCount, StickCount = 0, 0, 0
    local RockCount, BoulderCount = 0, 0

    -- Раньше цикл кончался на MapSize/2 - ChunkSize.
    -- 2000 не делится на 256, поэтому полоса около 208 студов (примерно 1/10 карты) оставалась пустой.
    local half = MapSize / 2
    local cursorX = -half
    while cursorX < half - 0.001 do
        local chunkX = math.min(ChunkSize, half - cursorX)
        local cursorZ = -half
        while cursorZ < half - 0.001 do
            local chunkZ = math.min(ChunkSize, half - cursorZ)

            local region = Region3.new(
                Vector3.new(cursorX, props.column_bottom_y, cursorZ),
                Vector3.new(cursorX + chunkX, props.column_top_y, cursorZ + chunkZ)
            ):ExpandToGrid(VoxelRes)

            local rMin = region.CFrame.Position - (region.Size / 2)
            local materials = Terrain:ReadVoxels(region, VoxelRes)

            if materials and materials[1] and materials[1][1] then
                local sizeX, sizeY, sizeZ = #materials, #materials[1], #materials[1][1]

                for xi = 1, sizeX do
                    for zi = 1, sizeZ do
                        local columnOk = false
                        for yi = sizeY, 1, -1 do
                            local mat = materials[xi][yi][zi]
                            if mat == Enum.Material.Water then
                                break
                            end
                            if mat ~= Enum.Material.Air then
                                columnOk = ALLOWED[mat] == true
                                break
                            end
                        end

                        if columnOk then
                            local worldX = rMin.X + (xi - 0.5) * VoxelRes
                            local worldZ = rMin.Z + (zi - 0.5) * VoxelRes
                            local rand = math.random()

                            -- 1. ТОНКИЕ ДЕРЕВЬЯ. Порог = вероятность thin_tree.
                            if rand < spawn.thin_tree then
                                local _, radius = spawnModel(
                                    ThinTreeTemplate,
                                    props.thin_tree_scale,
                                    worldX,
                                    worldZ,
                                    CFrame.new(),
                                    thinRadius,
                                    nearWaterThin
                                )
                                if radius then
                                    ThinTreeCount += 1
                                    if placeBesideStick(worldX, worldZ, radius) then
                                        StickCount += 1
                                    end
                                end

                            -- 2. МЕГА-ДЕРЕВЬЯ. Порог строго выше порога тонких деревьев.
                            elseif rand < spawn.mega_tree then
                                local _, radius = spawnModel(
                                    MegaTreeTemplate,
                                    props.mega_tree_scale,
                                    worldX,
                                    worldZ,
                                    CFrame.new(),
                                    megaRadius,
                                    nearWaterMega,
                                    prepareMega
                                )
                                if radius then
                                    MegaTreeCount += 1
                                end

                            -- 3. ОТДЕЛЬНЫЕ ВЕТКИ. Порог строго выше мега-деревьев.
                            elseif rand < spawn.stick then
                                local stickRadius = math.max(looseStickSize[1], looseStickSize[3]) * 0.5
                                local hit = usableGround(worldX, worldZ, stickRadius, stickRadius)
                                if hit and makeStick(worldX, worldZ, looseStickSize, props.stick_tilt, hit, stickRadius) then
                                    StickCount += 1
                                end

                            -- 4. МЕЛКИЕ КАМНИ. Порог строго выше веток.
                            -- SmallRock — UnionOperation, ScaleTo к нему не применяется.
                            elseif rand < spawn.small_rock then
                                local rot = CFrame.Angles(0, math.random() * math.pi * 2, 0)
                                if spawnPart(SmallRockTemplate, worldX, worldZ, rot, smallRockColor, smallRockRadius) then
                                    RockCount += 1
                                end

                            -- 5. ВАЛУНЫ. Порог строго выше мелких камней.
                            -- MediumRock — UnionOperation, ScaleTo к нему не применяется.
                            elseif rand < spawn.boulder then
                                local rotX = math.rad(math.random(-props.boulder_tilt, props.boulder_tilt))
                                local rotY = math.random() * math.pi * 2
                                local rot = CFrame.Angles(rotX, rotY, 0)
                                if spawnPart(MediumRockTemplate, worldX, worldZ, rot, boulderColor, boulderRadius) then
                                    BoulderCount += 1
                                end
                            end
                        end
                    end
                end
            end

            if cursorZ == -half then
                print(string.format("Чанк [%.0f, %.0f] | Деревья: %d Мега: %d Камни: %d Валуны: %d",
                    cursorX, cursorZ, ThinTreeCount, MegaTreeCount, RockCount, BoulderCount))
                wait()
            end

            cursorZ += ChunkSize
        end
        cursorX += ChunkSize
    end

    print("✅ ВСЁ ГОТОВО!")
    print(string.format(" Время: %.2f сек | 🌱 Деревья: %d | 🌳 Мега: %d | Ветки: %d | 🪨 Камни: %d | Валуны: %d",
        tick() - startTime, ThinTreeCount, MegaTreeCount, StickCount, RockCount, BoulderCount))
end

return ObjectGenerator
