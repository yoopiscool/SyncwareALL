-- Blox Fruits: box ESP + silent aim (upper torso) + UI + hold-to-aim key (keyboard, mouse, side buttons). Single file.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer
local mouse = lp:GetMouse()

-- re-run safety: tear down the previous session
local env = (getgenv and getgenv()) or _G
if env.SyncwareUnload then pcall(env.SyncwareUnload) end
local session = {}
env.SyncwareSession = session
local conns, drawings = {}, {}

local function on(signal, fn)
    local c = signal:Connect(fn)
    conns[#conns + 1] = c
    return c
end

local CFG = {
    -- ESP
    esp = true,
    outline = Color3.fromRGB(255, 255, 255),
    fill = Color3.fromRGB(128, 128, 128),
    fillOpacity = 0.35,
    thickness = 1,
    names = true,          -- player name above each box (follows the ESP color)
    espDistance = 5000,

    -- Silent aim
    aim = true,
    holdToAim = true,      -- true = only aim while the key is held
    aimKey = "E",          -- KeyCode name, MouseButton1/2/3, XButton1 (side back), XButton2 (side forward)
    aimMode = "nearest",   -- "nearest" or "cursor"
    soloLock = true,
    aimDistance = 2000,
    fov = 150,
    showFov = false,
    fovColor = Color3.fromRGB(255, 255, 255),
    fovThickness = 1,

    teamCheck = false,

    -- Fly
    fly = false,
    flySpeed = 60,
    flyKey = "F",          -- press to toggle fly (KeyCode name or MouseButton1/2/3)
    noclip = false,        -- walk through walls and parts
    gun = false,           -- gun aura: multi-target ShootGunEvent bursts while a Gun tool is held
    gunRange = 1000,       -- studs
    gunBurst = 12,         -- shots per Heartbeat, split across targets
    gunCacheShots = 10,    -- shots sent per validator code before generating the next one
    gunMaxTargets = 10,    -- nearest N targets per burst (spread mode)
    gunMode = "spread",    -- "spread" = shots split across targets; "single" = whole burst on one target until it dies, then the next
    npcCheck = false,      -- on = ESP, silent aim, Khel Khatam and Gun ignore NPCs (players only)
    autoV3 = false,        -- keeps firing the race ability (V3) every autoV3Interval seconds
    autoV3Interval = 3,
    autoV4 = false,        -- presses Y for V4 whenever the gauge is full and V4 is not already on
    antiStun = false,      -- zeroes the character's Stun value every frame
    orbit = false,         -- circle the selected player (pick one in the SuS tab)
    orbitSpeed = 3,        -- radians per second
    orbitRadius = 12,      -- studs from the target
    orbitTweenSpeed = 250, -- studs per second while flying in to the target before orbiting
    orbitHeight = 0,       -- studs above the target's root
    khelKhatam = false,    -- kill aura: hits every living player/NPC in range via RegisterAttack/RegisterHit
    stick = false,         -- tween to the selected player and stay glued to them (pick one in the SuS tab)
    stickSpeed = 250,      -- studs per second while flying in
    stickDistance = 3,     -- studs behind the target (0 = on top of them)
    safeMode = false,      -- when HP% drops below safeHP, tween up to the sky and hold until HP recovers
    safeHP = 35,           -- HP percent threshold
    safeRecover = 2000,    -- HP that must be regained above the threshold before coming back down
    safeHeight = 3000,     -- studs above where you were
    safeSpeed = 600,       -- studs per second, up and back down
    auraRange = 100,       -- studs; widen with the slider if hits still land

    -- Performance
    fpsBoost = false,
    fpsSuper = false,      -- implies fpsBoost; also drops mesh detail, accessories, lights, grass, ESP fill
    fpsUnlock = false,
}

------------------------------------------------------------------
-- Shared state
------------------------------------------------------------------
local hasDrawing = pcall(function() Drawing.new("Square"):Remove() end)
local boxes = {}
local target = nil
local holding = false
local binding = false
local bindRefresh = nil

-- mouse side buttons: Roblox doesn't expose them, so poll the executor
local XBUTTONS = {XButton1 = 0x05, XButton2 = 0x06}
local keyPoll
for _, name in ipairs({"iskeypressed", "iskeydown", "isKeyPressed", "isKeyDown", "is_key_pressed", "is_key_down"}) do
    local f = (getgenv and getgenv()[name]) or rawget(_G, name)
    if type(f) == "function" then keyPoll = f break end
end
if not keyPoll then
    local f = (getgenv and getgenv().GetAsyncKeyState) or rawget(_G, "GetAsyncKeyState")
    if type(f) == "function" then
        keyPoll = function(code) local r = f(code) return r == true or (type(r) == "number" and r ~= 0) end
    end
end
local canPoll = keyPoll ~= nil

local function xDown(name)
    if not canPoll then return false end
    if type(isrbxactive) == "function" then
        local okA, active = pcall(isrbxactive)
        if okA and not active then return false end
    end
    local ok, r = pcall(keyPoll, XBUTTONS[name])
    return ok and r == true
end

local function draw(class)
    local d = Drawing.new(class)
    drawings[#drawings + 1] = d
    return d
end

local fovCircle
if hasDrawing then
    fovCircle = draw("Circle")
    fovCircle.NumSides = 64
    fovCircle.Filled = false
    fovCircle.Transparency = 1
    fovCircle.Visible = false
end

local function newBox()
    local fill = draw("Square")
    fill.Filled = true
    fill.Color = CFG.fill
    fill.Transparency = CFG.fillOpacity
    fill.Visible = false

    local outline = draw("Square")
    outline.Filled = false
    outline.Color = CFG.outline
    outline.Thickness = CFG.thickness
    outline.Transparency = 1
    outline.Visible = false

    local name = draw("Text")
    name.Center = true
    name.Outline = true
    name.Size = 13
    name.Color = CFG.outline
    name.Transparency = 1
    name.Text = ""
    name.Visible = false

    return {outline = outline, fill = fill, name = name}
end

local function hide(b)
    if b then
        b.outline.Visible = false
        b.fill.Visible = false
        b.name.Visible = false
    end
end

local function addPlayer(p)
    if p ~= lp and hasDrawing and not boxes[p] then boxes[p] = newBox() end
end

local function removePlayer(p)
    local b = boxes[p]
    if b then
        pcall(function() b.outline:Remove() end)
        pcall(function() b.fill:Remove() end)
        pcall(function() b.name:Remove() end)
        boxes[p] = nil
    end
end

for _, p in ipairs(Players:GetPlayers()) do addPlayer(p) end
on(Players.PlayerAdded, addPlayer)
on(Players.PlayerRemoving, removePlayer)

local function aimPartOf(char)
    return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
end

local function isTeammate(plr)
    return CFG.teamCheck and plr.Team ~= nil and plr.Team == lp.Team
end

------------------------------------------------------------------
-- Main loop: side-button polling, ESP, target selection
------------------------------------------------------------------
on(RunService.RenderStepped, function()
    -- side buttons: capture while binding, otherwise drive "holding"
    if binding then
        if canPoll then
            for name in pairs(XBUTTONS) do
                if xDown(name) then
                    CFG.aimKey = name
                    binding = false
                    holding = false
                    if bindRefresh then bindRefresh() end
                    break
                end
            end
        end
    elseif XBUTTONS[CFG.aimKey] then
        holding = xDown(CFG.aimKey)
    end

    local cam = workspace.CurrentCamera
    if not cam then return end
    local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local mousePos = UIS:GetMouseLocation()
    local players = Players:GetPlayers()

    local solo = CFG.soloLock and #players == 2
    local nearestMode = solo or CFG.aimMode == "nearest"
    local aimLive = CFG.aim and (not CFG.holdToAim or holding)

    if fovCircle then
        fovCircle.Position = mousePos
        fovCircle.Radius = CFG.fov
        fovCircle.Color = CFG.fovColor
        fovCircle.Thickness = CFG.fovThickness
        fovCircle.Visible = aimLive and CFG.showFov and not nearestMode
    end

    local best, bestScore = nil, math.huge

    for _, plr in ipairs(players) do
        if plr ~= lp then
            local b = boxes[plr]
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local alive = myRoot and root and hum and hum.Health > 0 and not isTeammate(plr)
                and not (CFG.npcCheck and Players:GetPlayerFromCharacter(char) ~= plr)

            if not alive then
                hide(b)
            else
                local dist = (root.Position - myRoot.Position).Magnitude

                -- ESP box
                if b and (CFG.esp or CFG.names) and dist <= CFG.espDistance then
                    local center, onScreen = cam:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local top = cam:WorldToViewportPoint(root.Position + Vector3.new(0, 2.8, 0))
                        local bottom = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3.2, 0))
                        local h = math.abs(top.Y - bottom.Y)
                        local w = h * 0.6
                        local pos = Vector2.new(center.X - w / 2, top.Y)
                        local size = Vector2.new(w, h)

                        if CFG.esp then
                            b.fill.Position, b.fill.Size = pos, size
                            b.outline.Position, b.outline.Size = pos, size
                            b.fill.Visible = not CFG.fpsSuper   -- super boost: outline only, half the Drawing cost
                            b.outline.Visible = true
                        else
                            b.fill.Visible = false
                            b.outline.Visible = false
                        end

                        if CFG.names then
                            local t = b.name
                            t.Text = (plr.DisplayName ~= plr.Name) and (plr.DisplayName .. " (@" .. plr.Name .. ")") or plr.Name
                            t.Color = CFG.outline
                            t.Position = Vector2.new(center.X, top.Y - 16)
                            t.Visible = true
                        else
                            b.name.Visible = false
                        end
                    else
                        hide(b)
                    end
                else
                    hide(b)
                end

                -- aim target selection
                if aimLive and (solo or dist <= CFG.aimDistance) then
                    local part = aimPartOf(char)
                    if part then
                        if nearestMode then
                            if dist < bestScore then
                                best, bestScore = part, dist
                            end
                        else
                            local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                            if onScreen then
                                local d = (Vector2.new(sp.X, sp.Y) - mousePos).Magnitude
                                if d <= CFG.fov and d < bestScore then
                                    best, bestScore = part, d
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    target = aimLive and best or nil
end)

------------------------------------------------------------------
-- UI
------------------------------------------------------------------
local THEME = {
    bg = Color3.fromRGB(246, 246, 242),       -- "minimal light": warm off-white card
    bar = Color3.fromRGB(246, 246, 242),
    row = Color3.fromRGB(255, 255, 255),
    accent = Color3.fromRGB(59, 108, 240),    -- toggles, sliders, active tab
    off = Color3.fromRGB(212, 214, 220),
    text = Color3.fromRGB(36, 38, 44),
    muted = Color3.fromRGB(122, 125, 134),
    stroke = Color3.fromRGB(224, 224, 218),
    dollar = Color3.fromRGB(255, 255, 255),   -- tint of the $ image (white = as supplied; try the accent green)
}
local ROW_T = 0        -- row transparency so the background $ shows through
local BG_DOLLAR_T = 1    -- background $ transparency (higher = fainter)

