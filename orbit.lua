--[[
    ╔══════════════════════════════════════════════════════════╗
    ║   OPTIMIZER v2.0                                         ║
    ║   Оптимизация Roblox для слабых устройств                ║
    ║   Работает в Delta / Arceus X / Fluxus                   ║
    ╚══════════════════════════════════════════════════════════╝
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

-- ==================== НАСТРОЙКИ ====================
local SETTINGS = {
    RemoveTextures = true,      -- убирает текстуры (Decal, Texture)
    RemoveMeshes = false,       -- убирает меши (может сломать вид карты)
    RemoveParticles = true,     -- убирает частицы
    RemoveLights = true,        -- убирает PointLight/SpotLight/SurfaceLight
    RemoveShadows = true,       -- убирает тени
    RemoveDecals = true,        -- убирает наклейки
    RemoveFog = true,           -- убирает туман
    RemoveSky = true,           -- убирает небо
    RemoveAtmosphere = true,    -- убирает атмосферу
    RemoveBloom = true,         -- убирает Bloom
    RemoveBlur = true,          -- убирает Blur
    RemoveSunRays = true,       -- убирает SunRays
    RemoveColorCorrection = true,
    RemoveDepthOfField = true,
    TerrainLowQuality = true,   -- понижает качество террейна
    KillSounds = false,         -- глушит все звуки (по желанию)
    BoostFPS = true,            -- убирает лишние обновления
}

-- ==================== УТИЛИТЫ ====================
local function safeRemove(obj)
    pcall(function() obj:Destroy() end)
end

local removed = {
    decals = 0, textures = 0, particles = 0,
    lights = 0, meshes = 0, sounds = 0
}

-- ==================== ОЧИСТКА ОБЪЕКТА ====================
local function optimizeInstance(obj)
    local className = obj.ClassName

    if SETTINGS.RemoveDecals and className == "Decal" then
        safeRemove(obj); removed.decals = removed.decals + 1

    elseif SETTINGS.RemoveTextures and className == "Texture" then
        safeRemove(obj); removed.textures = removed.textures + 1

    elseif SETTINGS.RemoveParticles and (className == "ParticleEmitter"
        or className == "Fire" or className == "Smoke"
        or className == "Sparkles" or className == "Trail"
        or className == "Beam" or className == "Explosion") then
        safeRemove(obj); removed.particles = removed.particles + 1

    elseif SETTINGS.RemoveLights and (className == "PointLight"
        or className == "SpotLight" or className == "SurfaceLight") then
        safeRemove(obj); removed.lights = removed.lights + 1

    elseif SETTINGS.RemoveMeshes and (className == "SpecialMesh"
        or className == "MeshPart" or className == "CylinderMesh"
        or className == "BlockMesh") then
        if className == "MeshPart" then
            obj.TextureID = ""
        else
            safeRemove(obj)
        end
        removed.meshes = removed.meshes + 1

    elseif SETTINGS.KillSounds and (className == "Sound" or className == "SoundGroup") then
        safeRemove(obj); removed.sounds = removed.sounds + 1

    elseif SETTINGS.RemoveShadows and obj:IsA("BasePart") then
        obj.CastShadow = false
    end
end

-- ==================== ПОСТОЯННАЯ ОЧИСТКА (для новых объектов) ====================
local function hookAll()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        optimizeInstance(obj)
    end
    for _, obj in ipairs(Lighting:GetDescendants()) do
        optimizeInstance(obj)
    end

    Workspace.DescendantAdded:Connect(function(obj)
        task.wait(0.05)
        pcall(optimizeInstance, obj)
    end)
    Lighting.DescendantAdded:Connect(function(obj)
        task.wait(0.05)
        pcall(optimizeInstance, obj)
    end)
end

-- ==================== ОСВЕЩЕНИЕ ====================
local function optimizeLighting()
    Lighting.GlobalShadows = false
    Lighting.Outlines = false
    Lighting.Brightness = 2
    Lighting.Ambient = Color3.fromRGB(120, 120, 120)
    Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 120)

    if SETTINGS.RemoveFog then
        Lighting.FogEnd = 100000
        Lighting.FogStart = 100000
    end

    for _, effect in ipairs(Lighting:GetChildren()) do
        local cn = effect.ClassName
        if SETTINGS.RemoveSky and cn == "Sky" then
            safeRemove(effect)
        elseif SETTINGS.RemoveAtmosphere and cn == "Atmosphere" then
            safeRemove(effect)
        elseif SETTINGS.RemoveBloom and cn == "BloomEffect" then
            safeRemove(effect)
        elseif SETTINGS.RemoveBlur and cn == "BlurEffect" then
            safeRemove(effect)
        elseif SETTINGS.RemoveSunRays and cn == "SunRaysEffect" then
            safeRemove(effect)
        elseif SETTINGS.RemoveColorCorrection and cn == "ColorCorrectionEffect" then
            safeRemove(effect)
        elseif SETTINGS.RemoveDepthOfField and cn == "DepthOfFieldEffect" then
            safeRemove(effect)
        end
    end

    Lighting.DescendantAdded:Connect(function(obj)
        task.wait(0.05)
        local cn = obj.ClassName
        if (SETTINGS.RemoveSky and cn == "Sky")
            or (SETTINGS.RemoveAtmosphere and cn == "Atmosphere")
            or (SETTINGS.RemoveBloom and cn == "BloomEffect")
            or (SETTINGS.RemoveBlur and cn == "BlurEffect")
            or (SETTINGS.RemoveSunRays and cn == "SunRaysEffect")
            or (SETTINGS.RemoveColorCorrection and cn == "ColorCorrectionEffect")
            or (SETTINGS.RemoveDepthOfField and cn == "DepthOfFieldEffect") then
            safeRemove(obj)
        end
    end)
end

-- ==================== ТЕРРЕЙН ====================
local function optimizeTerrain()
    if not Terrain or not SETTINGS.TerrainLowQuality then return end
    pcall(function()
        Terrain.WaterWaveSize = 0
        Terrain.WaterWaveSpeed = 0
        Terrain.WaterReflectance = 0
        Terrain.WaterTransparency = 1
        Terrain.Decoration = false
    end)
end

-- ==================== ГРАФИКА ====================
local function setGraphicsLow()
    -- Отключаем тени у всех частей
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            pcall(function() obj.CastShadow = false end)
        elseif obj:IsA("ParticleEmitter") then
            pcall(function() obj.Enabled = false end)
        end
    end
end

-- ==================== FPS BOOST ====================
local function boostFPS()
    if not SETTINGS.BoostFPS then return end
    -- Убираем лишние RenderStepped-скрипты из CoreGui
    pcall(function()
        for _, obj in ipairs(game:GetService("CoreGui"):GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("ImageLabel") then
                obj.Visible = false
            end
        end
    end)
end

-- ==================== ЗАПУСК ====================
local function runOptimization()
    local t0 = tick()

    optimizeLighting()
    optimizeTerrain()
    hookAll()
    setGraphicsLow()
    boostFPS()

    local elapsed = math.floor((tick() - t0) * 100) / 100
    return string.format(
        "✅ Оптимизация выполнена за %.2f сек\n" ..
        "• Наклеек убрано: %d\n" ..
        "• Текстур убрано: %d\n" ..
        "• Частиц убрано: %d\n" ..
        "• Света убрано: %d\n" ..
        "• Мешей убрано: %d\n" ..
        "• Звуков убрано: %d",
        elapsed,
        removed.decals, removed.textures, removed.particles,
        removed.lights, removed.meshes, removed.sounds
    )
end

-- ==================== UI ====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OptimizerUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 999
screenGui.Parent = game.CoreGui

local mainBtn = Instance.new("TextButton")
mainBtn.Size = UDim2.new(0, 56, 0, 56)
mainBtn.Position = UDim2.new(0, 20, 0, 170)
mainBtn.BackgroundColor3 = Color3.fromRGB(30, 40, 35)
mainBtn.BackgroundTransparency = 0.1
mainBtn.TextColor3 = Color3.fromRGB(140, 255, 180)
mainBtn.Font = Enum.Font.GothamBold
mainBtn.TextSize = 24
mainBtn.Text = "⚡"
mainBtn.AutoButtonColor = false
mainBtn.Parent = screenGui
Instance.new("UICorner", mainBtn).CornerRadius = UDim.new(0, 14)
local mainStroke = Instance.new("UIStroke", mainBtn)
mainStroke.Color = Color3.fromRGB(120, 255, 160)
mainStroke.Thickness = 1.5

local resultLabel = Instance.new("TextLabel")
resultLabel.Size = UDim2.new(0, 260, 0, 140)
resultLabel.Position = UDim2.new(0, 90, 0, 170)
resultLabel.BackgroundColor3 = Color3.fromRGB(20, 28, 24)
resultLabel.BackgroundTransparency = 0.1
resultLabel.BorderSizePixel = 0
resultLabel.TextColor3 = Color3.fromRGB(200, 255, 220)
resultLabel.Font = Enum.Font.Gotham
resultLabel.TextSize = 11
resultLabel.TextWrapped = true
resultLabel.TextXAlignment = Enum.TextXAlignment.Left
resultLabel.TextYAlignment = Enum.TextYAlignment.Top
resultLabel.Visible = false
resultLabel.Text = ""
resultLabel.Parent = screenGui
Instance.new("UICorner", resultLabel).CornerRadius = UDim.new(0, 10)
local rStroke = Instance.new("UIStroke", resultLabel)
rStroke.Color = Color3.fromRGB(120, 255, 160)
rStroke.Thickness = 1

-- Кнопка применения
local applyBtn = Instance.new("TextButton")
applyBtn.Size = UDim2.new(1, -16, 0, 34)
applyBtn.Position = UDim2.new(0, 8, 0, 100)
applyBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 50)
applyBtn.TextColor3 = Color3.fromRGB(180, 255, 200)
applyBtn.Font = Enum.Font.GothamBold
applyBtn.TextSize = 12
applyBtn.Text = "🚀 ОПТИМИЗИРОВАТЬ"
applyBtn.AutoButtonColor = true
applyBtn.Parent = resultLabel
Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 8)

