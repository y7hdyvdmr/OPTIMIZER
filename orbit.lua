--[[
    ╔══════════════════════════════════════════════════════════╗
    ║   OPTIMIZER v5.0 — PRESETS + FOV + MAX FPS               ║
    ║   + Пресеты: Низкая / Средняя / Высокая оптимизация      ║
    ║   + FOV: полный экран телефона (70° – 120°)              ║
    ║   + FPS-буст до 30-35 на слабых устройствах              ║
    ║   + Безопасный куллинг (не проваливаешься сквозь пол)    ║
    ║   + НЕ трогает UI игры / Delta / Roblox                  ║
    ╚══════════════════════════════════════════════════════════╝
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")
local LocalPlayer = Players.LocalPlayer

-- ==================== НАСТРОЙКИ ====================
local SETTINGS = {
    -- Камера
    FOV = 90,                    -- 70..120 (больше = шире обзор)
    CameraZoomMax = 500,
    CameraZoomMin = 0.1,
    ExtendCameraPitch = true,
    PitchLimit = 88,

    -- Куллинг
    CameraCulling = false,
    CullRange = 300,
    CheckInterval = 0.20,
    RefreshInterval = 3.0,

    -- Эффекты
    RemoveParticles = true,
    RemoveLights = true,
    RemoveShadows = true,
    RemoveDecals = true,
    RemoveTextures = true,
    RemoveFog = true,
    RemoveSky = true,
    RemoveAtmosphere = true,
    RemoveBloom = true,
    RemoveBlur = true,
    RemoveSunRays = true,
    RemoveColorCorrection = true,
    RemoveDepthOfField = true,
    TerrainLowQuality = true,
    KillSounds = false,
    KillReflections = true,      -- reflectance = 0 у всех частей
}

-- ==================== FPS СЧЁТЧИК ====================
local fpsState = { current = 0, before = 0, after = 0, frameCount = 0, lastTime = tick() }

RunService.RenderStepped:Connect(function()
    fpsState.frameCount = fpsState.frameCount + 1
    local now = tick()
    if now - fpsState.lastTime >= 0.5 then
        fpsState.current = math.floor(fpsState.frameCount / (now - fpsState.lastTime) + 0.5)
        fpsState.frameCount = 0
        fpsState.lastTime = now
    end
end)

local function measureFPS(duration)
    duration = duration or 1.5
    local frames = 0
    local startT = tick()
    local conn = RunService.RenderStepped:Connect(function() frames = frames + 1 end)
    repeat task.wait(0.05) until tick() - startT >= duration
    conn:Disconnect()
    return math.floor(frames / (tick() - startT) + 0.5)
end

-- ==================== КАМЕРА (FOV + ЗУМ) ====================
local cameraBoosted = false
local origZoomMax, origZoomMin, origFOV

local function applyCamera()
    cameraBoosted = true

    pcall(function()
        origZoomMax = LocalPlayer.CameraMaxZoomDistance
        origZoomMin = LocalPlayer.CameraMinZoomDistance
        LocalPlayer.CameraMaxZoomDistance = SETTINGS.CameraZoomMax
        LocalPlayer.CameraMinZoomDistance = SETTINGS.CameraZoomMin
    end)

    -- FOV для полного экрана
    local cam = Workspace.CurrentCamera
    if cam then
        origFOV = cam.FieldOfView
        cam.FieldOfView = SETTINGS.FOV
    end

    -- Расширение наклона вверх/вниз
    if SETTINGS.ExtendCameraPitch then
        task.spawn(function()
            local ok, PlayerModule = pcall(function()
                return require(LocalPlayer.PlayerScripts:WaitForChild("PlayerModule", 10))
            end)
            if ok and PlayerModule then
                local cameras = PlayerModule:GetCameras()
                local active = cameras and cameras.activeCameraController
                if active then
                    pcall(function() active.MIN_Y = -SETTINGS.PitchLimit end)
                    pcall(function() active.MAX_Y =  SETTINGS.PitchLimit end)
                end
            end
        end)
    end
end

local function restoreCamera()
    cameraBoosted = false
    pcall(function()
        LocalPlayer.CameraMaxZoomDistance = origZoomMax or 128
        LocalPlayer.CameraMinZoomDistance = origZoomMin or 0.5
    end)
    local cam = Workspace.CurrentCamera
    if cam and origFOV then cam.FieldOfView = origFOV end
end

local function setFOV(v)
    SETTINGS.FOV = v
    local cam = Workspace.CurrentCamera
    if cam then cam.FieldOfView = v end
end

applyCamera()

-- ==================== КУЛЛИНГ (БЕЗОПАСНЫЙ) ====================
local culled = {}
local allParts = {}
local lastRefresh = 0

local function refreshParts()
    local list = {}
    local char = LocalPlayer.Character
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Anchored then
            local skip = false
            if char and (obj == char or obj:IsDescendantOf(char)) then skip = true end
            if not skip then table.insert(list, obj) end
        end
    end
    allParts = list
end

local function isInView(worldPos, cam)
    if not cam then return true end
    local sp, onScreen = cam:WorldToViewportPoint(worldPos)
    return onScreen and sp.Z > 0
end

local function uncullPart(part)
    if culled[part] then
        pcall(function() part.LocalTransparencyModifier = culled[part].t end)
        culled[part] = nil
    end
end

local function cullPart(part)
    if not culled[part] then
        culled[part] = { t = part.LocalTransparencyModifier }
        pcall(function() part.LocalTransparencyModifier = 1 end)
    end
end

local function restoreAll()
    for p in pairs(culled) do uncullPart(p) end
    culled = {}
end

local function cullStep()
    if not SETTINGS.CameraCulling then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end

    if tick() - lastRefresh > SETTINGS.RefreshInterval then
        refreshParts(); lastRefresh = tick()
    end

    local camPos = cam.CFrame.Position
    local rangeSq = SETTINGS.CullRange * SETTINGS.CullRange

    for part in pairs(culled) do
        if not part or not part.Parent then
            culled[part] = nil
        elseif isInView(part.Position, cam) then
            uncullPart(part)
        end
    end

    for _, part in ipairs(allParts) do
        if part.Parent and not culled[part] then
            local dx = part.Position.X - camPos.X
            local dy = part.Position.Y - camPos.Y
            local dz = part.Position.Z - camPos.Z
            local distSq = dx*dx + dy*dy + dz*dz
            if distSq > rangeSq or not isInView(part.Position, cam) then
                cullPart(part)
            end
        end
    end
end

task.spawn(function()
    task.wait(1)
    while true do
        pcall(cullStep)
        task.wait(SETTINGS.CheckInterval)
    end
end)

-- ==================== ОПТИМИЗАЦИЯ ====================
local function safeRemove(obj) pcall(function() obj:Destroy() end) end

local removed = { decals=0, textures=0, particles=0, lights=0, sounds=0, reflections=0 }

local function optimizeInstance(obj)
    local cn = obj.ClassName
    if SETTINGS.RemoveDecals and cn == "Decal" then
        safeRemove(obj); removed.decals = removed.decals + 1
    elseif SETTINGS.RemoveTextures and cn == "Texture" then
        safeRemove(obj); removed.textures = removed.textures + 1
    elseif SETTINGS.RemoveParticles and (cn=="ParticleEmitter" or cn=="Fire" or cn=="Smoke" or cn=="Sparkles" or cn=="Trail" or cn=="Beam" or cn=="Explosion") then
        safeRemove(obj); removed.particles = removed.particles + 1
    elseif SETTINGS.RemoveLights and (cn=="PointLight" or cn=="SpotLight" or cn=="SurfaceLight") then
        safeRemove(obj); removed.lights = removed.lights + 1
    elseif SETTINGS.KillSounds and (cn=="Sound" or cn=="SoundGroup") then
        safeRemove(obj); removed.sounds = removed.sounds + 1
    elseif obj:IsA("BasePart") then
        if SETTINGS.RemoveShadows then pcall(function() obj.CastShadow = false end) end
        if SETTINGS.KillReflections and obj.Reflectance > 0 then
            pcall(function() obj.Reflectance = 0 end)
            removed.reflections = removed.reflections + 1
        end
    end
end

local function hookAll()
    for _, o in ipairs(Workspace:GetDescendants()) do optimizeInstance(o) end
    for _, o in ipairs(Lighting:GetDescendants()) do optimizeInstance(o) end
    Workspace.DescendantAdded:Connect(function(o) task.wait(0.05); pcall(optimizeInstance, o) end)
    Lighting.DescendantAdded:Connect(function(o) task.wait(0.05); pcall(optimizeInstance, o) end)
end

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

    for _, e in ipairs(Lighting:GetChildren()) do
        local cn = e.ClassName
        if SETTINGS.RemoveSky and cn == "Sky" then safeRemove(e)
        elseif SETTINGS.RemoveAtmosphere and cn == "Atmosphere" then safeRemove(e)
        elseif SETTINGS.RemoveBloom and cn == "BloomEffect" then safeRemove(e)
        elseif SETTINGS.RemoveBlur and cn == "BlurEffect" then safeRemove(e)
        elseif SETTINGS.RemoveSunRays and cn == "SunRaysEffect" then safeRemove(e)
        elseif SETTINGS.RemoveColorCorrection and cn == "ColorCorrectionEffect" then safeRemove(e)
        elseif SETTINGS.RemoveDepthOfField and cn == "DepthOfFieldEffect" then safeRemove(e)
        end
    end
end

local function optimizeTerrain()
    if not Terrain then return end
    pcall(function()
        Terrain.WaterWaveSize = 0
        Terrain.WaterWaveSpeed = 0
        Terrain.WaterReflectance = 0
        Terrain.WaterTransparency = 1
        Terrain.Decoration = false
    end)
end

local function setGraphicsLow()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            pcall(function() obj.CastShadow = false end)
        elseif obj:IsA("ParticleEmitter") then
            pcall(function() obj.Enabled = false end)
        end
    end
end

-- ==================== ПРЕСЕТЫ ОПТИМИЗАЦИИ ====================
local PRESETS = {
    Low = {
        name = "Низкая",
        CameraCulling = false,
        RemoveParticles = false,
        RemoveLights = false,
        RemoveShadows = false,
        RemoveDecals = false,
        RemoveTextures = false,
        RemoveFog = false,
        RemoveSky = false,
        RemoveAtmosphere = false,
        RemoveBloom = true,
        RemoveBlur = true,
        RemoveSunRays = false,
        RemoveColorCorrection = false,
        RemoveDepthOfField = false,
        TerrainLowQuality = false,
        KillReflections = false,
        FOV = 80,
    },
    Medium = {
        name = "Средняя",
        CameraCulling = false,
        RemoveParticles = true,
        RemoveLights = true,
        RemoveShadows = true,
        RemoveDecals = false,
        RemoveTextures = false,
        RemoveFog = true,
        RemoveSky = false,
        RemoveAtmosphere = false,
        RemoveBloom = true,
        RemoveBlur = true,
        RemoveSunRays = true,
        RemoveColorCorrection = true,
        RemoveDepthOfField = true,
        TerrainLowQuality = true,
        KillReflections = true,
        FOV = 90,
    },
    High = {
        name = "Высокая",
        CameraCulling = true,
        RemoveParticles = true,
        RemoveLights = true,
        RemoveShadows = true,
        RemoveDecals = true,
        RemoveTextures = true,
        RemoveFog = true,
        RemoveSky = true,
        RemoveAtmosphere = true,
        RemoveBloom = true,
        RemoveBlur = true,
        RemoveSunRays = true,
        RemoveColorCorrection = true,
        RemoveDepthOfField = true,
        TerrainLowQuality = true,
        KillReflections = true,
        FOV = 100,
    },
}

local function applyPreset(key)
    local p = PRESETS[key]
    if not p then return end
    for k, v in pairs(p) do
        if k ~= "name" then SETTINGS[k] = v end
    end
    setFOV(SETTINGS.FOV)
    if not SETTINGS.CameraCulling then restoreAll() end
end

-- ==================== ЗАПУСК ====================
local function runOptimization(onStatus)
    local status = onStatus or function() end
    status("📊 Замер FPS до...")
    task.wait(0.2)
    local fpsBefore = measureFPS(1.5)

    status("⚡ Оптимизация...")
    optimizeLighting(); optimizeTerrain(); hookAll(); setGraphicsLow()
    task.wait(0.3)

    status("📊 Замер FPS после...")
    task.wait(0.2)
    local fpsAfter = measureFPS(1.5)

    fpsState.before = fpsBefore; fpsState.after = fpsAfter
    local diff = fpsAfter - fpsBefore
    local sign = diff >= 0 and "+" or ""
    local percent = fpsBefore > 0 and math.floor((diff / fpsBefore) * 100) or 0

    return string.format(
        "🎯 FPS ДО:  %d\n🚀 FPS ПОСЛЕ: %d\n📈 Прирост: %s%d (%s%d%%)\n" ..
        "━━━━━━━━━━━━━━━\n🧹 Очищено:\n• Наклеек: %d\n• Текстур: %d\n" ..
        "• Частиц: %d\n• Света: %d\n• Отражений: %d",
        fpsBefore, fpsAfter, sign, diff, sign, percent,
        removed.decals, removed.textures, removed.particles,
        removed.lights, removed.reflections
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

local panel = Instance.new("ScrollingFrame")
panel.Size = UDim2.new(0, 310, 0, 560)
panel.Position = UDim2.new(0, 85, 0, 80)
panel.BackgroundColor3 = Color3.fromRGB(20, 28, 24)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.CanvasSize = UDim2.new(0, 0, 0, 860)
panel.ScrollBarThickness = 3
panel.ScrollBarImageColor3 = Color3.fromRGB(120, 255, 160)
panel.Parent = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local pStroke = Instance.new("UIStroke", panel)
pStroke.Color = Color3.fromRGB(120, 255, 160)
pStroke.Thickness = 1

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 26)
title.Position = UDim2.new(0, 8, 0, 6)
title.BackgroundTransparency = 1
title.Text = "⚡ OPTIMIZER v5.0"
title.TextColor3 = Color3.fromRGB(180, 255, 200)
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = panel

local liveFpsLabel = Instance.new("TextLabel")
liveFpsLabel.Size = UDim2.new(1, -16, 0, 24)
liveFpsLabel.Position = UDim2.new(0, 8, 0, 34)
liveFpsLabel.BackgroundColor3 = Color3.fromRGB(15, 22, 18)
liveFpsLabel.BorderSizePixel = 0
liveFpsLabel.Text = "🎮 Сейчас FPS: --"
liveFpsLabel.TextColor3 = Color3.fromRGB(255, 230, 100)
liveFpsLabel.Font = Enum.Font.GothamBold
liveFpsLabel.TextSize = 13
liveFpsLabel.Parent = panel
Instance.new("UICorner", liveFpsLabel).CornerRadius = UDim.new(0, 6)

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -16, 0, 20)
statusLabel.Position = UDim2.new(0, 8, 0, 62)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "🎥 Скрыто: 0   |   📷 FOV: 90°"
statusLabel.TextColor3 = Color3.fromRGB(140, 200, 255)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 11
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = panel

local resultLabel = Instance.new("TextLabel")
resultLabel.Size = UDim2.new(1, -16, 0, 70)
resultLabel.Position = UDim2.new(0, 8, 0, 86)
resultLabel.BackgroundColor3 = Color3.fromRGB(15, 22, 18)
resultLabel.BackgroundTransparency = 0.2
resultLabel.BorderSizePixel = 0
resultLabel.TextColor3 = Color3.fromRGB(200, 255, 220)
resultLabel.Font = Enum.Font.Gotham
resultLabel.TextSize = 11
resultLabel.TextWrapped = true
resultLabel.TextXAlignment = Enum.TextXAlignment.Left
resultLabel.TextYAlignment = Enum.TextYAlignment.Top
resultLabel.Text = "Выбери пресет, потом нажми\n«ОПТИМИЗИРОВАТЬ»"
resultLabel.Parent = panel
Instance.new("UICorner", resultLabel).CornerRadius = UDim.new(0, 8)

-- ==================== КНОПКИ ПРЕСЕТОВ ====================
local function makePresetBtn(text, x, w, y, key, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 0, 32)
    b.Position = UDim2.new(0, x, 0, y)
    b.BackgroundColor3 = color
    b.TextColor3 = Color3.fromRGB(240, 255, 240)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Text = text
    b.AutoButtonColor = true
    b.Parent = panel
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    b.Activated:Connect(function()
        applyPreset(key)
        resultLabel.Text = "✅ Пресет «" .. PRESETS[key].name .. "» применён!\nFOV: " .. SETTINGS.FOV .. "°"
    end)
    return b
end

makePresetBtn("🟢 Низкая",  8,  90, 164, "Low",    Color3.fromRGB(35, 65, 45))
makePresetBtn("🟡 Средняя", 105, 90, 164, "Medium", Color3.fromRGB(75, 65, 25))
makePresetBtn("🔴 Высокая", 202, 90, 164, "High",   Color3.fromRGB(75, 35, 35))

-- ==================== FOV КНОПКИ ====================
local fovLabel = Instance.new("TextLabel")
fovLabel.Size = UDim2.new(1, -16, 0, 18)
fovLabel.Position = UDim2.new(0, 8, 0, 202)
fovLabel.BackgroundTransparency = 1
fovLabel.Text = "📷 FOV (поле зрения) — полный экран"
fovLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
fovLabel.Font = Enum.Font.GothamBold
fovLabel.TextSize = 11
fovLabel.TextXAlignment = Enum.TextXAlignment.Left
fovLabel.Parent = panel

local fovValues = { 70, 80, 90, 100, 110, 120 }
for i, v in ipairs(fovValues) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 45, 0, 26)
    b.Position = UDim2.new(0, 8 + (i-1)*48, 0, 224)
    b.BackgroundColor3 = Color3.fromRGB(35, 50, 70)
    b.TextColor3 = Color3.fromRGB(200, 230, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.Text = tostring(v)
    b.AutoButtonColor = true
    b.Parent = panel
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.Activated:Connect(function()
        setFOV(v)
        resultLabel.Text = "📷 FOV = " .. v .. "°"
    end)
end

-- ==================== КНОПКИ-ПЕРЕКЛЮЧАТЕЛИ ====================
local function makeToggle(text, y, getter, setter)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 26)
    b.Position = UDim2.new(0, 8, 0, y)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.AutoButtonColor = true
    b.Parent = panel
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local function refresh()
        local on = getter()
        b.Text = text .. ": " .. (on and "ВКЛ" or "ВЫКЛ")
        if on then
            b.BackgroundColor3 = Color3.fromRGB(35, 65, 45)
            b.TextColor3 = Color3.fromRGB(160, 255, 180)
        else
            b.BackgroundColor3 = Color3.fromRGB(55, 40, 40)
            b.TextColor3 = Color3.fromRGB(220, 160, 160)
        end
    end
    b.Activated:Connect(function() setter(not getter()); refresh() end)
    refresh()
    return b