-- $ image, embedded (white glyph on transparent), written to the executor workspace at runtime
local DOLLAR_B64 = table.concat({
    "iVBORw0KGgoAAAANSUhEUgAAAIAAAAC+CAQAAABXR8+dAAANCElEQVR42u3de5Ac1XXH8U93z2qfEi9DALmUgAmRkY0AIwFCEB6FEC4TUabiMgm2Yxch5RBc",
    "TpE4EKeKmOB/iG0qCeVKBSo4Dq+YVwGOQQlIgqhsUExsHDAlYUJMxNuAkXb2Od2dP6a12t3plbQ7vbO72u6/JM1qp++3zz33nHN/93SQnucVgxKtu1KBWXNV",
    "7PCaagsBBEKJdPYACFW0zWcApNIW3lDa0um21ys0z68SQAmgBFACKAGUAEoAJYASQAmgBFACKAGUAEoAJYASQAmgBFACKAGUAEoAJYASQAmgBFACKAGUAObB",
    "VZnRbw8aHkDL5RMzC2AgR5nSMV8AhAad7nzxiGYsFfmZ2yxopYJoJgHEzvQX4/71Sf8kmB8AoF9NLMr+Fou8N7+cYKgiGAEQiEb+XC6DJYASQAmgBFACKAHs",
    "vwACoSjn2wOhoJUHKiotH3Y95hsyLNbX8BM1icFRcKb9ZEGlpUMfMpxlfEc6RLuTGPW0AxzseH3e9sts4G3ahOLpwxCkp3lB37Rm4YHIkCH8ipMsc4ql3ucg",
    "7bk/nXrHu97xnP/0U897E6FOsntM5xaAQGTQsAOcbZ21Dh/1WZIz28cfqHrVEx61yYvoFBVvC9MLIDJsyKEudbml2aDrww7GGP9YBLIjPOnIBN3pEbfaaECX",
    "QDw3AARCVQe6wuWWZO4snKR/TzPDr+eIT/u674h1F+kap2sZDKWq1njc9ZaIJULRpJe3IEuRU7HER9zh35ylKinuvsNpMv1BqW9Y73g1Se6KP1lPEkokzrHR",
    "1wQGiqochNMy/H6HedAfSyQqhX1HmC2IV1nvaNVilvBwWoa/2Hpr1IS5vz+VqKlNMI9jNfGEPikSqDnTv1uutwgrCAuf+0MO9oAPq+U+oVgsEKqoCHKHGamI",
    "hNm8zw/ean7Nw05RHYcgmHwYXWwkGEiE/sWJucOPs5rfgGc95eeescZVoxxaIvS0r/mQE5zkCFG2dkQ5dx07wkNW26a7uWWxUvDzr7rOOTnDTyUirPddT3g+",
    "C4mXjonsUvzCXeAwJ1rjAh/MFsKwwU5ih7rbx7whamZRDAud/X1WuXpUoXt0fBfZ5Dxr3eQnKrodKLIg54FUHKDLu9a7ykqf8GTm/OQgON5RhpvLHYsEkAj8",
    "lbaGGC8VSPyJsz2qS7cuaebq0hwHWXeBFd26DbvbGS61TdRwwLsmco0ndDUXxIUFPv9+a52dmfrYaK7fx31dl27JHjz8bpCkYrFQtza3W+XvBGOcZqziQTfo",
    "HGMbUzgHXxyAVOjKhm2tVCJ1mQcslE7aXaViqR47fcEldoxMhUTkJX8whdhy2gAEBhxjtXTcb0xFrneHhYan7KpqIj3ucr7XsnwwNeQyr1vQfA4TFjYBEh/T",
    "IxnzTBKhrW7QrtakddUs9KQ1XhapiVxrQ7MLYLEAEpE1uc/4G6raCsjehvV41jqvaHOfG3QVkxZXCpoAwxZZOi4OS4Xe868qBWXwNd1+7EyL/bdKUQlxUYFQ",
    "zZEWj1sAE5EtXtNeWPYe6/K//seC5oKf4gGEUotVxhW0UvxYImrSA4ydah2CIgsixYXCixoqegG2F55tFly7Ki4OOCDHM9Brll/FAAjs6kg0PgZsmx8AUgzk",
    "5AB5drFfAoCd8grdh84fC3i1YVMjwIm5qex+CCD0usFxXiDEiQ5rNmOfG1Og4m0vjQMQSBzsTLXZrEIoygLa7PRMg9Q5xRXCljfPC/Z9XEU+mw0NNdlI4kzr",
    "9LVUhxBMBnlRAFKBTao5MXrqJkuK2sbY57tpOYBEpxc91hCqhhJH+raFqi0LipLJrDthgYaXuCUnFogkftOjjrZT2BIt8KTWnOIAxDo9bHPOuh+KrbDJxQZU",
    "BSrTviwGMwGAUM1Xcz+JxN7vHt9zliG9aqIiCpqzKxSulysecasodxsjkTjfRhtd5iBV782OzrLFhiipNn/qhVwEu/Z3znCzZ3zb5xwyG/rLFi2RiVSdaoPO",
    "CVUcu7c737bDUWMsKPKYtToKrCC12AKIdXvSJfonTILCEcnLIWOGX7+G1Ayg0iofUXyUHuvxgIvs2EMtMMgUAGmD7/51lzhGolfVkKhpcU3Lp8Cu1KjXaW5x",
    "nLRhr2jvV5+f+g8bPe1VBDqLLYO2AkDdFxziOn9IpgnZVze6e3P1LT/wiMdsQ7u26RHMTp9OMDJk2FpfsTILkPdVvpJmGOo/vcOj7vCIqoqOuaUUrUsl233G",
    "H/lw5h8mkahmyXXdHn7iVnd53QJtc0UpujsGHNDjQpdbnVWO65KXYBIY6the9jdutrNYpej0q8UDoZpBkZOsc5FlI/FAMoGMbk/Rw/Ou8UCRdtAKufyulyr0",
    "o8fJznG6FRZOIc6sO8ib/Zl39RQTLrUGwO5geNggQkuc7FQXOnaSbxypa81/5Hc9XwyCVgKQrQSh2JAYX3Rjg6YsFe/l3FBNxZsutrkIBK2u19ZlsqkFDlDJ",
    "FVMGKkKB2oQPpaLmMN9zbhFi2ZkqWNeFcum4wbPZGW70I6mKcMLiVkVsoTsdp79ZBDN7fF5OMrTZZh2W+y3rLJOvE92lFL3TGQabK7vPti2LQGQRnvJlK11s",
    "4wQ6USI1x7vWYHNjmH17NrGaQJceifuc57c9k6MT3WUFV1qpr5lRzM5Nq7qrpFu7e6zy1+N0orvT5zZfnptOcF+tIdEj9iWXGsiZ65HUR61oxhXO/sPTNaGF",
    "bvcJQzkTIVHxuf3JCeZPiGELPeRLOTYQYJ1DDU61gDZXjs/XdLnJEw0rQih1uJVT34KfKwBSodj10gYriKVWsb9bADUdNnm6QZAfCCyfuhBnLnWQqBj2XeP3",
    "nwN8UNc4nfp+CSDB97PFbyyA9zlwqnnhXAKQCr2gL+dJd1s8qivdfguAindtJycg6pmqG5xbAEJDDf3m6k6xfbYEQkEBh6WDPQbHg/LaaARTN6qin1A/TZ7l",
    "S/fwSUXnuOGmzanSi1WIDDjC5Vbqn6aplepwcG6MUDXF9iqVAocf63SH1V6xwltFHGnLWQjbHJRj8MOqMx0JBhh0s9UGLPY1tWnY3Q/EjrEo55P3vDnVY1TF",
    "nRvsc61L1LSr+R2/Pw3SyFBqtXAc3ARbvTezACp6fdJfikUCkcSNVugtGEGC0+Qdy9iqNtWSSFjI0+91qluko/oDdbvTrxZqBaFBS53TILgI8QNT7jAVFnJj",
    "i92me9SthWIfcL/D9BYmkA3FvmDhuKQnFdrp8amXxsMCDLPin31gXEkiEjvRekfZWYgVRHp9yKUN2rNE6ode1jGTFjBsuzyNcGy5Tc7R27RGOFKzyLcsbPie",
    "QOAu8UxaAFztjZyydSS2xMO+qE+1CdlbxaBBf+8j4obnH3jZPc2oBYqYAp1e9RVhTuATSSxwo3stVzU0hTwhFOm1yP0umaA3yT96p5nTyUVYQE2Xm92rklOU",
    "CKUSH7fF31qsV9/I7u++DD3Sp+psG1yUM/xEaLt/aE4tUtypsc/YkougrgdY4EpP+aoVhvXqUxPm2kOgkgHqV1V1srttsDxn+PUJcLXXmmvHXykIQJt+n/So",
    "o3NbKEVSicP9uWtsca/NfuYdcU4OV1OzA5Fjne4CF2qX5jZTqqm4z+3NNlIoKlCJdXrJWvdblosgyCBETnEKtnvRBkuN7yl6iIst8xuWOlZP9pvz3Ges4lmf",
    "b/5lDEVKZCJVh7vXqkzkMhEq+7goxiaS08UirzvLtuYbaYST9sl7uuFub7rAbaI9NL6MMluIJxDBJFkrpXTCUyU1kTdcbGsRbVQmB2Bv57FiHQZ8yme9JdpD",
    "y6R6W+X8RTHMuslN1HG0bvzn+n4xKrGiKzeJSLdvOcPDIuE+9I2anKcJRB50nueK0gkWX7pKxXps81GfsjVrhdm8xDnNfMcvXWGdX+gu6lTJ9NTuajp1us2p",
    "Pu/prJ1qnPWAmvzQk+zJD7vDKt/UZUFxgunpFErWuwq3O9/vOduBI09yz32FR+d5RlaMdzzkm7YIimqg1AoA9dW/fgZoiXNdaPWYjhLxHl61tXu1qfov3/GQ",
    "n6O7+FdxtUIqG0kNinGE45zgJCd4v4V7sYDtXvWMzX5oq1ikY3reQ9YqrXC9UjiUua4eix2kw2d9elSJIxX4P7d43XZve9lr2f/smI6e4kWHwnt3ZTW0ZXt4",
    "w7YJJJb59KiBJSLPuW7kzjozmX0ynecIWyuV3dVSMdSpoqqr4SfaRLokWW/IFrx8b2a0wmm2uCW5iOJWHqktX7JSAigBlABKACWAeXzN7Jmh+qq/OznS+qYa",
    "MwtgwZi3jEbonj8AUoEXPT7q0FOi3ZZWN9dp9cnRsVetIc0Jc945sB9PgbaG4aat7i40005wxpsplXFACaAEUAIoAZQASgAlgBJACaAEUAIoAZQASgAlgBJA",
    "CaAEUAIoAZQASgAlgHlzVUzppfX7E4DEsOFsczSYjwCWWDTyVuh5COD/AcQ1YdENjozmAAAAAElFTkSuQmCC",
})

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP = {}
for idx = 1, #B64 do B64_LOOKUP[B64:sub(idx, idx)] = idx - 1 end

local function b64decode(s)
    local out, acc, bits = {}, 0, 0
    for ch in s:gmatch("[A-Za-z0-9+/]") do
        acc = acc * 64 + B64_LOOKUP[ch]
        bits = bits + 6
        if bits >= 8 then
            bits = bits - 8
            local byte = math.floor(acc / 2 ^ bits)
            acc = acc % 2 ^ bits
            out[#out + 1] = string.char(byte)
        end
    end
    return table.concat(out)
end

local dollarAsset = nil
if type(writefile) == "function" and type(getcustomasset) == "function" then
    pcall(function()
        writefile("syncware_dollar.png", b64decode(DOLLAR_B64))
        dollarAsset = getcustomasset("syncware_dollar.png")
    end)
end

-- Roblox logo, embedded (round-masked PNG), written to the executor workspace at runtime
local LOGO_B64 = table.concat({
    "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",
    "0D69aeLLoAAAAASUVORK5CYII=",
})

local logoAsset = nil
if type(writefile) == "function" and type(getcustomasset) == "function" then
    pcall(function()
        writefile("syncware_logo.png", b64decode(LOGO_B64))
        logoAsset = getcustomasset("syncware_logo.png")
    end)
end

local function make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function corner(o, r) make("UICorner", {CornerRadius = UDim.new(0, r)}, o) end

-- $ graphic: the image when available, a plain "$" text glyph otherwise
local function dollarGfx(parent, x, y, w, h, rot, transp, z)
    if dollarAsset then
        return make("ImageLabel", {
            Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y), Rotation = rot,
            BackgroundTransparency = 1, Image = dollarAsset, ImageColor3 = THEME.dollar,
            ImageTransparency = transp, ScaleType = Enum.ScaleType.Fit, ZIndex = z,
        }, parent)
    end
    return make("TextLabel", {
        Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y), Rotation = rot,
        BackgroundTransparency = 1, Text = "$", TextScaled = true,
        Font = Enum.Font.GothamBlack, TextColor3 = THEME.dollar,
        TextTransparency = transp, ZIndex = z,
    }, parent)
end

local function guiParent()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    local ok2 = pcall(function() return game:GetService("CoreGui"):GetChildren() end)
    if ok2 then return game:GetService("CoreGui") end
    return lp:WaitForChild("PlayerGui")
