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
    local treeBaseRadius = cfg.tree_base_radius
    local maxSlopeTree = cfg.max_slope_for_tree
    local maxSlopeProp = cfg.max_slope_for_prop
    local flattenRadius = cfg.flatten_radius
    local flatFraction = cfg.flatten_flat_fraction
    local exclusionRadius = cfg.exclusion_radius
    local spawnSearchRadius = cfg.spawn_search_radius
    local nearWaterThin = cfg.near_water_radius_thin
    local nearWaterMega = cfg.near_water_radius_mega

    if occupancyCell <= 0 then
        warn("⚠️ occupancy_cell_size должен быть больше 0. Беру voxel_res.")
        occupancyCell = VoxelRes
    end
    if flatFraction <= 0.05 or flatFraction >= 1 then
        warn("⚠️ flatten_flat_fraction должен быть между 0 и 1. Беру 0.5.")
        flatFraction = 0.5
    end
    if exclusionRadius < 0 or flattenRadius < 0 or treeBaseRadius <= 0 then
        warn("⚠️ Некорректные tree_base_radius / flatten_radius / exclusion_radius в biome_config.")
    end
    if exclusionRadius < 0 then
        exclusionRadius = 0
    end

    local function slopeLimit(mode)
        if mode == "level" then
            return maxSlopeTree
        end
        return maxSlopeProp
    end

    local function canLevel(mode)
        return mode == "level" or mode == "pad"
    end

    -- Вода и скала сюда не входят: на них объекты не ставятся.
    local ALLOWED = {
        [Enum.Material.Grass] = true,
        [Enum.Material.Ground] = true,
        [Enum.Material.Mud] = true,
        [Enum.Material.LeafyGrass] = true,
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

    -- Половина зазора с каждой стороны: вместе выходит exclusion_radius между основаниями.
    local function claimRadius(radius)
        return radius + exclusionRadius * 0.5
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

    local function slopeDegrees(normal)
        return math.deg(math.acos(math.clamp(normal.Y, -1, 1)))
    end

    -- mode "level": крутой уклон не запрещает спавн, его потом срезает площадка.
    local function inspectGround(x, z, sampleRadius, mode)
        local radius = sampleRadius
        if radius < 1 then
            radius = 1
        end
        local offsets = { { 0, 0 } }
        local spokes = 8
        for index = 1, spokes do
            local angle = (index / spokes) * math.pi * 2
            offsets[#offsets + 1] = { math.cos(angle) * radius, math.sin(angle) * radius }
        end

        local center = nil
        local ringSum, ringCount = 0, 0
        local minY, maxY = math.huge, -math.huge
        local steep = false
        local limit = slopeLimit(mode)

        for index, off in offsets do
            local hit = groundHit(x + off[1], z + off[2])
            if not hit or hit.Normal.Y <= 0 then
                return nil
            end
            if hit.Material == Enum.Material.Water or not ALLOWED[hit.Material] then
                return nil
            end
            if pointIsWet(x + off[1], z + off[2], hit.Position.Y) then
                return nil
            end
            if slopeDegrees(hit.Normal) > limit then
                if not canLevel(mode) then
                    return nil
                end
                steep = true
            end
            if index == 1 then
                center = hit
            else
                ringSum += hit.Position.Y
                ringCount += 1
            end
            minY = math.min(minY, hit.Position.Y)
            maxY = math.max(maxY, hit.Position.Y)
        end

        -- Кольцо проб — это диаметр основания, поэтому допуск уклона тоже на весь диаметр.
        local allowedDrop = 2 * radius * math.tan(math.rad(limit))
        if maxY - minY > allowedDrop then
            if not canLevel(mode) then
                return nil
            end
            steep = true
        end

        local padY = center.Position.Y
        if ringCount > 0 then
            -- Средняя высота кромки основания, а не вершина холма в центре луча.
            padY = ringSum / ringCount
        end

        return {
            hit = center,
            steep = steep,
            padY = padY,
            material = center.Material,
        }
    end

    local halfMap = MapSize / 2

    local function inMap(x, z, radius)
        return x - radius > -halfMap and x + radius < halfMap
            and z - radius > -halfMap and z + radius < halfMap
    end

    local function seek(x, z, occupyRadius, sampleRadius, mode)
        local padded = claimRadius(occupyRadius)

        local function accept(px, pz)
            if not inMap(px, pz, occupyRadius) then
                return nil, "bounds"
            end
            if not areaFree(px, pz, padded) then
                return nil, "busy"
            end
            local info = inspectGround(px, pz, sampleRadius, mode)
            if not info then
                return nil, "ground"
            end
            return info, nil
        end

        local info, reason = accept(x, z)
        if info then
            return { x = x, z = z, info = info, moved = false }
        end
        if reason ~= "busy" or spawnSearchRadius <= 0 then
            return nil
        end

        local step = math.max(occupancyCell, 1)
        for dist = step, spawnSearchRadius, step do
            local turns = math.floor((2 * math.pi * dist) / step)
            if turns < 8 then
                turns = 8
            end
            if turns > 24 then
                turns = 24
            end
            local spin = math.random() * math.pi * 2
            for turn = 1, turns do
                local angle = spin + (turn / turns) * math.pi * 2
                local px = x + math.cos(angle) * dist
                local pz = z + math.sin(angle) * dist
                local nearby = accept(px, pz)
                if nearby then
                    return { x = px, z = pz, info = nearby, moved = true }
                end
            end
        end

        return nil
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

    -- Сажает самую нижнюю точку сетки на площадку.
    -- lockXZ держит ствол в центре выровненного круга, а не на исходном пике.
    local function seatInstance(inst, x, z, rot, groundY, lockXZ)
        local placed = CFrame.new(x, groundY, z) * rot
        if inst:IsA("Model") then
            inst:PivotTo(placed)
            local parts = opaqueParts(inst)
            if #parts == 0 then
                return false
            end
            local minY, maxY = math.huge, -math.huge
            local corners = {}
            for _, part in parts do
                local hx = part.Size.X * 0.5
                local hy = part.Size.Y * 0.5
                local hz = part.Size.Z * 0.5
                local cf = part.CFrame
                for _, sx in { -hx, hx } do
                    for _, sy in { -hy, hy } do
                        for _, sz in { -hz, hz } do
                            local point = cf:PointToWorldSpace(Vector3.new(sx, sy, sz))
                            corners[#corners + 1] = point
                            minY = math.min(minY, point.Y)
                            maxY = math.max(maxY, point.Y)
                        end
                    end
                end
            end
            local baseX, baseZ = x, z
            if lockXZ then
                local band = minY + math.max((maxY - minY) * 0.2, VoxelRes)
                local sumX, sumZ, count = 0, 0, 0
                for _, point in corners do
                    if point.Y <= band then
                        sumX += point.X
                        sumZ += point.Z
                        count += 1
                    end
                end
                if count > 0 then
                    baseX = sumX / count
                    baseZ = sumZ / count
                end
            else
                for _, point in corners do
                    if point.Y <= minY + 0.001 then
                        baseX = point.X
                        baseZ = point.Z
                        break
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

    local function measuredBaseRadius(model)
        local pivot = model:GetPivot()
        local points = {}
        local function push(part)
            if not part:IsA("BasePart") or part.Transparency >= 1 then
                return
            end
            local hx = part.Size.X * 0.5
            local hy = part.Size.Y * 0.5
            local hz = part.Size.Z * 0.5
            local cf = part.CFrame
            for _, sx in { -hx, hx } do
                for _, sy in { -hy, hy } do
                    for _, sz in { -hz, hz } do
                        local world = cf:PointToWorldSpace(Vector3.new(sx, sy, sz))
                        points[#points + 1] = pivot:PointToObjectSpace(world)
                    end
                end
            end
        end
        for _, child in model:GetDescendants() do
            push(child)
        end
        if #points == 0 then
            return 0
        end
        local minY, maxY = math.huge, -math.huge
        for _, point in points do
            minY = math.min(minY, point.Y)
            maxY = math.max(maxY, point.Y)
        end
        local band = minY + math.max((maxY - minY) * 0.2, VoxelRes)
        local radius = 0
        for _, point in points do
            if point.Y <= band then
                radius = math.max(radius, math.sqrt(point.X * point.X + point.Z * point.Z))
            end
        end
        return radius
    end

    -- Внутренние flatten_flat_fraction радиуса — ровная земля, остаток плавно возвращается в склон.
    local function discRadii(baseRadius, wide)
        local outer = baseRadius / flatFraction
        if wide then
            outer = math.max(flattenRadius, outer)
        end
        return outer * flatFraction, outer
    end

    local padsLeveled = 0
    local warnedExpand = false

    local function flattenDisc(cx, cz, inner, outer, padY, material)
        local res = VoxelRes
        local minY, maxY = padY, padY
        local heights = {}

        local function remember(x, z, y)
            heights[math.floor(x / res + 0.5) .. ":" .. math.floor(z / res + 0.5)] = y
            minY = math.min(minY, y)
            maxY = math.max(maxY, y)
        end

        for x = cx - outer, cx + outer, res do
            for z = cz - outer, cz + outer, res do
                local dx = x - cx
                local dz = z - cz
                if dx * dx + dz * dz <= (outer + res) * (outer + res) then
                    local hit = groundHit(x, z)
                    local inside = dx * dx + dz * dz <= inner * inner
                    if not hit or hit.Material == Enum.Material.Water then
                        if inside then
                            return false
                        end
                    elseif not ALLOWED[hit.Material] then
                        if inside then
                            remember(x, z, padY)
                        end
                    else
                        remember(x, z, hit.Position.Y)
                    end
                end
            end
        end

        if maxY - minY < res then
            maxY = minY + res
        end

        local region = Region3.new(
            Vector3.new(cx - outer, minY - res * 2, cz - outer),
            Vector3.new(cx + outer, maxY + res * 2, cz + outer)
        ):ExpandToGrid(res)
        local materials, occupancy = Terrain:ReadVoxels(region, res)
        if not materials or not materials[1] or not materials[1][1] or not occupancy then
            return false
        end

        local rMin = region.CFrame.Position - (region.Size / 2)
        local sizeX, sizeY, sizeZ = #materials, #materials[1], #materials[1][1]

        for xi = 1, sizeX do
            for zi = 1, sizeZ do
                local wx = rMin.X + (xi - 0.5) * res
                local wz = rMin.Z + (zi - 0.5) * res
                local dx = wx - cx
                local dz = wz - cz
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist <= outer then
                    local oldY = heights[math.floor(wx / res + 0.5) .. ":" .. math.floor(wz / res + 0.5)]
                    if not oldY then
                        local hit = groundHit(wx, wz)
                        oldY = hit and hit.Position.Y or padY
                    end
                    local newY = padY
                    if dist > inner and outer > inner + 0.001 then
                        local u = (dist - inner) / (outer - inner)
                        local smooth = u * u * (3 - 2 * u)
                        newY = padY + (oldY - padY) * smooth
                    end
                    local solidTop = math.clamp(math.floor((newY - rMin.Y - 0.001) / res) + 1, 1, sizeY)
                    local clearTop = math.clamp(math.floor((math.max(oldY, newY) - rMin.Y - 0.001) / res) + 1, 1, sizeY)
                    for yi = 1, sizeY do
                        if yi < solidTop then
                            local mat = materials[xi][yi][zi]
                            if mat == Enum.Material.Air or mat == Enum.Material.Water then
                                materials[xi][yi][zi] = material
                                occupancy[xi][yi][zi] = 1
                            end
                        elseif yi == solidTop then
                            materials[xi][yi][zi] = material
                            occupancy[xi][yi][zi] = 1
                        elseif yi <= clearTop then
                            materials[xi][yi][zi] = Enum.Material.Air
                            occupancy[xi][yi][zi] = 0
                        end
                    end
                end
            end
        end

        local ok, err = pcall(function()
            Terrain:WriteVoxels(region, res, materials, occupancy)
        end)
        if not ok then
            warn("⚠️ Не удалось выровнять площадку: " .. tostring(err))
            return false
        end
        padsLeveled += 1
        if padsLeveled % 5 == 0 then
            task.wait()
        end
        return true
    end

    local function anchorY(x, z, padY)
        local hit = groundHit(x, z)
        if hit and hit.Material ~= Enum.Material.Water and math.abs(hit.Position.Y - padY) <= VoxelRes * 1.5 then
            return hit.Position.Y
        end
        return padY
    end

    -- Ищем шаблоны
    local assetsFolder = RepStorage:FindFirstChild("assets")
    local ThinTreeTemplate = assetsFolder and assetsFolder:FindFirstChild("BigTree")
    local MegaTreeTemplate = assetsFolder and assetsFolder:FindFirstChild("MegaTree")
    local SmallRockTemplate = assetsFolder and assetsFolder:FindFirstChild("SmallRock")
    local MediumRockTemplate = assetsFolder and assetsFolder:FindFirstChild("MediumRock")

    if not ThinTreeTemplate then
        warn("⚠️ НЕ НАШЕЛ BigTree В assets! Деревья/ветки у дерева пропущу.")
    end
    if not MegaTreeTemplate then
        warn("⚠️ НЕ НАШЕЛ MegaTree В assets!")
    end
    if not SmallRockTemplate then
        warn("⚠️ НЕ НАШЕЛ SmallRock В assets!")
    end
    if not MediumRockTemplate then
        warn("⚠️ НЕ НАШЕЛ MediumRock В assets!")
    end

    local stickColor = colorFrom(props.stick_color)
    local smallRockColor = colorFrom(props.small_rock_color)
    local boulderColor = colorFrom(props.boulder_color)
    local besideSize = props.stick_beside_size
    local looseStickSize = props.stick_size
    local scaleWarned = false
    local measureWarned = false
    local maxMeasured = 0

    local function scaleModel(model, scale)
        if scale == 1 or not model:IsA("Model") then
            return
        end
        local ok, err = pcall(function()
            model:ScaleTo(scale)
        end)
        if not ok and not scaleWarned then
            scaleWarned = true
            warn("⚠️ ScaleTo не применился: " .. tostring(err))
        end
    end

    local function placeModel(template, scale, x, z, rot, occupyRadius, sampleRadius, mode, widePad, prepare)
        if not template or not template:IsA("Model") then
            return nil
        end

        local model = template:Clone()
        if not model.PrimaryPart then
            local part = model:FindFirstChildWhichIsA("BasePart", true)
            if part then
                model.PrimaryPart = part
            end
        end
        scaleModel(model, scale)
        if prepare then
            prepare(model)
        end

        local footprint = occupyRadius
        local groundRadius = sampleRadius
        if widePad then
            local measured = measuredBaseRadius(model)
            if measured > maxMeasured then
                maxMeasured = measured
            end
            local padCap = math.max(treeBaseRadius, flattenRadius * flatFraction)
            if measured > padCap then
                if not measureWarned then
                    measureWarned = true
                    print(string.format(
                        "Основание MegaTree по мешу %.0f ст. Площадка ограничена tree_base_radius / flatten_radius (%.0f).",
                        measured, padCap
                    ))
                end
                measured = padCap
            end
            footprint = math.max(footprint, treeBaseRadius, measured)
            groundRadius = math.max(groundRadius, footprint)
        end

        local spot = seek(x, z, footprint, groundRadius, mode)
        if not spot then
            model:Destroy()
            return nil
        end

        local groundY = spot.info.hit.Position.Y
        if canLevel(mode) and spot.info.steep then
            local inner, outer = discRadii(groundRadius, widePad)
            if widePad and outer > flattenRadius + 0.01 and not warnedExpand then
                warnedExpand = true
                print(string.format(
                    "Площадка расширена до %.0f: основание %.0f не влезает в flatten_radius %.0f.",
                    outer, groundRadius, flattenRadius
                ))
            end
            if not flattenDisc(spot.x, spot.z, inner, outer, spot.info.padY, spot.info.material) then
                model:Destroy()
                return nil
            end
            groundY = anchorY(spot.x, spot.z, spot.info.padY)
        end

        model.Parent = workspace
        if not seatInstance(model, spot.x, spot.z, rot, groundY, mode == "level") then
            model:Destroy()
            return nil
        end
        -- mega_tree_lift < 0 утапливает корни ниже поверхности.
        local lift = 0
        if widePad then
            lift = props.mega_tree_lift or 0
        else
            lift = props.thin_tree_lift or 0
        end
        if lift ~= 0 then
            model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
        end
        anchorAll(model)
        claim(spot.x, spot.z, claimRadius(footprint))
        return model, footprint, spot.x, spot.z, spot.moved
    end

    local function spawnPart(template, x, z, rot, color, occupyRadius)
        if not template or not template:IsA("BasePart") then
            return nil
        end
        local visual = math.max(template.Size.X, template.Size.Z) * 0.5
        local footprint = math.max(occupyRadius, visual)
        local spot = seek(x, z, footprint, math.max(footprint, 1), "pad")
        if not spot then
            return nil
        end

        local groundY = spot.info.hit.Position.Y
        if spot.info.steep then
            local inner, outer = discRadii(footprint, false)
            if not flattenDisc(spot.x, spot.z, inner, outer, spot.info.padY, spot.info.material) then
                return nil
            end
            groundY = anchorY(spot.x, spot.z, spot.info.padY)
        end

        local part = template:Clone()
        part.Color = color
        part.Transparency = props.rock_transparency
        part.Parent = workspace
        if not seatInstance(part, spot.x, spot.z, rot, groundY, false) then
            part:Destroy()
            return nil
        end
        anchorAll(part)
        claim(spot.x, spot.z, claimRadius(footprint))
        return part, spot.moved
    end

    local function makeStick(x, z, size, tilt, groundY, radius)
        local stick = Instance.new("Part")
        stick.Name = "Stick"
        stick.Size = Vector3.new(size[1], size[2], size[3])
        stick.Color = stickColor
        stick.Shape = Enum.PartType.Cylinder
        stick.CanCollide = false
        stick.Parent = workspace
        local rot = CFrame.Angles(0, 0, math.rad(math.random(-tilt, tilt)))
        if not seatInstance(stick, x, z, rot, groundY, false) then
            stick:Destroy()
            return false
        end
        anchorAll(stick)
        claim(x, z, claimRadius(radius))
        return true
    end

    local function placeBesideStick(x, z, treeRadius)
        if math.random() >= props.stick_beside_chance then
            return false
        end
        local stickRadius = math.max(besideSize[1], besideSize[3]) * 0.5
        local minDist = math.max(props.stick_beside_dist_min, treeRadius + stickRadius + exclusionRadius)
        local maxDist = math.max(props.stick_beside_dist_max, minDist)
        for _ = 1, 6 do
            local angle = math.random() * math.pi * 2
            local dist = minDist
            if maxDist > minDist then
                dist = minDist + math.random() * (maxDist - minDist)
            end
            local sx = x + math.cos(angle) * dist
            local sz = z + math.sin(angle) * dist
            local spot = seek(sx, sz, stickRadius, math.max(stickRadius, 1), "strict")
            if spot and makeStick(spot.x, spot.z, besideSize, props.stick_beside_tilt, spot.info.hit.Position.Y, stickRadius) then
                return true
            end
        end
        return false
    end

    local function prepareMega(model)
        -- Видимые части непрозрачные; Soil только якорь посадки.
        for _, child in model:GetDescendants() do
            if child:IsA("BasePart") then
                child.Transparency = 0
            end
        end
        if model:IsA("BasePart") then
            model.Transparency = 0
        end

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
        "Основание %.0f | уклон дерева %.0f° | площадка %.0f (ровных %.0f%%) | зазор %.0f | поиск %.0f",
        treeBaseRadius,
        maxSlopeTree,
        flattenRadius,
        flatFraction * 100,
        exclusionRadius,
        spawnSearchRadius
    ))
    local startTime = tick()
    local ThinTreeCount, MegaTreeCount, StickCount = 0, 0, 0
    local RockCount, BoulderCount = 0, 0
    local movedCount = 0

    local function noteMove(moved)
        if moved then
            movedCount += 1
        end
    end

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
                                if ThinTreeTemplate then
                                    local _, radius, px, pz, moved = placeModel(
                                        ThinTreeTemplate,
                                        props.thin_tree_scale,
                                        worldX,
                                        worldZ,
                                        CFrame.new(),
                                        thinRadius,
                                        math.max(nearWaterThin, thinRadius),
                                        "level",
                                        false,
                                        nil
                                    )
                                    if radius then
                                        ThinTreeCount += 1
                                        noteMove(moved)
                                        if placeBesideStick(px, pz, radius) then
                                            StickCount += 1
                                        end
                                    end
                                end

                            -- 2. МЕГА-ДЕРЕВЬЯ. Порог строго выше порога тонких деревьев.
                            elseif rand < spawn.mega_tree then
                                if MegaTreeTemplate then
                                    local _, radius, _, _, moved = placeModel(
                                        MegaTreeTemplate,
                                        props.mega_tree_scale,
                                        worldX,
                                        worldZ,
                                        CFrame.new(),
                                        megaRadius,
                                        math.max(nearWaterMega, treeBaseRadius),
                                        "level",
                                        true,
                                        prepareMega
                                    )
                                    if radius then
                                        MegaTreeCount += 1
                                        noteMove(moved)
                                    end
                                end

                            -- 3. ОТДЕЛЬНЫЕ ВЕТКИ. Порог строго выше мега-деревьев.
                            elseif rand < spawn.stick then
                                local stickRadius = math.max(looseStickSize[1], looseStickSize[3]) * 0.5
                                local spot = seek(worldX, worldZ, stickRadius, math.max(stickRadius, 1), "strict")
                                if spot and makeStick(spot.x, spot.z, looseStickSize, props.stick_tilt, spot.info.hit.Position.Y, stickRadius) then
                                    StickCount += 1
                                    noteMove(spot.moved)
                                end

                            -- 4. МЕЛКИЕ КАМНИ. Порог строго выше веток.
                            -- SmallRock — UnionOperation, ScaleTo к нему не применяется.
                            elseif rand < spawn.small_rock then
                                local rot = CFrame.Angles(0, math.random() * math.pi * 2, 0)
                                local part, moved = spawnPart(SmallRockTemplate, worldX, worldZ, rot, smallRockColor, smallRockRadius)
                                if part then
                                    RockCount += 1
                                    noteMove(moved)
                                end

                            -- 5. ВАЛУНЫ. Порог строго выше мелких камней.
                            -- MediumRock — UnionOperation, ScaleTo к нему не применяется.
                            elseif rand < spawn.boulder then
                                local rotX = math.rad(math.random(-props.boulder_tilt, props.boulder_tilt))
                                local rotY = math.random() * math.pi * 2
                                local rot = CFrame.Angles(rotX, rotY, 0)
                                local part, moved = spawnPart(MediumRockTemplate, worldX, worldZ, rot, boulderColor, boulderRadius)
                                if part then
                                    BoulderCount += 1
                                    noteMove(moved)
                                end
                            end
                        end
                    end
                end
            end

            print(string.format("Чанк [%.0f, %.0f] | Деревья: %d Мега: %d Камни: %d Валуны: %d",
                cursorX, cursorZ, ThinTreeCount, MegaTreeCount, RockCount, BoulderCount))
            -- Yield каждый чанк: иначе Studio убивает ObjectGen по timeout после ландшафта.
            task.wait()

            cursorZ += ChunkSize
        end
        cursorX += ChunkSize
    end

    print("✅ ВСЁ ГОТОВО!")
    print(string.format(" Время: %.2f сек | 🌱 Деревья: %d | 🌳 Мега: %d | Ветки: %d | 🪨 Камни: %d | Валуны: %d",
        tick() - startTime, ThinTreeCount, MegaTreeCount, StickCount, RockCount, BoulderCount))
    print(string.format(" Площадок под деревья: %d | сдвинуто из занятой точки: %d | основание меша до %.0f",
        padsLeveled, movedCount, maxMeasured))
end

return ObjectGenerator
