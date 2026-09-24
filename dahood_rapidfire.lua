-- language: Luau, target: Roblox Da Hood, executor: UNC-compatible
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local lp = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local MainEvent = ReplicatedStorage:WaitForChild("MainEvent")
local GunHandler = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GunHandler"))

if not getconnections then
    warn("[pengooin] getconnections unavailable — original gun scripts may double-fire")
end

local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local state = {
    firing = false,
    mouseDown = false,
    thread = nil,
    conns = {},
    disabledConns = {},
    currentTool = nil,
    fly = {
        active = false,
        conn = nil,
        stateConn = nil,
        lastTick = 0,
    },
    speed = {
        active = false,
        conn = nil,
        propConn = nil,
    },
    ragebot = {
        active = false,
        target = nil,
        thread = nil,
        hidden = false,
        restores = nil,
        camState = nil,
        origCF = nil,
        renderBind = nil,
        clone = nil,
    },
    autoArmor = {
        active = false,
        thread = nil,
    },
    combat = {
        aimbot = {conn = nil, keyHeld = false},
        triggerbot = {conn = nil, lastFireAt = 0, keyHeld = false},
        fov = {conn = nil, sgui = nil, ring = nil},
    },
}

local function clearConns()
    for _, c in state.conns do
        c:Disconnect()
    end
    table.clear(state.conns)
end

local function enableOriginal()
    for _, c in state.disabledConns do
        pcall(function() c:Enable() end)
    end
    table.clear(state.disabledConns)
end

local function disableOriginal(tool)
    enableOriginal()
    if not tool or not getconnections then return end
    for _, conn in getconnections(tool.Activated) do
        conn:Disable()
        table.insert(state.disabledConns, conn)
    end
end

local function cleanup()
    state.firing = false
    state.mouseDown = false
    local t = state.thread
    state.thread = nil
    if t then pcall(task.cancel, t) end
    clearConns()
    enableOriginal()
    state.currentTool = nil
end

local function getMuzzle(tool)
    local handle = tool:FindFirstChild("Handle")
    if not handle then return nil, nil end
    local def = tool:FindFirstChild("Default")
    if def then
        local mesh = def:FindFirstChild("Mesh")
        if mesh then
            local muz = mesh:FindFirstChild("Muzzle")
            if muz then return muz.WorldPosition, handle end
        end
    end
    return (handle.CFrame * CFrame.new(0, 0.3, 2)).Position, handle
end

local function canFire()
    local char = lp.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local be = char:FindFirstChild("BodyEffects")
    if not be then return false end
    if not char:FindFirstChild("FULLY_LOADED_CHAR") then return false end
    if char:FindFirstChild("FORCEFIELD") then return false end
    if char:FindFirstChild("GRABBING_CONSTRAINT") then return false end
    if be:FindFirstChild("Block") then return false end
    if be:FindFirstChild("Cuff") and be.Cuff.Value then return false end
    if be:FindFirstChild("K.O") and be["K.O"].Value then return false end
    if be:FindFirstChild("Grabbed") and be.Grabbed.Value then return false end
    if be:FindFirstChild("Dead") and be.Dead.Value then return false end
    if be:FindFirstChild("Reload") and be.Reload.Value then return false end
    if be:FindFirstChild("Attacking") and be.Attacking.Value then return false end
    return true
end

local function getGun()
    local char = lp.Character
    if not char then return nil end
    local tool = char:FindFirstChildWhichIsA("Tool")
    if not tool then return nil end
    if not tool:FindFirstChild("Handle") or not tool:FindFirstChild("Ammo") then return nil end
    if tool:GetAttribute("Cooldown") then return nil end
    return tool
end

local function burstSize(tool)
    if tool:FindFirstChild("GunClientBurst") then
        return math.min(tool.Ammo.Value, 3)
    end
    return 1
end

local function fireShot(tool, char)
    local origin, handle = getMuzzle(tool)
    if not origin or not handle then return end

    local range = (tool:FindFirstChild("Range") and tool.Range.Value) or 200
    local remote = tool:FindFirstChild("RemoteEvent")
    local count = burstSize(tool)
    local sc = tool:FindFirstChild("ShootingCooldown")
    local bulletDelay = sc and sc.Value or 0.05

    if remote then
        remote:FireServer("Shoot")
    end

    for i = 1, count do
        if not state.firing or not state.mouseDown then break end
        if tool.Ammo.Value <= 0 then break end
        if tool.Parent ~= char then break end

        origin = getMuzzle(tool) or origin
        local dir = GunHandler.getAim(origin, range)
        local aim = origin + dir * range

        local a, b, c = GunHandler.shoot({
            Shooter = char,
            Handle = handle,
            ForcedOrigin = origin,
            AimPosition = aim,
            Range = range,
            BeamColor = Color3.new(1, 0.545098, 0.14902),
        })

        MainEvent:FireServer("ShootGun", handle, origin, a, b, c)

        if i < count then
            task.wait(bulletDelay)
        end
    end

    if remote then
        remote:FireServer()
    end
end

local function fireLoop()
    while state.firing do
        if not state.mouseDown then
            RunService.Heartbeat:Wait()
            continue
        end

        if not canFire() then
            task.wait(0.1)
            continue
        end

        local char = lp.Character
        local tool = getGun()

        if not tool then
            task.wait(0.1)
            continue
        end

        if tool.Ammo.Value <= 0 then
            if Toggles.AutoReload.Value then
                MainEvent:FireServer("Reload", tool)
                local timeout = tick() + 5
                while tick() < timeout and state.firing do
                    local be = char and char:FindFirstChild("BodyEffects")
                    if be and not be.Reload.Value and tool.Ammo.Value > 0 then
                        break
                    end
                    task.wait(0.1)
                end
            else
                task.wait(0.1)
            end
            continue
        end

        if state.currentTool ~= tool then
            disableOriginal(tool)
            state.currentTool = tool
        end

        fireShot(tool, char)
        task.wait(math.max(Options.FireDelay.Value, 0.01))
    end
    state.thread = nil
end

local function spawnLoop()
    if state.firing and not state.thread then
        state.thread = task.spawn(fireLoop)
    end
end

-- ── GUI ──

local Window = Library:CreateWindow({
    Title = "pengooin | private",
    Center = true,
    AutoShow = true,
    TabPadding = 3,
    MenuFadeTime = 0.2,
})

local Tabs = {
    Combat = Window:AddTab("Combat"),
    Movement = Window:AddTab("Movement"),
    Buy = Window:AddTab("Buy"),
    Ragebot = Window:AddTab("Ragebot"),
    Settings = Window:AddTab("Settings"),
}

local box = Tabs.Ragebot:AddLeftGroupbox("Rapid Fire")

box:AddToggle("RapidFire", {
    Text = "Rapid Fire",
    Default = false,
    Tooltip = "Bypass fire rate cooldown on all guns",
}):AddKeyPicker("RapidFireKey", {
    Default = "None",
    SyncToggleState = true,
    Mode = "Toggle",
    Text = "Rapid Fire",
})

box:AddDivider()

box:AddSlider("FireDelay", {
    Text = "Cycle Delay",
    Default = 0.05,
    Min = 0.01,
    Max = 1.0,
    Rounding = 2,
    Tooltip = "Seconds between shot cycles. Lower = faster. Under 0.05 is aggressive.",
})

box:AddToggle("AutoReload", {
    Text = "Auto Reload",
    Default = true,
    Tooltip = "Reload automatically when magazine empties",
})

local moveBox = Tabs.Movement:AddLeftGroupbox("Fly")

moveBox:AddToggle("Fly", {
    Text = "Fly",
    Default = false,
    Tooltip = "BodyVelocity/BodyGyro flight — camera-relative WASD, space up, ctrl down",
}):AddKeyPicker("FlyKey", {
    Default = "F",
    SyncToggleState = true,
    Mode = "Toggle",
    Text = "Fly",
})

moveBox:AddSlider("FlySpeed", {
    Text = "Fly Speed",
    Default = 50,
    Min = 10,
    Max = 200,
    Rounding = 0,
    Tooltip = "Studs per second. Da Hood server flags per-frame delta > ~4 studs — keep under ~120 to stay clean.",
})

moveBox:AddToggle("FlyVertical", {
    Text = "Vertical on Space/Ctrl",
    Default = true,
    Tooltip = "Space = up, LeftCtrl = down. Off = camera pitch only",
})

local speedBox = Tabs.Movement:AddRightGroupbox("Walkspeed")

speedBox:AddToggle("WalkSpeed", {
    Text = "Walk Speed",
    Default = false,
    Tooltip = "Overrides Humanoid.WalkSpeed and re-applies on server clamp",
}):AddKeyPicker("WalkSpeedKey", {
    Default = "G",
    SyncToggleState = true,
    Mode = "Toggle",
    Text = "Walk Speed",
})

