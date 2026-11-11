print("🚀 Сервер R1 запускается...")

local Players = game:GetService("Players")
-- Сразу, до require: иначе игрок успевает заспавниться и упасть в пустоту.
Players.CharacterAutoLoads = false

local SSS = game:GetService("ServerScriptService")
local TerrainGen = require(SSS.TerrainGenerator)
local ObjectGen = require(SSS.ObjectGenerator)
local ConfigLoader = require(SSS.ConfigLoader)

local function configStamp(cfg)
    local probs = cfg.probabilities
    local props = cfg.props
    return string.format(
        "grass6|%.4f|%.4f|%.4f|%.4f|%.4f|%.2f|%.2f|%.2f|%.1f|%.1f|%.0f|%.1f|%.2f|%.1f|%.2f|%.1f|%.0f|%.2f|%.1f|%.2f|%.2f|%.1f|%.1f|%.4f|%.4f|%.0f|%.2f|%.2f|%.1f|%.0f|%.0f|%.0f|%.0f",
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
        props.mega_tree_hp or 75,
        props.stick_tilt or 0, props.stick_beside_tilt or 0,
        props.boulder_tilt or 0
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

local worldReady = false

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

-- Поднимаем только если персонаж застрял под рельефом — не ставим на невидимую «полку».
local function liftCharacter(character)
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    local pos = root.Position
    local ground = surfaceY(pos.X, pos.Z)
    if pos.Y < ground + 1 then
        root.CFrame = CFrame.new(pos.X, ground + 3, pos.Z)
    end
end

-- Прозрачная точка спавна без коллизии: игрок падает сразу на землю.
local function ensureSpawnLocation()
    local y = surfaceY(0, 0) + 8
    local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
    if not spawn then
        spawn = Instance.new("SpawnLocation")
        spawn.Name = "SpawnLocation"
        spawn.Parent = workspace
    end
    spawn.Anchored = true
    spawn.CanCollide = false
    spawn.CanQuery = false
    spawn.CanTouch = false
    spawn.Size = Vector3.new(6, 1, 6)
    spawn.Transparency = 1
    spawn.Duration = 0
    spawn.Neutral = true
    spawn.Position = Vector3.new(0, y, 0)
    for _, child in ipairs(spawn:GetChildren()) do
        if child:IsA("Decal") then
            child.Transparency = 1
        end
    end
end

-- Манекен у спавна: проверка хитбокса/урона FistWeapon.
local function ensureTrainingDummy()
    local old = workspace:FindFirstChild("TrainingDummy")
    if old then
        old:Destroy()
    end

    local x, z = 14, 0
    local ground = surfaceY(x, z)

    local model = Instance.new("Model")
    model.Name = "TrainingDummy"

    local function addPart(name, size, offset, color)
        local part = Instance.new("Part")
        part.Name = name
        part.Size = size
        part.Anchored = true
        part.CanCollide = true
        part.Massless = true
        part.Material = Enum.Material.SmoothPlastic
        part.Color = color
        part.CFrame = CFrame.new(x, ground, z) * CFrame.new(offset)
        part.Parent = model
        return part
    end

    local root = addPart("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), Color3.fromRGB(190, 150, 110))
    addPart("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), Color3.fromRGB(220, 180, 140))
    addPart("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), Color3.fromRGB(190, 150, 110))
    addPart("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), Color3.fromRGB(190, 150, 110))
    addPart("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), Color3.fromRGB(80, 90, 120))
    addPart("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), Color3.fromRGB(80, 90, 120))

    local humanoid = Instance.new("Humanoid")
    humanoid.Name = "Humanoid"
    humanoid.MaxHealth = 200
    humanoid.Health = 200
    humanoid.DisplayName = "Манекен"
    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.AutoRotate = false
    humanoid.Parent = model

    model.PrimaryPart = root
    model.Parent = workspace

    humanoid.Died:Connect(function()
        task.delay(1.5, ensureTrainingDummy)
    end)
end

local function hasLivingCharacter(player)
    local character = player.Character
    if not character then
        return false
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    return humanoid ~= nil and humanoid.Health > 0 and root ~= nil
end

-- LoadCharacter иногда молча не срабатывает в тот же кадр — ждём и пробуем ещё раз.
local function loadCharacterNow(player)
    if not player.Parent then
        return
    end
    for attempt = 1, 5 do
        if not player.Parent then
            return
        end
        if hasLivingCharacter(player) then
            liftCharacter(player.Character :: Model)
            print("Игрок заспавнен: " .. player.Name)
            return
        end

        local arrived: Model? = nil
        local conn = player.CharacterAdded:Connect(function(character)
            arrived = character
        end)
        local ok, err = pcall(function()
            player:LoadCharacter()
        end)
        if not ok then
            warn("LoadCharacter ошибка (" .. player.Name .. "): " .. tostring(err))
        end

        local deadline = os.clock() + 3
        while player.Parent and arrived == nil and not hasLivingCharacter(player) and os.clock() < deadline do
            task.wait(0.1)
        end
        conn:Disconnect()

        local ch = player.Character or arrived
        if ch and hasLivingCharacter(player) then
            if not ch:FindFirstChild("HumanoidRootPart") then
                ch:WaitForChild("HumanoidRootPart", 5)
            end
            liftCharacter(ch)
            print("Игрок заспавнен: " .. player.Name)
            return
        end
        task.wait(0.2 * attempt)
    end
    warn("Не удалось заспавнить игрока: " .. player.Name)
end

local function spawnPlayer(player)
    if not worldReady or not player.Parent then
        return
    end
    task.spawn(loadCharacterNow, player)
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        if worldReady then
            task.defer(liftCharacter, character)
        end
    end)
    spawnPlayer(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
    player.CharacterAdded:Connect(function(character)
        if worldReady then
            task.defer(liftCharacter, character)
        end
    end)
end

local function releasePlayers()
    ensureSpawnLocation()
    ensureTrainingDummy()
    worldReady = true
    -- После готовности мира обычный автоспавн/респавн снова включён.
    Players.CharacterAutoLoads = true
    print("Мир готов — спавню игроков (" .. #Players:GetPlayers() .. ")")
    for _, player in ipairs(Players:GetPlayers()) do
        spawnPlayer(player)
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

    -- Временный прозрачный пол выше будущей поверхности (на случай раннего персонажа).
    local floorY = cfg.base_height
        + (cfg.terrain.noise_amplitude_1 or 0)
        + (cfg.terrain.noise_amplitude_2 or 0)
        + 16
    local baseplate = workspace:FindFirstChild("Baseplate")
    if baseplate and baseplate:IsA("BasePart") then
        baseplate.Position = Vector3.new(0, floorY, 0)
        baseplate.Transparency = 1
        baseplate.CanCollide = true
    end
    local genFloor = workspace:FindFirstChild("_GenFloor")
    if not genFloor then
        genFloor = Instance.new("Part")
        genFloor.Name = "_GenFloor"
        genFloor.Anchored = true
        genFloor.CanCollide = true
        genFloor.CanQuery = false
        genFloor.CanTouch = false
        genFloor.Size = Vector3.new(512, 1, 512)
        genFloor.Transparency = 1
        genFloor.Parent = workspace
    end
    genFloor.Position = Vector3.new(0, floorY, 0)
    genFloor.Transparency = 1

    local okTerrain, errTerrain = pcall(function()
        TerrainGen.Generate()
    end)
    if not okTerrain then
        warn("❌ Генерация ландшафта упала: " .. tostring(errTerrain))
        releasePlayers()
        return
    end

    print("Ландшафт готов — ставлю объекты...")

    local okObjects, errObjects = pcall(function()
        ObjectGen.Generate()
    end)
    if not okObjects then
        warn("❌ Генерация объектов упала: " .. tostring(errObjects))
        releasePlayers()
        return
    end

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
    releasePlayers()
else
    print("ℹ️ Мир уже существует. Пропускаю генерацию.")
    releasePlayers()
end
