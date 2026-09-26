--[[
    ╔══════════════════════════════════════════════════════════╗
    ║   OPTIMIZER v4.1 — CULLING + LOD                         ║
    ║   + Камера-куллинг (убирает то, что вне поля зрения)     ║
    ║   + LOD: дальние объекты упрощаются                      ║
    ║   + Кнопки для каждой оптимизации                        ║
    ║   + FPS счётчик: было / стало / сейчас                   ║
    ║   + НЕ трогает UI игры / Delta / Roblox                  ║
    ║   Работает в Delta / Arceus X / Fluxus                   ║
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
    -- Камера-куллинг
    CameraCulling = true,
    CullRange = 250,
    CheckInterval = 0.30,
    RefreshInterval = 3.0,
    CullUnanchored = false,

    -- ★ LOD (Level of Detail)
    LODEnabled = true,
    LODMode = 2,                 -- 1 = Обычный, 2 = Агрессивный
    LODNearDistance = 120,       -- ближе — оригинал
    LODFarDistance = 220,        -- дальше — упрощённый вид
    LODMaterial = Enum.Material.SmoothPlastic,
    LODReflectance = 0,
    LODTransparencyBoost = 0,    -- 0..0.3 (для агрессивного можно 0.1)

    -- Эффекты
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
    KillSounds = false,
}

-- ==================== FPS СЧЁТЧИК ====================
local fpsState = {
    current = 0, before = 0, after = 0,
    frameCount = 0, lastTime = tick(),
}

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

-- ==================== КАМЕРА-КУЛЛИНГ ====================
local hiddenFolder
local culled = {}
local allParts = {}
local lastRefresh = 0

local function setupHiddenFolder()
    local existing = game:FindFirstChild("_OptHidden")
    if existing then existing:Destroy() end
    hiddenFolder = Instance.new("Folder")
    hiddenFolder.Name = "_OptHidden"
    hiddenFolder.Parent = game
end

local function refreshParts()
    local list = {}
    local char = LocalPlayer.Character
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Parent ~= hiddenFolder then
            local skip = false
            if char and (obj == char or obj:IsDescendantOf(char)) then
                skip = true
            end
            if not skip and not SETTINGS.CullUnanchored and not obj.Anchored then
                skip = true
            end
            if not skip then
                table.insert(list, obj)
            end
        end
    end
    allParts = list
end

local function isInView(worldPos, cam)
    if not cam then return true end
    local screenPos, onScreen = cam:WorldToViewportPoint(worldPos)
    if not onScreen then return false end
    if screenPos.Z <= 0 then return false end
    return true
end

local function restoreAll()
    for part, data in pairs(culled) do
        if part and part.Parent == hiddenFolder then
            pcall(function() part.Parent = data.parent end)
        end
    end
    culled = {}
end

local function cullStep()
    if not SETTINGS.CameraCulling then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end

    if tick() - lastRefresh > SETTINGS.RefreshInterval then
        refreshParts()
        lastRefresh = tick()
    end

    local camPos = cam.CFrame.Position
    local rangeSq = SETTINGS.CullRange * SETTINGS.CullRange

    for part, data in pairs(culled) do
        if not part or not part.Parent then
            culled[part] = nil
        elseif isInView(part.Position, cam) then
            if part.Parent == hiddenFolder then
                pcall(function() part.Parent = data.parent end)
            end
            culled[part] = nil
        end
    end

    for _, part in ipairs(allParts) do
        if part.Parent and part.Parent ~= hiddenFolder and not culled[part] then
            local dx = part.Position.X - camPos.X
            local dy = part.Position.Y - camPos.Y
            local dz = part.Position.Z - camPos.Z
            local distSq = dx*dx + dy*dy + dz*dz

            local shouldCull = false
            if distSq > rangeSq then
                shouldCull = true
            elseif not isInView(part.Position, cam) then
                shouldCull = true
            end

            if shouldCull then
                culled[part] = { parent = part.Parent }
                pcall(function() part.Parent = hiddenFolder end)
            end
        end
    end
end

-- ==================== ★ LOD (Level of Detail) ====================
-- Запоминаем оригинальные параметры, чтобы вернуть при приближении
local lodBackup = {}

local function applyLODToPart(part, mode)
    if not part:IsA("BasePart") then return end

    -- Сохраняем оригинал один раз
    if not lodBackup[part] then
        lodBackup[part] = {
            Material = part.Material,
            Reflectance = part.Reflectance,
            Transparency = part.Transparency,
            CastShadow = part.CastShadow,
            -- для MeshPart
            TextureID = part:IsA("MeshPart") and part.TextureID or nil,
            RenderFidelity = part:IsA("MeshPart") and part.RenderFidelity or nil,
        }
    end
    local orig = lodBackup[part]

    if mode == 0 then
        -- Вернуть оригинал
        pcall(function()
            part.Material = orig.Material
            part.Reflectance = orig.Reflectance
            part.Transparency = orig.Transparency
            part.CastShadow = orig.CastShadow
            if part:IsA("MeshPart") then
                if orig.TextureID then part.TextureID = orig.TextureID end
                if orig.RenderFidelity then part.RenderFidelity = orig.RenderFidelity end
            end
        end)
    elseif mode == 1 then
        -- Обычный LOD: дешёвый материал, без отражений, без тени
        pcall(function()
            part.Material = SETTINGS.LODMaterial
            part.Reflectance = SETTINGS.LODReflectance
            part.CastShadow = false
            if part:IsA("MeshPart") then
                part.RenderFidelity = Enum.RenderFidelity.Performance
            end
        end)
    elseif mode == 2 then
        -- Агрессивный LOD: + прозрачность и без текстур
        pcall(function()
            part.Material = SETTINGS.LODMaterial
            part.Reflectance = 0
            part.CastShadow = false
            part.Transparency = math.min(orig.Transparency + 0.15, 1)
            if part:IsA("MeshPart") then
                part.TextureID = ""
                part.RenderFidelity = Enum.RenderFidelity.Performance
            end
        end)
    end
end

local function lodStep()
    if not SETTINGS.LODEnabled then return end
    local cam = Workspace.CurrentCamera
    if not cam then return end

    local camPos = cam.CFrame.Position
    local char = LocalPlayer.Character
    local nearSq = SETTINGS.LODNearDistance * SETTINGS.LODNearDistance
    local farSq = SETTINGS.LODFarDistance * SETTINGS.LODFarDistance

    for _, part in ipairs(allParts) do
        if part.Parent and part.Parent ~= hiddenFolder then
            -- не трогаем персонажа
            local skip = false
            if char and (part == char or part:IsDescendantOf(char)) then
                skip = true
            end
            if not skip then
                local dx = part.Position.X - camPos.X
                local dy = part.Position.Y - camPos.Y
                local dz = part.Position.Z - camPos.Z
                local distSq = dx*dx + dy*dy + dz*dz

                if distSq <= nearSq then
                    applyLODToPart(part, 0)  -- оригинал
                elseif distSq <= farSq then
                    applyLODToPart(part, 1)  -- обычный LOD
                else
                    applyLODToPart(part, SETTINGS.LODMode)  -- выбранный режим
                end
            end
        end
    end
end

local function restoreLOD()
    for part, orig in pairs(lodBackup) do
        if part and part.Parent then
            applyLODToPart(part, 0)
        end
    end
    lodBackup = {}
end

-- Общий цикл: сначала куллинг, потом LOD
task.spawn(function()
    setupHiddenFolder()
    task.wait(1)
    while true do
        pcall(cullStep)
        pcall(lodStep)
        task.wait(SETTINGS.CheckInterval)
    end
end)

-- ==================== ОБЫЧНЫЕ ОПТИМИЗАЦИИ ====================
local function safeRemove(obj) pcall(function() obj:Destroy() end) end

local removed = { decals=0, textures=0, particles=0, lights=0, sounds=0 }

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
    elseif SETTINGS.RemoveShadows and obj:IsA("BasePart") then
        obj.CastShadow = false
    end
end

local function hookAll()
    for _, obj in ipairs(Workspace:GetDescendants()) do optimizeInstance(obj) end
    for _, obj in ipairs(Lighting:GetDescendants()) do optimizeInstance(obj) end
    Workspace.DescendantAdded:Connect(function(obj) task.wait(0.05); pcall(optimizeInstance, obj) end)
    Lighting.DescendantAdded:Connect(function(obj) task.wait(0.05); pcall(optimizeInstance, obj) end)
end

local function optimizeLighting()
    Lighting.GlobalShadows = false
    Lighting.Outlines = false
    if SETTINGS.RemoveFog then
        Lighting.FogEnd = 100000
        Lighting.FogStart = 100000
    end
    for _, effect in ipairs(Lighting:GetChildren()) do
        local cn = effect.ClassName
        if SETTINGS.RemoveSky and cn == "Sky" then safeRemove(effect)
        elseif SETTINGS.RemoveAtmosphere and cn == "Atmosphere" then safeRemove(effect)
        elseif SETTINGS.RemoveBloom and cn == "BloomEffect" then safeRemove(effect)
        elseif SETTINGS.RemoveBlur and cn == "BlurEffect" then safeRemove(effect)
        elseif SETTINGS.RemoveSunRays and cn == "SunRaysEffect" then safeRemove(effect)
        elseif SETTINGS.RemoveColorCorrection and cn == "ColorCorrectionEffect" then safeRemove(effect)
        elseif SETTINGS.RemoveDepthOfField and cn == "DepthOfFieldEffect" then safeRemove(effect)
        end
    end
end

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

local function setGraphicsLow()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            pcall(function() obj.CastShadow = false end)
        elseif obj:IsA("ParticleEmitter") then
            pcall(function() obj.Enabled = false end)
        end
    end
end

-- ==================== ЗАПУСК ====================
local function runOptimization(onStatus)
    local status = onStatus or function() end
    status("📊 Замер FPS до оптимизации...")
    task.wait(0.2)
    local fpsBefore = measureFPS(1.5)

    status("⚡ Оптимизация...")
    optimizeLighting()
    optimizeTerrain()
    hookAll()
    setGraphicsLow()
    task.wait(0.3)

    status("📊 Замер FPS после...")
    task.wait(0.2)
    local fpsAfter = measureFPS(1.5)

    fpsState.before = fpsBefore
    fpsState.after = fpsAfter
    local diff = fpsAfter - fpsBefore
    local sign = diff >= 0 and "+" or ""
    local percent = fpsBefore > 0 and math.floor((diff / fpsBefore) * 100) or 0

    return string.format(
        "🎯 FPS ДО:  %d\n🚀 FPS ПОСЛЕ: %d\n📈 Прирост: %s%d (%s%d%%)\n" ..
        "━━━━━━━━━━━━━━━\n🧹 Очищено:\n• Наклеек: %d\n• Текстур: %d\n" ..
        "• Частиц: %d\n• Света: %d\n• Звуков: %d",
        fpsBefore, fpsAfter, sign, diff, sign, percent,
        removed.decals, removed.textures, removed.particles,
        removed.lights, removed.sounds
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
panel.Size = UDim2.new(0, 300, 0, 520)
panel.Position = UDim2.new(0, 90, 0, 90)
panel.BackgroundColor3 = Color3.fromRGB(20, 28, 24)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.CanvasSize = UDim2.new(0, 0, 0, 800)
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
title.Text = "⚡ OPTIMIZER v4.1 — CULL + LOD"
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

local cullStatus = Instance.new("TextLabel")
cullStatus.Size = UDim2.new(1, -16, 0, 20)
cullStatus.Position = UDim2.new(0, 8, 0, 62)
cullStatus.BackgroundTransparency = 1
cullStatus.Text = "🎥 Скрыто: 0   |   🎚️ LOD: 0"
cullStatus.TextColor3 = Color3.fromRGB(140, 200, 255)
cullStatus.Font = Enum.Font.GothamBold
cullStatus.TextSize = 11
cullStatus.TextXAlignment = Enum.TextXAlignment.Left
cullStatus.Parent = panel

local resultLabel = Instance.new("TextLabel")
resultLabel.Size = UDim2.new(1, -16, 0, 90)
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
resultLabel.Text = "Настрой оптимизации кнопками ниже,\nпотом нажми «ОПТИМИЗИРОВАТЬ»"
resultLabel.Parent = panel
Instance.new("UICorner", resultLabel).CornerRadius = UDim.new(0, 8)

-- ==================== КНОПКИ-ПЕРЕКЛЮЧАТЕЛИ ====================
local function makeToggle(text, y, getter, setter)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -16, 0, 28)
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

    b.Activated:Connect(function()
        setter(not getter())
        refresh()
    end)
    refresh()
    return b
end

makeToggle("🎥 Камера-куллинг", 184, function() return SETTINGS.CameraCulling end,
    function(v) SETTINGS.CameraCulling = v; if not v then restoreAll() end end)
makeToggle("🎚️ LOD (упрощение дальних)", 214, function() return SETTINGS.LODEnabled end,
    function(v) SETTINGS.LODEnabled = v; if not v then restoreLOD() end end)
makeToggle("🧹 Частицы", 244, function() return SETTINGS.RemoveParticles end,
    function(v) SETTINGS.RemoveParticles = v end)
makeToggle("💡 Свет", 274, function() return SETTINGS.RemoveLights end,
    function(v) SETTINGS.RemoveLights = v end)
makeToggle("🌑 Тени", 304, function() return SETTINGS.RemoveShadows end,
    function(v) SETTINGS.RemoveShadows = v end)
makeToggle("🎨 Наклейки / Текстуры", 334,
    function() return SETTINGS.RemoveDecals and SETTINGS.RemoveTextures end,
    function(v) SETTINGS.RemoveDecals = v; SETTINGS.RemoveTextures = v end)
makeToggle("🌫 Туман", 364, function() return SETTINGS.RemoveFog end,
    function(v) SETTINGS.RemoveFog = v end)
makeToggle("🌌 Небо / Атмосфера", 394,
    function() return SETTINGS.RemoveSky and SETTINGS.RemoveAtmosphere end,
    function(v) SETTINGS.RemoveSky = v; SETTINGS.RemoveAtmosphere = v end)
makeToggle("🌸 Пост-эффекты", 424,
    function() return SETTINGS.RemoveBloom and SETTINGS.RemoveBlur end,
    function(v)
        SETTINGS.RemoveBloom = v; SETTINGS.RemoveBlur = v
        SETTINGS.RemoveSunRays = v; SETTINGS.RemoveColorCorrection = v
        SETTINGS.RemoveDepthOfField = v
    end)
makeToggle("🌊 Террейн", 454, function() return SETTINGS.TerrainLowQuality end,
    function(v) SETTINGS.TerrainLowQuality = v end)
makeToggle("🔊 Глушить звуки", 484, function() return SETTINGS.KillSounds end,
    function(v) SETTINGS.KillSounds = v end)

-- ==================== КНОПКА РЕЖИМА LOD ====================
local lodModeBtn = Instance.new("TextButton")
lodModeBtn.Size = UDim2.new(1, -16, 0, 28)
lodModeBtn.Position = UDim2.new(0, 8, 0, 518)
lodModeBtn.BackgroundColor3 = Color3.fromRGB(40, 55, 75)
lodModeBtn.TextColor3 = Color3.fromRGB(160, 200, 255)
lodModeBtn.Font = Enum.Font.GothamBold
lodModeBtn.TextSize = 11
lodModeBtn.AutoButtonColor = true
lodModeBtn.Parent = panel
Instance.new("UICorner", lodModeBtn).CornerRadius = UDim.new(0, 8)

local lodModeNames = { "Обычный", "Агрессивный" }
local function refreshLodModeBtn()
    local mode = SETTINGS.LODMode
    local name = (mode == 1 and lodModeNames[1]) or (mode == 2 and lodModeNames[2]) or "?"
    lodModeBtn.Text = "🎚️ Режим LOD: " .. name
    if mode == 2 then
        lodModeBtn.BackgroundColor3 = Color3.fromRGB(70, 40, 45)
        lodModeBtn.TextColor3 = Color3.fromRGB(255, 180, 200)
    else
        lodModeBtn.BackgroundColor3 = Color3.fromRGB(40, 55, 75)
        lodModeBtn.TextColor3 = Color3.fromRGB(160, 200, 255)
    end
end
lodModeBtn.Activated:Connect(function()
    SETTINGS.LODMode = (SETTINGS.LODMode == 1) and 2 or 1
    refreshLodModeBtn()
end)
refreshLodModeBtn()

-- ==================== КНОПКИ ДЕЙСТВИЙ ====================
local applyBtn = Instance.new("TextButton")
applyBtn.Size = UDim2.new(1, -16, 0, 34)
applyBtn.Position = UDim2.new(0, 8, 0, 552)
applyBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 50)
applyBtn.TextColor3 = Color3.fromRGB(180, 255, 200)
applyBtn.Font = Enum.Font.GothamBold
applyBtn.TextSize = 12
applyBtn.Text = "🚀 ОПТИМИЗИРОВАТЬ"
applyBtn.AutoButtonColor = true
applyBtn.Parent = panel
Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 8)

