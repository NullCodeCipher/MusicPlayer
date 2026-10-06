--[[
    ORBITUNE
    Massive Upgrade / V2

    Features:
    - Music scanning
    - MP3 / OGG / WAV
    - Recursive folders
    - Playlist browser
    - Search
    - Spectrum visualizer
    - Loudness visualizer
    - Random visualizer
    - Rainbow mode
    - Shuffle
    - Repeat: Off / All / One
    - Previous / Next
    - Smart previous-track behavior
    - Progress seeking
    - Volume control
    - EQ presets
    - UI scaling
    - Hide keybind
    - PC dragging
    - Mobile dragging
    - Mobile playlist scrolling
    - Persistent settings
    - Cover art
    - Preloading
    - Safer asset loading
    - Duplicate GUI protection
    - Better cleanup
    - Keyboard shortcuts
    - Smooth animations
]]

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------

local MAX_DEPTH = 3

local EXTENSIONS = {
    mp3 = true,
    ogg = true,
    wav = true,
}

local IMAGE_EXTENSIONS = {
    png = true,
    jpg = true,
    jpeg = true,
    webp = true,
}

local BASE = "iamosulazer"
local ICONS = BASE .. "/icons"

local STATE_FILE = BASE .. "/Last State.txt"
local FALLBACK = BASE .. "/fallback.png"

local SAMPLE_DIR = BASE .. "/Your Playlist"
local SAMPLE_SONG = SAMPLE_DIR .. "/Bad Apple.ogg"

local FALLBACK_URL =
    "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/osu.png"

local SAMPLE_URL =
    "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/Bad%20Apple.ogg"

local ICON_SCALE = 0.6

