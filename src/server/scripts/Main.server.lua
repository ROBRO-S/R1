print("🚀 Сервер R1 запускается...")

local SSS = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local TerrainGen = require(SSS.TerrainGenerator)
local ObjectGen = require(SSS.ObjectGenerator)
local ConfigLoader = require(SSS.ConfigLoader)

local function configStamp(cfg)
    local probs = cfg.probabilities
    local props = cfg.props
    return string.format(
        "grass6|%.4f|%.4f|%.4f|%.4f|%.4f|%.2f|%.2f|%.2f|%.1f|%.1f|%.0f|%.1f|%.2f|%.1f|%.2f|%.1f|%.0f|%.2f|%.1f|%.2f|%.2f|%.1f|%.1f|%.4f|%.4f|%.0f|%.2f|%.2f|%.1f|%.0f|%.0f",
        probs.thin_tree, probs.mega_tree, probs.stick, probs.small_rock, probs.boulder,
        cfg.water_world_y, cfg.pond_level,
        props.thin_tree_scale, props.mega_tree_scale,
        cfg.tree_base_radius, cfg.max_slope_for_tree, cfg.flatten_radius,
        cfg.flatten_flat_fraction, cfg.exclusion_radius,
        cfg.pond_density, cfg.min_pond_size, cfg.min_ponds_per_chunk,
        cfg.terrain.pond_depth, cfg.terrain.pond_rim, cfg.terrain.pond_shore, cfg.terrain.pond_min_fill,
        cfg.terrain.noise_amplitude_1, cfg.terrain.noise_amplitude_2,
        cfg.terrain.noise_scale_1, cfg.terrain.noise_scale_2,
        cfg.terrain.edge_margin or 0,
        cfg.terrain.grass_coverage or 0, cfg.terrain.grass_height or 0,
        props.mega_tree_lift or 0,
        props.stick_tilt or 0, props.stick_beside_tilt or 0
    )
end

local cfg = ConfigLoader.Get()
local stamp = configStamp(cfg)

local legacyFlag = workspace:FindFirstChild("WorldGenerated_v1")
if legacyFlag then
    legacyFlag:Destroy()
end

local WorldFlag = workspace:FindFirstChild("WorldGenerated_v2")
local savedStamp = WorldFlag and WorldFlag:GetAttribute("ConfigStamp")
local configChanged = WorldFlag ~= nil and savedStamp ~= stamp

if configChanged then
    warn("⚠️ biome_config изменился. Пересобираю мир.")
    WorldFlag:Destroy()
    WorldFlag = nil
end

-- Спавн и игроков поднимаем на поверхность рельефа (Baseplate на Y=0 оказывается внутри земли).
local function surfaceY(x, z)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = { workspace.Terrain }
    params.IgnoreWater = true
    local hit = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), params)
    if hit then
        return hit.Position.Y
    end
    return cfg.base_height
end

local function liftSpawnAndPlayers()
    local y = surfaceY(0, 0) + 4
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("SpawnLocation") then
            inst.Anchored = true
            inst.Position = Vector3.new(0, y, 0)
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            local pos = root.Position
            local top = surfaceY(pos.X, pos.Z) + 4
            if pos.Y < top then
                root.CFrame = CFrame.new(pos.X, top, pos.Z)
            end
        end
    end
end

if not WorldFlag then
    warn("⚠️ Мир не найден. Начинаю полную генерацию...")
    
    print(" Очищаю карту от старых объектов...")
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name == "BigTree" or obj.Name == "thin_tree" or obj.Name == "Stick" 
           or obj.Name == "SmallRock" or obj.Name == "MediumRock" or obj.Name == "MegaTree" then
            obj:Destroy()
        end
    end

    -- Временный пол НАД будущей поверхностью: Baseplate на Y≈0 тонет в рельефе (дно -50…верх ~10).
    local baseplate = workspace:FindFirstChild("Baseplate")
    if baseplate and baseplate:IsA("BasePart") then
        baseplate.Position = Vector3.new(0, cfg.base_height + 8, 0)
        baseplate.CanCollide = true
    end
    local genFloor = workspace:FindFirstChild("_GenFloor")
    if not genFloor then
        genFloor = Instance.new("Part")
        genFloor.Name = "_GenFloor"
        genFloor.Anchored = true
        genFloor.CanCollide = true
        genFloor.Size = Vector3.new(512, 1, 512)
        genFloor.Transparency = 1
        genFloor.Parent = workspace
    end
    genFloor.Position = Vector3.new(0, cfg.base_height + 8, 0)

    local okTerrain, errTerrain = pcall(function()
        TerrainGen.Generate()
    end)
    if not okTerrain then
        warn("❌ Генерация ландшафта упала: " .. tostring(errTerrain))
        return
    end

    liftSpawnAndPlayers()
    print("Ландшафт готов — ставлю объекты...")

    local okObjects, errObjects = pcall(function()
        ObjectGen.Generate()
    end)
    if not okObjects then
        warn("❌ Генерация объектов упала: " .. tostring(errObjects))
        return
    end

    liftSpawnAndPlayers()

    if baseplate then
        baseplate:Destroy()
    end
    if genFloor then
        genFloor:Destroy()
    end
    local leftover = workspace:FindFirstChild("_GenFloor")
    if leftover then
        leftover:Destroy()
    end
    
    local flag = Instance.new("BoolValue")
    flag.Name = "WorldGenerated_v2"
    flag:SetAttribute("ConfigStamp", stamp)
    flag.Parent = workspace
    
    print("✨ Мир успешно создан!")
else
    print("ℹ️ Мир уже существует. Пропускаю генерацию.")
    liftSpawnAndPlayers()
end