speedBox:AddSlider("WalkSpeedValue", {
    Text = "Walk Speed",
    Default = 60,
    Min = 16,
    Max = 400,
    Rounding = 0,
    Tooltip = "CFrame-nudge speed — reads WASD via Humanoid.MoveDirection, never writes WalkSpeed. Per-frame clamp caps effective ceiling ~240/s at 60fps.",
})

-- ── Fly ──

local function getRoot()
    local char = lp.Character
    if not char then return nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    if not hrp or not hum then return nil, nil end
    return hrp, hum
end

local function stopFly()
    state.fly.active = false
    if state.fly.conn then state.fly.conn:Disconnect(); state.fly.conn = nil end
end

local function startFly()
    stopFly()
    local hrp, hum = getRoot()
    if not hrp or not hum then return end

    state.fly.active = true

    state.fly.conn = RunService.Heartbeat:Connect(function(dt)
        if not state.fly.active then return end
        local root = getRoot()
        if not root then return end

        local speed = Options.FlySpeed.Value
        local step = math.min(speed * dt, 4)

        local cam = camera.CFrame
        local move = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - cam.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + cam.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - cam.RightVector end

        if Toggles.FlyVertical.Value then
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - Vector3.new(0, 1, 0) end
        end

        if move.Magnitude > 0 then
            root.CFrame = root.CFrame + move.Unit * step
        else
            root.CFrame = root.CFrame + Vector3.new(0, math.min(workspace.Gravity * dt * dt * 0.5, 4), 0)
        end

        root.AssemblyLinearVelocity = Vector3.zero
    end)
end

-- ── Walkspeed ──

local function stopSpeed()
    state.speed.active = false
    if state.speed.conn then state.speed.conn:Disconnect(); state.speed.conn = nil end
    if state.speed.propConn then state.speed.propConn:Disconnect(); state.speed.propConn = nil end
end

local function startSpeed()
    stopSpeed()
    local hrp, hum = getRoot()
    if not hrp or not hum then return end
    state.speed.active = true

    state.speed.conn = RunService.Heartbeat:Connect(function(dt)
        if not state.speed.active then return end
        if state.fly.active then return end
        local root, humanoid = getRoot()
        if not root or not humanoid then return end

        local dir = humanoid.MoveDirection
        if dir.Magnitude < 0.01 then return end

        local speed = Options.WalkSpeedValue.Value
        local extra = math.max(speed - humanoid.WalkSpeed, 0)
        local step = math.min(extra * dt, 4)
        if step <= 0 then return end

        root.CFrame = root.CFrame + dir.Unit * step
    end)
end

-- ── Buy ──

local GUN_KEYWORDS = {
    "AK47","AR","SMG","LMG","Glock","Deagle","Revolver","Shotgun","Rifle","Sniper","Uzi",
    "M4","MP5","P90","AUG","Flintlock","RPG","GrenadeLauncher","Flamethrower","Silencer",
    "SilencerAR","Molotov","Grenade","Flashbang","TacticalShotgun","Drum-Shotgun","DrumGun",
    "Double-Barrel","Bat","Pitchfork","Knife","Machete","Sword","Chainsaw","Pistol","Musket",
    "Crossbow","Bow","Katana","Hammer","Fireworks","Firework",
}
local FOOD_KEYWORDS = {
    "Pizza","Chicken","Burger","Hamburger","Fries","Donut","Salad","Coke","Water","BloxyCola",
    "Soda","Sandwich","Taco","Sushi","Cake","Cookie","IceCream","Coffee","Bread","Steak","Egg",
    "Milk","Juice","Fruit","Apple","Banana","Beer","Wine","HotDog","Lemonade","Lettuce","Meat",
    "Popcorn","Popsicle","Latte","Starblox","Cranberry","FoodsCart",
}

local function parseItem(model)
    local name = model.Name
    if name:find("Robux") then return nil end
    local cd = model:FindFirstChildOfClass("ClickDetector")
    if not cd then return nil end
    local amountPrefix = name:match("^(%d+)%s+")
    local inner = name:match("%[([^%]]+)%]") or name:match("^(.-)%s%-%s%$")
    if not inner then return nil end
    local price = tonumber(name:match("%$(%d+)"))
    return {
        model = model,
        cd = cd,
        inner = inner,
        amount = tonumber(amountPrefix),
        price = price,
        isAmmo = inner:find("Ammo") ~= nil,
    }
end

local function keywordMatch(name, list)
    for _, kw in list do
        if name:find(kw, 1, true) then return true end
    end
    return false
end

local function classify(item)
    local n = item.inner
    if item.isAmmo then return "Ammo" end
    if n:find("Armor") or n:find("AntiBodies") then return "Armor" end
    if n:find("Mask") or n == "Bandana" or n:find("Hockey") or n:find("Ski Mask") then return "Masks" end
    if keywordMatch(n, FOOD_KEYWORDS) then return "Food" end
    if keywordMatch(n, GUN_KEYWORDS) then return "Guns" end
    return "Misc"
end

-- ── Silent-buy primitives (hoisted for reuse by both the Buy tab and the
--     ragebot auto-armor loop). Same movement-during-click pattern verified
--     for Da Hood shop pads; the buy is silent-on-client via a high-priority
--     BindToRenderStep that pins transparency + camera each frame. ──

local function moneyValue()
    local ok, v = pcall(function()
        return lp:FindFirstChild("DataFolder") and lp.DataFolder:FindFirstChild("Currency") and lp.DataFolder.Currency.Value
    end)
    return ok and v or 0
end

local function hideCharacter(char)
    local restores = {}
    for _, d in char:GetDescendants() do
        if d:IsA("BasePart") then
            restores[d] = {kind = "part", trans = d.LocalTransparencyModifier, shadow = d.CastShadow}
            d.LocalTransparencyModifier = 1
            d.CastShadow = false
        elseif d:IsA("Decal") or d:IsA("Texture") then
            restores[d] = {kind = "decal", val = d.Transparency}
            d.Transparency = 1
        elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
            restores[d] = {kind = "gui", val = d.Enabled}
            d.Enabled = false
        elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
            restores[d] = {kind = "effect", val = d.Enabled}
            d.Enabled = false
        elseif d:IsA("Light") then
            restores[d] = {kind = "light", val = d.Enabled}
            d.Enabled = false
        end
    end
    return restores
end

local function restoreCharacter(restores)
    for d, r in restores do
        if d.Parent then
            if r.kind == "part" then
                d.LocalTransparencyModifier = r.trans
                d.CastShadow = r.shadow
            elseif r.kind == "decal" then d.Transparency = r.val
            elseif r.kind == "gui" then d.Enabled = r.val
            elseif r.kind == "effect" then d.Enabled = r.val
            elseif r.kind == "light" then d.Enabled = r.val
            end
        end
    end
end

local function silentBuy(item)
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return false end

    local target = item.model.PrimaryPart or item.model:FindFirstChild("Head")
    if not target then return false end

    local originalCF = hrp.CFrame
    local anchor = CFrame.new(target.Position + Vector3.new(-2, 3, 0))
    local moneyStart = moneyValue()
    local pricePaid = 0

    local cam = Workspace.CurrentCamera
    local origCamCF = cam.CFrame
    local origCamType = cam.CameraType
    local origCamSubject = cam.CameraSubject
    cam.CameraType = Enum.CameraType.Scriptable
    cam.CFrame = origCamCF

    local restores = hideCharacter(char)

    local bindName = "pengooin_SilentBuy_" .. tostring(tick())
    RunService:BindToRenderStep(bindName, 3000, function()
        for d, r in restores do
            if d.Parent then
                if r.kind == "part" then
                    d.LocalTransparencyModifier = 1
                    d.CastShadow = false
                elseif r.kind == "decal" then d.Transparency = 1
                elseif r.kind == "gui" then d.Enabled = false
                elseif r.kind == "effect" then d.Enabled = false
                elseif r.kind == "light" then d.Enabled = false
                end
            end
        end
        cam.CFrame = origCamCF
    end)

    hrp.CFrame = anchor
    RunService.Heartbeat:Wait()

    local maxBursts = 6
    for burst = 1, maxBursts do
        for i = 1, 25 do
            local angle = (i / 25 + burst) * math.pi * 4
            local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
            hum:Move(dir, false)
            hrp.CFrame = hrp.CFrame + Vector3.new(math.cos(angle) * 0.3, 0, math.sin(angle) * 0.3)
            if i % 2 == 0 then
                pcall(fireclickdetector, item.cd)
            end
            RunService.Heartbeat:Wait()
        end
        local currentMoney = moneyValue()
        local spent = moneyStart - currentMoney
        if spent > pricePaid then
            pricePaid = spent
            if item.amount == nil then break end
            if item.price and spent >= item.price then break end
        end
    end

    hum:Move(Vector3.zero, false)
    hrp.CFrame = originalCF
    for _ = 1, 3 do RunService.Heartbeat:Wait() end

    pcall(function() RunService:UnbindFromRenderStep(bindName) end)
    restoreCharacter(restores)
    cam.CameraType = origCamType
    cam.CameraSubject = origCamSubject

    return pricePaid > 0
