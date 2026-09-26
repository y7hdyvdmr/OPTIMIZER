--[[
    ╔══════════════════════════════════════════════════════════╗
    ║   OPTIMIZER v5.5 — PRO CAMERA                            ║
    ║   + Камера смотрит далеко вниз/вверх                     ║
    ║   + Ползунок расстояния (дистанция камеры)               ║
    ║   + Пресеты дистанции: 50, 100, 250, 500, 1000           ║
    ║   + Скрытие игроков + FOV + оптимизация                  ║
    ║   + НЕ трогает UI игры / Delta / Roblox                  ║
    ╚══════════════════════════════════════════════════════════╝
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")
local LocalPlayer = Players.LocalPlayer

-- ==================== НАСТРОЙКИ ====================
local SETTINGS = {
    FOV = 90,
    CameraZoomMax = 500,
    CameraZoomMin = 0.1,
    ExtendCameraPitch = true,
    PitchLimit = 89,          -- почти вертикально вниз/вверх
    HideOtherPlayers = true,
    PlayerHideDistance = 50,
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
    KillReflections = true,
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

-- ==================== ★ PRO КАМЕРА ====================
local cameraBoosted = false
local origZoomMax, origZoomMin, origFOV

local function applyCamera()
    cameraBoosted = true

    pcall(function()
        if not origZoomMax then origZoomMax = LocalPlayer.CameraMaxZoomDistance end
        if not origZoomMin then origZoomMin = LocalPlayer.CameraMinZoomDistance end
        LocalPlayer.CameraMaxZoomDistance = SETTINGS.CameraZoomMax
        LocalPlayer.CameraMinZoomDistance = SETTINGS.CameraZoomMin
    end)

    local cam = Workspace.CurrentCamera
    if cam then
        if not origFOV then origFOV = cam.FieldOfView end
        cam.FieldOfView = SETTINGS.FOV
    end

    -- ★ Расширяем лимит наклона вверх/вниз
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
                pcall(function() active.minPitch = -SETTINGS.PitchLimit end)
                pcall(function() active.maxPitch =  SETTINGS.PitchLimit end)
            end

            local oc = cameras and cameras.activeOcclusion
            if oc then
                pcall(function() oc.enabled = false end)
            end
        end
    end)
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

local function setZoomDistance(v)
    SETTINGS.CameraZoomMax = v
    pcall(function()
        LocalPlayer.CameraMaxZoomDistance = v
    end)
end

applyCamera()

-- ==================== СКРЫТИЕ ИГРОКОВ ====================
local hiddenPlayers = {}
local playerHideConn = nil

local function hidePlayerParts(plr)
    if not plr or plr == LocalPlayer then return end
    if hiddenPlayers[plr] then return end
    local char = plr.Character
    if not char then return end

    local parts = {}
    local function processObj(obj)
        if obj:IsA("BasePart") or obj:IsA("Decal") or obj:IsA("ParticleEmitter")
            or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Fire") or obj:IsA("Smoke") then
            table.insert(parts, {
                obj = obj,
                transparency = obj.Transparency,
                localTrans = obj:IsA("BasePart") and obj.LocalTransparencyModifier or nil,
                enabled = obj.Enabled,
                isPart = obj:IsA("BasePart"),
            })
            pcall(function()
                if obj:IsA("BasePart") then
                    obj.Transparency = 1
                    obj.LocalTransparencyModifier = 1
                    obj.CanCollide = false
                    obj.CanQuery = false
                    obj.CanTouch = false
                else
                    obj.Transparency = 1
                    obj.Enabled = false
                end
            end)
        end
    end

    processObj(char)
    for _, obj in ipairs(char:GetDescendants()) do processObj(obj) end

    local ff = char:FindFirstChildOfClass("ForceField")
    if ff then pcall(function() ff.Visible = false end) end

    hiddenPlayers[plr] = parts
end

local function showPlayerParts(plr)
    if not hiddenPlayers[plr] then return end
    for _, data in ipairs(hiddenPlayers[plr]) do
        pcall(function()
            if data.obj then
                data.obj.Transparency = data.transparency or 0
                if data.isPart and data.localTrans ~= nil then
                    data.obj.LocalTransparencyModifier = data.localTrans
                end
                if not data.isPart then
                    data.obj.Enabled = data.enabled ~= false
                end
                if data.isPart then
                    data.obj.CanCollide = true
                    data.obj.CanQuery = true
                    data.obj.CanTouch = true
                end
            end
        end)
    end
    hiddenPlayers[plr] = nil
end

local function showAllPlayers()
    for plr in pairs(hiddenPlayers) do showPlayerParts(plr) end
end

local function hookPlayers()
    if playerHideConn then playerHideConn:Disconnect(); playerHideConn = nil end
    playerHideConn = RunService.Heartbeat:Connect(function()
        if not SETTINGS.HideOtherPlayers then
            if next(hiddenPlayers) then showAllPlayers() end
            return
        end
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end
        local myPos = myRoot.Position

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root and root.Parent then
                    local dist = (root.Position - myPos).Magnitude
                    if dist > SETTINGS.PlayerHideDistance then
                        hidePlayerParts(plr)
                    else
                        if hiddenPlayers[plr] then showPlayerParts(plr) end
                    end
                else
                    if hiddenPlayers[plr] then showPlayerParts(plr) end
                end
            end
        end
    end)
end

hookPlayers()

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

-- ==================== ПРЕСЕТЫ ====================
local PRESETS = {
    Low = {
        name = "Низкая",
        HideOtherPlayers = true, PlayerHideDistance = 1,
        RemoveParticles = false, RemoveLights = false, RemoveShadows = false,
        RemoveDecals = false, RemoveTextures = false, RemoveFog = false,
        RemoveSky = false, RemoveAtmosphere = false,
        RemoveBloom = true, RemoveBlur = true, RemoveSunRays = false,
        RemoveColorCorrection = false, RemoveDepthOfField = false,
        TerrainLowQuality = false, KillReflections = false, FOV = 80,
    },
    Medium = {
        name = "Средняя",
        HideOtherPlayers = true, PlayerHideDistance = 50,
        RemoveParticles = true, RemoveLights = true, RemoveShadows = true,
        RemoveDecals = false, RemoveTextures = false, RemoveFog = true,
        RemoveSky = false, RemoveAtmosphere = false,
        RemoveBloom = true, RemoveBlur = true, RemoveSunRays = true,
        RemoveColorCorrection = true, RemoveDepthOfField = true,
        TerrainLowQuality = true, KillReflections = true, FOV = 90,
    },
    High = {
        name = "Высокая",
        HideOtherPlayers = true, PlayerHideDistance = 100,
        RemoveParticles = true, RemoveLights = true, RemoveShadows = true,
        RemoveDecals = true, RemoveTextures = true, RemoveFog = true,
        RemoveSky = true, RemoveAtmosphere = true,
        RemoveBloom = true, RemoveBlur = true, RemoveSunRays = true,
        RemoveColorCorrection = true, RemoveDepthOfField = true,
        TerrainLowQuality = true, KillReflections = true, FOV = 100,
    },
}

local function applyPreset(key)
    local p = PRESETS[key]
    if not p then return end
    for k, v in pairs(p) do
        if k ~= "name" then SETTINGS[k] = v end
    end
    setFOV(SETTINGS.FOV)
    if not SETTINGS.HideOtherPlayers then showAllPlayers() end
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
panel.Size = UDim2.new(0, 320, 0, 580)
panel.Position = UDim2.new(0, 85, 0, 70)
panel.BackgroundColor3 = Color3.fromRGB(20, 28, 24)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Visible = false
panel.CanvasSize = UDim2.new(0, 0, 0, 1020)
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
title.Text = "⚡ OPTIMIZER v5.5 — PRO CAM"
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
statusLabel.Text = "👥 Скрыто: 0  |  📷 FOV: 90  |  📏 Дист: 500"
statusLabel.TextColor3 = Color3.fromRGB(140, 200, 255)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 10
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = panel

local resultLabel = Instance.new("TextLabel")
resultLabel.Size = UDim2.new(1, -16, 0, 60)
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

-- ==================== ПРЕСЕТЫ ====================
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
        resultLabel.Text = "✅ Пресет «" .. PRESETS[key].name .. "»"
    end)
    return b
end

makePresetBtn("🟢 Низкая",  8,  95, 154, "Low",    Color3.fromRGB(35, 65, 45))
makePresetBtn("🟡 Средняя", 110, 95, 154, "Medium", Color3.fromRGB(75, 65, 25))
makePresetBtn("🔴 Высокая", 212, 95, 154, "High",   Color3.fromRGB(75, 35, 35))

-- ==================== ★ ДИСТАНЦИЯ КАМЕРЫ (ползунок + кнопки) ====================
local zoomLabel = Instance.new("TextLabel")
zoomLabel.Size = UDim2.new(1, -16, 0, 18)
zoomLabel.Position = UDim2.new(0, 8, 0, 194)
zoomLabel.BackgroundTransparency = 1
zoomLabel.Text = "📏 Дальность камеры (стад)"
zoomLabel.TextColor3 = Color3.fromRGB(200, 255, 200)
zoomLabel.Font = Enum.Font.GothamBold
zoomLabel.TextSize = 11
zoomLabel.TextXAlignment = Enum.TextXAlignment.Left
zoomLabel.Parent = panel

-- ★ Ползунок расстояния
local sliderBg = Instance.new("Frame")
sliderBg.Size = UDim2.new(1, -16, 0, 16)
sliderBg.Position = UDim2.new(0, 8, 0, 216)
sliderBg.BackgroundColor3 = Color3.fromRGB(30, 45, 35)
sliderBg.BorderSizePixel = 0
sliderBg.Parent = panel
Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(0, 8)

local sliderFill = Instance.new("Frame")
sliderFill.Size = UDim2.new(0.5, 0, 1, 0)
sliderFill.BackgroundColor3 = Color3.fromRGB(100, 220, 140)
sliderFill.BorderSizePixel = 0
sliderFill.Parent = sliderBg
Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(0, 8)

local sliderKnob = Instance.new("TextButton")
sliderKnob.Size = UDim2.new(0, 20, 0, 20)
sliderKnob.Position = UDim2.new(0.5, -10, 0, -2)
sliderKnob.BackgroundColor3 = Color3.fromRGB(180, 255, 200)
sliderKnob.Text = ""
sliderKnob.AutoButtonColor = false
sliderKnob.Parent = sliderBg
Instance.new("UICorner", sliderKnob).CornerRadius = UDim.new(0, 10)

local zoomValueLabel = Instance.new("TextLabel")
zoomValueLabel.Size = UDim2.new(1, -16, 0, 16)
zoomValueLabel.Position = UDim2.new(0, 8, 0, 234)
zoomValueLabel.BackgroundTransparency = 1
zoomValueLabel.Text = "Значение: 500"
zoomValueLabel.TextColor3 = Color3.fromRGB(180, 255, 200)
zoomValueLabel.Font = Enum.Font.GothamBold
zoomValueLabel.TextSize = 10
zoomValueLabel.Parent = panel

local ZOOM_MIN, ZOOM_MAX = 10, 2000
local function setSliderValue(t)   -- t = 0..1
    t = math.clamp(t, 0, 1)
    local v = math.floor(ZOOM_MIN + (ZOOM_MAX - ZOOM_MIN) * t)
    sliderFill.Size = UDim2.new(t, 0, 1, 0)
    sliderKnob.Position = UDim2.new(t, -10, 0, -2)
    zoomValueLabel.Text = "Значение: " .. v .. " стад"
    setZoomDistance(v)
end

local draggingSlider = false
sliderKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingSlider = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingSlider = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if not draggingSlider then return end
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
        local rel = (input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X
        setSliderValue(rel)
    end
end)
-- Тап по полосе
sliderBg.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local rel = (input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X
        setSliderValue(rel)
    end
end)

-- ★ Кнопки быстрой дистанции
local zoomPresets = { 50, 100, 250, 500, 1000, 2000 }
for i, v in ipairs(zoomPresets) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 47, 0, 24)
    b.Position = UDim2.new(0, 8 + (i-1)*50, 0, 254)
    b.BackgroundColor3 = Color3.fromRGB(35, 60, 45)
    b.TextColor3 = Color3.fromRGB(180, 255, 200)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.Text = tostring(v)
    b.AutoButtonColor = true
    b.Parent = panel
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.Activated:Connect(function()
        local t = (v - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN)
        setSliderValue(t)
        resultLabel.Text = "📏 Дистанция камеры: " .. v .. " стад"
    end)