end

local gui = make("ScreenGui", {
    Name = "Syncware", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
gui.Parent = guiParent()

-- logo button: dark circle, tilted white square with a dark center
local LOGO = {
    size = 44,     -- button diameter (px), matched to the real Roblox logo
    disc = Color3.fromRGB(18, 18, 21),
    mark = Color3.fromRGB(255, 255, 255),
    tilt = 12,     -- degrees
    outer = 18,    -- white square size (px)
    inner = 7,     -- center cutout size (px)
}
local opener = make("TextButton", {
    Size = UDim2.fromOffset(LOGO.size, LOGO.size), Position = UDim2.fromOffset(16, 120),
    BackgroundColor3 = LOGO.disc, BackgroundTransparency = logoAsset and 1 or 0,
    Text = "", BorderSizePixel = 0, AutoButtonColor = false,
}, gui)
corner(opener, LOGO.size / 2)
if logoAsset then
    make("ImageLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = logoAsset,
        ScaleType = Enum.ScaleType.Fit, Active = false, ZIndex = 2,
    }, opener)
else
    make("UIStroke", {Color = Color3.fromRGB(0, 0, 0), Thickness = 1, Transparency = 0.5}, opener)
    local sq = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(LOGO.outer, LOGO.outer), Rotation = LOGO.tilt,
        BackgroundColor3 = LOGO.mark, BorderSizePixel = 0, Active = false, ZIndex = 2,
    }, opener)
    corner(sq, 3)
    local hole = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(LOGO.inner, LOGO.inner),
        BackgroundColor3 = LOGO.disc, BorderSizePixel = 0, Active = false, ZIndex = 3,
    }, sq)
    corner(hole, 1)
end

local win = make("Frame", {
    Size = UDim2.fromOffset(300, 340), Position = UDim2.fromOffset(76, 120),
    BackgroundColor3 = THEME.bg, BorderSizePixel = 0, Visible = false,
}, gui)
corner(win, 12)
make("UIStroke", {Color = THEME.stroke, Thickness = 1}, win)

-- background $ decor (behind everything)
local decor = make("Frame", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 1,
}, win)
local bigDollar = dollarGfx(decor, 0, 0, 150, 223, 0, BG_DOLLAR_T, 1)  -- single centered $
bigDollar.AnchorPoint = Vector2.new(0.5, 0.5)
bigDollar.Position = UDim2.fromScale(0.5, 0.5)
bigDollar.Visible = false

local bar = make("TextLabel", {
    Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = THEME.bar, BorderSizePixel = 0,
    Text = "  $yncware", TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = THEME.text, Font = Enum.Font.GothamBold, TextSize = 14, ZIndex = 2,
}, win)
corner(bar, 12)

-- credit, sits right after the title text
make("TextLabel", {
    Size = UDim2.new(1, -130, 1, 0), Position = UDim2.fromOffset((bar.TextBounds.X > 0 and bar.TextBounds.X or 80) + 6, 0),
    BackgroundTransparency = 1, Text = "made by .syncccc", TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = THEME.muted, Font = Enum.Font.Gotham, TextSize = 11,
    Active = false, ZIndex = 3,
}, bar)

local closeBtn = make("TextButton", {
    Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -30, 0, 0),
    BackgroundTransparency = 1, Text = "x", TextColor3 = THEME.muted,
    Font = Enum.Font.GothamBold, TextSize = 14, ZIndex = 3,
}, win)