end

-- Shared lock so the Buy tab's buttons and the ragebot auto-armor loop can't
-- both fire silentBuy at once (double-hide, double-teleport = broken state).
local g_buyLock = false
local function dispatchBuy(item, onDone)
    if g_buyLock then return false end
    g_buyLock = true
    task.spawn(function()
        local ok, result = pcall(silentBuy, item)
        g_buyLock = false
        if not ok then warn("[pengooin] silentBuy failed:", result) end
        if onDone then pcall(onDone, ok and result) end
    end)
    return true
end

local function buildBuyTab()
    local shopFolder = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Shop")
    if not shopFolder then
        Tabs.Buy:AddLeftGroupbox("Error"):AddLabel("Shop folder not found (workspace.Ignored.Shop). Rejoin after map load.")
        return
    end

    local buckets = {Guns = {}, Ammo = {}, Masks = {}, Food = {}, Armor = {}, Misc = {}}
    local byKey = {}
    for _, m in shopFolder:GetChildren() do
        local item = parseItem(m)
        if item then
            local unitCost = item.amount and (item.price / math.max(item.amount, 1)) or item.price or math.huge
            local key = item.inner .. "|" .. tostring(item.amount or 0)
            local existing = byKey[key]
            if not existing or unitCost < existing.unitCost then
                item.unitCost = unitCost
                byKey[key] = item
            end
        end
    end

    for _, item in byKey do
        table.insert(buckets[classify(item)], item)
    end

    for _, list in buckets do
        table.sort(list, function(a, b)
            if a.inner == b.inner then return (a.amount or 0) > (b.amount or 0) end
            return a.inner < b.inner
        end)
    end

    local gunsBox = Tabs.Buy:AddLeftGroupbox("Guns")
    local ammoBox = Tabs.Buy:AddRightGroupbox("Ammo")
    local masksBox = Tabs.Buy:AddLeftGroupbox("Masks")
    local foodBox = Tabs.Buy:AddRightGroupbox("Food")
    local armorBox = Tabs.Buy:AddLeftGroupbox("Armor")
    local miscBox = Tabs.Buy:AddRightGroupbox("Misc")

    local function buyOnce(item)
        dispatchBuy(item)
    end

    local function addButtons(box, list)
        if #list == 0 then
            box:AddLabel("(none)")
            return
        end
        for _, item in list do
            local label = item.amount
                and string.format("%s x%d ($%d)", item.inner:gsub(" Ammo", ""), item.amount, item.price or 0)
                or string.format("%s ($%d)", item.inner, item.price or 0)
            box:AddButton({ Text = label, Func = function() buyOnce(item) end })
        end
    end

    addButtons(gunsBox, buckets.Guns)
    addButtons(masksBox, buckets.Masks)
    addButtons(armorBox, buckets.Armor)
    addButtons(foodBox, buckets.Food)
    addButtons(miscBox, buckets.Misc)
    addButtons(ammoBox, buckets.Ammo)

    if #buckets.Ammo > 0 then
        local heldBox = Tabs.Buy:AddLeftGroupbox("Ammo for Held Weapon")
        heldBox:AddButton({
            Text = "Buy Ammo for Held Weapon",
            Func = function()
                local char = lp.Character
                local tool = char and char:FindFirstChildWhichIsA("Tool")
                if not tool then
                    Library:Notify("No weapon equipped", 3)
                    return
                end
                local gunName = tool.Name:match("%[([^%]]+)%]") or tool.Name
                task.spawn(function()
                    local hits = 0
                    for _, ammo in buckets.Ammo do
                        if ammo.inner:find(gunName, 1, true) then
                            if silentBuy(ammo) then hits += 1 end
                        end
                    end
                    Library:Notify(hits > 0
                        and string.format("Bought %d ammo pack(s) for %s", hits, gunName)
                        or ("No ammo found for " .. gunName), 3)
                end)
            end,
        })
    end
end

buildBuyTab()

-- ── Ragebot ──

local function randomVoidPos()
    return Vector3.new(
        math.random(-1500, 1500),
        math.random(-500, -300),
        math.random(-1500, 1500)
    )
end

-- rotating strafe angle: golden-angle step gives good coverage without repeats
local STRAFE_STEP = math.rad(137.508)
local function nextStrafeAngle()
    state.ragebot.strafeAngle = (state.ragebot.strafeAngle or math.random() * math.pi * 2) + STRAFE_STEP
    return state.ragebot.strafeAngle + (math.random() - 0.5) * 0.4
end

local function strafeOffsetAt(angle, distance)
    return Vector3.new(math.cos(angle) * distance, math.random(-1, 2), math.sin(angle) * distance)
end

local function getTargetPlayer()
    local name = Options.RagebotTarget and Options.RagebotTarget.Value
    if not name or name == "None" then return nil end
    for _, p in Players:GetPlayers() do
        if p.Name == name or p.DisplayName == name then return p end
    end
    return nil
end

local function targetAlive(p)
    if not p then return false end
    local c = p.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    -- Corpse window: Dead / SDeath flip true after the killing stomp and stay
    -- true for ~3s until respawn. Humanoid.Health can be > 0 during this window
    -- (bleedout physics), so HP alone isn't a reliable "still alive" signal.
    local be = c:FindFirstChild("BodyEffects")
    if be then
        local dead = be:FindFirstChild("Dead")
        if dead and dead.Value then return false end
        local sdeath = be:FindFirstChild("SDeath")
        if sdeath and sdeath.Value then return false end
    end
    return true
end

local function targetHRP(p)
    return p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

local function targetHead(p)
    return p and p.Character and p.Character:FindFirstChild("Head")
end

-- Local player alive + fully-loaded check. Used by ragebot to skip fire cycles
-- while dead / mid-respawn so we don't crash on destroyed parts or fire from
-- a corpse. Bounded wait: up to `frames` heartbeats for the humanoid to come
-- back alive after death; returns false if the ragebot is disabled or timeout.
local function selfAlive()
    local char = lp.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or not hrp.Parent then return false end
    if hum.Health <= 0 then return false end
    return true
end

local function waitSelfAlive(frames)
    for _ = 1, frames or 300 do
        if not state.ragebot.active then return false end
        if selfAlive() then return true end
        RunService.Heartbeat:Wait()
    end
    return selfAlive()
end

local function targetDowned(p)
    local c = p and p.Character
    if not c then return false end
    local be = c:FindFirstChild("BodyEffects")
    if not be then return false end
    -- Fully-dead corpse (post-stomp, awaiting respawn) is NOT a stomp target.
    -- Live poll 2026-09-24: Dead + SDeath flip true ~0.25s after the killing
    -- stomp; K.O. stays true through the whole corpse window, so relying on
    -- K.O. alone re-enters the stomp branch and pins us on top of the body.
    local dead = be:FindFirstChild("Dead")
    if dead and dead.Value then return false end
    local sdeath = be:FindFirstChild("SDeath")
    if sdeath and sdeath.Value then return false end
    local ko = be:FindFirstChild("K.O")
    if ko and ko.Value then return true end
    local h = c:FindFirstChildOfClass("Humanoid")
    return h and h.Health <= 0
end

local function targetProtected(p)
    local c = p and p.Character
    if not c then return false end
    -- Da Hood spawn-protection uses actual Roblox ForceField Instance(s) — the
    -- default child is named "ForceField" (Roblox default) and a "ForceField_TESTING"
    -- sibling also appears briefly. FindFirstChildOfClass covers both regardless
    -- of instance name. Verified by 10s poll on a fresh spawn 2026-09-24.
    if c:FindFirstChildOfClass("ForceField") then return true end
    -- Legacy all-caps BoolValue marker some events / admin scripts still set.
    if c:FindFirstChild("FORCEFIELD") then return true end
    return false
end

