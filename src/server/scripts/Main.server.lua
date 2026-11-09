print("🚀 Сервер R1 запускается...")

local SSS = game:GetService("ServerScriptService")
local TerrainGen = require(SSS.TerrainGenerator)
local ObjectGen = require(SSS.ObjectGenerator)
local ConfigLoader = require(SSS.ConfigLoader)

local function configStamp(cfg)
    local probs = cfg.probabilities
    local props = cfg.props
    return string.format(
        "flat1|%.4f|%.4f|%.4f|%.4f|%.4f|%.2f|%.2f|%.1f|%.1f|%.0f|%.1f|%.2f|%.1f|%.2f|%.1f|%.0f|%.2f|%.1f|%.2f|%.2f|%.1f|%.1f|%.4f|%.4f",
        probs.thin_tree, probs.mega_tree, probs.stick, probs.small_rock, probs.boulder,
        cfg.water_world_y, cfg.pond_level,
        props.mega_tree_scale,
        cfg.tree_base_radius, cfg.max_slope_for_tree, cfg.flatten_radius,
        cfg.flatten_flat_fraction, cfg.exclusion_radius,
        cfg.pond_density, cfg.min_pond_size, cfg.min_ponds_per_chunk,
        cfg.terrain.pond_depth, cfg.terrain.pond_rim, cfg.terrain.pond_shore, cfg.terrain.pond_min_fill,
        cfg.terrain.noise_amplitude_1, cfg.terrain.noise_amplitude_2,
        cfg.terrain.noise_scale_1, cfg.terrain.noise_scale_2
    )
end

local stamp = configStamp(ConfigLoader.Get())

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
    flag.Name = "WorldGenerated_v2"
    flag:SetAttribute("ConfigStamp", stamp)
    flag.Parent = workspace
    
    print("✨ Мир успешно создан!")
else
    print("ℹ️ Мир уже существует. Пропускаю генерацию.")
end