-- open / close wired immediately, before anything else can fail
local TweenService = game:GetService("TweenService")
local function tween(o, t, props, style)
    local ok, tw = pcall(TweenService.Create, TweenService, o,
        TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    if ok then tw:Play() end
    return tw
end

-- window open/close: quick scale pop instead of an instant flip
local winScale = make("UIScale", {Scale = 1}, win)
local openToken = 0
local function setOpen(v)
    openToken += 1
    local my = openToken
    if v then
        winScale.Scale = 0.92
        win.Visible = true
        tween(winScale, 0.16, {Scale = 1}, Enum.EasingStyle.Back)
    else
        tween(winScale, 0.1, {Scale = 0.92})
        task.delay(0.1, function()
            if openToken == my then win.Visible = false end
        end)
    end
end
local openerMoved = false
on(opener.Activated, function()
    if openerMoved then openerMoved = false return end
    setOpen(not win.Visible)
end)
on(closeBtn.Activated, function() setOpen(false) end)
on(UIS.InputBegan, function(i)
    if i.KeyCode == Enum.KeyCode.LeftControl and not UIS:GetFocusedTextBox() then
        setOpen(not win.Visible)
    end
end)

local tabRow = make("Frame", {
    Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 38),
    BackgroundTransparency = 1, ZIndex = 2,
}, win)
make("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, tabRow)

local pageHolder = make("Frame", {
    Size = UDim2.new(1, -16, 1, -78), Position = UDim2.fromOffset(8, 72),
    BackgroundTransparency = 1, ZIndex = 2,
}, win)

local pages, tabBtns = {}, {}
local tabCount = 0

local function showPage(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(tabBtns) do
        local sel = (n == name)
        b.BackgroundColor3 = THEME.accent
        tween(b, 0.15, {
            BackgroundTransparency = sel and 0 or 1,
            TextColor3 = sel and Color3.fromRGB(255, 255, 255) or THEME.muted,
        })
    end
end

local function newPage(name)
    tabCount = tabCount + 1
    local btn = make("TextButton", {
        Size = UDim2.new(1 / 6, -5, 1, 0), BackgroundColor3 = THEME.accent, BackgroundTransparency = 1,
        BorderSizePixel = 0, Text = name, TextColor3 = THEME.muted, TextScaled = true,
        Font = Enum.Font.GothamBold, ZIndex = 2, LayoutOrder = tabCount,
    }, tabRow)
    corner(btn, 14)
    make("UITextSizeConstraint", {MaxTextSize = 12, MinTextSize = 8}, btn)
    local page = make("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.accent, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, ZIndex = 2,
    }, pageHolder)
    make("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, page)
    pages[name], tabBtns[name] = page, btn
    on(btn.Activated, function() showPage(name) end)
    return page
end

-- drag by title bar
do
    local dragging, startPos, startMouse
    on(bar.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startMouse = true, win.Position, i.Position
        end
    end)
    on(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startMouse
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    on(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- drag the logo button (a click without movement still toggles the window)
do
    local dragging, startPos, startMouse
    on(opener.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startMouse = true, opener.Position, i.Position
            openerMoved = false
        end
    end)
    on(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startMouse
            if d.Magnitude > 4 then openerMoved = true end
            if openerMoved then
                local vp = gui.AbsoluteSize
                local x = math.clamp(startPos.X.Offset + d.X, 0, math.max(vp.X - LOGO.size, 0))
                local y = math.clamp(startPos.Y.Offset + d.Y, 0, math.max(vp.Y - LOGO.size, 0))
                opener.Position = UDim2.fromOffset(x, y)
            end
        end
    end)
    on(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- controls share state through CFG; syncers keep duplicate toggles in step
local syncers = {}
local applyers = {}   -- key -> function(value): sets CFG, repaints the control, runs its onChange (the Configs tab loads through these)
local function sync(key)
    for _, f in ipairs(syncers[key] or {}) do f() end
end

local function toggle(parent, label, key, onChange)
    local btn = make("TextButton", {
        Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
        AutoButtonColor = false, Text = "  " .. label, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = THEME.text, Font = Enum.Font.Gotham, TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
    }, parent)
    corner(btn, 6)
    local pill = make("Frame", {
        Size = UDim2.fromOffset(34, 18), Position = UDim2.new(1, -44, 0.5, -9),
        BackgroundColor3 = THEME.off, BorderSizePixel = 0, ZIndex = 3,
    }, btn)
    corner(pill, 9)
    local knob = make("Frame", {
        Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(2, 2),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, ZIndex = 4,
    }, pill)
    corner(knob, 7)
    local painted = false
    local function paint()
        local c = CFG[key] and THEME.accent or THEME.off
        local pos = CFG[key] and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2)
        if painted then
            tween(pill, 0.15, {BackgroundColor3 = c})
            tween(knob, 0.15, {Position = pos})
        else
            pill.BackgroundColor3, knob.Position = c, pos
            painted = true
        end
    end
    paint()
    syncers[key] = syncers[key] or {}
    table.insert(syncers[key], paint)
    applyers[key] = function(v)
        if CFG[key] == v then return end
        CFG[key] = v
        sync(key)
        if onChange then onChange(v) end
    end
    on(btn.Activated, function()
        CFG[key] = not CFG[key]
        sync(key)
        if onChange then onChange(CFG[key]) end
    end)
end

local function slider(parent, label, key, min, max, step, onChange)
    local f = make("Frame", {
        Size = UDim2.new(1, -6, 0, 30), BackgroundColor3 = THEME.row,
        BackgroundTransparency = ROW_T, BorderSizePixel = 0, ZIndex = 2,
    }, parent)
    corner(f, 6)
    local txt = make("TextLabel", {
        Size = UDim2.new(0.5, -8, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.text,
        Font = Enum.Font.Gotham, TextSize = 12, ZIndex = 3,
    }, f)
    local track = make("Frame", {
        Size = UDim2.new(0.5, -14, 0, 4), Position = UDim2.new(0.5, 4, 0.5, -2),
        BackgroundColor3 = THEME.off, BorderSizePixel = 0, ZIndex = 3,
    }, f)
    corner(track, 2)
    local fill = make("Frame", {
        BackgroundColor3 = THEME.accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 4,
    }, track)
    corner(fill, 2)

    local function set(v)
        v = math.clamp(math.floor(v / step + 0.5) * step, min, max)
        v = tonumber(string.format("%.2f", v))
        CFG[key] = v
        fill.Size = UDim2.fromScale((v - min) / (max - min), 1)
        txt.Text = string.format("%s: %g", label, v)
        if onChange then onChange(v) end
    end
    set(CFG[key])
    applyers[key] = function(v) if type(v) == "number" then set(v) end end

    local dragging = false
    local function fromInput(i)
        local a = math.clamp((i.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        set(min + a * (max - min))
    end
    on(track.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromInput(i)
        end
    end)
    on(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            fromInput(i)
        end
    end)
    on(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local function cycle(parent, label, key, options)
    local btn = make("TextButton", {
        Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
        AutoButtonColor = false, TextColor3 = THEME.text, Font = Enum.Font.Gotham,
        TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
    }, parent)
    corner(btn, 6)
    btn.TextXAlignment = Enum.TextXAlignment.Left
    local val = make("TextLabel", {
        Size = UDim2.new(0.5, -10, 1, 0), Position = UDim2.fromScale(0.5, 0), BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = THEME.muted,
        Font = Enum.Font.Gotham, TextSize = 13, ZIndex = 3,
    }, btn)
    local function refresh() btn.Text = "  " .. label; val.Text = tostring(CFG[key]) end
    refresh()
    applyers[key] = function(v)
        if table.find(options, v) then CFG[key] = v refresh() end
    end
    on(btn.Activated, function()
        local idx = table.find(options, CFG[key]) or 0
        CFG[key] = options[idx % #options + 1]
        refresh()
    end)
end

-- keybind (hold-to-aim): keyboard, mouse buttons, and side buttons
local function inputName(i)
    if i.UserInputType == Enum.UserInputType.Keyboard then
        return i.KeyCode.Name
    end
    return i.UserInputType.Name -- MouseButton1 / MouseButton2 / MouseButton3
end

local function keybind(parent, label)
    local btn = make("TextButton", {
        Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
        AutoButtonColor = false, TextColor3 = THEME.text, Font = Enum.Font.Gotham,
        TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
    }, parent)
    corner(btn, 6)
    btn.TextXAlignment = Enum.TextXAlignment.Left
    local val = make("TextLabel", {
        Size = UDim2.new(0.5, -10, 1, 0), Position = UDim2.fromScale(0.5, 0), BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = THEME.muted,
        Font = Enum.Font.Gotham, TextSize = 13, ZIndex = 3,
    }, btn)
    local function refresh()
        btn.Text = "  " .. label
        val.Text = binding and "press a key..." or CFG.aimKey
    end
    bindRefresh = refresh
    applyers.aimKey = function(v)
        if type(v) == "string" then CFG.aimKey = v binding = false holding = false refresh() end
    end
    refresh()

    on(btn.Activated, function()
        binding = true
        holding = false
        refresh()
    end)

    on(UIS.InputBegan, function(i, gp)
        if binding then
            if i.UserInputType == Enum.UserInputType.Keyboard or i.UserInputType.Name:find("MouseButton") then
                -- ignore the click that started binding (left click on the bind button)
                if i.UserInputType == Enum.UserInputType.MouseButton1 and gp then return end
                if i.KeyCode ~= Enum.KeyCode.Escape then
                    CFG.aimKey = inputName(i)
                end
                binding = false
                holding = false
                refresh()
            end
            return
        end
        if not gp and not XBUTTONS[CFG.aimKey] and inputName(i) == CFG.aimKey then
            holding = true
        end
    end)

    on(UIS.InputEnded, function(i)
        if not XBUTTONS[CFG.aimKey] and inputName(i) == CFG.aimKey then holding = false end
    end)

    on(UIS.WindowFocusReleased, function() holding = false end)
end

-- color wheel box: hue segments x light/dark rings (like a swatch wheel), click to pick
local function colorBox(parent, label, onPick)
    local box = make("Frame", {
        Size = UDim2.new(1, -6, 0, 190), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
        BorderSizePixel = 0, ZIndex = 2,
    }, parent)
    corner(box, 6)
    make("TextLabel", {
        Size = UDim2.new(1, -60, 0, 22), Position = UDim2.fromOffset(8, 4), BackgroundTransparency = 1,
        Text = label, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.text,
        Font = Enum.Font.Gotham, TextSize = 13, ZIndex = 3,
    }, box)
    local preview = make("Frame", {
        Size = UDim2.fromOffset(30, 14), Position = UDim2.new(1, -38, 0, 8),
        BackgroundColor3 = CFG.outline, BorderSizePixel = 0, ZIndex = 3,
    }, box)
    corner(preview, 4)
    make("UIStroke", {Color = THEME.off, Thickness = 1}, preview)

    local SIZE = 150
    local wheel = make("Frame", {
        Size = UDim2.fromOffset(SIZE, SIZE), AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 32), BackgroundTransparency = 1, ZIndex = 3,
    }, box)
    local marker = make("Frame", {
        Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1, Visible = false, ZIndex = 7,
    }, wheel)
    corner(marker, 7)
    make("UIStroke", {Color = Color3.fromRGB(0, 0, 0), Thickness = 3}, marker)
    local inner = make("Frame", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7,
    }, marker)
    corner(inner, 7)
    make("UIStroke", {Color = Color3.fromRGB(255, 255, 255), Thickness = 1}, inner)

    local function pick(color, x, y)
        preview.BackgroundColor3 = color
        marker.Position = UDim2.fromOffset(x, y)
        marker.Visible = true
        onPick(color)
    end

    local c = SIZE / 2
    local HUES = 24
    local RINGS = { -- {saturation, value}: light -> vivid -> dark, inner to outer
        {0.18, 1}, {0.40, 1}, {0.65, 1}, {1, 1}, {1, 0.78}, {1, 0.55},
    }
    local innerR = 12
    local thick = (c - innerR) / #RINGS

    local function cell(color, x, y, w, h, rot, round)
        local b = make("TextButton", {
            Size = UDim2.fromOffset(w, h), Position = UDim2.fromOffset(x, y), AnchorPoint = Vector2.new(0.5, 0.5),
            Rotation = rot, BackgroundColor3 = color, BorderSizePixel = 0, Text = "",
            AutoButtonColor = false, ZIndex = 4,
        }, wheel)
        if round then corner(b, round) end
        on(b.Activated, function() pick(color, x, y) end)
    end

    cell(Color3.fromRGB(255, 255, 255), c, c, innerR * 2 - 2, innerR * 2 - 2, 0, innerR)
    for ring = 1, #RINGS do
        local radius = innerR + (ring - 0.5) * thick
        local sat, val = RINGS[ring][1], RINGS[ring][2]
        local arc = 2 * math.pi * radius / HUES + 1.5
        for h = 0, HUES - 1 do
            local ang = h / HUES * 2 * math.pi - math.pi / 2
            cell(Color3.fromHSV(h / HUES, sat, val),
                c + radius * math.cos(ang), c + radius * math.sin(ang),
                thick + 1, arc, math.deg(ang))
        end
    end

    return function(color)   -- used by the Configs tab
        preview.BackgroundColor3 = color
        marker.Visible = false
        onPick(color)
    end
end

-- FPS boost: lowers client graphics, restorable. Tier 1 = boost, tier 2 = super (implies boost).
local Lighting = game:GetService("Lighting")
local FPS = {on = false, super = false, gen = 0, sgen = 0, saved = {}, conn = nil, quality = nil, mesh = nil}

-- lvl = tier to record the change under (nil = apply without recording, for streamed-in objects)
local function fpsSet(inst, prop, value, lvl)
    local ok, old = pcall(function() return inst[prop] end)
    if ok and old ~= value and pcall(function() inst[prop] = value end) and lvl then
        FPS.saved[#FPS.saved + 1] = {inst, prop, old, lvl}
    end
end

local function fpsHandle(o, lvl)
    if o:IsA("Terrain") then return end
    if o:IsA("BasePart") then
        fpsSet(o, "Material", Enum.Material.SmoothPlastic, lvl)
        fpsSet(o, "Reflectance", 0, lvl)
        fpsSet(o, "CastShadow", false, lvl)
    elseif o:IsA("Decal") or o:IsA("Texture") then
        fpsSet(o, "Transparency", 1, lvl)
    elseif o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Beam") or o:IsA("Smoke")
        or o:IsA("Fire") or o:IsA("Sparkles") then
        fpsSet(o, "Enabled", false, lvl)
    end
end

-- super tier: mesh fidelity + mesh textures, accessories, lights, explosions, forcefields
local function fpsHandleSuper(o, lvl)
    if o:IsA("BasePart") then
        if o:IsA("MeshPart") then
            fpsSet(o, "RenderFidelity", Enum.RenderFidelity.Performance, lvl)
            fpsSet(o, "TextureID", "", lvl)
        end
        local p = o.Parent
        if p and p:IsA("Accessory") then fpsSet(o, "Transparency", 1, lvl) end
    elseif o:IsA("PointLight") or o:IsA("SpotLight") or o:IsA("SurfaceLight") then
        fpsSet(o, "Enabled", false, lvl)
    elseif o:IsA("Explosion") or o:IsA("ForceField") then
        fpsSet(o, "Visible", false, lvl)
    end
end

local function fpsApply()
    FPS.gen = FPS.gen + 1
    local gen = FPS.gen

    pcall(function()
        FPS.quality = settings().Rendering.QualityLevel
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
    fpsSet(Lighting, "GlobalShadows", false, 1)
    fpsSet(Lighting, "Technology", Enum.Technology.Compatibility, 1)
    for _, c in ipairs(Lighting:GetChildren()) do
        if c:IsA("PostEffect") then fpsSet(c, "Enabled", false, 1) end
    end
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        for _, prop in ipairs({"WaterWaveSize", "WaterWaveSpeed", "WaterReflectance"}) do
            fpsSet(terrain, prop, 0, 1)
        end
    end

    -- new objects (effects, mobs, map streaming) get lowered too, without being recorded
    FPS.conn = workspace.DescendantAdded:Connect(function(o)
        if FPS.on then pcall(fpsHandle, o, nil) end
        if FPS.super then pcall(fpsHandleSuper, o, nil) end
    end)

    -- existing map, in chunks so it doesn't freeze the client
    task.spawn(function()
        local n = 0
        for _, o in ipairs(workspace:GetDescendants()) do
            if FPS.gen ~= gen or not FPS.on then return end
            pcall(fpsHandle, o, 1)
            n = n + 1
            if n % 1500 == 0 then task.wait() end
        end
    end)
end

local function fpsSuperApply()
    FPS.super = true
    FPS.sgen = FPS.sgen + 1
    local gen = FPS.sgen

    -- lowest mesh detail level
    pcall(function()
        local r = settings().Rendering
        if FPS.mesh == nil then FPS.mesh = r.MeshPartDetailLevel end
        r.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04
    end)

    -- sky haze / atmosphere
    for _, c in ipairs(Lighting:GetChildren()) do
        if c:IsA("Atmosphere") then
            fpsSet(c, "Density", 0, 2)
            fpsSet(c, "Haze", 0, 2)
            fpsSet(c, "Glare", 0, 2)
        end
    end

    -- clouds + terrain grass
    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        local clouds = terrain:FindFirstChildOfClass("Clouds")
        if clouds then fpsSet(clouds, "Enabled", false, 2) end
        if type(gethiddenproperty) == "function" and type(sethiddenproperty) == "function" then
            pcall(function()
                local old = gethiddenproperty(terrain, "Decoration")
                if old == true and pcall(sethiddenproperty, terrain, "Decoration", false) then
                    FPS.saved[#FPS.saved + 1] = {terrain, "Decoration", old, 2, true}
                end
            end)
        end
    end

    task.spawn(function()
        local n = 0
        for _, o in ipairs(workspace:GetDescendants()) do
            if FPS.sgen ~= gen or not FPS.super then return end
            pcall(fpsHandleSuper, o, 2)
            n = n + 1
            if n % 1500 == 0 then task.wait() end
        end
    end)
end

-- minLvl 1 (default): undo everything and shut the boost off. minLvl 2: undo only the super tier.
local function fpsRestore(minLvl)
    minLvl = minLvl or 1
    FPS.sgen = FPS.sgen + 1
    FPS.super = false

    local keep, undo = {}, {}
    for _, r in ipairs(FPS.saved) do
        if r[4] >= minLvl then undo[#undo + 1] = r else keep[#keep + 1] = r end
    end
    FPS.saved = keep

    if FPS.mesh ~= nil then
        pcall(function() settings().Rendering.MeshPartDetailLevel = FPS.mesh end)
        FPS.mesh = nil
    end

    if minLvl <= 1 then
        FPS.gen = FPS.gen + 1
        FPS.on = false
        if FPS.conn then pcall(function() FPS.conn:Disconnect() end) FPS.conn = nil end
        if FPS.quality then
            pcall(function() settings().Rendering.QualityLevel = FPS.quality end)
            FPS.quality = nil
        end
    end

    task.spawn(function()
        for i = #undo, 1, -1 do
            local r = undo[i]
            pcall(function()
                if r[5] then sethiddenproperty(r[1], r[2], r[3]) else r[1][r[2]] = r[3] end
            end)
            if i % 1500 == 0 then task.wait() end
        end
    end)
end

-- ESP tab
local espPage = newPage("ESP")
toggle(espPage, "Box ESP", "esp")
toggle(espPage, "Names", "names")
toggle(espPage, "Team check", "teamCheck")
applyers.outline = colorBox(espPage, "ESP color", function(color)
    CFG.outline, CFG.fill = color, color
    for _, b in pairs(boxes) do
        b.outline.Color = color
        b.fill.Color = color
    end
end)
slider(espPage, "ESP distance", "espDistance", 100, 10000, 100)
slider(espPage, "Box fill opacity", "fillOpacity", 0, 1, 0.05, function(v)
    for _, b in pairs(boxes) do b.fill.Transparency = v end
end)

-- Silent Aim tab
local aimPage = newPage("Silent Aim")
toggle(aimPage, "Silent aim", "aim")
toggle(aimPage, "Hold to aim", "holdToAim")
keybind(aimPage, "Aim key")
cycle(aimPage, "Aim mode", "aimMode", {"nearest", "cursor"})
toggle(aimPage, "Solo lock", "soloLock")
toggle(aimPage, "Team check", "teamCheck")
toggle(aimPage, "Show FOV circle", "showFov")
slider(aimPage, "FOV radius", "fov", 20, 500, 5)
slider(aimPage, "Aim distance", "aimDistance", 100, 5000, 50)

-- Performance tab
local perfPage = newPage("FPS")
local fpsLabel = make("TextLabel", {
    Size = UDim2.new(1, -6, 0, 22), BackgroundTransparency = 1, Text = "FPS: --",
    TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.accent,
    Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 2,
}, perfPage)
do
    local acc, frames = 0, 0
    on(RunService.RenderStepped, function(dt)
        acc, frames = acc + dt, frames + 1
        if acc >= 0.5 then
            fpsLabel.Text = string.format("FPS: %d", math.floor(frames / acc + 0.5))
            acc, frames = 0, 0
        end
    end)
end
toggle(perfPage, "FPS boost", "fpsBoost", function(v)
    if v then
        FPS.on = true
        fpsApply()
    else
        -- turning the base boost off takes super with it
        if CFG.fpsSuper then CFG.fpsSuper = false sync("fpsSuper") end
        fpsRestore(1)
    end
end)
toggle(perfPage, "Super FPS boost", "fpsSuper", function(v)
    if v then
        -- super sits on top of the base boost, so switch that on too if it isn't
        if not CFG.fpsBoost then
            CFG.fpsBoost = true
            sync("fpsBoost")
            FPS.on = true
            fpsApply()
        end
        fpsSuperApply()
    else
        fpsRestore(2)
    end
end)
if type(setfpscap) == "function" then
    toggle(perfPage, "Unlock FPS cap", "fpsUnlock", function(v)
        pcall(setfpscap, v and 999 or 60)
    end)
else
    make("TextLabel", {
        Size = UDim2.new(1, -6, 0, 32), BackgroundTransparency = 1, TextWrapped = true,
        Text = "FPS cap unlock needs setfpscap, which this executor lacks.",
        TextColor3 = Color3.fromRGB(196, 108, 20), Font = Enum.Font.Gotham, TextSize = 12, ZIndex = 2,
    }, perfPage)
end
make("TextLabel", {
    Size = UDim2.new(1, -6, 0, 92), BackgroundTransparency = 1, TextWrapped = true,
    Text = "Boost: low quality level, no shadows, plain materials, no textures, particles or effects.\nSuper: on top of that, lowest mesh detail, no mesh textures, accessories, lights, haze, clouds or grass, and ESP boxes drawn outline only. Turn off to restore.",
    TextColor3 = THEME.muted, Font = Enum.Font.Gotham, TextSize = 11, ZIndex = 2,
}, perfPage)

-- SuS tab
local susPage = newPage("SuS")

-- Fly: camera-relative WASD, Space up, LeftControl down. Moves the root by CFrame each frame
-- (no body movers, no PlatformStand), so the character stays upright and the game can't strip anything.
local function flyStop()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then pcall(function() root.AssemblyLinearVelocity = Vector3.zero end) end
end

on(RunService.Heartbeat, function(dt)
    if not CFG.fly or session.safeActive or session.stickActive then return end
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local cam = workspace.CurrentCamera
    if not (root and hum and cam) or hum.Health <= 0 then return end

    local dir = Vector3.zero
    if not UIS:GetFocusedTextBox() then
        local cf = cam.CFrame
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
    end

    -- hold position against gravity; face the camera's heading, upright
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    local look = cam.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    local pos = root.Position
    if dir.Magnitude > 0 then pos += dir.Unit * CFG.flySpeed * dt end
    if flat.Magnitude > 0.001 then
        root.CFrame = CFrame.lookAt(pos, pos + flat)
    else
        root.CFrame = CFrame.new(pos) * (root.CFrame - root.Position)
    end
end)

toggle(susPage, "Fly", "fly", function(v)
    if not v then flyStop() end
end)
slider(susPage, "Fly speed", "flySpeed", 10, 300, 5)

-- Noclip: each Stepped (before physics), switch off CanCollide on every character part.
-- Only parts that were collidable get touched, and they are remembered so turning it off restores exactly those.
do
    local touched = {}

    function session.noclipRestore()
        for part in pairs(touched) do
            if part.Parent then pcall(function() part.CanCollide = true end) end
        end
        table.clear(touched)
    end

    on(RunService.Stepped, function()
        if not CFG.noclip then return end
        local char = lp.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                touched[part] = true
                part.CanCollide = false
            end
        end
    end)

    toggle(susPage, "Noclip", "noclip", function(v)
        if not v then session.noclipRestore() end
    end)
end

-- Khel Khatam: kill aura. The game's melee hit remote is now an obfuscated one (named "288") that takes
-- (token, number, hit part, {}, nil, token). The tokens come from the game itself, so a hook captures the
-- remote and tokens from your own real hits (land one normal hit after executing to prime it), then the
-- aura replays that call at every living player/Enemies NPC within CFG.auraRange. Falls back to the old
-- RE/RegisterHit shape if that remote exists and nothing has been captured.
do
    local MAX_TARGETS = 8
    local combo = 0
    local warned = {}
    local function warnOnce(key, msg)
        if warned[key] then return end
        warned[key] = true
        warn("[syncware] Khel Khatam: " .. msg)
    end

    local RegisterHit, RegisterAttack
    local hitRemote, tokA, tokB, tokC
    local loop

    local function khelStop()
        if loop then
            pcall(task.cancel, loop)
            loop = nil
        end
    end
    session.khelStop = khelStop

    local function resolveRemotes()
        local mods = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
        local net = mods and mods:FindFirstChild("Net")
        RegisterHit = net and net:FindFirstChild("RE/RegisterHit")
        RegisterAttack = net and net:FindFirstChild("RE/RegisterAttack")
        return RegisterAttack ~= nil
    end

    -- capture: a non-script call with 6 args (string, number, part of a character, table, nil, string)
    if hookmetamethod and newcclosure and checkcaller and getnamecallmethod then
        pcall(function()
            local old
            old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                if env.SyncwareSession == session and not checkcaller() and getnamecallmethod() == "FireServer"
                    and select("#", ...) == 6 then
                    local a1, a2, a3, a4, a5, a6 = ...
                    if type(a1) == "string" and type(a2) == "number" and typeof(a3) == "Instance" and type(a6) == "string" then
                        local ok, isHit = pcall(function()
                            return a3:IsA("BasePart") and a3.Parent ~= nil
                                and a3.Parent:FindFirstChildOfClass("Humanoid") ~= nil
                        end)
                        if ok and isHit then
                            hitRemote, tokA, tokB, tokC = self, a1, a2, a6
                        end
                    end
                end
                return old(self, ...)
            end))
        end)
    end

    local function hitPart(char)
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    end

    local function strike(list)
        if #list == 0 then return end
        local ok, err = pcall(function()
            if not hitRemote and not RegisterHit then
                warnOnce("prime", "no hit captured yet - land one normal hit on an enemy, then it will start")
                return
            end
            combo = combo % 4 + 1
            RegisterAttack:FireServer(0.4, combo)   -- what a real swing sends: (cooldown, combo 1-4)
            if hitRemote then
                for _, e in ipairs(list) do
                    hitRemote:FireServer(tokA, tokB, e.part, {}, nil, tokC)
                end
            else
                local all = {}
                for _, e in ipairs(list) do all[#all + 1] = {e.char, e.char:FindFirstChild("Head") or e.part} end
                RegisterHit:FireServer(all[1][2], all)
            end
        end)
        if not ok then warnOnce("strike", "fire failed - " .. tostring(err)) end
    end

    local function khelStart()
        khelStop()
        if not resolveRemotes() then
            warn("[syncware] Khel Khatam: ReplicatedStorage.Modules.Net RE/RegisterAttack not found - aura off")
            CFG.khelKhatam = false
            sync("khelKhatam")
            return
        end
        loop = task.spawn(function()
            while CFG.khelKhatam and env.SyncwareSession == session do
                task.wait(0.05)
                local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                if myRoot then
                    local list = {}
                    local function consider(char)
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        local root = char:FindFirstChild("HumanoidRootPart")
                        local part = hitPart(char)
                        if hum and root and part and hum.Health > 0 then
                            local d = (root.Position - myRoot.Position).Magnitude
                            if d <= CFG.auraRange then list[#list + 1] = {char = char, part = part, dist = d} end
                        end
                    end

                    for _, plr in ipairs(Players:GetPlayers()) do
                        local char = plr ~= lp and plr.Character
                        if char and not isTeammate(plr) then consider(char) end
                    end
                    local enemies = (not CFG.npcCheck) and workspace:FindFirstChild("Enemies") or nil
                    if enemies then
                        for _, npc in ipairs(enemies:GetChildren()) do consider(npc) end
                    end

                    table.sort(list, function(a, b) return a.dist < b.dist end)
                    while #list > MAX_TARGETS do list[#list] = nil end
                    strike(list)
                end
            end
        end)
    end

    toggle(susPage, "Khel Khatam", "khelKhatam", function(v)
        if v then khelStart() else khelStop() end
    end)
    slider(susPage, "Aura range", "auraRange", 10, 5000, 10)
end

-- Gun: gun aura. While on and a tool with ToolTip "Gun" is held, each Heartbeat it fires a burst of
-- ShootGunEvent shots split across the nearest players/Enemies in range, sending a Validator2 code from the
-- CombatController shoot function's upvalues every CFG.gunCacheShots shots. Needs debug upvalue functions.
do
    local conn
    local startId = 0

    local function gunStop()
        startId = startId + 1
        if conn then
            pcall(function() conn:Disconnect() end)
            conn = nil
        end
    end
    session.gunStop = gunStop

    local function gunFail(msg)
        warn("[syncware] Gun: " .. msg)
        CFG.gun = false
        sync("gun")
    end

    local function gunStart()
        gunStop()
        startId = startId + 1
        local myId = startId

        local getupval = debug and debug.getupvalue or getupvalue
        local setupval = debug and debug.setupvalue or setupvalue
        local getupvals = debug and debug.getupvalues or getupvalues
        if not (getupval and setupval and getupvals) then
            gunFail("debug.getupvalue/setupvalue/getupvalues missing - gun aura off")
            return
        end

        task.spawn(function()
            local RS = game:GetService("ReplicatedStorage")
            local mods = RS:WaitForChild("Modules", 5)
            local net = mods and mods:WaitForChild("Net", 5)
            local ShootGunEvent = net and net:WaitForChild("RE/ShootGunEvent", 5)
            local remotes = RS:WaitForChild("Remotes", 5)
            local Validator2 = remotes and remotes:WaitForChild("Validator2", 5)
            local controllers = RS:WaitForChild("Controllers", 5)
            local combatModule = controllers and controllers:WaitForChild("CombatController", 5)

            if myId ~= startId or not CFG.gun then return end   -- toggled off / restarted while resolving
            if not (ShootGunEvent and Validator2 and combatModule) then
                gunFail("ShootGunEvent, Validator2 or CombatController not found - gun aura off")
                return
            end

            local ShootFunction = nil
            local V_Idx = {v26 = 12, v22 = 13, v25 = 14, v21 = 15, v23 = 16, v24 = 17, v27 = 18}

            local function InitGun()
                local ok, result = pcall(require, combatModule)
                if ok and type(result) == "table" and result.Attack then
                    ShootFunction = getupval(result.Attack, 9)
                end
            end

            local function GetNextValidator()
                if not ShootFunction then InitGun() end
                if not ShootFunction then return 0, 0 end

                local upvals = getupvals(ShootFunction)
                if not upvals then return 0, 0 end

                if upvals[V_Idx.v21] ~= 727595 then
                    for i, v in pairs(upvals) do
                        if v == 727595 then
                            local offset = i - 15
                            V_Idx.v21 = i
                            V_Idx.v22 = 13 + offset
                            V_Idx.v23 = 16 + offset
                            V_Idx.v24 = 17 + offset
                            V_Idx.v26 = 12 + offset
                            V_Idx.v25 = 14 + offset
                            V_Idx.v27 = 18 + offset
                            break
                        end
                    end
                end

                local v1 = getupval(ShootFunction, V_Idx.v21)
                local v2 = getupval(ShootFunction, V_Idx.v22)
                local v3 = getupval(ShootFunction, V_Idx.v23)
                local v4 = getupval(ShootFunction, V_Idx.v24)
                local v5 = getupval(ShootFunction, V_Idx.v25)
                local v6 = getupval(ShootFunction, V_Idx.v26)
                local v7 = getupval(ShootFunction, V_Idx.v27)

                if not (v1 and v2 and v3 and v4 and v5 and v6 and v7) then return 0, 0 end

                local v8 = v6 * v2
                local v9 = (v5 * v2 + v6 * v1) % v3
                v9 = (v9 * v3 + v8) % v4
                v5 = math.floor(v9 / v3)
                v6 = v9 - v5 * v3
                v7 = v7 + 1

                setupval(ShootFunction, V_Idx.v25, v5)
                setupval(ShootFunction, V_Idx.v26, v6)
                setupval(ShootFunction, V_Idx.v27, v7)

                return math.floor(v9 / v4 * 16777215), v7
            end

            -- nearest CFG.gunMaxTargets living Enemies NPCs and players inside CFG.gunRange
            local function GetValidTargets()
                local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                if not myRoot then return {} end
                local myPos = myRoot.Position
                local found = {}

                local enemies = (not CFG.npcCheck) and workspace:FindFirstChild("Enemies") or nil
                if enemies then
                    for _, npc in ipairs(enemies:GetChildren()) do
                        local h = npc:FindFirstChildOfClass("Humanoid")
                        local r = npc:FindFirstChild("HumanoidRootPart")
                        if h and h.Health > 0 and r then
                            local d = (r.Position - myPos).Magnitude
                            if d <= CFG.gunRange then found[#found + 1] = {part = r, distance = d, hum = h} end
                        end
                    end
                end

                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= lp and plr.Character and not isTeammate(plr) then
                        local h = plr.Character:FindFirstChildOfClass("Humanoid")
                        local r = plr.Character:FindFirstChild("HumanoidRootPart")
                        if h and h.Health > 0 and r then
                            local d = (r.Position - myPos).Magnitude
                            if d <= CFG.gunRange then found[#found + 1] = {part = r, distance = d, hum = h} end
                        end
                    end
                end

                table.sort(found, function(a, b) return a.distance < b.distance end)
                local out = {}
                for i = 1, math.min(#found, CFG.gunMaxTargets) do out[i] = found[i].part end
                return out, found
            end

            local cachedCode, cachedCount, cacheUses = 0, 0, 0
            local locked = nil   -- single-target mode: {part, hum} currently being shot

            -- one shot; false = no validator code available, abandon this burst
            local function shoot(tool, part)
                if cacheUses >= CFG.gunCacheShots or cachedCode == 0 then
                    cachedCode, cachedCount = GetNextValidator()
                    cacheUses = 0
                    if cachedCode == 0 then return false end
                end
                if cacheUses == 0 then
                    Validator2:FireServer(cachedCode, cachedCount)
                end
                tool:SetAttribute("LocalTotalShots", (tool:GetAttribute("LocalTotalShots") or 0) + 1)
                ShootGunEvent:FireServer(part.Position, {part})
                cacheUses = cacheUses + 1
                return true
            end

            conn = RunService.Heartbeat:Connect(function()
                if not CFG.gun or env.SyncwareSession ~= session then return end
                pcall(function()
                    local tool = lp.Character and lp.Character:FindFirstChildOfClass("Tool")
                    if not tool or tool.ToolTip ~= "Gun" then return end

                    local targets, entries = GetValidTargets()
                    local n = #targets
                    if n == 0 then locked = nil return end

                    tool:SetAttribute("LocalOverheat", 0)

                    -- single target: whole burst on one enemy until it dies / leaves range, then the next nearest
                    if CFG.gunMode == "single" then
                        local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                        local keep = false
                        if locked and myRoot and locked.part.Parent and locked.hum.Parent and locked.hum.Health > 0 then
                            keep = (locked.part.Position - myRoot.Position).Magnitude <= CFG.gunRange
                        end
                        if not keep then locked = entries[1] end
                        for _ = 1, CFG.gunBurst do
                            if not shoot(tool, locked.part) then return end
                        end
                        return
                    end

                    local per = math.floor(CFG.gunBurst / n)
                    local extra = CFG.gunBurst % n

                    for t = 1, n do
                        for _ = 1, per do
                            if not shoot(tool, targets[t]) then return end
                        end
                    end
                    for e = 1, extra do
                        if not shoot(tool, targets[e]) then return end
                    end
                end)
            end)
        end)
    end

    toggle(susPage, "Gun", "gun", function(v)
        if v then gunStart() else gunStop() end
    end)
    cycle(susPage, "Gun mode", "gunMode", {"spread", "single"})
end

-- NPC check, Auto V3, Auto V4, Anti stun.
-- NPC check is read by ESP, silent aim, Khel Khatam and Gun (Enemies NPCs are skipped when it is on).
-- Race remote / values below are the commonly used Blox Fruits ones, not verified against the current game build.
do
    local lastV3, lastV4, lastV4Log, acc = 0, 0, 0, 0

    local function pressKey(code)
        task.spawn(function()
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendKeyEvent(true, code, false, game)
                task.wait(0.15)
                vim:SendKeyEvent(false, code, false, game)
            end)
        end)
    end

    -- V4 straight through the Awakening tool's RemoteFunction, so the client-side "disable your transformation
    -- first" check on the Y key never runs. Falls back to the Y key if the tool is missing.
    local function fireV4(char)
        task.spawn(function()
            local ok, err = pcall(function()
                local tool = lp.Backpack:FindFirstChild("Awakening") or char:FindFirstChild("Awakening")
                local rf = tool and tool:FindFirstChild("RemoteFunction")
                if not rf then error("Awakening RemoteFunction not found") end
                rf:InvokeServer(true)
            end)
            if not ok then
                warn("[syncware] V4: " .. tostring(err) .. " - falling back to Y")
                pressKey(Enum.KeyCode.Y)
            end
        end)
    end

    on(RunService.Heartbeat, function(dt)
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum) or hum.Health <= 0 then return end

        -- anti stun: every frame
        if CFG.antiStun then
            local st = char:FindFirstChild("Stun")
            if st then
                if st:IsA("BoolValue") then
                    if st.Value then st.Value = false end
                elseif (st:IsA("NumberValue") or st:IsA("IntValue")) and st.Value ~= 0 then
                    st.Value = 0
                end
            end
            local a = char:GetAttribute("Stun")
            if type(a) == "number" and a ~= 0 then char:SetAttribute("Stun", 0) end
        end

        -- race abilities: checked 4x a second
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        if UIS:GetFocusedTextBox() then return end
        local now = os.clock()

        -- V4: fired through the Awakening remote when the gauge is full and V4 is not on; works inside fruit transformations.
        if CFG.autoV4 and now - lastV4 > 2 then
            -- look on the character first, then on the player (the values can live in either while transformed)
            local function val(name) return char:FindFirstChild(name) or lp:FindFirstChild(name, true) end
            local energy = val("RaceEnergy")
            local on4 = val("RaceTransformed")
            local full = energy == nil or energy.Value >= 1   -- values can be hidden while transformed: then just try
            local active = on4 and on4.Value == true
            if full and not active then
                lastV4 = now
                fireV4(char)
                -- diagnostics, at most every 6s: what the script saw when it pressed Y
                if now - lastV4Log > 6 then
                    lastV4Log = now
                    local seen = {}
                    for _, c in ipairs(char:GetChildren()) do
                        local n = c.Name
                        if n:find("Race") or n:find("Transform") or n:find("Stun") then seen[#seen + 1] = n end
                    end
                    warn("[syncware] V4: fired | energy=" .. tostring(energy and energy.Value)
                        .. " transformed=" .. tostring(on4 and on4.Value)
                        .. " | char has: " .. table.concat(seen, ","))
                end
            end
        end

        -- V3: fire the race ability remote on a timer
        if CFG.autoV3 and now - lastV3 >= CFG.autoV3Interval then
            lastV3 = now
            pcall(function()
                game:GetService("ReplicatedStorage").Remotes.CommE:FireServer("ActivateAbility")
            end)
        end
    end)

    toggle(susPage, "NPC check", "npcCheck")
    toggle(susPage, "Auto V3", "autoV3")
    toggle(susPage, "Auto V4", "autoV4")
    toggle(susPage, "Anti stun", "antiStun")
end

-- Orbit: pick a player from the list, switch Orbit on, and the character circles them each Heartbeat
-- (root CFrame, facing the target). Radius / speed / height live in CFG.
do
    local orbitPlayer = nil
    local angle = 0
    local phase = "approach"   -- "approach" = tween in to the ring, "orbit" = circling

    local function orbitStop()
        local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if root then pcall(function() root.AssemblyLinearVelocity = Vector3.zero end) end
    end
    session.orbitStop = orbitStop

    -- aim the approach at the ring point on our side of the target, and restart the tween-in
    local function seedAngle()
        local tRoot = orbitPlayer and orbitPlayer.Character and orbitPlayer.Character:FindFirstChild("HumanoidRootPart")
        local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if tRoot and root then
            local d = root.Position - tRoot.Position
            angle = math.atan2(d.Z, d.X)
        end
        phase = "approach"
    end

    toggle(susPage, "Orbit", "orbit", function(v)
        if v then
            if not orbitPlayer then
                -- nothing to orbit yet: flip back off and open the list
                CFG.orbit = false
                sync("orbit")
                session.orbitOpenList()
                return
            end
            seedAngle()
        else
            orbitStop()
        end
    end)

    slider(susPage, "Orbit distance", "orbitRadius", 3, 100, 1)
    slider(susPage, "Orbit speed", "orbitSpeed", 0.5, 20, 0.5)

    local header = make("TextButton", {
        Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
        AutoButtonColor = false, TextColor3 = THEME.text, Font = Enum.Font.Gotham,
        TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
    }, susPage)
    corner(header, 6)

    local listFrame = make("Frame", {
        Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Visible = false, ZIndex = 2,
    }, susPage)
    make("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, listFrame)

    local function nameOf(p)
        if p.DisplayName ~= p.Name then return p.DisplayName .. " (@" .. p.Name .. ")" end
        return p.Name
    end

    local function refreshHeader()
        header.Text = "Orbit target: " .. (orbitPlayer and nameOf(orbitPlayer) or "none (tap to pick)")
    end

    local function rebuild(skip)
        for _, c in ipairs(listFrame:GetChildren()) do
            if c:IsA("GuiObject") then c:Destroy() end
        end
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and p ~= skip then list[#list + 1] = p end
        end
        table.sort(list, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)

        if #list == 0 then
            make("TextLabel", {
                Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = "no other players in the server",
                TextColor3 = THEME.muted, Font = Enum.Font.Gotham, TextSize = 12, ZIndex = 2,
            }, listFrame)
            return
        end

        for i, p in ipairs(list) do
            local sel = (p == orbitPlayer)
            local b = make("TextButton", {
                Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = sel and THEME.accent or THEME.row,
                BackgroundTransparency = sel and 0 or ROW_T, AutoButtonColor = false,
                Text = "  " .. nameOf(p), TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = sel and Color3.fromRGB(255, 255, 255) or THEME.text,
                Font = Enum.Font.Gotham, TextSize = 12, BorderSizePixel = 0, ZIndex = 2, LayoutOrder = i,
            }, listFrame)
            corner(b, 6)
            b.Activated:Connect(function()
                -- tapping the selected player again clears the selection
                orbitPlayer = (orbitPlayer == p) and nil or p
                if orbitPlayer and CFG.orbit then seedAngle() end
                if not orbitPlayer and CFG.orbit then
                    CFG.orbit = false
                    sync("orbit")
                    orbitStop()
                end
                refreshHeader()
                rebuild()
            end)
        end
    end

    function session.orbitOpenList()
        listFrame.Visible = true
        rebuild()
    end

    on(header.Activated, function()
        listFrame.Visible = not listFrame.Visible
        if listFrame.Visible then rebuild() end
    end)

    on(Players.PlayerAdded, function() if listFrame.Visible then rebuild() end end)
    on(Players.PlayerRemoving, function(p)
        if p == orbitPlayer then
            orbitPlayer = nil
            if CFG.orbit then
                CFG.orbit = false
                sync("orbit")
                orbitStop()
            end
            refreshHeader()
        end
        if listFrame.Visible then rebuild(p) end
    end)

    refreshHeader()

    on(RunService.Heartbeat, function(dt)
        if not CFG.orbit or session.safeActive or session.stickActive then return end
        local tRoot = orbitPlayer and orbitPlayer.Character and orbitPlayer.Character:FindFirstChild("HumanoidRootPart")
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (tRoot and root and hum) or hum.Health <= 0 then return end

        local c = tRoot.Position

        -- approach: close the gap at a capped speed (a straight snap to the ring is what gets rubber-banded)
        if phase == "approach" then
            local goal = c + Vector3.new(math.cos(angle) * CFG.orbitRadius, CFG.orbitHeight, math.sin(angle) * CFG.orbitRadius)
            local delta = goal - root.Position
            local step = CFG.orbitTweenSpeed * dt
            if delta.Magnitude > step + 1 then
                local pos = root.Position + delta.Unit * step
                root.AssemblyLinearVelocity = Vector3.zero
                root.CFrame = CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z))
                return
            end
            phase = "orbit"
        end

        angle = angle + CFG.orbitSpeed * dt
        local pos = c + Vector3.new(math.cos(angle) * CFG.orbitRadius, CFG.orbitHeight, math.sin(angle) * CFG.orbitRadius)
        root.AssemblyLinearVelocity = Vector3.zero
        root.CFrame = CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z))
    end)
end

-- Stick player: its own player list. Pick someone, switch Stick player on: you tween to them, then every
-- Heartbeat your root is placed stickDistance studs behind them (same facing), so you follow wherever they go.
-- Fly and orbit pause while it is active; safe mode still takes priority.
do
    local stickPlayer = nil

    local function stickStop()
        session.stickActive = false
        local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        if root then pcall(function() root.AssemblyLinearVelocity = Vector3.zero end) end
    end
    session.stickStop = stickStop

    toggle(susPage, "Stick player", "stick", function(v)
        if v then
            if not stickPlayer then
                CFG.stick = false
                sync("stick")
                session.stickOpenList()
            end
        else
            stickStop()
        end
    end)
    slider(susPage, "Stick distance", "stickDistance", 0, 15, 1)

    local header = make("TextButton", {
        Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
        AutoButtonColor = false, TextColor3 = THEME.text, Font = Enum.Font.Gotham,
        TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
    }, susPage)
    corner(header, 6)

    local listFrame = make("Frame", {
        Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Visible = false, ZIndex = 2,
    }, susPage)
    make("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, listFrame)

    local function nameOf(p)
        if p.DisplayName ~= p.Name then return p.DisplayName .. " (@" .. p.Name .. ")" end
        return p.Name
    end

    local function refreshHeader()
        header.Text = "Stick target: " .. (stickPlayer and nameOf(stickPlayer) or "none (tap to pick)")
    end

    local function rebuild(skip)
        for _, c in ipairs(listFrame:GetChildren()) do
            if c:IsA("GuiObject") then c:Destroy() end
        end
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and p ~= skip then list[#list + 1] = p end
        end
        table.sort(list, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)

        if #list == 0 then
            make("TextLabel", {
                Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = "no other players in the server",
                TextColor3 = THEME.muted, Font = Enum.Font.Gotham, TextSize = 12, ZIndex = 2,
            }, listFrame)
            return
        end

        for i, p in ipairs(list) do
            local sel = (p == stickPlayer)
            local b = make("TextButton", {
                Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = sel and THEME.accent or THEME.row,
                BackgroundTransparency = sel and 0 or ROW_T, AutoButtonColor = false,
                Text = "  " .. nameOf(p), TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = sel and Color3.fromRGB(255, 255, 255) or THEME.text,
                Font = Enum.Font.Gotham, TextSize = 12, BorderSizePixel = 0, ZIndex = 2, LayoutOrder = i,
            }, listFrame)
            corner(b, 6)
            b.Activated:Connect(function()
                -- tapping the selected player again clears the selection
                stickPlayer = (stickPlayer == p) and nil or p
                if not stickPlayer and CFG.stick then
                    CFG.stick = false
                    sync("stick")
                    stickStop()
                end
                refreshHeader()
                rebuild()
            end)
        end
    end

    function session.stickOpenList()
        listFrame.Visible = true
        rebuild()
    end

    on(header.Activated, function()
        listFrame.Visible = not listFrame.Visible
        if listFrame.Visible then rebuild() end
    end)

    on(Players.PlayerAdded, function() if listFrame.Visible then rebuild() end end)
    on(Players.PlayerRemoving, function(p)
        if p == stickPlayer then
            stickPlayer = nil
            if CFG.stick then
                CFG.stick = false
                sync("stick")
                stickStop()
            end
            refreshHeader()
        end
        if listFrame.Visible then rebuild(p) end
    end)

    refreshHeader()

    on(RunService.Heartbeat, function(dt)
        if not CFG.stick then session.stickActive = false return end
        local tRoot = stickPlayer and stickPlayer.Character and stickPlayer.Character:FindFirstChild("HumanoidRootPart")
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if session.safeActive or not (tRoot and root and hum) or hum.Health <= 0 then
            session.stickActive = false
            return
        end
        session.stickActive = true

        local goalCF = tRoot.CFrame * CFrame.new(0, 0, CFG.stickDistance)
        local delta = goalCF.Position - root.Position
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        -- far away: tween in at stickSpeed; close: lock onto them every frame
        local step = CFG.stickSpeed * dt
        if delta.Magnitude > math.max(step, 6) then
            local pos = root.Position + delta.Unit * step
            root.CFrame = CFrame.lookAt(pos, pos + tRoot.CFrame.LookVector)
        else
            root.CFrame = goalCF
        end
    end)
end

-- fly key box: click, press a key, then that key toggles fly on/off
do
    local flyBinding = false
    local btn = make("TextButton", {
        Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
        AutoButtonColor = false, TextColor3 = THEME.text, Font = Enum.Font.Gotham,
        TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
    }, susPage)
    corner(btn, 6)
    local function refresh()
        btn.Text = flyBinding and "Fly key: press a key..." or ("Fly key: " .. tostring(CFG.flyKey))
    end
    refresh()
    applyers.flyKey = function(v)
        if type(v) == "string" then CFG.flyKey = v flyBinding = false refresh() end
    end

    on(btn.Activated, function()
        flyBinding = true
        refresh()
    end)

    on(UIS.InputBegan, function(i, gp)
        if flyBinding then
            if i.UserInputType == Enum.UserInputType.Keyboard or i.UserInputType.Name:find("MouseButton") then
                -- ignore the click that started binding
                if i.UserInputType == Enum.UserInputType.MouseButton1 and gp then return end
                if i.KeyCode ~= Enum.KeyCode.Escape then
                    CFG.flyKey = inputName(i)
                end
                flyBinding = false
                refresh()
            end
            return
        end
        if not gp and not UIS:GetFocusedTextBox() and inputName(i) == CFG.flyKey then
            CFG.fly = not CFG.fly
            sync("fly")
            if not CFG.fly then flyStop() end
        end
    end)
end

-- Safe mode: below CFG.safeHP percent HP, tween straight up CFG.safeHeight studs and hold there (fly/orbit pause).
-- Once HP is safeRecover above the threshold it tweens back to the spot it left from. Turning it off mid-escape
-- also returns you.
do
    local state = "idle"   -- idle | up | hold | down
    local home, sky

    local function stepTo(root, pos, dt)
        local cur = root.Position
        local delta = pos - cur
        local step = CFG.safeSpeed * dt
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        if delta.Magnitude <= step then
            root.CFrame = CFrame.new(pos) * (root.CFrame - root.Position)
            return true
        end
        root.CFrame = CFrame.new(cur + delta.Unit * step) * (root.CFrame - root.Position)
        return false
    end

    function session.safeStop()
        state = "idle"
        session.safeActive = false
    end

    on(RunService.Heartbeat, function(dt)
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (root and hum) or hum.Health <= 0 then
            state = "idle"
            session.safeActive = false
            return
        end

        local limitHP = hum.MaxHealth * CFG.safeHP / 100
        local low = hum.Health < limitHP
        -- back down only after healing safeRecover above the threshold (capped at max HP so it stays reachable)
        local recovered = hum.Health >= math.min(hum.MaxHealth, limitHP + CFG.safeRecover)

        if state == "idle" then
            if CFG.safeMode and low then
                home = root.Position
                sky = home + Vector3.new(0, CFG.safeHeight, 0)
                state = "up"
            end
        elseif state == "up" or state == "hold" then
            if not CFG.safeMode or recovered then state = "down" end
        elseif state == "down" then
            if CFG.safeMode and low then state = "up" end
        end

        session.safeActive = state ~= "idle"
        if state == "up" then
            if stepTo(root, sky, dt) then state = "hold" end
        elseif state == "hold" then
            stepTo(root, sky, dt)
        elseif state == "down" then
            if stepTo(root, home, dt) then
                state = "idle"
                session.safeActive = false
            end
        end
    end)

    toggle(susPage, "Safe mode", "safeMode")
    slider(susPage, "Safe HP %", "safeHP", 5, 95, 1)
    slider(susPage, "Heal above", "safeRecover", 0, 10000, 100)
    slider(susPage, "Safe height", "safeHeight", 500, 10000, 100)
end

-- Others tab
local othersPage = newPage("Others")
do
    local armedAt = 0
    local busy = false
    local btn = make("TextButton", {
        Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
        AutoButtonColor = false, Text = "Reset stats", TextColor3 = THEME.text, Font = Enum.Font.Gotham,
        TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
    }, othersPage)
    corner(btn, 6)
    local status = make("TextLabel", {
        Size = UDim2.new(1, -6, 0, 44), BackgroundTransparency = 1, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        Text = "Costs 2,500 Fragments. Click twice to confirm.",
        TextColor3 = THEME.muted, Font = Enum.Font.Gotham, TextSize = 12, ZIndex = 2,
    }, othersPage)

    local function say(t) status.Text = t end

    local function teamButton(team)
        local b = make("TextButton", {
            Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
            AutoButtonColor = false, Text = "Join " .. team, TextColor3 = THEME.text, Font = Enum.Font.Gotham,
            TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
        }, othersPage)
        corner(b, 6)
        on(b.Activated, function()
            task.spawn(function()
                local ok, r = pcall(function()
                    local rem = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 5)
                    local commF = rem and rem:WaitForChild("CommF_", 5)
                    if not commF then error("Remotes.CommF_ not found") end
                    return commF:InvokeServer("SetTeam", team)
                end)
                if ok then
                    say("Team " .. team .. ": " .. tostring(r))
                    print("[syncware] SetTeam", team, "->", r)
                else
                    say("Team change failed: " .. tostring(r))
                    warn("[syncware] SetTeam failed - " .. tostring(r))
                end
            end)
        end)
    end

    -- CommF_ "BlackbeardReward","Refund","1" asks, "2" does it (the stat-refund NPC's calls). Return values are shown
    -- so a changed build is visible instead of failing silently.
    on(btn.Activated, function()
        if busy then return end
        if os.clock() - armedAt > 4 then
            armedAt = os.clock()
            btn.Text = "Click again to confirm (2,500 Fragments)"
            task.delay(4, function()
                if os.clock() - armedAt >= 4 then btn.Text = "Reset stats" end
            end)
            return
        end
        armedAt = 0
        btn.Text = "Reset stats"
        busy = true
        task.spawn(function()
            local ok, err = pcall(function()
                local rem = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 5)
                local commF = rem and rem:WaitForChild("CommF_", 5)
                if not commF then error("Remotes.CommF_ not found") end
                local r1 = commF:InvokeServer("BlackbeardReward", "Refund", "1")
                local r2 = commF:InvokeServer("BlackbeardReward", "Refund", "2")
                say("Check: " .. tostring(r1) .. " | Reset: " .. tostring(r2))
                print("[syncware] reset stats - check:", r1, "reset:", r2)
            end)
            if not ok then
                say("Reset failed: " .. tostring(err))
                warn("[syncware] reset stats failed - " .. tostring(err))
            end
            busy = false
        end)
    end)

    make("TextLabel", {
        Size = UDim2.new(1, -6, 0, 18), BackgroundTransparency = 1, Text = "Team",
        TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.muted,
        Font = Enum.Font.GothamBold, TextSize = 12, ZIndex = 2,
    }, othersPage)
    teamButton("Marines")
    teamButton("Pirates")
end

-- Configs tab: save every setting to Syncware/configs/<name>.json, load it later, and pick one to autoload on execute.
-- Loading goes through the same controls (applyers), so toggles, sliders and the color wheel update and run their effects.
-- Not saved: Orbit (it needs a player picked each session).
do
    local HttpService = game:GetService("HttpService")
    local DIR, AUTO = "Syncware/configs", "Syncware/autoload.txt"
    local cfgPage = newPage("Configs")

    local fsOk = type(writefile) == "function" and type(readfile) == "function"
        and type(listfiles) == "function" and type(isfile) == "function"
        and type(isfolder) == "function" and type(makefolder) == "function"

    if not fsOk then
        warn("[syncware] writefile/readfile/listfiles/isfile/isfolder/makefolder missing - configs unavailable")
        make("TextLabel", {
            Size = UDim2.new(1, -6, 0, 48), BackgroundTransparency = 1, TextWrapped = true,
            Text = "Configs need writefile, readfile, listfiles, isfile, isfolder and makefolder, which this executor lacks.",
            TextColor3 = Color3.fromRGB(196, 108, 20), Font = Enum.Font.Gotham, TextSize = 12, ZIndex = 2,
        }, cfgPage)
    else
        local selected = nil

        local function sanitize(str)
            str = tostring(str or ""):gsub("[^%w_%- ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
            return str:sub(1, 32)
        end

        local function ensureDirs()
            if not isfolder("Syncware") then makefolder("Syncware") end
            if not isfolder(DIR) then makefolder(DIR) end
        end

        local function pathOf(name) return DIR .. "/" .. name .. ".json" end

        local function listNames()
            ensureDirs()
            local names = {}
            local ok, files = pcall(listfiles, DIR)
            if ok and type(files) == "table" then
                for _, f in ipairs(files) do
                    local n = tostring(f):match("([^/\\]+)%.json$")
                    if n then names[#names + 1] = n end
                end
            end
            table.sort(names, function(a, b) return a:lower() < b:lower() end)
            return names
        end

        local function getAutoload()
            if isfile(AUTO) then
                local ok, t = pcall(readfile, AUTO)
                if ok then
                    t = sanitize(t)
                    if t ~= "" then return t end
                end
            end
            return nil
        end

        local function snapshot()
            local out = {}
            for k, v in pairs(CFG) do
                if k ~= "orbit" then
                    if typeof(v) == "Color3" then
                        out[k] = {
                            r = math.floor(v.R * 255 + 0.5),
                            g = math.floor(v.G * 255 + 0.5),
                            b = math.floor(v.B * 255 + 0.5),
                        }
                    elseif type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
                        out[k] = v
                    end
                end
            end
            return out
        end

        local function applyConfig(data)
            local keys = {}
            for k in pairs(data) do
                if k ~= "orbit" and CFG[k] ~= nil then keys[#keys + 1] = k end
            end
            table.sort(keys)   -- fpsBoost sorts before fpsSuper, which the FPS toggles rely on
            local n = 0
            for _, k in ipairs(keys) do
                local v, cur = data[k], CFG[k]
                if typeof(cur) == "Color3" then
                    if type(v) == "table" and type(v.r) == "number" and type(v.g) == "number" and type(v.b) == "number" then
                        v = Color3.fromRGB(math.clamp(v.r, 0, 255), math.clamp(v.g, 0, 255), math.clamp(v.b, 0, 255))
                    else
                        v = nil
                    end
                elseif type(v) ~= type(cur) then
                    v = nil
                end
                if v ~= nil then
                    local ok, err = pcall(function()
                        if applyers[k] then applyers[k](v) else CFG[k] = v end
                    end)
                    if ok then n = n + 1 else warn("[syncware] config: could not apply " .. k .. " - " .. tostring(err)) end
                end
            end
            return n
        end

        local function loadConfig(name)
            local path = pathOf(name)
            if not isfile(path) then return nil, "no config named " .. name end
            local okR, raw = pcall(readfile, path)
            if not okR then return nil, "could not read " .. name end
            local okJ, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if not okJ or type(data) ~= "table" then return nil, name .. " is not a valid config" end
            return applyConfig(data)
        end

        -- widgets
        local box = make("TextBox", {
            Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
            Text = "", PlaceholderText = "config name", PlaceholderColor3 = Color3.fromRGB(120, 120, 130),
            ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = THEME.text, Font = Enum.Font.Gotham, TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
        }, cfgPage)
        corner(box, 6)
        make("UIPadding", {PaddingLeft = UDim.new(0, 8)}, box)

        local status
        local function say(t) status.Text = t end

        local listFrame
        local function refreshList()
            for _, c in ipairs(listFrame:GetChildren()) do
                if c:IsA("GuiObject") then c:Destroy() end
            end
            local names = listNames()
            local auto = getAutoload()
            if #names == 0 then
                make("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = "no saved configs yet",
                    TextColor3 = THEME.muted, Font = Enum.Font.Gotham, TextSize = 12, ZIndex = 2,
                }, listFrame)
                return
            end
            for i, name in ipairs(names) do
                local sel = (name == selected)
                local b = make("TextButton", {
                    Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = sel and THEME.accent or THEME.row,
                    BackgroundTransparency = sel and 0 or ROW_T, AutoButtonColor = false,
                    Text = "  " .. name .. (name == auto and "   (autoload)" or ""),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextColor3 = sel and Color3.fromRGB(255, 255, 255) or THEME.text,
                    Font = Enum.Font.Gotham, TextSize = 12, BorderSizePixel = 0, ZIndex = 2, LayoutOrder = i,
                }, listFrame)
                corner(b, 6)
                b.Activated:Connect(function()
                    selected = name
                    box.Text = name
                    refreshList()
                end)
            end
        end

        -- which config an action means: the name typed in the box, else the highlighted row
        local function target()
            local n = sanitize(box.Text)
            if n == "" then n = selected or "" end
            return n
        end

        local function button(text, fn)
            local b = make("TextButton", {
                Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = THEME.row, BackgroundTransparency = ROW_T,
                AutoButtonColor = false, Text = text, TextColor3 = THEME.text, Font = Enum.Font.Gotham,
                TextSize = 13, BorderSizePixel = 0, ZIndex = 2,
            }, cfgPage)
            corner(b, 6)
            on(b.Activated, function()
                local ok, err = pcall(fn)
                if not ok then say("error: " .. tostring(err)) end
            end)
            return b
        end

        button("Save", function()
            local name = target()
            if name == "" then say("type a config name first") return end
            ensureDirs()
            writefile(pathOf(name), HttpService:JSONEncode(snapshot()))
            selected = name
            box.Text = name
            say("Saved " .. name)
            refreshList()
        end)

        button("Load", function()
            local name = target()
            if name == "" then say("pick or type a config name") return end
            local n, err = loadConfig(name)
            if n then say("Loaded " .. name .. " (" .. n .. " settings)") else say(err) end
        end)

        if type(delfile) == "function" then
            button("Delete", function()
                local name = target()
                if name == "" then say("pick or type a config name") return end
                if not isfile(pathOf(name)) then say("no config named " .. name) return end
                delfile(pathOf(name))
                if getAutoload() == name then writefile(AUTO, "") end
                if selected == name then selected = nil end
                say("Deleted " .. name)
                refreshList()
            end)
        end

        button("Set autoload", function()
            local name = target()
            if name == "" then say("pick or type a config name") return end
            if not isfile(pathOf(name)) then say("save " .. name .. " first") return end
            ensureDirs()
            writefile(AUTO, name)
            say("Autoload: " .. name)
            refreshList()
        end)

        button("Clear autoload", function()
            ensureDirs()
            writefile(AUTO, "")
            say("Autoload cleared")
            refreshList()
        end)

        status = make("TextLabel", {
            Size = UDim2.new(1, -6, 0, 30), BackgroundTransparency = 1, TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, Text = "",
            TextColor3 = THEME.accent, Font = Enum.Font.Gotham, TextSize = 12, ZIndex = 2,
        }, cfgPage)

        make("TextLabel", {
            Size = UDim2.new(1, -6, 0, 18), BackgroundTransparency = 1, Text = "Saved configs",
            TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = THEME.muted,
            Font = Enum.Font.GothamBold, TextSize = 12, ZIndex = 2,
        }, cfgPage)

        listFrame = make("Frame", {
            Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1, ZIndex = 2,
        }, cfgPage)
        make("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, listFrame)

        pcall(refreshList)

        -- autoload: runs once, right after every control exists
        local auto = getAutoload()
        if auto then
            local ok, n, err = pcall(loadConfig, auto)
            if ok and n then
                say("Autoloaded " .. auto .. " (" .. n .. " settings)")
            else
                warn("[syncware] autoload failed - " .. tostring(ok and err or n))
                say("Autoload failed: " .. tostring(ok and err or n))
            end
        end
    end
end

-- light theme: hairline border on every white row
for _, o in ipairs(win:GetDescendants()) do
    if o:IsA("GuiObject") and o.BackgroundColor3 == THEME.row and o.BackgroundTransparency < 1
        and o.Size.Y.Offset >= 24 and not o:FindFirstChildOfClass("UIStroke") then
        make("UIStroke", {Color = THEME.stroke, Thickness = 1}, o)
        if o:IsA("TextButton") then
            o.MouseEnter:Connect(function() tween(o, 0.1, {BackgroundColor3 = Color3.fromRGB(240, 242, 250)}) end)
            o.MouseLeave:Connect(function() tween(o, 0.1, {BackgroundColor3 = THEME.row}) end)
        end
    end
end

showPage("ESP")
setOpen(true)

------------------------------------------------------------------
-- Hooks (last, wrapped so a missing executor function can't break the UI)
------------------------------------------------------------------
local function active() return env.SyncwareSession == session end

local hooksOk = false
if hookmetamethod and newcclosure and checkcaller and getnamecallmethod then
    hooksOk = pcall(function()
        local oldIndex
        oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if target and active() and not checkcaller() and self == mouse then
                if key == "Hit" then
                    return CFrame.new(target.Position)
                elseif key == "Target" then
                    return target
                end
            end
            return oldIndex(self, key)
        end))

        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if target and active() and not checkcaller() and self == workspace then
                local method = getnamecallmethod()
                local args = {...}
                if method == "Raycast" and typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
                    args[2] = (target.Position - args[1]).Unit * args[2].Magnitude
                    return oldNamecall(self, unpack(args))
                elseif (method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList"
                    or method == "FindPartOnRayWithWhitelist") and typeof(args[1]) == "Ray" then
                    local r = args[1]
                    args[1] = Ray.new(r.Origin, (target.Position - r.Origin).Unit * r.Direction.Magnitude)
                    return oldNamecall(self, unpack(args))
                end
            end
            return oldNamecall(self, ...)
        end))
    end)
end

if not hooksOk then
    warn("[syncware] hookmetamethod/newcclosure/checkcaller missing - silent aim inactive")
    make("TextLabel", {
        Size = UDim2.new(1, -6, 0, 32), BackgroundTransparency = 1, TextWrapped = true,
        Text = "Silent aim hooks unavailable on this executor.", TextColor3 = Color3.fromRGB(200, 60, 60),
        Font = Enum.Font.Gotham, TextSize = 12, ZIndex = 2,
    }, aimPage)
end
if not hasDrawing then
    warn("[syncware] Drawing library missing - ESP boxes and FOV circle inactive")
end
if not dollarAsset then
    warn("[syncware] writefile/getcustomasset missing - using a text $ instead of the image")
end
if not logoAsset then
    warn("[syncware] writefile/getcustomasset missing - using the drawn logo instead of the image")
end

env.SyncwareUnload = function()
    env.SyncwareSession = nil
    target = nil
    holding = false
    binding = false
    pcall(fpsRestore)
    CFG.fly = false
    pcall(flyStop)
    CFG.noclip = false
    pcall(session.noclipRestore)
    CFG.khelKhatam = false
    pcall(session.khelStop)
    CFG.gun = false
    pcall(session.gunStop)
    CFG.orbit = false
    pcall(session.orbitStop)
    CFG.safeMode = false
    pcall(session.safeStop)
    CFG.stick = false
    pcall(session.stickStop)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, d in ipairs(drawings) do pcall(function() d:Remove() end) end
    pcall(function() gui:Destroy() end)
end