-- Predicate: should the ragebot suppress its fire cycle against this target
-- right now, based on the "Don't Shoot When" multi-select. Used both by the
-- outer loop (to hold void and preserve ammo) and by the magic-bullet hook
-- (to leave bullets alone when the user explicitly wants no shots to land).
local function shouldSkipTarget(target)
    if not target then return true end
    local skip = Options.RagebotSkip and Options.RagebotSkip.Value or {}
    if typeof(skip) == "table" then
        if skip.Invulnerable and targetProtected(target) then return true end
    end
    return false
end

local function rbHide()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or state.ragebot.hidden then return end

    state.ragebot.origCF = hrp.CFrame

    state.ragebot.camState = {
        subject = camera.CameraSubject,
        type = camera.CameraType,
    }

    local restores = {}
    for _, d in char:GetDescendants() do
        if d:IsA("BasePart") then
            restores[d] = {kind = "part", trans = d.LocalTransparencyModifier, shadow = d.CastShadow}
            d.LocalTransparencyModifier = 1
            d.CastShadow = false
        elseif d:IsA("Decal") or d:IsA("Texture") then
            restores[d] = {kind = "decal", val = d.Transparency}
            d.Transparency = 1
        elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
            restores[d] = {kind = "gui", val = d.Enabled}
            d.Enabled = false
        elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
            restores[d] = {kind = "effect", val = d.Enabled}
            d.Enabled = false
        elseif d:IsA("Light") then
            restores[d] = {kind = "light", val = d.Enabled}
            d.Enabled = false
        end
    end
    state.ragebot.restores = restores

    local bindName = "pengooin_Rage_" .. tostring(tick())
    state.ragebot.renderBind = bindName
    RunService:BindToRenderStep(bindName, 3000, function()
        for d, r in restores do
            if d.Parent then
                if r.kind == "part" then
                    d.LocalTransparencyModifier = 1
                    d.CastShadow = false
                elseif r.kind == "decal" then d.Transparency = 1
                elseif r.kind == "gui" then d.Enabled = false
                elseif r.kind == "effect" then d.Enabled = false
                elseif r.kind == "light" then d.Enabled = false
                end
            end
        end
    end)

    state.ragebot.hidden = true
end

local function rbShow()
    if not state.ragebot.hidden then return end
    if state.ragebot.renderBind then
        pcall(function() RunService:UnbindFromRenderStep(state.ragebot.renderBind) end)
        state.ragebot.renderBind = nil
    end
    if state.ragebot.restores then
        for d, r in state.ragebot.restores do
            if d.Parent then
                if r.kind == "part" then
                    d.LocalTransparencyModifier = r.trans
                    d.CastShadow = r.shadow
                elseif r.kind == "decal" then d.Transparency = r.val
                elseif r.kind == "gui" then d.Enabled = r.val
                elseif r.kind == "effect" then d.Enabled = r.val
                elseif r.kind == "light" then d.Enabled = r.val
                end
            end
        end
        state.ragebot.restores = nil
    end
    if state.ragebot.camState then
        camera.CameraSubject = state.ragebot.camState.subject
        camera.CameraType = state.ragebot.camState.type
        state.ragebot.camState = nil
    end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and state.ragebot.origCF then hrp.CFrame = state.ragebot.origCF end
    state.ragebot.origCF = nil
    state.ragebot.hidden = false
end

local function rbTeleport(pos)
    local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.CFrame = CFrame.new(pos)
end

local function rbParkVoid()
    local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.CFrame = CFrame.new(randomVoidPos())
    hrp.AssemblyLinearVelocity = Vector3.zero
end

local function rbHoldVoid(frames)
    for i = 1, frames do
        if not state.ragebot.active then break end
        -- Re-fetch HRP every frame — if we die mid-hold, the old reference
        -- points at a destroyed part and any write throws. Skip cleanly and
        -- let the outer loop / CharacterAdded handler pick up the new char.
        local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if hrp and hrp.Parent then
            if hrp.Position.Y > -250 then
                hrp.CFrame = CFrame.new(randomVoidPos())
            end
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
        RunService.Heartbeat:Wait()
    end
end

-- Collect the tools matching the ragebot Guns dropdown. Searches Backpack + Character,
-- dedupes by name, caps at 2. Returns [] when nothing valid is selected/owned.
local function collectSelectedGuns()
    local sel = Options.RagebotGuns and Options.RagebotGuns.Value or {}
    local wanted = {}
    if typeof(sel) == "table" then
        for name, on in sel do
            if on then wanted[name] = true end
        end
    end

    local char = lp.Character
    local out, seen = {}, {}
    local function scan(container)
        if not container then return end
        for _, t in container:GetChildren() do
            if t:IsA("Tool") and wanted[t.Name] and not seen[t.Name] then
                if t:FindFirstChild("Handle") and t:FindFirstChild("Ammo") then
                    seen[t.Name] = true
                    table.insert(out, t)
                    if #out >= 2 then return end
                end
            end
        end
    end
    scan(char)
    scan(lp.Backpack)
    return out
end

-- Silent multi-parent: drop every selected gun into the character at once.
-- MainModule.GunHold only checks that *some* gun is a child of the character,
-- and MainEvent:FireServer("ShootGun", handle, ...) routes by explicit handle,
-- so both guns pass server validation even though the character animator can
-- only visually grip one at a time.
local function ensureGunsEquipped(guns, char)
    for _, t in guns do
        if t.Parent ~= char then t.Parent = char end
    end
end

local function fireOneGun(tool, target, char)
    local handle = tool:FindFirstChild("Handle")
    local ammoObj = tool:FindFirstChild("Ammo")
    if not handle or not ammoObj then return end
    if ammoObj.Value <= 0 then
        MainEvent:FireServer("Reload", tool)
        return
    end

    local range = (tool:FindFirstChild("Range") and tool.Range.Value) or 200
    local remote = tool:FindFirstChild("RemoteEvent")

    if remote then remote:FireServer("Shoot") end

    local burstSize = tool:FindFirstChild("GunClientBurst") and math.min(ammoObj.Value, 3) or 1
    for i = 1, burstSize do
        if ammoObj.Value <= 0 or tool.Parent ~= char then break end
        local currentTargetHRP = targetHRP(target)
        if not currentTargetHRP then break end

        local muzzlePos
        local def = tool:FindFirstChild("Default")
        if def and def:FindFirstChild("Mesh") and def.Mesh:FindFirstChild("Muzzle") then
            muzzlePos = def.Mesh.Muzzle.WorldPosition
        else
            muzzlePos = handle.Position
        end

        local lead = currentTargetHRP.AssemblyLinearVelocity * 0.03
        local aim = currentTargetHRP.Position + lead

        local a, b, c = GunHandler.shoot({
            Shooter = char,
            Handle = handle,
            ForcedOrigin = muzzlePos,
            AimPosition = aim,
            Range = range,
            BeamColor = Color3.new(1, 0.2, 0.2),
        })
        MainEvent:FireServer("ShootGun", handle, muzzlePos, a, b, c)
        if i < burstSize then task.wait(0.04) end
    end

    if remote then remote:FireServer() end
end

local function rbStrafeShoot(target)
    if not selfAlive() then return end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local guns = collectSelectedGuns()
    if #guns == 0 then return end

    ensureGunsEquipped(guns, char)

    local tHRP = targetHRP(target)
    if not tHRP then return end

    -- rotating strafe angle around target
    local angle = nextStrafeAngle()
    local dist = 6 + math.random() * 8
    local strafePos = tHRP.Position + strafeOffsetAt(angle, dist)
    hrp.CFrame = CFrame.new(strafePos, tHRP.Position)
    hrp.AssemblyLinearVelocity = Vector3.zero

    -- physics replication is ~30Hz — 3 heartbeats (~50ms) is the minimum
    -- window before the server accepts a Shoot RPC with a matching origin.
    for _ = 1, 3 do
        if not state.ragebot.active then return end
        RunService.Heartbeat:Wait()
    end
    hrp.CFrame = CFrame.new(strafePos, tHRP.Position)
    hrp.AssemblyLinearVelocity = Vector3.zero

    for _, tool in guns do
        if not state.ragebot.active then break end
        fireOneGun(tool, target, char)
    end

    RunService.Heartbeat:Wait()
    rbParkVoid()
end

-- ragdoll can leave HRP floating at the old alive position while the visible
-- body flops elsewhere. pick the lowest major part — that's what's actually
-- on the ground and what the server hitbox for stomp checks against.
local RAGDOLL_PARTS = {"UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart"}
local function findRagdollBody(tChar)
    if not tChar then return nil end
    local best
    for _, name in RAGDOLL_PARTS do
        local p = tChar:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            if not best or p.Position.Y < best.Position.Y then
                best = p
            end
        end
    end
    return best
end