local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(1, -16, 0, 28)
restoreBtn.Position = UDim2.new(0, 8, 0, 592)
restoreBtn.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
restoreBtn.TextColor3 = Color3.fromRGB(180, 220, 255)
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.TextSize = 11
restoreBtn.Text = "🔙 Вернуть всё (снять куллинг + LOD)"
restoreBtn.AutoButtonColor = true
restoreBtn.Parent = panel
Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0, 8)

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(1, -16, 0, 28)
resetBtn.Position = UDim2.new(0, 8, 0, 626)
resetBtn.BackgroundColor3 = Color3.fromRGB(50, 35, 35)
resetBtn.TextColor3 = Color3.fromRGB(255, 180, 180)
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 11
resetBtn.Text = "🔄 Сбросить счётчик FPS"
resetBtn.AutoButtonColor = true
resetBtn.Parent = panel
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 8)

-- ==================== ЖИВОЙ FPS И СТАТУС ====================
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

        if cullStatus and cullStatus.Parent then
            local n = 0
            for _ in pairs(culled) do n = n + 1 end
            local lodCount = 0
            for _ in pairs(lodBackup) do lodCount = lodCount + 1 end
            cullStatus.Text = string.format("🎥 Скрыто: %d   |   🎚️ LOD: %d", n, lodCount)
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
    restoreLOD()
    resultLabel.Text = "🔙 Все скрытые объекты и LOD\nвозвращены в исходное состояние."
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
    RestoreAll = function() restoreAll(); restoreLOD() end,
    Culled = culled,
    LODBackup = lodBackup,
    Settings = SETTINGS,
}
