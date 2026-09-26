--[[
    ╔══════════════════════════════════════════════════════════╗
    ║   OPTIMIZER v3.1                                         ║
    ║   + Счётчик FPS: было / стало / сейчас                   ║
    ║   + НЕ трогает CoreGui (иконки Delta и Roblox)           ║
    ║   + Скрывает только игровой UI                           ║
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
    RemoveTextures = true,
    RemoveMeshes = false,
    RemoveParticles = true,
    RemoveLights = true,
    RemoveShadows = true,
    RemoveDecals = true,
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
    HideGameUI = true,          -- скрывает ТОЛЬКО игровой UI (не Delta!)
    HideChat = true,            -- скрывает чат
    HideTopbar = true,          -- скрывает топбар Roblox в игре
}

-- ==================== FPS СЧЁТЧИК ====================
local fpsState = {
    current = 0,
    before = 0,
    after = 0,
    frameCount = 0,
    lastTime = tick(),
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
    local conn
    conn = RunService.RenderStepped:Connect(function()
        frames = frames + 1
    end)
    repeat task.wait(0.05) until tick() - startT >= duration
    conn:Disconnect()
    local elapsed = tick() - startT
    return math.floor(frames / elapsed + 0.5)
end

-- ==================== УТИЛИТЫ ====================
local function safeRemove(obj)
    pcall(function() obj:Destroy() end)
end

local removed = {
    decals = 0, textures = 0, particles = 0,
    lights = 0, meshes = 0, sounds = 0
}

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

-- ★ НОВОЕ: скрывает только ИГРОВОЙ UI, не трогает Delta/Roblox
local function hideGameUI()
    if not SETTINGS.HideGameUI then return end

    -- 1. Отключаем стандартный топбар Roblox (только в игре)
    pcall(function()
        StarterGui:SetCore("TopbarEnabled", false)
    end)

    -- 2. Скрываем чат
    if SETTINGS.HideChat then
        pcall(function()
            StarterGui:SetCore("ChatWindowSize", UDim2.new(0, 0, 0, 0))
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
        end)
    end

    -- 3. Скрываем игровой интерфейс (но НЕ CoreGui Delta!)
    for _, obj in ipairs(LocalPlayer:WaitForChild("PlayerGui"):GetChildren()) do
        if obj:IsA("ScreenGui") and obj.Name ~= "OptimizerUI" then
            pcall(function() obj.Enabled = false end)
        end
    end

    -- 4. Следим, чтобы новые ScreenGui игры тоже скрывались
    LocalPlayer.PlayerGui.ChildAdded:Connect(function(obj)
        task.wait(0.1)
        if obj:IsA("ScreenGui") and obj.Name ~= "OptimizerUI" then
            pcall(function() obj.Enabled = false end)
        end
    end)
end

-- ==================== ЗАПУСК С ЗАМЕРОМ ====================
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
    hideGameUI()
    task.wait(0.3)

    status("📊 Замер FPS после оптимизации...")
    task.wait(0.2)
    local fpsAfter = measureFPS(1.5)

    fpsState.before = fpsBefore
    fpsState.after = fpsAfter

    local diff = fpsAfter - fpsBefore
    local sign = diff >= 0 and "+" or ""
    local percent = fpsBefore > 0 and math.floor((diff / fpsBefore) * 100) or 0

    return string.format(
        "🎯 FPS ДО:  %d\n" ..
        "🚀 FPS ПОСЛЕ: %d\n" ..
        "📈 Прирост: %s%d (%s%d%%)\n" ..
        "━━━━━━━━━━━━━━━\n" ..
        "🧹 Очищено:\n" ..
        "• Наклеек: %d\n" ..
        "• Текстур: %d\n" ..
        "• Частиц: %d\n" ..
        "• Света: %d\n" ..
        "• Мешей: %d\n" ..
        "• Звуков: %d",
        fpsBefore, fpsAfter,
        sign, diff, sign, percent,
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

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 280, 0, 340)
panel.Position = UDim2.new(0, 90, 0, 170)
panel.BackgroundColor3 = Color3.fromRGB(20, 28, 24)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local pStroke = Instance.new("UIStroke", panel)
pStroke.Color = Color3.fromRGB(120, 255, 160)
pStroke.Thickness = 1

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 26)
title.Position = UDim2.new(0, 8, 0, 6)
title.BackgroundTransparency = 1
title.Text = "⚡ OPTIMIZER v3.1"
title.TextColor3 = Color3.fromRGB(180, 255, 200)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
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

local resultLabel = Instance.new("TextLabel")
resultLabel.Size = UDim2.new(1, -16, 0, 130)
resultLabel.Position = UDim2.new(0, 8, 0, 64)
resultLabel.BackgroundColor3 = Color3.fromRGB(15, 22, 18)
resultLabel.BackgroundTransparency = 0.2
resultLabel.BorderSizePixel = 0
resultLabel.TextColor3 = Color3.fromRGB(200, 255, 220)
resultLabel.Font = Enum.Font.Gotham
resultLabel.TextSize = 11
resultLabel.TextWrapped = true
resultLabel.TextXAlignment = Enum.TextXAlignment.Left
resultLabel.TextYAlignment = Enum.TextYAlignment.Top
resultLabel.Text = "Нажми кнопку ниже, чтобы\nзамерить FPS и оптимизировать."
resultLabel.Parent = panel
Instance.new("UICorner", resultLabel).CornerRadius = UDim.new(0, 8)

local applyBtn = Instance.new("TextButton")
applyBtn.Size = UDim2.new(1, -16, 0, 34)
applyBtn.Position = UDim2.new(0, 8, 0, 200)
applyBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 50)
applyBtn.TextColor3 = Color3.fromRGB(180, 255, 200)
applyBtn.Font = Enum.Font.GothamBold
applyBtn.TextSize = 12
applyBtn.Text = "🚀 ОПТИМИЗИРОВАТЬ"
applyBtn.AutoButtonColor = true
applyBtn.Parent = panel
Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 8)

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(1, -16, 0, 26)
resetBtn.Position = UDim2.new(0, 8, 0, 240)
resetBtn.BackgroundColor3 = Color3.fromRGB(50, 35, 35)
resetBtn.TextColor3 = Color3.fromRGB(255, 180, 180)
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 11
resetBtn.Text = "🔄 Сбросить счётчик"
resetBtn.AutoButtonColor = true
resetBtn.Parent = panel
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 8)