local function rbStompCycle(target)
    if not selfAlive() then return end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local tChar = target and target.Character
    if not tChar then return end

    -- Stay pinned on the body while firing Stomp every frame. Server-side
    -- stomp handler validates the shooter's HRP position AT RPC-arrival time;
    -- teleporting away in the same frame as firing gets the stomp rejected
    -- (server sees us in void, not on the corpse). Keep the pin until either:
    --   - targetDowned flips false (Dead / SDeath went true — stomp landed)
    --   - deadline hits (~2s safety cap, in case something wedges the state)
    --   - ragebot toggle turns off
    -- The updated targetDowned returns FALSE the moment Dead/SDeath flip, so
    -- this loop exits immediately after the killing stomp registers.
    local deadline = tick() + 2
    while tick() < deadline and state.ragebot.active and targetDowned(target) do
        local body = findRagdollBody(tChar)
        if not body then break end

        hrp.CFrame = CFrame.new(body.Position + Vector3.new(0, 3.2, 0))
        hrp.AssemblyLinearVelocity = Vector3.zero
        pcall(function() MainEvent:FireServer("Stomp") end)
        RunService.Heartbeat:Wait()
    end
end

local function rbUpdateSpectate()
    local target = getTargetPlayer()
    if target and target.Character then
        local hum = target.Character:FindFirstChildOfClass("Humanoid")
        if hum and camera.CameraSubject ~= hum then
            camera.CameraSubject = hum
            camera.CameraType = Enum.CameraType.Custom
        end
        return
    end
    local ownHum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if ownHum and camera.CameraSubject ~= ownHum then
        camera.CameraSubject = ownHum
        camera.CameraType = Enum.CameraType.Custom
    end
end

local function rbLoop()
    if not waitSelfAlive(600) then return end
    rbHide()
    rbUpdateSpectate()
    rbParkVoid()
    rbHoldVoid(3)

    while state.ragebot.active do
        -- Death guard: if we're dead / mid-respawn, wait for humanoid to come
        -- back before doing anything. The CharacterAdded handler rebinds the
        -- hidden state to the fresh character; we just need to not spin on
        -- a corpse or write to destroyed parts.
        if not selfAlive() then
            if not waitSelfAlive(600) then break end
        end

        rbUpdateSpectate()
        local target = getTargetPlayer()
        if not target or not target.Parent then
            rbHoldVoid(6)
            continue
        end

        if not targetAlive(target) or shouldSkipTarget(target) then
            rbHoldVoid(6)
            continue
        end

        if targetDowned(target) and Toggles.RagebotAutoStomp.Value then
            rbStompCycle(target)
            -- Stomp cycle exits pinned on the body (or wherever findRagdollBody
            -- last put us). Yank to void and idle a few frames so Dead/SDeath
            -- propagation is stable before the next iteration's targetAlive
            -- check — which will skip the corpse until respawn.
            rbParkVoid()
            rbHoldVoid(4)
            continue
        end

        rbStrafeShoot(target)

        -- rest in void between shot cycles. no spam — just sit still.
        local waitFrames = math.max(1, math.floor(Options.RagebotDelay.Value * 60))
        rbHoldVoid(waitFrames)
    end
end

local function rbStart()
    if state.ragebot.thread then return end
    state.ragebot.active = true
    state.ragebot.thread = task.spawn(function()
        -- Outer restart loop: rbLoop can crash if the local character dies
        -- mid-operation (writes to a destroyed HRP, GunHandler.shoot on a
        -- dead humanoid, etc). Re-enter automatically so death doesn't kill
        -- the ragebot — dj expects toggle to stay live across respawns.
        while state.ragebot.active do
            local ok, err = pcall(rbLoop)
            if not ok then warn("[pengooin] ragebot loop crashed, restarting:", err) end
            if not state.ragebot.active then break end
            -- clear stale hide-state so the next rbHide binds cleanly
            pcall(rbShow)
            task.wait(0.3)
        end
        pcall(rbShow)
        state.ragebot.thread = nil
    end)
end

local function rbStop()
    state.ragebot.active = false
end

-- Ragebot GUI

local rageBox = Tabs.Ragebot:AddLeftGroupbox("Target")

local function refreshTargets()
    local names = {"None"}
    for _, p in Players:GetPlayers() do
        if p ~= lp then table.insert(names, p.Name) end
    end
    if Options.RagebotTarget then
        Options.RagebotTarget:SetValues(names)
    end
end

rageBox:AddDropdown("RagebotTarget", {
    Values = {"None"},
    Default = "None",
    Text = "Target Player",
    Tooltip = "Player to hunt. List refreshes when players join/leave.",
})

rageBox:AddButton({
    Text = "Refresh Player List",
    Func = refreshTargets,
})

rageBox:AddDropdown("RagebotGuns", {
    Values = {"[Rifle]", "[AUG]"},
    Default = "[Rifle]",
    Text = "Guns to Use",
    Multi = true,
    Tooltip = "Pick 1 or 2. If 2 are selected the ragebot dual-wields — parents both into the character and fires both per shot cycle. Fists never equip.",
})

Options.RagebotGuns:OnChanged(function()
    local sel = Options.RagebotGuns.Value or {}
    local count = 0
    for _, on in sel do if on then count += 1 end end
    if count > 2 then
        Library:Notify("Ragebot: max 2 guns — extras will be ignored", 3)
    end
end)

Players.PlayerAdded:Connect(refreshTargets)
Players.PlayerRemoving:Connect(refreshTargets)
refreshTargets()

local runBox = Tabs.Ragebot:AddRightGroupbox("Behavior")

runBox:AddToggle("Ragebot", {
    Text = "Enable Ragebot",
    Default = false,
    Tooltip = "Void spam + auto-shoot selected target; stomp on downed; wait through spawn protection",
}):AddKeyPicker("RagebotKey", {
    Default = "None",
    SyncToggleState = true,
    Mode = "Toggle",
    Text = "Ragebot",
})

runBox:AddToggle("RagebotAutoStomp", {
    Text = "Auto-Stomp Downed",
    Default = true,
    Tooltip = "When target is K.O., teleport on them and stomp to finish the kill",
})

runBox:AddDropdown("RagebotSkip", {
    Values = {"Invulnerable"},
    Default = "Invulnerable",
    Text = "Don't Shoot When",
    Multi = true,
    Tooltip = "Suppress ragebot fire (preserve ammo) while any selected condition holds. Invulnerable = target has spawn-protection FORCEFIELD.",
})

runBox:AddSlider("RagebotDelay", {
    Text = "Shot Cycle Delay",
    Default = 0.15,
    Min = 0.05,
    Max = 1.0,
    Rounding = 2,
    Tooltip = "Seconds between shot bursts from void",
})

Toggles.Ragebot:OnChanged(function()
    if Toggles.Ragebot.Value then rbStart() else rbStop() end
end)

-- ── Auto Buy Armor ──

local ARMOR_MAX = {
    ["Medium Armor"] = 100,
    ["High-Medium Armor"] = 100,
    ["Fire Armor"] = 200,
    ["AntiBodies"] = 100,
}
local ARMOR_FIELD = {
    ["Medium Armor"] = "Armor",
    ["High-Medium Armor"] = "Armor",
    ["Fire Armor"] = "FireArmor",
    ["AntiBodies"] = "Armor",
}

-- Find the cheapest live shop pad whose bracketed name matches the selected
-- armor type. Returns an item table shaped like the ones parseItem produces,
-- so we can hand it straight to silentBuy via dispatchBuy.
local function findArmorPad(armorType)
    local shopFolder = workspace:FindFirstChild("Ignored") and workspace.Ignored:FindFirstChild("Shop")
    if not shopFolder then return nil end
    local best
    for _, m in shopFolder:GetChildren() do
        local inner = m.Name:match("%[([^%]]+)%]")
        if inner == armorType then
            local cd = m:FindFirstChildOfClass("ClickDetector")
            local price = tonumber(m.Name:match("%$(%d+)"))
            if cd and price and (not best or price < best.price) then
                if m.PrimaryPart or m:FindFirstChild("Head") then
                    best = {model = m, cd = cd, price = price, inner = armorType, amount = nil}
                end
            end
        end
    end
    return best
end

local function armorPercent(armorType)
    local field = ARMOR_FIELD[armorType]
    local maxV = ARMOR_MAX[armorType]
    if not field or not maxV then return 100 end
    local char = lp.Character
    local be = char and char:FindFirstChild("BodyEffects")
    if not be then return 100 end
    local val = be:FindFirstChild(field)
    if not val or not val:IsA("ValueBase") then return 100 end
    return (val.Value / maxV) * 100
end

local function stopAutoArmor()
    state.autoArmor.active = false
    local t = state.autoArmor.thread
    state.autoArmor.thread = nil
    if t then pcall(task.cancel, t) end