end

makeToggle("🎥 Камера-куллинг", 258, function() return SETTINGS.CameraCulling end,
    function(v) SETTINGS.CameraCulling = v; if not v then restoreAll() end end)
makeToggle("📷 Расширение камеры", 286, function() return cameraBoosted end,
    function(v) if v then applyCamera() else restoreCamera() end end)
makeToggle("🧹 Частицы", 314, function() return SETTINGS.RemoveParticles end,
    function(v) SETTINGS.RemoveParticles = v end)
makeToggle("💡 Свет", 342, function() return SETTINGS.RemoveLights end,
    function(v) SETTINGS.RemoveLights = v end)
makeToggle("🌑 Тени", 370, function() return SETTINGS.RemoveShadows end,
    function(v) SETTINGS.RemoveShadows = v end)
makeToggle("🎨 Наклейки / Текстуры", 398,
    function() return SETTINGS.RemoveDecals and SETTINGS.RemoveTextures end,
    function(v) SETTINGS.RemoveDecals = v; SETTINGS.RemoveTextures = v end)
makeToggle("🌫 Туман", 426, function() return SETTINGS.RemoveFog end,
    function(v) SETTINGS.RemoveFog = v end)
makeToggle("🌌 Небо / Атмосфера", 454,
    function() return SETTINGS.RemoveSky and SETTINGS.RemoveAtmosphere end,
    function(v) SETTINGS.RemoveSky = v; SETTINGS.RemoveAtmosphere = v end)