-- ★ Кнопка возврата игрового UI
local restoreBtn = Instance.new("TextButton")
restoreBtn.Size = UDim2.new(1, -16, 0, 26)
restoreBtn.Position = UDim2.new(0, 8, 0, 272)
restoreBtn.BackgroundColor3 = Color3.fromRGB(35, 50, 65)
restoreBtn.TextColor3 = Color3.fromRGB(180, 220, 255)
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.TextSize = 11
restoreBtn.Text = "🔙 Вернуть игровой UI"
restoreBtn.AutoButtonColor = true
restoreBtn.Parent = panel
Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0, 8)

local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, -16, 0, 30)
infoLabel.Position = UDim2.new(0, 8, 0, 304)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Иконки Delta и Roblox не затрагиваются"
infoLabel.TextColor3 = Color3.fromRGB(140, 180, 160)
infoLabel.Font = Enum.Font.Gotham
infoLabel.TextSize = 10
infoLabel.TextWrapped = true
infoLabel.Parent = panel

-- ==================== ЖИВОЙ FPS В UI ====================
task.spawn(function()
    while task.wait(0.5) do
        if liveFpsLabel and liveFpsLabel.Parent then
            local fps = fpsState.current
            local color = Color3.fromRGB(255, 230, 100)
            local icon = "🎮"
            if fps >= 50 then
                color = Color3.fromRGB(100, 255, 130); icon = "🟢"
            elseif fps >= 30 then
                color = Color3.fromRGB(255, 230, 100); icon = "🟡"
            else
                color = Color3.fromRGB(255, 120, 120); icon = "🔴"
            end
            liveFpsLabel.Text = string.format("%s Сейчас FPS: %d", icon, fps)
            liveFpsLabel.TextColor3 = color
        end
    end
end)

-- ==================== ОБРАБОТЧИКИ ====================
mainBtn.Activated:Connect(function()
    panel.Visible = not panel.Visible
end)

local optimizing = false

applyBtn.Activated:Connect(function()
    if optimizing then return end
    optimizing = true

    applyBtn.Text = "⏳ Замер и оптимизация..."
    applyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 30)
    resultLabel.Text = "📊 Замер FPS до оптимизации..."

    task.spawn(function()
        local report = runOptimization(function(status)
            resultLabel.Text = status
        end)
        resultLabel.Text = report
        applyBtn.Text = "✅ ГОТОВО"
        applyBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 50)
        task.wait(2)
        applyBtn.Text = "🚀 ОПТИМИЗИРОВАТЬ"
        applyBtn.BackgroundColor3 = Color3.fromRGB(40, 70, 50)
        optimizing = false
    end)
end)

resetBtn.Activated:Connect(function()
    fpsState.before = 0
    fpsState.after = 0
    resultLabel.Text = "🔄 Счётчик сброшен.\nНажми «ОПТИМИЗИРОВАТЬ»,\nчтобы замерить FPS заново."
end)

-- ★ Возврат игрового UI
restoreBtn.Activated:Connect(function()
    pcall(function()
        StarterGui:SetCore("TopbarEnabled", true)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
    end)
    for _, obj in ipairs(LocalPlayer:WaitForChild("PlayerGui"):GetChildren()) do
        if obj:IsA("ScreenGui") and obj.Name ~= "OptimizerUI" then
            pcall(function() obj.Enabled = true end)
        end
    end
    resultLabel.Text = "🔙 Игровой UI возвращён.\n(иконки Delta и Roblox и так не трогались)"
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
    MeasureFPS = measureFPS,
    GetCurrentFPS = function() return fpsState.current end,
    GetBeforeFPS = function() return fpsState.before end,
    GetAfterFPS = function() return fpsState.after end,
    Settings = SETTINGS,
}