end

local function startAutoArmor()
    stopAutoArmor()
    state.autoArmor.active = true
    state.autoArmor.thread = task.spawn(function()
        while state.autoArmor.active do
            local ok, err = pcall(function()
                if not selfAlive() then return end
                local armorType = Options.AutoArmorType.Value
                if not armorType or armorType == "" or armorType == "None" then return end
                local threshold = Options.AutoArmorThreshold.Value or 20
                if armorPercent(armorType) >= threshold then return end
                local pad = findArmorPad(armorType)
                if not pad then return end
                dispatchBuy(pad)
            end)
            if not ok then warn("[pengooin] auto-armor:", err) end
            -- Poll cadence: check every 1.5s. silentBuy itself takes ~1s so
            -- effective re-buy rate is ~2-3s. Don't hammer faster than that.
            for _ = 1, 90 do
                if not state.autoArmor.active then break end
                RunService.Heartbeat:Wait()
            end
        end
    end)
end

local autoBox = Tabs.Ragebot:AddRightGroupbox("Auto Buy")

autoBox:AddToggle("AutoBuyArmor", {
    Text = "Auto Buy Armor",
    Default = false,
    Tooltip = "When armor falls below the threshold, silently teleport to the cheapest matching shop pad and buy fresh armor.",
})

autoBox:AddDropdown("AutoArmorType", {
    Values = {"Medium Armor", "High-Medium Armor", "Fire Armor", "AntiBodies"},
    Default = "Medium Armor",
    Text = "Armor Type",
    Tooltip = "Which armor pad to buy from. Fire Armor uses BodyEffects.FireArmor (max 200); the rest use BodyEffects.Armor (max 100).",
})

autoBox:AddSlider("AutoArmorThreshold", {
    Text = "Restock Below %",
    Default = 20,
    Min = 0,
    Max = 90,
    Rounding = 0,
    Suffix = "%",
    Tooltip = "Trigger a buy when armor drops under this percent of max.",
})

Toggles.AutoBuyArmor:OnChanged(function()
    if Toggles.AutoBuyArmor.Value then startAutoArmor() else stopAutoArmor() end
end)

-- ── Combat Tab ────────────────────────────────────────────────────────────
-- Silent aim / aimbot / triggerbot / bullet manipulation / magic bullet.
-- Client-side targeting only (part resolvers, closest-to-mouse selection,
-- FOV circle). All server-facing overrides happen in the shared GunHandler
-- .shoot hook below — one code path so ragebot and silent-aim stack cleanly.

local PART_CHOICES = {
    "Head", "UpperTorso", "HumanoidRootPart", "LowerTorso",
    "Random Part", "Closest to Mouse",
}

local RANDOM_PARTS = {
    "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
    "RightUpperArm", "LeftUpperArm", "RightHand", "LeftHand",
    "RightUpperLeg", "LeftUpperLeg", "RightFoot", "LeftFoot",
}

local function firstExisting(char, names)
    for _, n in names do
        local p = char:FindFirstChild(n)
        if p and p:IsA("BasePart") then return p end
    end
    return nil
end

local function partScreenDist(part, mx, my)
    if not part or not part:IsA("BasePart") then return math.huge end
    local sp, on = camera:WorldToScreenPoint(part.Position)
    if not on or sp.Z <= 0 then return math.huge end
    local dx, dy = sp.X - mx, sp.Y - my
    return math.sqrt(dx * dx + dy * dy)
end