makeToggle("🌸 Пост-эффекты", 482,
    function() return SETTINGS.RemoveBloom and SETTINGS.RemoveBlur end,
    function(v)
        SETTINGS.RemoveBloom = v; SETTINGS.RemoveBlur = v
        SETTINGS.RemoveSunRays = v; SETTINGS.RemoveColorCorrection = v
        SETTINGS.RemoveDepthOfField = v
    end)
makeToggle("🌊 Террейн", 510, function() return SETTINGS.TerrainLowQuality end,
    function(v) SETTINGS.TerrainLowQuality = v end)
makeToggle("✨ Отражения", 538, function() return SETTINGS.KillReflections end,
    function(v) SETTINGS.KillReflections = v end)
makeToggle("🔊 Глушить звуки", 566, function() return SETTINGS.KillSounds end,
    function(v) SETTINGS.KillSounds = v end)

-- ==================== КНОПКИ ДЕЙСТВИЙ ====================
local applyBtn = Instance.new("TextButton")
applyBtn.Size = UDim2.new(1, -16, 0, 34)
applyBtn.Position = UDim2.new(0, 8, 0, 604)
applyBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 50)
applyBtn.TextColor3 = Color3.fromRGB(180, 255, 200)
applyBtn.Font = Enum.Font.GothamBold
applyBtn.TextSize = 12
applyBtn.Text = "🚀 ОПТИМИЗИРОВАТЬ"
applyBtn.AutoButtonColor = true
applyBtn.Parent = panel
Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 8)