local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, -16, 0, 58)
infoLabel.Position = UDim2.new(0, 8, 0, 38)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "⚡ OPTIMIZER v2.0\nНажми кнопку ниже для оптимизации\nFPS должен вырасти"
infoLabel.TextColor3 = Color3.fromRGB(180, 220, 200)
infoLabel.Font = Enum.Font.GothamBold
infoLabel.TextSize = 11
infoLabel.TextWrapped = true
infoLabel.Parent = resultLabel

-- ==================== ОБРАБОТЧИКИ ====================
mainBtn.Activated:Connect(function()
    resultLabel.Visible = not resultLabel.Visible
end)

applyBtn.Activated:Connect(function()
    applyBtn.Text = "⏳ Работаю..."
    applyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 30)
    task.wait(0.1)
    local report = runOptimization()
    infoLabel.Text = report
    applyBtn.Text = "✅ ГОТОВО"
    applyBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 50)
    task.wait(2)
    applyBtn.Text = "🚀 ОПТИМИЗИРОВАТЬ"
    applyBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 50)
end)

-- ==================== ПЕРЕТАСКИВАНИЕ ====================
local dragging, dragStart, startPos = false, nil, nil
mainBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = input.Position; startPos = mainBtn.Position
    end
end)
mainBtn.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - dragStart
        mainBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
mainBtn.InputEnded:Connect(function() dragging = false end)

-- Автоматический запуск при старте (можно отключить)
task.wait(2)
pcall(runOptimization)

return {
    Optimize = runOptimization,
    Settings = SETTINGS,
}