local function resolvePart(char, choice)
    if not char then return nil end
    if choice == "Head" then
        return char:FindFirstChild("Head")
    elseif choice == "UpperTorso" then
        return firstExisting(char, {"UpperTorso", "Torso"})
    elseif choice == "HumanoidRootPart" then
        return char:FindFirstChild("HumanoidRootPart")
    elseif choice == "LowerTorso" then
        return firstExisting(char, {"LowerTorso", "HumanoidRootPart", "UpperTorso"})
    elseif choice == "Random Part" then
        for _ = 1, 5 do
            local n = RANDOM_PARTS[math.random(1, #RANDOM_PARTS)]
            local p = char:FindFirstChild(n)
            if p and p:IsA("BasePart") then return p end
        end
        return char:FindFirstChild("HumanoidRootPart")
    elseif choice == "Closest to Mouse" then
        local m = lp:GetMouse()
        local best, bestD = nil, math.huge
        for _, p in char:GetChildren() do
            if p:IsA("BasePart") then
                local d = partScreenDist(p, m.X, m.Y)
                if d < bestD then best, bestD = p, d end
            end
        end
        return best or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild("HumanoidRootPart")
end

local function isValidEnemy(p)
    if not p or p == lp then return false end
    local c = p.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then return false end
    if targetProtected(p) then return false end
    if targetDowned(p) then return false end
    -- Also gate on the same Dead/SDeath signal used elsewhere so corpses
    -- never get counted as valid enemies.
    local be = c:FindFirstChild("BodyEffects")
    if be then
        local dead = be:FindFirstChild("Dead")
        if dead and dead.Value then return false end
        local sdeath = be:FindFirstChild("SDeath")
        if sdeath and sdeath.Value then return false end
    end
    return true
end

-- Find the enemy whose Head (or HRP fallback) is closest to the mouse cursor
-- in screen space. When useFOV is true, exclude anyone whose screen distance
-- exceeds fovRadius pixels. Shared by silent aim, aimbot, and triggerbot FOV.
local function pickClosestEnemy(useFOV, fovRadius)
    local m = lp:GetMouse()
    local mx, my = m.X, m.Y
    local best, bestD = nil, math.huge
    for _, p in Players:GetPlayers() do
        if isValidEnemy(p) then
            local head = p.Character:FindFirstChild("Head") or p.Character:FindFirstChild("HumanoidRootPart")
            if head then
                local sp, on = camera:WorldToScreenPoint(head.Position)
                if on and sp.Z > 0 then
                    local dx, dy = sp.X - mx, sp.Y - my
                    local d = math.sqrt(dx * dx + dy * dy)
                    if (not useFOV or d <= fovRadius) and d < bestD then
                        best, bestD = p, d
                    end
                end
            end
        end
    end
    return best
end

-- Combat UI ───────────────────────────────────────────────────────────────

local silentBox = Tabs.Combat:AddLeftGroupbox("Silent Aim")

silentBox:AddToggle("SilentAim", {
    Text = "Silent Aim",
    Default = false,
    Tooltip = "Rewrites the aim vector inside GunHandler.shoot to the chosen part on the closest enemy before the ShootGun RPC leaves. Server sees a legitimate aim toward the target.",
}):AddKeyPicker("SilentAimKey", {
    Default = "None",
    SyncToggleState = true,
    Mode = "Toggle",
    Text = "Silent Aim",
})

silentBox:AddDropdown("SilentAimPart", {
    Values = PART_CHOICES,
    Default = "Head",
    Text = "Target Part",
    Tooltip = "Head = max damage. Random Part varies per shot. Closest to Mouse picks whichever limb sits nearest the cursor for each individual shot.",
})

silentBox:AddToggle("SilentAimUseFOV", {
    Text = "Use FOV",
    Default = false,
    Tooltip = "Only redirect bullets when the closest enemy is within the FOV radius. Off = every shot locks on regardless of aim direction.",
})

local aimboxBox = Tabs.Combat:AddRightGroupbox("Aimbot")

aimboxBox:AddToggle("Aimbot", {
    Text = "Aimbot",
    Default = false,
    Tooltip = "Rotate the camera to look at the closest enemy's chosen part while the aim key is held.",
}):AddKeyPicker("AimbotKey", {
    Default = "MB2",
    SyncToggleState = false,
    Mode = "Hold",
    Text = "Aimbot",
})

aimboxBox:AddDropdown("AimbotPart", {
    Values = PART_CHOICES,
    Default = "Head",
    Text = "Target Part",
})

aimboxBox:AddSlider("AimbotSmoothness", {
    Text = "Smoothness",
    Default = 8,
    Min = 1,
    Max = 20,
    Rounding = 0,
    Tooltip = "Higher = snappier. 1 = slow drag, 20 = near-instant snap.",
})

aimboxBox:AddToggle("AimbotUseFOV", {
    Text = "Use FOV",
    Default = true,
    Tooltip = "Only lock the camera onto enemies within the FOV radius.",
})

local triggerBox = Tabs.Combat:AddLeftGroupbox("Triggerbot")

triggerBox:AddToggle("Triggerbot", {
    Text = "Triggerbot",
    Default = false,
    Tooltip = "Auto-fire the currently held gun the moment the mouse cursor lands on an enemy character.",
}):AddKeyPicker("TriggerbotKey", {
    Default = "None",
    SyncToggleState = true,
    Mode = "Toggle",
    Text = "Triggerbot",
})

triggerBox:AddSlider("TriggerActivationDelay", {
    Text = "Activation Delay",
    Default = 40,
    Min = 0,
    Max = 500,
    Rounding = 0,
    Suffix = " ms",
    Tooltip = "How long the mouse must be over an enemy before firing. Higher = more human-looking.",
})

triggerBox:AddSlider("TriggerCooldown", {
    Text = "Fire Cooldown",
    Default = 120,
    Min = 50,
    Max = 1000,
    Rounding = 0,
    Suffix = " ms",
    Tooltip = "Minimum time between consecutive triggerbot shots.",
})

triggerBox:AddToggle("TriggerUseFOV", {
    Text = "Use FOV",
    Default = false,
    Tooltip = "Also require the target to be within the FOV radius, on top of the mouse-over check.",
})

local fovBox = Tabs.Combat:AddLeftGroupbox("FOV Circle")

fovBox:AddToggle("ShowFOV", {
    Text = "Draw FOV",
    Default = false,
    Tooltip = "Render a circle around the cursor at the FOV radius so you can see exactly what silent aim / aimbot will consider.",
})

fovBox:AddSlider("FOVSize", {
    Text = "FOV Radius",
    Default = 120,
    Min = 10,
    Max = 500,
    Rounding = 0,
    Suffix = " px",
})

fovBox:AddLabel("FOV Color"):AddColorPicker("FOVColor", {
    Default = Color3.fromRGB(255, 100, 100),
    Title = "FOV Color",
})

-- FOV visualization ───────────────────────────────────────────────────────

local function destroyFOV()
    if state.combat.fov.conn then state.combat.fov.conn:Disconnect(); state.combat.fov.conn = nil end
    if state.combat.fov.sgui then state.combat.fov.sgui:Destroy(); state.combat.fov.sgui = nil end
    state.combat.fov.ring = nil
    state.combat.fov.stroke = nil
end

local function buildFOV()
    destroyFOV()
    local sgui = Instance.new("ScreenGui")
    sgui.Name = "pengooin_FOV"
    sgui.IgnoreGuiInset = true
    sgui.ResetOnSpawn = false
    sgui.DisplayOrder = 90
    sgui.Parent = lp:FindFirstChildOfClass("PlayerGui")
    state.combat.fov.sgui = sgui

    local ring = Instance.new("Frame")
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.BackgroundTransparency = 1
    ring.BorderSizePixel = 0
    ring.Size = UDim2.fromOffset(240, 240)
    ring.Parent = sgui

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Color = Options.FOVColor.Value
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = ring

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = ring

    state.combat.fov.ring = ring
    state.combat.fov.stroke = stroke

    state.combat.fov.conn = RunService.RenderStepped:Connect(function()
        if not Toggles.ShowFOV.Value then
            ring.Visible = false
            return
        end
        local m = lp:GetMouse()
        local r = Options.FOVSize.Value
        ring.Size = UDim2.fromOffset(r * 2, r * 2)
        ring.Position = UDim2.fromOffset(m.X, m.Y + 36)
        ring.Visible = true
        stroke.Color = Options.FOVColor.Value
    end)
end

Toggles.ShowFOV:OnChanged(function()
    if Toggles.ShowFOV.Value then buildFOV() else destroyFOV() end
end)

-- Aimbot ──────────────────────────────────────────────────────────────────

local function stopAimbot()
    if state.combat.aimbot.conn then state.combat.aimbot.conn:Disconnect(); state.combat.aimbot.conn = nil end
end

local function startAimbot()
    stopAimbot()
    state.combat.aimbot.conn = RunService.RenderStepped:Connect(function(dt)
        if not Toggles.Aimbot.Value then return end
        -- Require the aim key to be held (KeyPicker in Hold mode). If no key is
        -- bound, treat as always-on.
        local kp = Options.AimbotKey
        local keyBound = kp and kp.Value and kp.Value ~= "None"
        if keyBound and not kp:GetState() then return end

        local useFOV = Toggles.AimbotUseFOV.Value
        local fov = Options.FOVSize.Value
        local target = pickClosestEnemy(useFOV, fov)
        if not target then return end

        local part = resolvePart(target.Character, Options.AimbotPart.Value)
        if not part then return end

        local smooth = Options.AimbotSmoothness.Value / 20
        local aimAt = part.Position + part.AssemblyLinearVelocity * 0.03
        local goal = CFrame.new(camera.CFrame.Position, aimAt)
        camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(smooth * dt * 60, 0, 1))
    end)
end

Toggles.Aimbot:OnChanged(function()
    if Toggles.Aimbot.Value then startAimbot() else stopAimbot() end
end)

-- Triggerbot ──────────────────────────────────────────────────────────────

-- Fire the currently held gun once. Uses the same shoot pipeline as manual
-- fire so the shared GunHandler.shoot hook (silent aim / bullet manip) still
-- applies. Reads gun state directly instead of firing tool.Activated because
-- rapid-fire may have disabled the Activated listener.
local function fireOneShot()
    local char = lp.Character
    if not char then return end
    local tool = char:FindFirstChildWhichIsA("Tool")
    if not tool then return end
    if not tool:FindFirstChild("Handle") or not tool:FindFirstChild("Ammo") then return end
    if tool.Ammo.Value <= 0 then
        MainEvent:FireServer("Reload", tool)
        return
    end
    if tool:GetAttribute("Cooldown") then return end

    local origin, handle = getMuzzle(tool)
    if not origin or not handle then return end
    local range = (tool:FindFirstChild("Range") and tool.Range.Value) or 200
    local remote = tool:FindFirstChild("RemoteEvent")

    if remote then remote:FireServer("Shoot") end
    local dir = GunHandler.getAim(origin, range)
    local aim = origin + dir * range
    local a, b, c = GunHandler.shoot({
        Shooter = char,
        Handle = handle,
        ForcedOrigin = origin,
        AimPosition = aim,
        Range = range,
        BeamColor = Color3.new(1, 0.545098, 0.14902),
    })
    MainEvent:FireServer("ShootGun", handle, origin, a, b, c)
    if remote then remote:FireServer() end
end

local function stopTriggerbot()
    if state.combat.triggerbot.conn then state.combat.triggerbot.conn:Disconnect(); state.combat.triggerbot.conn = nil end
end

local function startTriggerbot()
    stopTriggerbot()
    local seenAt = 0
    state.combat.triggerbot.conn = RunService.Heartbeat:Connect(function()
        if not Toggles.Triggerbot.Value then seenAt = 0; return end

        local m = lp:GetMouse()
        local hit = m.Target
        if not hit then seenAt = 0; return end
        local model = hit:FindFirstAncestorOfClass("Model")
        local target = model and Players:GetPlayerFromCharacter(model)
        if not target or not isValidEnemy(target) then seenAt = 0; return end

        if Toggles.TriggerUseFOV.Value then
            local head = target.Character:FindFirstChild("Head")
            if head then
                local sp, on = camera:WorldToScreenPoint(head.Position)
                if not on or sp.Z <= 0 then seenAt = 0; return end
                local dx, dy = sp.X - m.X, sp.Y - m.Y
                if math.sqrt(dx * dx + dy * dy) > Options.FOVSize.Value then
                    seenAt = 0; return
                end
            end
        end

        local now = tick()
        if seenAt == 0 then seenAt = now; return end
        local delay = (Options.TriggerActivationDelay.Value or 0) / 1000
        local cooldown = (Options.TriggerCooldown.Value or 120) / 1000
        if now - seenAt < delay then return end
        if now - state.combat.triggerbot.lastFireAt < cooldown then return end

        state.combat.triggerbot.lastFireAt = now
        fireOneShot()
    end)
end

Toggles.Triggerbot:OnChanged(function()
    if Toggles.Triggerbot.Value then startTriggerbot() else stopTriggerbot() end
end)

-- Magic bullet hook: intercept GunHandler.shoot once. When a target is
-- selected, force AimPosition/Hit/Normal to the target's Head so the payload
-- sent to MainEvent("ShootGun") reports a head hit — regardless of walls,
-- angle, or where the mouse is aimed.
--
-- GunHandler.shoot returns (AimPosition, HitInstance, HitNormal) which the
-- caller forwards to MainEvent:FireServer("ShootGun", handle, origin, ...).
-- If args.Hit is populated, GunHandler.shoot skips its wall raycast and
-- returns those values verbatim — meaning the server-side hit registration
-- sees Head as the struck part every time.
-- Version sentinel so live-diagnostic probes can confirm this exact revision
-- of the hook is installed (bump the string on every semantic change to the
-- shoot hook, ragebot gating logic, or magic-bullet payload).
_G.pengooin_HookVersion = "2026-09-24-no-wall-bypass-manual"

-- Shared shoot hook. Two independent aim-override paths:
--   1. Ragebot (highest priority when its toggle is on) — always magic-bullets
--      the selected target's Head. Same behavior as before the combat tab.
--   2. Combat tab Silent Aim — closest-to-cursor enemy pick, configurable part,
--      optional FOV gate, optional Bullet Manipulation (wall bypass via Hit /
--      Normal override), optional Magic Bullet (force Head as reported hit).
-- Only one path runs per shot; ragebot wins when both are enabled.
do
    local origShoot = GunHandler.shoot
    GunHandler.shoot = function(args)
        if args and typeof(args) == "table" then
            local ragebotOn = Toggles.Ragebot and Toggles.Ragebot.Value

            if ragebotOn then
                local t = getTargetPlayer()
                if t and targetAlive(t) and not targetDowned(t) and not shouldSkipTarget(t) then
                    local head = targetHead(t)
                    if head then
                        local lead = head.AssemblyLinearVelocity * 0.03
                        local aim = head.Position + lead
                        args.AimPosition = aim
                        args.Hit = head
                        args.Normal = (args.ForcedOrigin and (args.ForcedOrigin - aim).Magnitude > 0)
                            and (args.ForcedOrigin - aim).Unit
                            or Vector3.new(0, 1, 0)
                        if args.ForcedOrigin and args.Range then
                            local dist = (aim - args.ForcedOrigin).Magnitude
                            if dist > args.Range then args.Range = dist + 25 end
                        end
                    end
                end
            elseif Toggles.SilentAim and Toggles.SilentAim.Value then
                -- Combat-tab Silent Aim: override AimPosition ONLY. Do NOT set
                -- args.Hit / args.Normal — that path triggered a permaban when
                -- combined with rapidfire (server-side detected headshots
                -- through walls at unnatural angles). Leaving the raycast to
                -- run naturally means bullets only land when line of sight
                -- exists, which matches human aim well enough.
                local useFOV = Toggles.SilentAimUseFOV and Toggles.SilentAimUseFOV.Value
                local fov = Options.FOVSize and Options.FOVSize.Value or 120
                local t = pickClosestEnemy(useFOV, fov)
                if t then
                    local part = resolvePart(t.Character, Options.SilentAimPart.Value)
                    if part then
                        local aim = part.Position + part.AssemblyLinearVelocity * 0.03
                        args.AimPosition = aim
                        if args.ForcedOrigin and args.Range then
                            local dist = (aim - args.ForcedOrigin).Magnitude
                            if dist > args.Range then args.Range = dist + 25 end
                        end
                    end
                end
            end
        end
        return origShoot(args)
    end
end

-- Server Position Indicator

local visBox = Tabs.Ragebot:AddLeftGroupbox("Server Position Indicator")

visBox:AddToggle("Indicator", {
    Text = "Show Server Position",
    Default = false,
    Tooltip = "White circle billboard attached to your character so you can see where the server sees you",
})

visBox:AddLabel("Indicator Color"):AddColorPicker("IndicatorColor", {
    Default = Color3.new(1, 1, 1),
    Title = "Indicator Color",
})

local vis = {
    sgui = nil, dot = nil, conn = nil, charConn = nil, dead = false,
}

local function destroyIndicator()
    if vis.conn then vis.conn:Disconnect(); vis.conn = nil end
    if vis.sgui then vis.sgui:Destroy(); vis.sgui = nil end
    vis.dot = nil

    local pg = lp:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, g in pg:GetChildren() do
            if g.Name == "pengooin_Indicator" then g:Destroy() end
        end
    end
end

local function buildIndicator()
    destroyIndicator()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local color = Options.IndicatorColor.Value

    if Toggles.Indicator.Value then
        local sgui = Instance.new("ScreenGui")
        sgui.Name = "pengooin_Indicator"
        sgui.IgnoreGuiInset = false
        sgui.ResetOnSpawn = false
        sgui.DisplayOrder = 100
        sgui.Parent = lp:FindFirstChildOfClass("PlayerGui")
        vis.sgui = sgui

        local dot = Instance.new("Frame")
        dot.Size = UDim2.fromOffset(16, 16)
        dot.BackgroundColor3 = color
        dot.BorderSizePixel = 0
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.Parent = sgui
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(1, 0)
        c.Parent = dot
        vis.dot = dot

        vis.conn = RunService.RenderStepped:Connect(function()
            local c = lp.Character
            local hd = c and c:FindFirstChild("Head")
            if hd then
                local sp, onScreen = camera:WorldToScreenPoint(hd.Position)
                if onScreen and sp.Z > 0 then
                    vis.dot.Position = UDim2.fromOffset(sp.X, sp.Y)
                    vis.dot.Visible = true
                else
                    vis.dot.Visible = false
                end
            else
                vis.dot.Visible = false
            end
        end)
    end
end

local function refreshIndicator()
    if vis.dead then return end
    buildIndicator()
end

Toggles.Indicator:OnChanged(refreshIndicator)
Options.IndicatorColor:OnChanged(refreshIndicator)

vis.charConn = lp.CharacterAdded:Connect(function()
    task.wait(0.5)
    if vis.dead then return end
    if Toggles.Indicator.Value then
        refreshIndicator()
    end
end)

lp.CharacterAdded:Connect(function(newChar)
    if not state.ragebot.active then return end
    -- rbShow tears down the leaked renderStep bind and stale restores map
    -- that reference the destroyed old character. Without this, every death
    -- adds a new bind on top of the old — visible as either a stuck-visible
    -- character or a duplicate hide fighting itself.
    pcall(rbShow)
    newChar:WaitForChild("HumanoidRootPart", 5)
    task.wait(0.3)
    if state.ragebot.active then pcall(rbHide) end
end)

-- ── Toggle Logic ──

local function trackChar(char)
    table.insert(state.conns, char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and state.firing then
            task.wait(0.3)
            if state.firing then
                disableOriginal(child)
                state.currentTool = child
            end
        end
    end))

    table.insert(state.conns, char.ChildRemoved:Connect(function(child)
        if child == state.currentTool then
            enableOriginal()
            state.currentTool = nil
        end
    end))