end

-- ==================== FOV ====================
local fovLabel = Instance.new("TextLabel")
fovLabel.Size = UDim2.new(1, -16, 0, 18)
fovLabel.Position = UDim2.new(0, 8, 0, 286)
fovLabel.BackgroundTransparency = 1
fovLabel.Text = "📷 FOV (поле зрения)"
fovLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
fovLabel.Font = Enum.Font.GothamBold
fovLabel.TextSize = 11
fovLabel.TextXAlignment = Enum.TextXAlignment.Left
fovLabel.Parent = panel

local fovValues = { 70, 80, 90, 100, 110, 120 }
for i, v in ipairs(fovValues) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 47, 0, 26)
    b.Position = UDim2.new(0, 8 + (i-1)*50, 0, 308)
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

-- ==================== ДИСТАНЦИЯ СКРЫТИЯ ИГРОКОВ ====================
local distLabel = Instance.new("TextLabel")
distLabel.Size = UDim2.new(1, -16, 0, 18)
distLabel.Position = UDim2.new(0, 8, 0, 342)
distLabel.BackgroundTransparency = 1
distLabel.Text = "👥 Скрывать игроков дальше (стад)"
distLabel.TextColor3 = Color3.fromRGB(255, 220, 160)
distLabel.Font = Enum.Font.GothamBold
distLabel.TextSize = 11
distLabel.TextXAlignment = Enum.TextXAlignment.Left
distLabel.Parent = panel