local ICON_FILES = {
    prev = {
        ICONS .. "/prev.png",
        "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/previous.png"
    },

    play = {
        ICONS .. "/play.png",
        "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/play.png"
    },

    pause = {
        ICONS .. "/pause.png",
        "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/pause.png"
    },

    next = {
        ICONS .. "/next.png",
        "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/next.png"
    },

    record = {
        ICONS .. "/record.png",
        "https://raw.githubusercontent.com/3-7x/CoolOsuThing/refs/heads/main/disc.png"
    },
}

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local RS = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")
local TXT = game:GetService("TextService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer

----------------------------------------------------------------
-- DUPLICATE PROTECTION
----------------------------------------------------------------

pcall(function()
    local old = Player:WaitForChild("PlayerGui"):FindFirstChild("Orbitune")

    if old then
        old:Destroy()
    end
end)

pcall(function()
    local old = workspace:FindFirstChild("OrbituneAudio")

    if old then
        old:Destroy()
    end
end)

----------------------------------------------------------------
-- FILESYSTEM
----------------------------------------------------------------

local function mkdir(path)
    if not isfolder(path) then
        pcall(makefolder, path)
    end
end

local function safeIsFile(path)
    local ok, result = pcall(isfile, path)
    return ok and result == true
end

local function safeIsFolder(path)
    local ok, result = pcall(isfolder, path)
    return ok and result == true
end

local function safeWrite(path, data)
    return pcall(writefile, path, data)
end

local function safeRead(path)
    local ok, result = pcall(readfile, path)

    if ok then
        return result
    end

    return nil
end

local function fetch(path, url, png)
    if safeIsFile(path) then
        return true
    end

    local ok = pcall(function()
        local data = game:HttpGet(url)

        if png then
            assert(data:sub(2, 4) == "PNG")
        else
            assert(#data > 4096)
        end

        writefile(path, data)
    end)

    return ok
end

local firstRun = not safeIsFolder(BASE)

mkdir(BASE)
mkdir(ICONS)

if not safeIsFile(STATE_FILE) then
    safeWrite(STATE_FILE, "{}")
end

fetch(FALLBACK, FALLBACK_URL, true)

if firstRun then
    mkdir(SAMPLE_DIR)
    fetch(SAMPLE_SONG, SAMPLE_URL)
end

----------------------------------------------------------------
-- ICON CACHE
----------------------------------------------------------------

local ICON = {}

for key, info in ICON_FILES do
    ICON[key] = ""

    if fetch(info[1], info[2], true) then
        pcall(function()
            ICON[key] = getcustomasset(info[1])
        end)
    end
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

local State = {}

pcall(function()
    local raw = safeRead(STATE_FILE)

    if raw then
        State = HttpService:JSONDecode(raw)
    end
end)

if type(State) ~= "table" then
    State = {}
end

local function saveState()
    pcall(function()
        safeWrite(
            STATE_FILE,
            HttpService:JSONEncode(State)
        )
    end)
end

----------------------------------------------------------------
-- CONFIGURATION
----------------------------------------------------------------

local Cfg = {
    rainbow = State.rainbow == true,

    mode = State.mode or "Spectrum",

    showName = State.showName ~= false,

    showTime = State.showTime ~= false,

    scale = tonumber(State.scale) or 1,

    volume = math.clamp(
        tonumber(State.volume) or 1,
        0,
        10
    ),

    shuffle = State.shuffle == true,

    repeatMode = State.repeatMode or "Off",

    rotation = State.rotation ~= false,

    animations = State.animations ~= false,
}

----------------------------------------------------------------
-- COLLECTION / CONNECTION MANAGEMENT
----------------------------------------------------------------

local collection = {}
local connections = {}

local function trackObject(object)
    collection[#collection + 1] = object
    return object
end

local function make(class, parent, props)
    local object = Instance.new(class)

    if props then
        for property, value in props do
            pcall(function()
                object[property] = value
            end)
        end
    end

    object.Parent = parent

    return trackObject(object)
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)

    connections[#connections + 1] = connection

    return connection
end

local function cleanup()
    pcall(function()
        CAS:UnbindAction("OrbituneWheel")
    end)

    for _, connection in connections do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(connections)

    for i = #collection, 1, -1 do
        pcall(function()
            collection[i]:Destroy()
        end)

        collection[i] = nil
    end
end

----------------------------------------------------------------
-- ANIMATION HELPERS
----------------------------------------------------------------

local function tween(object, duration, properties, style, direction)
    if not object or not object.Parent then
        return
    end

    local info = TweenInfo.new(
        duration,
        style or Enum.EasingStyle.Quad,
        direction or Enum.EasingDirection.Out
    )

    local tweenObject = TS:Create(
        object,
        info,
        properties
    )

    tweenObject:Play()

    return tweenObject
end

local function ease(x)
    return 1 - (1 - x) ^ 3
end

----------------------------------------------------------------
-- TABLE HELPERS
----------------------------------------------------------------

local function shuffle(tableObject)
    for i = #tableObject, 2, -1 do
        local j = math.random(i)

        tableObject[i], tableObject[j] =
            tableObject[j], tableObject[i]
    end
end

local function norm(path)
    return path
        :gsub("\\", "/")
        :gsub("/+$", "")
end

----------------------------------------------------------------
-- SONG SCANNER
----------------------------------------------------------------

local categories = {}
local songs = {}

local SKIP = {
    icons = true,
}

local function scanDir(dir, depth)
    if depth > MAX_DEPTH then
        return
    end

    local ok, files = pcall(listfiles, dir)

    if not ok or type(files) ~= "table" then
        if dir == "" then
            ok, files = pcall(listfiles, ".")
        end
    end

    if not ok or type(files) ~= "table" then
        return
    end

    local musicFiles = {}
    local directories = {}
    local covers = {}

    for _, path in files do
        local folder = safeIsFolder(path)

        if folder then
            local last = norm(path):match("([^/]+)$")

            if not (last and SKIP[last:lower()]) then
                directories[#directories + 1] = path
            end
        else
            local ext = path:match("%.([^%.]+)$")

            if ext then
                ext = ext:lower()
            end

            if ext and EXTENSIONS[ext] then
                local name =
                    path:match("([^/\\]+)%.[^%.]+$")

                musicFiles[#musicFiles + 1] = {
                    path = path,
                    name = name or "Unknown",
                    dir = dir,
                }

            elseif
                dir ~= ""
                and ext
                and IMAGE_EXTENSIONS[ext]
            then
                covers[#covers + 1] = path
            end
        end
    end

    if #musicFiles > 0 then
        shuffle(musicFiles)

        local label = norm(dir)

        if label == "" then
            label = "workspace"
        elseif label:sub(1, #BASE + 1) == BASE .. "/" then
            label = label:sub(#BASE + 2)
        end

        local category = {
            dir = dir,
            label = label,
            songs = musicFiles,
            covers = covers,
        }

        categories[#categories + 1] = category

        for _, song in musicFiles do
            songs[#songs + 1] = song
            song.idx = #songs
            song.category = category
        end
    end

    if depth < MAX_DEPTH then
        for _, directory in directories do
            scanDir(directory, depth + 1)
        end
    end
end

scanDir(
    getgenv().ScanWholeWorkspace and "" or BASE,
    0
)

----------------------------------------------------------------
-- LAST SONG
----------------------------------------------------------------

local lastSong

for _, song in songs do
    if song.path == State.lastSong then
        lastSong = song
        break
    end
end

----------------------------------------------------------------
-- ASSET HELPERS
----------------------------------------------------------------

local function asset(path)
    local ok, result = pcall(
        getcustomasset,
        path
    )

    if ok then
        return result
    end

    return ""
end

local defaultCover =
    safeIsFile(FALLBACK)
    and asset(FALLBACK)
    or ""

local function audioOf(song)
    if not song then
        return ""
    end

    if song.audio then
        return song.audio
    end

    local ok, result = pcall(
        getcustomasset,
        song.path
    )

    if ok then
        song.audio = result
        return result
    end

    return ""
end

local function coverOf(song)
    if not song then
        return defaultCover
    end

    if not song.playlistImages then
        song.playlistImages =
            song.category
            and song.category.covers
            or {}
    end

    local images = song.playlistImages

    if images and #images > 0 then
        for _ = 1, math.min(3, #images) do
            local path = images[math.random(#images)]

            if safeIsFile(path) then
                local result = asset(path)

                if result ~= "" then
                    return result
                end
            end
        end
    end

    return defaultCover
end

----------------------------------------------------------------
-- AUDIO ENGINE
----------------------------------------------------------------

local AudioFolder = make(
    "Folder",
    workspace,
    {
        Name = "OrbituneAudio",
    }
)

local AudioPlayer = make(
    "AudioPlayer",
    AudioFolder,
    {
        Looping = false,
        Volume = Cfg.volume,
    }
)

local Analyzer = make(
    "AudioAnalyzer",
    AudioFolder,
    {
        SpectrumEnabled = true,
        WindowSize = Enum.AudioWindowSize.Medium,
    }
)

make(
    "Wire",
    Analyzer,
    {
        SourceInstance = AudioPlayer,
        TargetInstance = Analyzer,
    }
)

local Equalizer = make(
    "AudioEqualizer",
    AudioFolder
)

make(
    "Wire",
    Equalizer,
    {
        SourceInstance = AudioPlayer,
        TargetInstance = Equalizer,
    }
)

local Output = make(
    "AudioDeviceOutput",
    AudioFolder
)

make(
    "Wire",
    Output,
    {
        SourceInstance = Equalizer,
        TargetInstance = Output,
    }
)

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------

local Gui = make(
    "ScreenGui",
    Player:WaitForChild("PlayerGui"),
    {
        Name = "Orbitune",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 999,
    }
)

local Holder = make(
    "Frame",
    Gui,
    {
        Name = "Holder",
        Size = UDim2.fromOffset(380, 380),
        Position = UDim2.fromScale(.5, .5),
        AnchorPoint = Vector2.new(.5, .5),
        BackgroundTransparency = 1,
    }
)

local HolderScale = make(
    "UIScale",
    Holder,
    {
        Scale = Cfg.scale,
    }
)

----------------------------------------------------------------
-- MAIN CIRCLE
----------------------------------------------------------------

local Circle = make(
    "Frame",
    Holder,
    {
        Name = "Circle",
        Size = UDim2.fromOffset(150, 150),
        Position = UDim2.fromScale(.5, .5),
        AnchorPoint = Vector2.new(.5, .5),
        BackgroundColor3 = Color3.fromRGB(18, 18, 24),
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }
)

make(
    "UICorner",
    Circle,
    {
        CornerRadius = UDim.new(1, 0),
    }
)

make(
    "UIStroke",
    Circle,
    {
        Thickness = 2,
        Color = Color3.new(1, 1, 1),
        Transparency = .8,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }
)

----------------------------------------------------------------
-- COVER
----------------------------------------------------------------

local Cover = make(
    "ImageLabel",
    Circle,
    {
        Name = "Cover",
        Image = lastSong and coverOf(lastSong) or defaultCover,
        AnchorPoint = Vector2.new(.5, .5),
        Position = UDim2.fromScale(.5, .5),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Crop,
    }
)

make(
    "UICorner",
    Cover,
    {
        CornerRadius = UDim.new(1, 0),
    }
)

----------------------------------------------------------------
-- VISUALIZER
----------------------------------------------------------------

local SENS = 12
local COUNT = 96
local INNER = 82
local MINL = 3
local MAXL = 120
local BARW = 3

local BarsFolder = make(
    "Frame",
    Holder,
    {
        Name = "Bars",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }
)

local Bars = {}

local function setBar(bar, length)
    local c =
        bar.Dir *
        (INNER + length / 2)

    bar.Frame.Size =
        UDim2.fromOffset(
            BARW,
            length
        )

    bar.Frame.Position =
        UDim2.new(
            .5,
            c.X,
            .5,
            c.Y
        )
end

for i = 1, COUNT do
    local angle =
        math.rad(
            30 -
            (
                -30 +
                (i - 1) /
                (COUNT - 1) *
                300
            )
        )

    local frame = make(
        "Frame",
        BarsFolder,
        {
            Name = "Bar" .. i,
            AnchorPoint = Vector2.new(.5, .5),
            Rotation = math.deg(angle) + 90,
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
        }
    )

    make(
        "UICorner",
        frame,
        {
            CornerRadius = UDim.new(1, 0),
        }
    )

    Bars[i] = {
        Frame = frame,
        Dir = Vector2.new(
            math.cos(angle),
            math.sin(angle)
        ),
    }

    setBar(
        Bars[i],
        MINL
    )
end

----------------------------------------------------------------
-- VISUALIZER LOOP
----------------------------------------------------------------

task.spawn(function()
    local smooth = table.create(COUNT, 0)
    local randomValues = table.create(COUNT, 0)

    local elapsed = 0
    local randomTimer = 0

    while Gui.Parent do
        local dt = RS.RenderStepped:Wait()

        elapsed += dt

        local mode = Cfg.mode

        local spectrum

        if mode == "Spectrum" then
            local ok, result =
                pcall(
                    Analyzer.GetSpectrum,
                    Analyzer
                )

            if ok then
                spectrum = result
            end
        end

        local spectrumCount =
            spectrum
            and #spectrum
            or 0

        local loudness = 0

        if mode == "Loudness" then
            loudness =
                math.clamp(
                    Analyzer.RmsLevel * 3.5,
                    0,
                    1
                )
        end

        if mode == "Random" then
            randomTimer -= dt

            if randomTimer <= 0 then
                randomTimer = .09

                local amp =
                    playing and 1 or 0

                for i = 1, COUNT do
                    randomValues[i] =
                        math.random() * amp
                end
            end
        end

        local smoothing =
            math.clamp(
                dt * 10,
                .08,
                .3
            )

        for i, bar in Bars do
            local value = 0

            if mode == "Spectrum" then
                if spectrumCount > 0 then
                    local index =
                        math.floor(
                            (i - 1) /
                            COUNT *
                            spectrumCount
                        ) + 1

                    value =
                        math.clamp(
                            (
                                spectrum[index]
                                or 0
                            ) * SENS,
                            0,
                            1
                        )
                end

            elseif mode == "Loudness" then
                value =
                    loudness *
                    (
                        .8 +
                        .2 *
                        math.sin(
                            elapsed * 6 +
                            i * .3
                        )
                    )

            elseif mode == "Random" then
                value =
                    randomValues[i]
                    or 0
            end

            smooth[i] +=
                (
                    value -
                    smooth[i]
                ) *
                smoothing

            setBar(
                bar,
                MINL +
                (
                    MAXL -
                    MINL
                ) *
                smooth[i]
            )

            if Cfg.rainbow then
                bar.Frame.BackgroundColor3 =
                    Color3.fromHSV(
                        (
                            elapsed * .15 +
                            i / COUNT
                        ) % 1,
                        .75,
                        1
                    )
            else
                bar.Frame.BackgroundColor3 =
                    Color3.new(1, 1, 1)
            end
        end
    end
end)

----------------------------------------------------------------
-- DRAG SYSTEM
----------------------------------------------------------------

local dragging = false
local dragStart
local startPosition
local dragMoved = false

local function beginDrag(input)
    dragging = true
    dragMoved = false

    dragStart = input.Position
    startPosition = Holder.Position
end

local function updateDrag(input)
    if not dragging then
        return
    end

    local delta =
        input.Position -
        dragStart

    if delta.Magnitude > 6 then
        dragMoved = true
    end

    Holder.Position =
        UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
end

connect(
    Circle.InputBegan,
    function(input)
        if
            input.UserInputType ==
            Enum.UserInputType.MouseButton1
            or
            input.UserInputType ==
            Enum.UserInputType.Touch
        then
            beginDrag(input)
        end
    end
)

connect(
    UIS.InputChanged,
    function(input)
        if
            input.UserInputType ==
            Enum.UserInputType.MouseMovement
            or
            input.UserInputType ==
            Enum.UserInputType.Touch
        then
            updateDrag(input)
        end
    end
)

connect(
    UIS.InputEnded,
    function(input)
        if
            input.UserInputType ==
            Enum.UserInputType.MouseButton1
            or
            input.UserInputType ==
            Enum.UserInputType.Touch
        then
            dragging = false
        end
    end
)

----------------------------------------------------------------
-- COLORS
----------------------------------------------------------------

local R = 75
local Ri = R * .92
local D = Ri * .62

local BORDER = 2
local GAP = 2

local cx = R
local cy = R

local ACCENT_A =
    Color3.fromRGB(
        140,
        100,
        255
    )

local ACCENT_B =
    Color3.fromRGB(
        255,
        200,
        255
    )

local BTN_IDLE =
    Color3.fromRGB(
        10,
        10,
        10
    )

local BTN_HOVER =
    Color3.fromRGB(
        40,
        40,
        40
    )

local BTN_PRESS =
    Color3.fromRGB(
        30,
        30,
        30
    )

local TEXT_IDLE =
    Color3.fromRGB(
        230,
        232,
        245
    )

local TEXT_HOVER =
    Color3.new(
        1,
        1,
        1
    )

local SONG_ON =
    Color3.fromRGB(
        190,
        170,
        255
    )

----------------------------------------------------------------
-- CIRCLE HELPER
----------------------------------------------------------------

local function disc(
    parent,
    size,
    position,
    color,
    zIndex
)
    local frame = make(
        "Frame",
        parent,
        {
            Size = UDim2.fromOffset(
                size,
                size
            ),

            Position = position,

            BackgroundColor3 = color,

            BorderSizePixel = 0,

            ZIndex = zIndex,
        }
    )

    make(
        "UICorner",
        frame,
        {
            CornerRadius =
                UDim.new(1, 0),
        }
    )

    return frame
end

----------------------------------------------------------------
-- CONTROL ISLAND
----------------------------------------------------------------

local IslandFolder = make(
    "Frame",
    Circle,
    {
        Name = "Island",

        Size = UDim2.fromScale(
            1,
            1
        ),

        BackgroundTransparency = 1,

        ZIndex = 3,
    }
)

local island = make(
    "Frame",
    IslandFolder,
    {
        Name = "Body",

        BackgroundTransparency = 1,

        ClipsDescendants = true,

        Position =
            UDim2.fromOffset(
                cx - Ri,
                cy - Ri
            ),

        Size =
            UDim2.fromOffset(
                Ri * 2,
                Ri - D
            ),

        ZIndex = 2,
    }
)

local islandDisc =
    disc(
        island,
        Ri * 2,
        UDim2.fromOffset(0, 0),
        Color3.new(1, 1, 1),
        2
    )

islandDisc.BackgroundTransparency = 1

make(
    "UIGradient",
    islandDisc,
    {
        Color =
            ColorSequence.new(
                ACCENT_A,
                ACCENT_B
            ),
    }
)

local Ri2 = Ri - BORDER
local D2 = D + BORDER

local btnW =
    Ri2 -
    GAP / 2

local btnH =
    Ri2 -
    D2

----------------------------------------------------------------
-- ICON
----------------------------------------------------------------

local function icon(
    parent,
    key,
    glyph,
    size,
    boxSize
)
    local text =
        make(
            "TextLabel",
            parent,
            {
                AnchorPoint =
                    Vector2.new(
                        .5,
                        .5
                    ),

                Size =
                    UDim2.fromOffset(
                        boxSize
                        or
                        size + 8,
                        boxSize
                        or
                        size + 8
                    ),

                BackgroundTransparency = 1,

                TextColor3 =
                    TEXT_IDLE,

                Font =
                    Enum.Font.BuilderSans,

                TextSize = size,
            }
        )

    local image =
        make(
            "ImageLabel",
            text,
            {
                AnchorPoint =
                    Vector2.new(
                        .5,
                        .5
                    ),

                Position =
                    UDim2.fromScale(
                        .5,
                        .5
                    ),

                Size =
                    UDim2.fromScale(
                        ICON_SCALE,
                        ICON_SCALE
                    ),

                BackgroundTransparency = 1,
            }
        )

    local function setIcon(
        iconKey,
        fallback
    )
        local id =
            ICON[iconKey]
            or ""

        image.Image = id

        image.Visible =
            id ~= ""

        text.Text =
            id ~= ""
            and ""
            or fallback
    end

    setIcon(
        key,
        glyph
    )

    return text, setIcon, image
end

----------------------------------------------------------------
-- MAIN BUTTON
----------------------------------------------------------------

local function makeButton(
    name,
    left,
    circleX,
    key,
    fallback,
    size,
    callback,
    shift
)
    local button =
        make(
            "TextButton",
            IslandFolder,
            {
                Name = name,

                BackgroundTransparency = 1,

                ClipsDescendants = true,

                AutoButtonColor = false,

                Text = "",

                Position =
                    UDim2.fromOffset(
                        left,
                        cy - Ri2
                    ),

                Size =
                    UDim2.fromOffset(
                        btnW,
                        btnH
                    ),

                ZIndex = 3,
            }
        )

    local circle =
        disc(
            button,
            Ri2 * 2,
            UDim2.fromOffset(
                circleX,
                0
            ),
            BTN_IDLE,
            3
        )

    local label, _, image =
        icon(
            button,
            key,
            fallback,
            size,
            34
        )

    label.Position =
        UDim2.new(
            .5,
            shift,
            .5,
            0
        )

    label.ZIndex = 4
    image.ZIndex = 5

    local scale =
        make(
            "UIScale",
            label
        )

    local hovering = false
    local pressed = false

    local function refresh()
        if pressed then
            tween(
                circle,
                .08,
                {
                    BackgroundColor3 =
                        BTN_PRESS
                }
            )

            tween(
                scale,
                .08,
                {
                    Scale = .9
                }
            )

        elseif hovering then
            tween(
                circle,
                .2,
                {
                    BackgroundColor3 =
                        BTN_HOVER
                }
            )

            tween(
                scale,
                .2,
                {
                    Scale = 1.05
                },
                Enum.EasingStyle.Back
            )

        else
            tween(
                circle,
                .25,
                {
                    BackgroundColor3 =
                        BTN_IDLE
                }
            )

            tween(
                scale,
                .25,
                {
                    Scale = 1
                }
            )
        end
    end

    connect(
        button.MouseEnter,
        function()
            hovering = true
            refresh()
        end
    )

    connect(
        button.MouseLeave,
        function()
            hovering = false
            pressed = false
            refresh()
        end
    )

    connect(
        button.MouseButton1Down,
        function()
            pressed = true
            refresh()
        end
    )

    connect(
        button.MouseButton1Up,
        function()
            pressed = false
            refresh()
        end
    )

    connect(
        button.Activated,
        function()
            if dragMoved then
                return
            end

            callback()
        end
    )

    return button
end

----------------------------------------------------------------
-- LIST SYSTEM
----------------------------------------------------------------

local BASE_W = 126
local PAD = 4
local MAIN_H = 28
local OPT_H = 24

local MIN_S = .38
local S0 = 48

local FY = cy

local ITEM_BG =
    Color3.fromRGB(
        26,
        26,
        38
    )

local ITEM_HL =
    Color3.fromRGB(
        64,
        64,
        100
    )

local Lists = {}

local function newList()
    local list = {
        entries = {},
        scroll = 0,
        targetScroll = 0,
        alpha = 0,
        target = 0,
        lastWheel = 0,
    }

    local entries = list.entries

    local frame =
        make(
            "Frame",
            Circle,
            {
                Size =
                    UDim2.fromScale(
                        1,
                        1
                    ),

                BackgroundTransparency = 1,

                ZIndex = 6,

                Visible = false,
            }
        )

    list.frame = frame

    Lists[#Lists + 1] = list

    local function centers()
        local total = 0
        local output = {}

        for i, entry in entries do
            output[i] =
                total +
                entry.targetHeight / 2

            total +=
                entry.targetHeight
        end

        return output
    end

    function list.clamp(value)
        local centerList = centers()

        if #centerList == 0 then
            return 0
        end

        local low =
            centerList[1]

        local high =
            centerList[1]

        for i, entry in entries do
            if entry.targetHeight > 0 then
                high =
                    centerList[i]
            end
        end

        return math.clamp(
            value,
            low,
            high
        )
    end

    function list.focus(entry)
        local centerList =
            centers()

        if centerList[entry.index] then
            list.targetScroll =
                list.clamp(
                    centerList[
                        entry.index
                    ]
                )
        end
    end

    function list.snap()
        local centerList =
            centers()

        list.scroll =
            centerList[1]
            or 0

        list.targetScroll =
            list.scroll
    end

    function list.add(
        kind,
        text,
        height,
        indent,
        textSize,
        color
    )
        local button =
            make(
                "TextButton",
                frame,
                {
                    AnchorPoint =
                        Vector2.new(
                            .5,
                            .5
                        ),

                    Size =
                        UDim2.fromOffset(
                            BASE_W,
                            height
                        ),

                    Position =
                        UDim2.fromOffset(
                            cx,
                            FY
                        ),

                    BackgroundColor3 =
                        ITEM_BG,

                    BorderSizePixel = 0,

                    AutoButtonColor = false,

                    Text = "",

                    ClipsDescendants = true,

                    Visible = false,
                }
            )

        make(
            "UICorner",
            button,
            {
                CornerRadius =
                    UDim.new(
                        0,
                        9
                    ),
            }
        )

        local stroke =
            make(
                "UIStroke",
                button,
                {
                    Thickness = 1,

                    Color =
                        Color3.new(
                            1,
                            1,
                            1
                        ),

                    Transparency = .9,

                    ApplyStrokeMode =
                        Enum.ApplyStrokeMode.Border,
                }
            )

        local scale =
            make(
                "UIScale",
                button
            )

        local label =
            make(
                "TextLabel",
                button,
                {
                    AnchorPoint =
                        Vector2.new(
                            0,
                            .5
                        ),

                    Position =
                        UDim2.new(
                            0,
                            indent,
                            .5,
                            0
                        ),

                    Size =
                        UDim2.new(
                            1,
                            -(indent + 26),
                            0,
                            height
                        ),

                    BackgroundTransparency = 1,

                    Text = text,

                    TextColor3 =
                        color
                        or
                        TEXT_IDLE,

                    Font =
                        Enum.Font.BuilderSans,

                    TextSize =
                        textSize
                        or
                        13,

                    TextXAlignment =
                        Enum.TextXAlignment.Left,

                    TextTruncate =
                        Enum.TextTruncate.AtEnd,
                }
            )

        local entry = {
            index = #entries + 1,

            kind = kind,

            frame = button,

            stroke = stroke,

            scale = scale,

            label = label,

            baseHeight = height,

            slot = height + PAD,

            currentHeight = height + PAD,

            targetHeight = height + PAD,

            hover = 0,

            hoverTarget = 0,

            press = 0,

            pressTarget = 0,

            flash = 0,

            fill = 0,

            state = false,
        }

        connect(
            button.MouseEnter,
            function()
                entry.hoverTarget = 1
            end
        )

        connect(
            button.MouseLeave,
            function()
                entry.hoverTarget = 0
                entry.pressTarget = 0
            end
        )

        connect(
            button.MouseButton1Down,
            function()
                entry.pressTarget = 1
            end
        )

        connect(
            button.MouseButton1Up,
            function()
                entry.pressTarget = 0
            end
        )

        entries[#entries + 1] =
            entry

        return entry
    end

    function list.tap(entry, callback)
        connect(
            entry.frame.Activated,
            function()
                if dragMoved then
                    return
                end

                callback()
            end
        )
    end

    local function indicator(
        entry,
        round,
        size
    )
        entry.indicator =
            make(
                "Frame",
                entry.frame,
                {
                    AnchorPoint =
                        Vector2.new(
                            1,
                            .5
                        ),

                    Position =
                        UDim2.new(
                            1,
                            -10,
                            .5,
                            0
                        ),

                    Size =
                        UDim2.fromOffset(
                            size,
                            size
                        ),

                    BackgroundColor3 =
                        ACCENT_B,

                    BackgroundTransparency = 1,

                    BorderSizePixel = 0,
                }
            )

        make(
            "UICorner",
            entry.indicator,
            {
                CornerRadius =
                    round
                    and
                    UDim.new(
                        1,
                        0
                    )
                    or
                    UDim.new(
                        .32,
                        0
                    ),
            }
        )

        entry.indicatorStroke =
            make(
                "UIStroke",
                entry.indicator,
                {
                    Thickness = 1.5,

                    Color =
                        Color3.new(
                            1,
                            1,
                            1
                        ),

                    ApplyStrokeMode =
                        Enum.ApplyStrokeMode.Border,
                }
            )
    end

    function list.toggle(
        text,
        default,
        callback
    )
        local entry =
            list.add(
                "toggle",
                text,
                MAIN_H,
                12,
                11
            )

        entry.state =
            default == true

        entry.fill =
            entry.state
            and 1
            or 0

        indicator(
            entry,
            false,
            14
        )

        list.tap(
            entry,
            function()
                entry.state =
                    not entry.state

                list.focus(entry)

                if callback then
                    callback(
                        entry.state
                    )
                end
            end
        )

        return entry
    end

    function list.button(
        text,
        callback,
        textSize
    )
        local entry =
            list.add(
                "button",
                text,
                MAIN_H,
                0,
                textSize
            )

        entry.label.TextXAlignment =
            Enum.TextXAlignment.Center

        entry.label.Position =
            UDim2.new(
                0,
                0,
                .5,
                0
            )

        entry.label.Size =
            UDim2.new(
                1,
                0,
                0,
                MAIN_H
            )

        list.tap(
            entry,
            function()
                entry.flash = 1

                list.focus(entry)

                if callback then
                    callback()
                end
            end
        )

        return entry
    end

    function list.textbox(
        text,
        default,
        callback
    )
        local entry =
            list.add(
                "textbox",
                text,
                MAIN_H,
                12,
                11
            )

        entry.label.Size =
            UDim2.new(
                1,
                -(12 + 62),
                0,
                MAIN_H
            )

        entry.last =
            tostring(
                default
                or ""
            )

        local box =
            make(
                "TextBox",
                entry.frame,
                {
                    AnchorPoint =
                        Vector2.new(
                            1,
                            .5
                        ),

                    Position =
                        UDim2.new(
                            1,
                            -8,
                            .5,
                            0
                        ),

                    Size =
                        UDim2.fromOffset(
                            46,
                            18
                        ),

                    BackgroundColor3 =
                        Color3.fromRGB(
                            12,
                            12,
                            18
                        ),

                    BorderSizePixel = 0,

                    Text =
                        entry.last,

                    TextColor3 =
                        TEXT_HOVER,

                    PlaceholderText =
                        "0-10",

                    Font =
                        Enum.Font.BuilderSans,

                    TextSize = 11,

                    ClearTextOnFocus = false,
                }
            )

        make(
            "UICorner",
            box,
            {
                CornerRadius =
                    UDim.new(
                        0,
                        6
                    ),
            }
        )

        connect(
            box.FocusLost,
            function()
                local number =
                    tonumber(
                        box.Text
                    )

                if number then
                    number =
                        math.clamp(
                            number,
                            0,
                            10
                        )

                    number =
                        math.floor(
                            number * 100 +
                            .5
                        ) / 100

                    entry.last =
                        tostring(number)

                    box.Text =
                        entry.last

                    if callback then
                        callback(number)
                    end
                else
                    box.Text =
                        entry.last
                end
            end
        )

        entry.box = box

        entry.tick =
            function(_, visibility)
                box.TextTransparency =
                    1 - visibility

                box.BackgroundTransparency =
                    1 -
                    .8 *
                    visibility
            end

        return entry
    end

    function list.header(text)
        local entry =
            list.add(
                "header",
                text,
                18,
                0,
                10,
                ACCENT_B
            )

        entry.flat = true

        entry.label.TextXAlignment =
            Enum.TextXAlignment.Center

        entry.label.Position =
            UDim2.new(
                0,
                0,
                .5,
                0
            )

        entry.label.Size =
            UDim2.new(
                1,
                0,
                0,
                18
            )

        return entry
    end

    function list.dropdown(
        text,
        multi,
        options,
        callback,
        defaultIndex
    )
        local header =
            list.add(
                "dropdown",
                text,
                MAIN_H,
                12,
                11
            )

        header.arrow =
            make(
                "TextLabel",
                header.frame,
                {
                    AnchorPoint =
                        Vector2.new(
                            1,
                            .5
                        ),

                    Position =
                        UDim2.new(
                            1,
                            -10,
                            .5,
                            0
                        ),

                    Size =
                        UDim2.fromOffset(
                            14,
                            14
                        ),

                    BackgroundTransparency = 1,

                    Text = "▼",

                    TextColor3 =
                        TEXT_IDLE,

                    Font =
                        Enum.Font.BuilderSans,

                    TextSize = 9,
                }
            )

        header.arrowRotation = 0
        header.arrowTarget = 0
        header.open = false
        header.options = {}

        for i, optionName in options do
            local option =
                list.add(
                    "option",
                    optionName,
                    OPT_H,
                    20,
                    11
                )

            option.currentHeight = 0
            option.targetHeight = 0

            option.state =
                (not multi)
                and
                i ==
                (
                    defaultIndex
                    or 1
                )

            option.fill =
                option.state
                and 1
                or 0

            indicator(
                option,
                not multi,
                10
            )

            header.options[#header.options + 1] =
                option

            list.tap(
                option,
                function()
                    if multi then
                        option.state =
                            not option.state
                    else
                        for _, other in header.options do
                            other.state =
                                other == option
                        end

                        header.open = false
                        header.arrowTarget = 0

                        for _, other in header.options do
                            other.targetHeight = 0
                        end
                    end

                    if callback then
                        callback(
                            optionName,
                            option.state
                        )
                    end
                end
            )
        end

        list.tap(
            header,
            function()
                header.open =
                    not header.open

                header.arrowTarget =
                    header.open
                    and 180
                    or 0

                for _, option in header.options do
                    option.targetHeight =
                        header.open
                        and option.slot
                        or 0
                end
            end
        )

        return header
    end

    connect(
        RS.RenderStepped,
        function(dt)
            local speed =
                1 -
                math.exp(
                    -dt * 14
                )

            if list.alpha <
                list.target
            then
                list.alpha =
                    math.min(
                        list.target,
                        list.alpha +
                        dt * 3
                    )

            elseif list.alpha >
                list.target
            then
                list.alpha =
                    math.max(
                        list.target,
                        list.alpha -
                        dt * 3
                    )
            end

            local alpha =
                list.alpha

            frame.Visible =
                alpha > .001

            if not frame.Visible then
                return
            end

            if
                list.lastWheel > 0
                and
                os.clock() -
                list.lastWheel >
                .15
            then
                list.lastWheel = 0
            end

            list.scroll +=
                (
                    list.targetScroll -
                    list.scroll
                ) *
                speed

            local top = 0

            for _, entry in entries do
                entry.currentHeight +=
                    (
                        entry.targetHeight -
                        entry.currentHeight
                    ) *
                    speed

                if math.abs(
                    entry.targetHeight -
                    entry.currentHeight
                ) < .05 then
                    entry.currentHeight =
                        entry.targetHeight
                end

                entry.center =
                    top +
                    entry.currentHeight /
                    2

                top +=
                    entry.currentHeight

                local fraction =
                    entry.currentHeight /
                    entry.slot

                if fraction < .02 then
                    entry.frame.Visible =
                        false

                    continue
                end

                local relative =
                    entry.center -
                    list.scroll

                local distance =
                    math.abs(relative)

                local scale =
                    MIN_S +
                    (
                        1 -
                        MIN_S
                    ) /
                    (
                        1 +
                        (
                            distance /
                            S0
                        ) ^ 2
                    )

                local offset =
                    MIN_S *
                    distance +
                    (
                        1 -
                        MIN_S
                    ) *
                    S0 *
                    math.atan(
                        distance /
                        S0
                    )

                local y =
                    FY +
                    (
                        relative < 0
                        and -offset
                        or offset
                    )

                local delay =
                    math.min(
                        distance / 32,
                        7
                    ) *
                    .07

                local entrance =
                    ease(
                        math.clamp(
                            (
                                alpha -
                                delay
                            ) /
                            .5,
                            0,
                            1
                        )
                    )

                y +=
                    (
                        1 -
                        entrance
                    ) *
                    70

                local height =
                    entry.baseHeight *
                    fraction

                local effectiveY =
                    math.abs(
                        y - cy
                    ) +
                    height *
                    .5 *
                    scale

                local allowed =
                    2 *
                    math.sqrt(
                        math.max(
                            0,
                            (
                                R - 4
                            ) ^ 2 -
                            effectiveY ^ 2
                        )
                    )

                local finalScale =
                    math.min(
                        scale,
                        allowed /
                        BASE_W
                    )

                local edge =
                    math.clamp(
                        (y - 34) / 16,
                        0,
                        1
                    ) *
                    math.clamp(
                        (146 - y) / 16,
                        0,
                        1
                    )

                local visibility =
                    entrance *
                    edge *
                    fraction

                if
                    visibility < .02
                    or
                    finalScale < .08
                then
                    entry.frame.Visible =
                        false

                    continue
                end

                entry.frame.Visible = true

                entry.hover +=
                    (
                        entry.hoverTarget -
                        entry.hover
                    ) *
                    speed

                entry.press +=
                    (
                        entry.pressTarget -
                        entry.press
                    ) *
                    speed

                entry.flash *=
                    1 -
                    math.min(
                        1,
                        dt * 6
                    )

                local focus =
                    (
                        scale -
                        MIN_S
                    ) /
                    (
                        1 -
                        MIN_S
                    )

                entry.frame.Position =
                    UDim2.fromOffset(
                        cx,
                        y
                    )

                entry.frame.Size =
                    UDim2.fromOffset(
                        BASE_W,
                        height
                    )

                entry.scale.Scale =
                    finalScale *
                    (
                        1 -
                        .05 *
                        entry.press
                    )

                if entry.flat then
                    entry.frame.BackgroundTransparency = 1
                    entry.stroke.Transparency = 1
                else
                    entry.frame.BackgroundColor3 =
                        ITEM_BG:Lerp(
                            ITEM_HL,
                            math.clamp(
                                entry.hover *
                                .7 +
                                entry.flash,
                                0,
                                1
                            )
                        )

                    entry.frame.BackgroundTransparency =
                        1 -
                        (
                            .3 +
                            .4 *
                            focus
                        ) *
                        visibility

                    entry.stroke.Transparency =
                        1 -
                        (
                            .1 +
                            .25 *
                            focus
                        ) *
                        visibility

                    entry.label.TextColor3 =
                        TEXT_IDLE:Lerp(
                            TEXT_HOVER,
                            entry.hover
                        )
                end

                entry.label.TextTransparency =
                    1 -
                    (
                        1 -
                        .55 *
                        (
                            1 -
                            focus
                        )
                    ) *
                    visibility

                if entry.indicator then
                    entry.fill +=
                        (
                            (
                                entry.state
                                and 1
                                or 0
                            ) -
                            entry.fill
                        ) *
                        speed

                    entry.indicator.BackgroundTransparency =
                        1 -
                        entry.fill *
                        visibility

                    entry.indicatorStroke.Transparency =
                        1 -
                        .8 *
                        visibility
                end

                if entry.arrow then
                    entry.arrowRotation +=
                        (
                            entry.arrowTarget -
                            entry.arrowRotation
                        ) *
                        speed

                    entry.arrow.Rotation =
                        entry.arrowRotation

                    entry.arrow.TextTransparency =
                        1 -
                        .8 *
                        visibility
                end

                if entry.tick then
                    entry.tick(
                        entry,
                        visibility,
                        focus
                    )
                end
            end
        end
    )

    return list
end

----------------------------------------------------------------
-- LISTS
----------------------------------------------------------------

local Settings = newList()
local Playlist = newList()

local function activeList()
    for _, list in Lists do
        if list.target == 1 then
            return list
        end
    end

    return nil
end

local listOpen = false

local function toggleList(list)
    local wasOpen =
        list.target == 1

    for _, other in Lists do
        other.target = 0
    end

    if not wasOpen then
        list.target = 1

        if list.onOpen then
            list.onOpen()
        end
    end

    listOpen = not wasOpen
end

----------------------------------------------------------------
-- SIDE BUTTONS
----------------------------------------------------------------

makeButton(
    "ButtonLeft",
    cx - Ri2,
    0,
    "settings",
    "∙∙∙",
    18,
    function()
        toggleList(Settings)
    end,
    20
)

makeButton(
    "ButtonRight",
    cx + GAP / 2,
    -(Ri2 + GAP / 2),
    "playlist",
    "♪",
    18,
    function()
        toggleList(Playlist)
    end,
    -20
)

----------------------------------------------------------------
-- CENTER CONTROLS
----------------------------------------------------------------

local Controls =
    make(
        "Frame",
        Holder,
        {
            Name = "Controls",

            Size =
                UDim2.fromScale(
                    1,
                    1
                ),

            BackgroundTransparency = 1,

            ZIndex = 8,

            Visible = false,
        }
    )

local Cluster =
    make(
        "Frame",
        Controls,
        {
            Name = "Cluster",

            Size =
                UDim2.fromScale(
                    1,
                    1
                ),

            BackgroundTransparency = 1,
        }
    )

local TimeLabel =
    make(
        "TextLabel",
        Cluster,
        {
            Name = "Time",

            AnchorPoint =
                Vector2.new(
                    .5,
                    .5
                ),

            Position =
                UDim2.fromOffset(
                    180,
                    245
                ),

            Size =
                UDim2.fromOffset(
                    80,
                    12
                ),

            BackgroundTransparency = 1,

            Text = "0:00 / 0:00",

            TextColor3 =
                Color3.fromRGB(
                    205,
                    210,
                    230
                ),

            TextTransparency = .2,

            Font =
                Enum.Font.BuilderSans,

            TextSize = 8,
        }
    )

----------------------------------------------------------------
-- PLAYBACK STATE
----------------------------------------------------------------

local cur
local playing = false
local pausedAt = 0
local startedAt = 0

local shuffleQueue = {}
local shufflePosition = 0

local function rebuildShuffle()
    table.clear(shuffleQueue)

    for _, song in songs do
        shuffleQueue[#shuffleQueue + 1] =
            song
    end

    shuffle(
        shuffleQueue
    )

    shufflePosition = 1

    if cur then
        for i, song in shuffleQueue do
            if song == cur then
                shufflePosition = i
                break
            end
        end
    end
end

rebuildShuffle()

----------------------------------------------------------------
-- NAME
----------------------------------------------------------------

local NAME_W = 116

local NameTint =
    make(
        "Frame",
        Controls,
        {
            AnchorPoint =
                Vector2.new(
                    .5,
                    .5
                ),

            Position =
                UDim2.fromOffset(
                    180,
                    299
                ),

            Size =
                UDim2.fromOffset(
                    NAME_W + 14,
                    20
                ),

            BackgroundColor3 =
                Color3.fromRGB(
                    8,
                    8,
                    12
                ),

            BackgroundTransparency = .45,

            BorderSizePixel = 0,
        }
    )

make(
    "UICorner",
    NameTint,
    {
        CornerRadius =
            UDim.new(
                1,
                0
            ),
    }
)

local NameFrame =
    make(
        "Frame",
        Holder,
        {
            Name = "NameBox",

            AnchorPoint =
                Vector2.new(
                    .5,
                    .5
                ),

            Position =
                UDim2.fromOffset(
                    180,
                    299
                ),

            Size =
                UDim2.fromOffset(
                    NAME_W,
                    16
                ),

            BackgroundTransparency = 1,

            ClipsDescendants = true,

            ZIndex = 8,
        }
    )

local NameLabel =
    make(
        "TextLabel",
        NameFrame,
        {
            Size =
                UDim2.fromScale(
                    1,
                    1
                ),

            BackgroundTransparency = 1,

            Text = "",

            TextTransparency = 1,

            TextColor3 =
                Color3.fromRGB(
                    205,
                    210,
                    230
                ),

            Font =
                Enum.Font.BuilderSans,

            TextSize = 12,
        }
    )

local nameToken = 0

local function setName(
    text,
    transparency
)
    nameToken += 1

    local token =
        nameToken

    NameLabel.Text =
        text

    local function width(value)
        return TXT:GetTextSize(
            value,
            12,
            Enum.Font.BuilderSans,
            Vector2.new(
                100000,
                20
            )
        ).X
    end

    if width(text) <= NAME_W then
        tween(
            NameLabel,
            .25,
            {
                TextTransparency =
                    transparency
                    or .1,
            }
        )

        return
    end

    local characters =
        utf8.len(text)
        or
        #text

    local function head(count)
        return text:sub(
            1,
            (
                utf8.offset(
                    text,
                    count + 1
                )
                or
                #text + 1
            ) - 1
        )
    end

    local function tail(start)
        return text:sub(
            utf8.offset(
                text,
                start
            )
            or 1
        )
    end

    local headCount = characters
    local tailStart = 1

    while
        headCount > 1
        and
        width(
            head(headCount) ..
            "..."
        ) >
        NAME_W
    do
        headCount -= 1
    end

    while
        tailStart < characters
        and
        width(
            "..." ..
            tail(tailStart)
        ) >
        NAME_W
    do
        tailStart += 1
    end

    local first =
        head(headCount) ..
        "..."

    local second =
        "..." ..
        tail(tailStart)

    task.spawn(function()
        local index = 0

        while
            nameToken == token
            and
            Gui.Parent
        do
            NameLabel.Text =
                index % 2 == 0
                and first
                or second

            index += 1

            NameLabel.TextTransparency = 1

            tween(
                NameLabel,
                .25,
                {
                    TextTransparency = .1,
                }
            )

            task.wait(2.2)

            if nameToken ~= token then
                break
            end

            tween(
                NameLabel,
                .25,
                {
                    TextTransparency = 1,
                }
            )

            task.wait(.3)
        end
    end)
end

----------------------------------------------------------------
-- PROGRESS BAR
----------------------------------------------------------------

local ProgFill =
    make(
        "Frame",
        NameTint,
        {
            Size =
                UDim2.fromScale(
                    0,
                    1
                ),

            BackgroundColor3 =
                Color3.new(
                    1,
                    1,
                    1
                ),

            BackgroundTransparency = .6,

            BorderSizePixel = 0,
        }
    )

make(
    "UICorner",
    ProgFill,
    {
        CornerRadius =
            UDim.new(
                1,
                0
            ),
    }
)

make(
    "UIGradient",
    ProgFill,
    {
        Color =
            ColorSequence.new(
                ACCENT_A,
                ACCENT_B
            ),
    }
)

local function formatTime(seconds)
    seconds =
        math.max(
            0,
            math.floor(
                seconds
            )
        )

    return string.format(
        "%d:%02d",
        seconds // 60,
        seconds % 60
    )
end

local function currentPosition()
    if not cur then
        return 0
    end

    if playing then
        return AudioPlayer.TimePosition
    end

    return pausedAt
end

local seeking = false
local seekInput
local seekFraction = 0

local function getSeekFraction(x)
    return math.clamp(
        (
            x -
            NameTint.AbsolutePosition.X
        ) /
        math.max(
            NameTint.AbsoluteSize.X,
            1
        ),
        0,
        1
    )
end

connect(
    NameTint.InputBegan,
    function(input)
        if not cur then
            return
        end

        if
            input.UserInputType ==
            Enum.UserInputType.MouseButton1
            or
            input.UserInputType ==
            Enum.UserInputType.Touch
        then
            seeking = true
            seekInput = input
            seekFraction =
                getSeekFraction(
                    input.Position.X
                )
        end
    end
)

connect(
    UIS.InputChanged,
    function(input)
        if not seeking then
            return
        end

        if
            input.UserInputType ==
            Enum.UserInputType.MouseMovement
            or
            input == seekInput
        then
            seekFraction =
                getSeekFraction(
                    input.Position.X
                )
        end
    end
)

connect(
    UIS.InputEnded,
    function(input)
        if not seeking then
            return
        end

        if
            input.UserInputType ==
            Enum.UserInputType.MouseButton1
            or
            input == seekInput
        then
            seeking = false

            local length =
                AudioPlayer.TimeLength

            if
                cur
                and
                length > 0
            then
                local position =
                    math.min(
                        seekFraction *
                        length,
                        math.max(
                            0,
                            length - .05
                        )
                    )

                if playing then
                    AudioPlayer.TimePosition =
                        position
                else
                    pausedAt =
                        position
                end
            end
        end
    end
)

connect(
    RS.RenderStepped,
    function()
        local length =
            cur
            and
            AudioPlayer.TimeLength
            or 0

        local position =
            seeking
            and
            seekFraction *
            length
            or
            currentPosition()

        local fraction =
            length > 0
            and
            math.clamp(
                position / length,
                0,
                1
            )
            or
            0

        ProgFill.Size =
            UDim2.fromScale(
                fraction,
                1
            )

        if Cfg.showTime then
            TimeLabel.Text =
                formatTime(position) ..
                " / " ..
                formatTime(length)
        end

        if
            Cfg.rotation
            and
            playing
        then
            Cover.Rotation +=
                8 *
                math.clamp(
                    1 / 60,
                    .005,
                    .03
                )
        end
    end
)

----------------------------------------------------------------
-- CONTROL BUTTONS
----------------------------------------------------------------

local pops = {}

local function controlButton(
    dx,
    dy,
    size,
    key,
    glyph,
    glyphSize,
    callback
)
    local button =
        make(
            "TextButton",
            Cluster,
            {
                AnchorPoint =
                    Vector2.new(
                        .5,
                        .5
                    ),

                Position =
                    UDim2.fromOffset(
                        180 + dx,
                        180 + dy
                    ),

                Size =
                    UDim2.fromOffset(
                        size,
                        size
                    ),

                BackgroundColor3 =
                    BTN_IDLE,

                BackgroundTransparency = .25,

                BorderSizePixel = 0,

                AutoButtonColor = false,

                Text = "",
            }
        )

    make(
        "UICorner",
        button,
        {
            CornerRadius =
                UDim.new(
                    1,
                    0
                ),
        }
    )

    make(
        "UIStroke",
        button,
        {
            Thickness = 1.5,

            Color =
                Color3.new(
                    1,
                    1,
                    1
                ),

            Transparency = .8,
        }
    )

    local scale =
        make(
            "UIScale",
            button,
            {
                Scale = 0,
            }
        )

    pops[#pops + 1] =
        scale

    local label, setter =
        icon(
            button,
            key,
            glyph,
            glyphSize
        )

    label.Position =
        UDim2.fromScale(
            .5,
            .5
        )

    connect(
        button.MouseEnter,
        function()
            tween(
                scale,
                .15,
                {
                    Scale = 1.1
                }
            )

            tween(
                button,
                .15,
                {
                    BackgroundColor3 =
                        BTN_HOVER
                }
            )
        end
    )

    connect(
        button.MouseLeave,
        function()
            tween(
                scale,
                .15,
                {
                    Scale = 1
                }
            )

            tween(
                button,
                .15,
                {
                    BackgroundColor3 =
                        BTN_IDLE
                }
            )
        end
    )

    connect(
        button.MouseButton1Down,
        function()
            tween(
                scale,
                .08,
                {
                    Scale = .88
                }
            )
        end
    )

    connect(
        button.MouseButton1Up,
        function()
            tween(
                scale,
                .12,
                {
                    Scale = 1.1
                }
            )
        end
    )

    connect(
        button.Activated,
        function()
            if dragMoved then
                return
            end

            callback()
        end
    )

    return button, setter
end

----------------------------------------------------------------
-- PLAYBACK
----------------------------------------------------------------

local playButtonSetter

local function refreshPlayButton()
    if not playButtonSetter then
        return
    end

    if playing then
        playButtonSetter(
            "pause",
            "❚❚"
        )
    else
        playButtonSetter(
            "play",
            "▶"
        )
    end
end

local function findSongIndex(song)
    if not song then
        return nil
    end

    return song.idx
end

local function getNextSong(direction)
    local count = #songs

    if count == 0 then
        return nil
    end

    if Cfg.shuffle then
        if #shuffleQueue ~= count then
            rebuildShuffle()
        end

        if direction > 0 then
            shufflePosition += 1

            if
                shufflePosition >
                #shuffleQueue
            then
                if Cfg.repeatMode == "All" then
                    rebuildShuffle()
                else
                    shufflePosition = 1
                end
            end

            return shuffleQueue[
                shufflePosition
            ]
        else
            shufflePosition =
                math.max(
                    1,
                    shufflePosition - 1
                )

            return shuffleQueue[
                shufflePosition
            ]
        end
    end

    local currentIndex =
        findSongIndex(cur)

    if not currentIndex then
        return songs[
            direction > 0
            and 1
            or count
        ]
    end

    local nextIndex =
        currentIndex +
        direction

    if nextIndex > count then
        if Cfg.repeatMode == "All" then
            nextIndex = 1
        else
            nextIndex = count
        end
    elseif nextIndex < 1 then
        if Cfg.repeatMode == "All" then
            nextIndex = count
        else
            nextIndex = 1
        end
    end

    return songs[nextIndex]
end

local playSong

playSong = function(song, position)
    if not song then
        return false
    end

    local audio =
        audioOf(song)

    if audio == "" then
        setName(
            "unable to load audio",
            .3
        )

        return false
    end

    cur = song
    playing = true

    startedAt =
        os.clock()

    pausedAt =
        position
        or 0

    State.lastSong =
        song.path

    saveState()

    pcall(function()
        AudioPlayer:Stop()
    end)

    local ok =
        pcall(function()
            AudioPlayer.Asset =
                audio

            AudioPlayer.TimePosition =
                position
                or 0

            AudioPlayer.Volume =
                Cfg.volume

            AudioPlayer:Play()
        end)

    if not ok then
        playing = false

        setName(
            "audio failed to play",
            .3
        )

        refreshPlayButton()

        return false
    end

    Cover.Image =
        coverOf(song)

    Cover.Rotation = 0

    setName(
        song.name
    )

    refreshPlayButton()

    if Cfg.shuffle then
        for i, value in shuffleQueue do
            if value == song then
                shufflePosition = i
                break
            end
        end
    end

    local nextSong =
        getNextSong(1)

    if nextSong then
        task.spawn(function()
            pcall(
                audioOf,
                nextSong
            )
        end)
    end

    return true
end

local function togglePlayback()
    if #songs == 0 then
        return
    end

    if not cur then
        playSong(
            lastSong
            or
            songs[1]
        )

        return
    end

    if playing then
        pausedAt =
            AudioPlayer.TimePosition

        playing = false

        pcall(function()
            AudioPlayer:Stop()
        end)
    else
        local ok =
            pcall(function()
                AudioPlayer.TimePosition =
                    pausedAt

                AudioPlayer.Volume =
                    Cfg.volume

                AudioPlayer:Play()
            end)

        if ok then
            playing = true
            startedAt =
                os.clock()
        end
    end

    refreshPlayButton()
end

local function nextTrack()
    if #songs == 0 then
        return
    end

    local nextSong =
        getNextSong(1)

    if nextSong then
        playSong(nextSong)
    end
end

local function previousTrack()
    if #songs == 0 then
        return
    end

    if
        cur
        and
        AudioPlayer.TimePosition >
        3
    then
        pcall(function()
            AudioPlayer.TimePosition = 0
        end)

        pausedAt = 0

        return
    end

    local previousSong =
        getNextSong(-1)

    if previousSong then
        playSong(previousSong)
    end
end

controlButton(
    -27,
    84,
    24,
    "prev",
    "◀◀",
    10,
    previousTrack
)

local _, setPlay =
    controlButton(
        0,
        90,
        29,
        "play",
        "▶",
        13,
        togglePlayback
    )

playButtonSetter =
    setPlay

controlButton(
    27,
    84,
    24,
    "next",
    "▶▶",
    10,
    nextTrack
)

----------------------------------------------------------------
-- AUDIO ENDED
----------------------------------------------------------------

connect(
    AudioPlayer.Ended,
    function()
        if not playing then
            return
        end

        if
            os.clock() -
            startedAt <
            .25
        then
            return
        end

        if
            Cfg.repeatMode ==
            "One"
        then
            playSong(cur)
            return
        end

        local nextSong =
            getNextSong(1)

        if nextSong then
            playSong(nextSong)
        else
            playing = false
            refreshPlayButton()
        end
    end
)

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------

do
    local SCALES = {
        ["70%"] = .7,
        ["80%"] = .8,
        ["100%"] = 1,
        ["120%"] = 1.2,
        ["140%"] = 1.4,
    }

    local EQ_PRESETS = {
        ["Bass Boost"] = {
            low = 8,
        },

        ["Vocal Boost"] = {
            low = -2,
            mid = 5,
        },

        ["Treble Boost"] = {
            high = 6,
        },

        ["Warm"] = {
            low = 3,
            high = -3,
        },

        ["V-Shape"] = {
            low = 6,
            mid = -3,
            high = 5,
        },

        ["Lo-Fi"] = {
            low = 2,
            high = -18,
        },
    }

    local eqActive =
        type(State.eq) == "table"
        and
        State.eq
        or
        {}

    local function applyEQ()
        local low = 0
        local mid = 0
        local high = 0

        for name, enabled in eqActive do
            if enabled then
                local preset =
                    EQ_PRESETS[name]

                if preset then
                    low +=
                        preset.low
                        or 0

                    mid +=
                        preset.mid
                        or 0

                    high +=
                        preset.high
                        or 0
                end
            end
        end

        Equalizer.LowGain =
            math.clamp(
                low,
                -80,
                10
            )

        Equalizer.MidGain =
            math.clamp(
                mid,
                -80,
                10
            )

        Equalizer.HighGain =
            math.clamp(
                high,
                -80,
                10
            )
    end

    local hideKey =
        State.hideKey
        and
        Enum.KeyCode[
            State.hideKey
        ]
        or nil

    local listening = false
    local hideButton

    local function keyName(key)
        return (
            key.Name
                :gsub(
                    "Right",
                    "R"
                )
                :gsub(
                    "Left",
                    "L"
                )
                :gsub(
                    "Control",
                    "Ctrl"
                )
        )
    end

    local scaleNames = {
        "70%",
        "80%",
        "100%",
        "120%",
        "140%",
    }

    local scaleDefault = 3

    for i, name in scaleNames do
        if
            SCALES[name] ==
            Cfg.scale
        then
            scaleDefault = i
            break
        end
    end

    Settings.header("VISUALIZER")

    Settings.toggle(
        "Rainbow Bars",
        Cfg.rainbow,
        function(value)
            Cfg.rainbow = value
            State.rainbow = value
            saveState()
        end
    )

    Settings.dropdown(
        "Reaction Mode",
        false,
        {
            "Spectrum",
            "Loudness",
            "Random",
        },
        function(name)
            Cfg.mode = name
            State.mode = name
            saveState()
        end,
        table.find(
            {
                "Spectrum",
                "Loudness",
                "Random",
            },
            Cfg.mode
        ) or 1
    )

    Settings.toggle(
        "Cover Rotation",
        Cfg.rotation,
        function(value)
            Cfg.rotation = value
            State.rotation = value
            saveState()
        end
    )

    Settings.header("DISPLAY")

    Settings.toggle(
        "Show Name",
        Cfg.showName,
        function(value)
            Cfg.showName = value
            State.showName = value

            NameTint.Visible =
                value

            NameFrame.Visible =
                value

            saveState()
        end
    )

    Settings.toggle(
        "Show Time",
        Cfg.showTime,
        function(value)
            Cfg.showTime = value
            State.showTime = value

            TimeLabel.Visible =
                value

            saveState()
        end
    )

    Settings.dropdown(
        "UI Scale",
        false,
        scaleNames,
        function(name)
            Cfg.scale =
                SCALES[name]

            State.scale =
                Cfg.scale

            tween(
                HolderScale,
                .3,
                {
                    Scale =
                        Cfg.scale,
                },
                Enum.EasingStyle.Cubic
            )

            saveState()
        end,
        scaleDefault
    )

    Settings.header("PLAYBACK")

    Settings.toggle(
        "Shuffle",
        Cfg.shuffle,
        function(value)
            Cfg.shuffle =
                value

            State.shuffle =
                value

            rebuildShuffle()

            saveState()
        end
    )

    Settings.dropdown(
        "Repeat",
        false,
        {
            "Off",
            "All",
            "One",
        },
        function(name)
            Cfg.repeatMode =
                name

            State.repeatMode =
                name

            saveState()
        end,
        table.find(
            {
                "Off",
                "All",
                "One",
            },
            Cfg.repeatMode
        ) or 1
    )

    Settings.textbox(
        "Volume",
        Cfg.volume,
        function(value)
            Cfg.volume =
                value

            State.volume =
                value

            AudioPlayer.Volume =
                value

            saveState()
        end
    )

    Settings.header("EQUALIZER")

    local eqDropdown =
        Settings.dropdown(
            "SFX",
            true,
            {
                "Bass Boost",
                "Vocal Boost",
                "Treble Boost",
                "Warm",
                "V-Shape",
                "Lo-Fi",
            },
            function(name, enabled)
                eqActive[name] =
                    enabled

                State.eq =
                    eqActive

                applyEQ()
                saveState()
            end
        )

    for _, option in eqDropdown.options do
        option.state =
            eqActive[
                option.label.Text
            ] == true

        option.fill =
            option.state
            and 1
            or 0
    end

    applyEQ()

    Settings.header("ACTIONS")

    Settings.button(
        "Play Random",
        function()
            if #songs == 0 then
                return
            end

            local song =
                songs[
                    math.random(
                        #songs
                    )
                ]

            if
                #songs > 1
                and
                song == cur
            then
                repeat
                    song =
                        songs[
                            math.random(
                                #songs
                            )
                        ]
                until
                    song ~= cur
            end

            playSong(song)
        end
    )

    hideButton =
        Settings.button(
            "Hide Bind [" ..
            (
                hideKey
                and
                keyName(hideKey)
                or
                "None"
            ) ..
            "]",
            function()
                listening = true

                hideButton.label.Text =
                    "Press a key..."
            end,
            11
        )

    Settings.button(
        "Unload UI",
        function()
            if playing then
                pcall(function()
                    AudioPlayer:Stop()
                end)
            end

            tween(
                HolderScale,
                .4,
                {
                    Scale = 0,
                },
                Enum.EasingStyle.Cubic
            )

            task.wait(.4)

            cleanup()
        end
    )

    Settings.snap()

    Cfg.showName =
        Cfg.showName

    Cfg.showTime =
        Cfg.showTime

    NameTint.Visible =
        Cfg.showName

    NameFrame.Visible =
        Cfg.showName

    TimeLabel.Visible =
        Cfg.showTime

    connect(
        UIS.InputBegan,
        function(input, gameProcessed)
            if listening then
                if
                    input.UserInputType ~=
                    Enum.UserInputType.Keyboard
                then
                    return
                end

                listening = false

                hideKey =
                    input.KeyCode ~=
                    Enum.KeyCode.Escape
                    and
                    input.KeyCode
                    or
                    nil

                State.hideKey =
                    hideKey
                    and
                    hideKey.Name
                    or
                    nil

                saveState()

                hideButton.label.Text =
                    "Hide Bind [" ..
                    (
                        hideKey
                        and
                        keyName(hideKey)
                        or
                        "None"
                    ) ..
                    "]"

                return
            end

            if
                gameProcessed
                or
                not hideKey
                or
                input.KeyCode ~=
                hideKey
                or
                UIS:GetFocusedTextBox()
            then
                return
            end

            Gui.Enabled =
                not Gui.Enabled

            if not Gui.Enabled then
                for _, list in Lists do
                    list.target = 0
                end

                listOpen = false
            end
        end
    )
end

----------------------------------------------------------------
-- PLAYLIST
----------------------------------------------------------------

if #songs == 0 then
    Playlist.header(
        "NO SONGS FOUND"
    )
else
    Playlist.header(
        tostring(#songs) ..
        " SONGS"
    )
end

for _, category in categories do
    Playlist.header(
        category.label
    )

    for _, song in category.songs do
        local entry =
            Playlist.add(
                "song",
                song.name,
                OPT_H,
                26,
                12
            )

        song.entry =
            entry

        local record, _, image =
            icon(
                entry.frame,
                "record",
                "◉",
                13
            )

        record.Position =
            UDim2.new(
                0,
                14,
                .5,
                0
            )

        record.TextColor3 =
            SONG_ON

        entry.tick =
            function(_, visibility)
                local active =
                    cur == song

                local transparency =
                    1 -
                    (
                        active
                        and visibility
                        or 0
                    )

                record.TextTransparency =
                    transparency

                image.ImageTransparency =
                    transparency

                if active then
                    entry.label.TextColor3 =
                        SONG_ON

                    if playing then
                        record.Rotation =
                            (
                                os.clock() *
                                220
                            ) % 360
                    end
                else
                    entry.label.TextColor3 =
                        TEXT_IDLE

                    record.Rotation = 0
                end
            end

        Playlist.tap(
            entry,
            function()
                entry.flash = 1
                playSong(song)
            end
        )
    end
end

Playlist.snap()

Playlist.onOpen =
    function()
        local song =
            cur
            or
            lastSong
            or
            songs[1]

        if
            song
            and
            song.entry
        then
            Playlist.focus(
                song.entry
            )
        end
    end

----------------------------------------------------------------
-- PLAYLIST TOUCH SCROLL
----------------------------------------------------------------

local Zone =
    make(
        "Frame",
        Circle,
        {
            Name = "Zone",

            Size =
                UDim2.fromScale(
                    1,
                    1
                ),

            BackgroundTransparency = 1,

            ZIndex = 10,
        }
    )

local zoneHover = false

connect(
    Zone.MouseEnter,
    function()
        zoneHover = true
    end
)

connect(
    Zone.MouseLeave,
    function()
        zoneHover = false
    end
)

local lastWheel = 0

local function wheelScroll(amount)
    local list =
        activeList()

    if not list then
        return false
    end

    if
        os.clock() -
        lastWheel <
        .02
    then
        return true
    end

    lastWheel =
        os.clock()

    list.targetScroll =
        list.clamp(
            list.targetScroll -
            amount *
            (
                MAIN_H +
                PAD
            )
        )

    list.lastWheel =
        os.clock()

    return true
end

CAS:BindActionAtPriority(
    "OrbituneWheel",
    function(_, _, input)
        if wheelScroll(
            input.Position.Z
        ) then
            return Enum.ContextActionResult.Sink
        end

        return Enum.ContextActionResult.Pass
    end,
    false,
    Enum.ContextActionPriority.High.Value,
    Enum.UserInputType.MouseWheel
)

connections[#connections + 1] = {
    Disconnect = function()
        pcall(function()
            CAS:UnbindAction(
                "OrbituneWheel"
            )
        end)
    end,
}

----------------------------------------------------------------
-- TOUCH LIST DRAGGING
----------------------------------------------------------------

local touchInput
local touchStartY
local touchStartScroll

connect(
    Zone.InputBegan,
    function(input)
        local list =
            activeList()

        if
            input.UserInputType ~=
            Enum.UserInputType.Touch
            or
            not list
        then
            return
        end

        touchInput =
            input

        touchStartY =
            input.Position.Y

        touchStartScroll =
            list.targetScroll

        dragMoved = false
    end
)

connect(
    UIS.InputChanged,
    function(input)
        local list =
            activeList()

        if
            input ~= touchInput
            or
            not list
        then
            return
        end

        local delta =
            (
                input.Position.Y -
                touchStartY
            ) /
            HolderScale.Scale

        if
            math.abs(delta) >
            6
        then
            dragMoved = true
        end

        if dragMoved then
            list.targetScroll =
                list.clamp(
                    touchStartScroll -
                    delta
                )
        end
    end
)

connect(
    UIS.InputEnded,
    function(input)
        if input ~= touchInput then
            return
        end

        touchInput = nil

        task.delay(
            .12,
            function()
                dragMoved = false
            end
        )
    end
)

----------------------------------------------------------------
-- KEYBOARD SHORTCUTS
----------------------------------------------------------------

connect(
    UIS.InputBegan,
    function(input, processed)
        if processed then
            return
        end

        if
            UIS:GetFocusedTextBox()
        then
            return
        end

        if
            input.KeyCode ==
            Enum.KeyCode.Space
        then
            togglePlayback()

        elseif
            input.KeyCode ==
            Enum.KeyCode.Right
        then
            nextTrack()

        elseif
            input.KeyCode ==
            Enum.KeyCode.Left
        then
            previousTrack()

        elseif
            input.KeyCode ==
            Enum.KeyCode.Up
        then
            Cfg.volume =
                math.clamp(
                    Cfg.volume + .1,
                    0,
                    10
                )

            AudioPlayer.Volume =
                Cfg.volume

        elseif
            input.KeyCode ==
            Enum.KeyCode.Down
        then
            Cfg.volume =
                math.clamp(
                    Cfg.volume - .1,
                    0,
                    10
                )

            AudioPlayer.Volume =
                Cfg.volume
        end
    end
)

----------------------------------------------------------------
-- INTRO CARD
----------------------------------------------------------------

local Card =
    make(
        "Frame",
        Circle,
        {
            Name = "Intro",

            AnchorPoint =
                Vector2.new(
                    .5,
                    .5
                ),

            Position =
                UDim2.fromScale(
                    .5,
                    .5
                ),

            Size =
                UDim2.fromScale(
                    1,
                    1
                ),

            BackgroundColor3 =
                Color3.new(
                    1,
                    1,
                    1
                ),

            BorderSizePixel = 0,

            ZIndex = 20,
        }
    )

local CardScale =
    make(
        "UIScale",
        Card
    )

make(
    "UICorner",
    Card,
    {
        CornerRadius =
            UDim.new(
                1,
                0
            ),
    }
)

make(
    "UIGradient",
    Card,
    {
        Color =
            ColorSequence.new(
                Color3.fromRGB(
                    24,
                    18,
                    44
                ),
                Color3.fromRGB(
                    12,
                    22,
                    38
                )
            ),

        Rotation = 45,
    }
)

local introTexts = {}

local function introLabel(
    text,
    y,
    width,
    height,
    size,
    color,
    transparency
)
    local label =
        make(
            "TextLabel",
            Card,
            {
                AnchorPoint =
                    Vector2.new(
                        .5,
                        .5
                    ),

                Position =
                    UDim2.fromScale(
                        .5,
                        y
                    ),

                Size =
                    UDim2.fromOffset(
                        width,
                        height
                    ),

                BackgroundTransparency = 1,

                Text = text,

                TextColor3 =
                    color,

                TextTransparency =
                    transparency
                    or 0,

                Font =
                    Enum.Font.BuilderSans,

                TextSize = size,

                TextWrapped = true,

                ZIndex = 21,
            }
        )

    introTexts[#introTexts + 1] =
        label

    return label
end

local infoText

if #songs == 0 then
    infoText =
        "No songs found"
elseif #songs == 1 then
    infoText =
        "1 song found!"
else
    infoText =
        tostring(#songs) ..
        " songs found!"
end

introLabel(
    infoText,
    .3,
    120,
    16,
    12,
    Color3.fromRGB(
        165,
        178,
        208
    )
)

introLabel(
    "ORBITUNE",
    .5,
    120,
    34,
    16,
    Color3.fromRGB(
        160,
        120,
        255
    )
)

local preloadText =
    introLabel(
        "preparing player...",
        .72,
        120,
        12,
        10,
        Color3.fromRGB(
            150,
            150,
            178
        ),
        .45
    )

local track =
    make(
        "Frame",
        Card,
        {
            AnchorPoint =
                Vector2.new(
                    .5,
                    .5
                ),

            Position =
                UDim2.fromScale(
                    .5,
                    .8
                ),

            Size =
                UDim2.fromOffset(
                    56,
                    3
                ),

            BackgroundColor3 =
                Color3.fromRGB(
                    40,
                    40,
                    62
                ),

            BorderSizePixel = 0,

            ZIndex = 21,
        }
    )

make(
    "UICorner",
    track,
    {
        CornerRadius =
            UDim.new(
                1,
                0
            ),
    }
)

local fill =
    make(
        "Frame",
        track,
        {
            Size =
                UDim2.fromScale(
                    0,
                    1
                ),

            BackgroundColor3 =
                Color3.new(
                    1,
                    1,
                    1
                ),

            BorderSizePixel = 0,

            ZIndex = 22,
        }
    )

make(
    "UICorner",
    fill,
    {
        CornerRadius =
            UDim.new(
                1,
                0
            ),
    }
)

make(
    "UIGradient",
    fill,
    {
        Color =
            ColorSequence.new(
                ACCENT_A,
                ACCENT_B
            ),
    }
)

----------------------------------------------------------------
-- INTRO ANIMATION
----------------------------------------------------------------

local ready = false

local function dismissIntro()
    tween(
        CardScale,
        .6,
        {
            Scale = 1.15,
        },
        Enum.EasingStyle.Cubic
    )

    tween(
        Card,
        .6,
        {
            BackgroundTransparency = 1,
        },
        Enum.EasingStyle.Cubic
    )

    for _, label in introTexts do
        tween(
            label,
            .45,
            {
                TextTransparency = 1,
            }
        )
    end

    tween(
        track,
        .45,
        {
            BackgroundTransparency = 1,
        }
    )

    tween(
        fill,
        .45,
        {
            BackgroundTransparency = 1,
        }
    )

    task.wait(.6)

    Card.Visible = false
end

task.spawn(function()
    local startTime =
        os.clock()

    local total =
        math.max(
            #songs,
            1
        )

    for index, song in songs do
        preloadText.Text =
            "preloading songs " ..
            index ..
            "/" ..
            #songs

        tween(
            fill,
            .12,
            {
                Size =
                    UDim2.fromScale(
                        index /
                        total,
                        1
                    ),
            }
        )

        -- Pre-cache audio safely.
        pcall(
            audioOf,
            song
        )

        if
            index % 3 == 0
        then
            task.wait()
        end
    end

    if #songs == 0 then
        tween(
            fill,
            .3,
            {
                Size =
                    UDim2.fromScale(
                        1,
                        1
                    ),
            }
        )
    end

    local elapsed =
        os.clock() -
        startTime

    task.wait(
        math.max(
            .3,
            1.8 - elapsed
        )
    )

    preloadText.Text =
        "ready"

    task.wait(.25)

    dismissIntro()

    Controls.Visible = true

    for index, scale in pops do
        task.delay(
            .07 * index,
            function()
                tween(
                    scale,
                    .4,
                    {
                        Scale = 1,
                    },
                    Enum.EasingStyle.Back
                )
            end
        )
    end

    setName(
        #songs > 0
        and
        "nothing playing"
        or
        "no songs found",
        .55
    )

    ready = true
end)

----------------------------------------------------------------
-- INITIAL LAYOUT
----------------------------------------------------------------

HolderScale.Scale = 0

tween(
    HolderScale,
    .45,
    {
        Scale = Cfg.scale,
    },
    Enum.EasingStyle.Cubic
)

Cluster.Position =
    UDim2.fromOffset(
        0,
        3
    )

----------------------------------------------------------------
-- SAVE FINAL STATE
----------------------------------------------------------------

State.rainbow =
    Cfg.rainbow

State.mode =
    Cfg.mode

State.showName =
    Cfg.showName

State.showTime =
    Cfg.showTime

State.scale =
    Cfg.scale

State.volume =
    Cfg.volume

State.shuffle =
    Cfg.shuffle

State.repeatMode =
    Cfg.repeatMode

State.rotation =
    Cfg.rotation

State.eq =
    State.eq
    or
    {}

saveState()

----------------------------------------------------------------
-- FINAL SAFETY
----------------------------------------------------------------

pcall(function()
    AudioPlayer.Volume =
        Cfg.volume
end)

print(
    "[Orbitune] Loaded " ..
    tostring(#songs) ..
    " song(s)."
)