end

Toggles.RapidFire:OnChanged(function()
    if Toggles.RapidFire.Value then
        state.firing = true

        table.insert(state.conns, UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                state.mouseDown = true
                spawnLoop()
            end
        end))

        table.insert(state.conns, UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                state.mouseDown = false
            end
        end))

        table.insert(state.conns, lp.CharacterAdded:Connect(function(char)
            enableOriginal()
            state.currentTool = nil
            trackChar(char)
        end))

        if lp.Character then
            trackChar(lp.Character)
        end

        local tool = getGun()
        if tool then
            disableOriginal(tool)
            state.currentTool = tool
        end

        if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            state.mouseDown = true
            spawnLoop()
        end
    else
        cleanup()
    end
end)

Toggles.Fly:OnChanged(function()
    if Toggles.Fly.Value then startFly() else stopFly() end
end)

Toggles.WalkSpeed:OnChanged(function()
    if Toggles.WalkSpeed.Value then startSpeed() else stopSpeed() end
end)


lp.CharacterAdded:Connect(function(char)
    char:WaitForChild("HumanoidRootPart", 5)
    task.wait(0.2)
    if Toggles.Fly and Toggles.Fly.Value then startFly() end
    if Toggles.WalkSpeed and Toggles.WalkSpeed.Value then startSpeed() end
end)

-- ── Settings ──

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("pengooin")
SaveManager:SetFolder("pengooin/dahood")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)

local function hardCleanup()
    vis.dead = true                                       -- gate any late refresh
    if vis.charConn then vis.charConn:Disconnect(); vis.charConn = nil end
    pcall(cleanup)
    pcall(stopFly)
    pcall(stopSpeed)
    pcall(rbStop)
    pcall(rbShow)
    pcall(stopAutoArmor)
    pcall(stopAimbot)
    pcall(stopTriggerbot)
    pcall(destroyFOV)
    pcall(destroyIndicator)
    -- second sweep on next frame to catch anything a Toggle:OnChanged
    -- callback rebuilt during Unload's teardown.
    task.defer(function()
        pcall(destroyIndicator)
    end)
end

Tabs.Settings:AddLeftGroupbox("Menu"):AddButton({
    Text = "Unload",
    Func = function()
        hardCleanup()
        pcall(function() Library:Unload() end)
        hardCleanup()                                     -- again, after Unload tears down GUI
    end,
})

Library:OnUnloaded(hardCleanup)