local distValues = { 1, 10, 30, 50, 80, 100, 150, 200 }
for i, v in ipairs(distValues) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 35, 0, 26)
    b.Position = UDim2.new(0, 8 + (i-1)*37, 0, 364)
    b.BackgroundColor3 = Color3.fromRGB(60, 50, 30)
    b.TextColor3 = Color3.fromRGB(255, 220, 160)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.Text = tostring(v)
    b.AutoButtonColor = true
    b.Parent = panel
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.Activated:Connect(function()
        SETTINGS.PlayerHideDistance = v
        resultLabel.Text = "👥 Игроки скрыты с " .. v .. " стад"
    end)
end

-- ==================== ПЕРЕКЛЮЧАТЕЛИ ====================
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

makeToggle("👥 Скрытие игроков", 398, function() return SETTINGS.HideOtherPlayers end,
    function(v) SETTINGS.HideOtherPlayers = v; if not v then showAllPlayers() end end)
makeToggle("📷 Расширение камеры", 426, function() return cameraBoosted end,
    function(v) if v then applyCamera() else restoreCamera() end end)
makeToggle("🧹 Частицы", 454, function() return SETTINGS.RemoveParticles end,
    function(v) SETTINGS.RemoveParticles = v end)
makeToggle("💡 Свет", 482, function() return SETTINGS.RemoveLights end,
    function(v) SETTINGS.RemoveLights = v end)