local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(1, -16, 0, 26)
restoreBtn.Position = UDim2.new(0, 8, 0, 644)
restoreBtn.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
restoreBtn.TextColor3 = Color3.fromRGB(180, 220, 255)
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.TextSize = 11
restoreBtn.Text = "🔙 Вернуть видимость"
restoreBtn.AutoButtonColor = true
restoreBtn.Parent = panel
Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0, 8)

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(1, -16, 0, 26)
resetBtn.Position = UDim2.new(0, 8, 0, 676)
resetBtn.BackgroundColor3 = Color3.fromRGB(50, 35, 35)
resetBtn.TextColor3 = Color3.fromRGB(255, 180, 180)
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 11
resetBtn.Text = "🔄 Сбросить счётчик FPS"
resetBtn.AutoButtonColor = true
resetBtn.Parent = panel
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 8)

-- ==================== ЖИВОЙ СТАТУС ====================
task.spawn(function()
    while task.wait(0.5) do
        if liveFpsLabel and liveFpsLabel.Parent then
            local fps = fpsState.current
            local color = Color3.fromRGB(255, 230, 100)
            local icon = "🎮"
            if fps >= 50 then color = Color3.fromRGB(100, 255, 130); icon = "🟢"
            elseif fps >= 30 then color = Color3.fromRGB(255, 230, 100); icon = "🟡"
            else color = Color3.fromRGB(255, 120, 120); icon = "🔴" end
            liveFpsLabel.Text = string.format("%s Сейчас FPS: %d", icon, fps)
            liveFpsLabel.TextColor3 = color
        end
        if statusLabel and statusLabel.Parent then
            local n = 0
            for _ in pairs(culled) do n = n + 1 end
            statusLabel.Text = string.format("🎥 Скрыто: %d   |   📷 FOV: %d°", n, SETTINGS.FOV)
        end
    end
end)

-- ==================== ОБРАБОТЧИКИ ====================
mainBtn.Activated:Connect(function() panel.Visible = not panel.Visible end)

local optimizing = false
applyBtn.Activated:Connect(function()
    if optimizing then return end
    optimizing = true
    applyBtn.Text = "⏳ Работаю..."
    applyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 30)
    task.spawn(function()
        local report = runOptimization(function(s) resultLabel.Text = s end)
        resultLabel.Text = report
        applyBtn.Text = "✅ ГОТОВО"
        applyBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 50)
        task.wait(2)
        applyBtn.Text = "🚀 ОПТИМИЗИРОВАТЬ"
        applyBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 50)
        optimizing = false
    end)
end)

restoreBtn.Activated:Connect(function()
    restoreAll()
    resultLabel.Text = "🔙 Вся видимость восстановлена."
end)

resetBtn.Activated:Connect(function()
    fpsState.before = 0; fpsState.after = 0
    resultLabel.Text = "🔄 Счётчик сброшен."
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

return {
    Optimize = runOptimization,
    RestoreAll = restoreAll,
    ApplyPreset = applyPreset,
    SetFOV = setFOV,
    Presets = PRESETS,
    Settings = SETTINGS,
}