makeToggle("🌑 Тени", 510, function() return SETTINGS.RemoveShadows end,
    function(v) SETTINGS.RemoveShadows = v end)
makeToggle("🎨 Наклейки / Текстуры", 538,
    function() return SETTINGS.RemoveDecals and SETTINGS.RemoveTextures end,
    function(v) SETTINGS.RemoveDecals = v; SETTINGS.RemoveTextures = v end)
makeToggle("🌫 Туман", 566, function() return SETTINGS.RemoveFog end,
    function(v) SETTINGS.RemoveFog = v end)
makeToggle("🌌 Небо / Атмосфера", 594,
    function() return SETTINGS.RemoveSky and SETTINGS.RemoveAtmosphere end,
    function(v) SETTINGS.RemoveSky = v; SETTINGS.RemoveAtmosphere = v end)
makeToggle("🌸 Пост-эффекты", 622,
    function() return SETTINGS.RemoveBloom and SETTINGS.RemoveBlur end,
    function(v)
        SETTINGS.RemoveBloom = v; SETTINGS.RemoveBlur = v
        SETTINGS.RemoveSunRays = v; SETTINGS.RemoveColorCorrection = v
        SETTINGS.RemoveDepthOfField = v
    end)
makeToggle("🌊 Террейн", 650, function() return SETTINGS.TerrainLowQuality end,
    function(v) SETTINGS.TerrainLowQuality = v end)
makeToggle("✨ Отражения", 678, function() return SETTINGS.KillReflections end,
    function(v) SETTINGS.KillReflections = v end)
makeToggle("🔊 Глушить звуки", 706, function() return SETTINGS.KillSounds end,
    function(v) SETTINGS.KillSounds = v end)

-- ==================== КНОПКИ ДЕЙСТВИЙ ====================
local applyBtn = Instance.new("TextButton")
applyBtn.Size = UDim2.new(1, -16, 0, 34)
applyBtn.Position = UDim2.new(0, 8, 0, 744)
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
restoreBtn.Position = UDim2.new(0, 8, 0, 784)
restoreBtn.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
restoreBtn.TextColor3 = Color3.fromRGB(180, 220, 255)
restoreBtn.Font = Enum.Font.GothamBold
restoreBtn.TextSize = 11
restoreBtn.Text = "🔙 Вернуть всех игроков"
restoreBtn.AutoButtonColor = true
restoreBtn.Parent = panel
Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0, 8)

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(1, -16, 0, 26)
resetBtn.Position = UDim2.new(0, 8, 0, 816)
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
            local pn = 0
            for _ in pairs(hiddenPlayers) do pn = pn + 1 end
            statusLabel.Text = string.format("👥 %d | 📷 %d° | 📏 %d",
                pn, SETTINGS.FOV, SETTINGS.CameraZoomMax)
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
    showAllPlayers()
    resultLabel.Text = "🔙 Все игроки видны снова."
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

-- Стартовое значение ползунка (500)
setSliderValue((500 - ZOOM_MIN) / (ZOOM_MAX - ZOOM_MIN))

return {
    Optimize = runOptimization,
    RestoreAll = showAllPlayers,
    ApplyPreset = applyPreset,
    SetFOV = setFOV,
    SetZoom = setZoomDistance,
    Presets = PRESETS,
    Settings = SETTINGS,
}
