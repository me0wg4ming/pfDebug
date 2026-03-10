local hide_self = true
local scanned = {}
local frameref = {}
local frames = {}
local data = {}
local frameAddon = {}  -- cache: data key -> addon name, populated once at hook time
local frameInfo  = {}  -- cache: data key -> { frameType, parentName }, populated once at hook time

-- Maximum recursion depth to prevent stack overflow
local MAX_SCAN_DEPTH = 50

-- search as many frames as possible that are children or subtree elements of
-- the given parent frame. all found frames are saved in the `frames`-table
local function ScanFrames(parent, parentname, depth)
  depth = depth or 0
  if depth > MAX_SCAN_DEPTH then return end
  
  -- find as many frames as possible by scanning through the parent's childs.
  local scanqueue

  if pcall(function() return parent:GetChildren() end) and parent:GetChildren() then
    scanqueue = { parent, { parent:GetChildren() } }
  else
    scanqueue = { parent }
  end

  for _, queue in pairs(scanqueue) do
    for objname, frame in pairs(queue) do
      if frame and type(frame) == "table" and frame ~= parent then
        local name = tostring(frame)
        if name and not scanned[name] then
          scanned[name] = true

          -- code hierarchy detection for unnamed frames
          local obj = "nil"
          local objname = type(objname) == "string" and objname or ""
          local parentname = type(parentname) == "string" and parentname or ""
          if objname == "_G" or frame == getfenv(0) or objname == "" then
            parentname = ""
            objname = ""
            obj = ""
          else
            obj = parentname .. ( parentname ~= "" and "." or "" ) .. objname
          end

          -- Safe frame type check
          local hasFrameType = false
          if pcall(function() hasFrameType = frame:GetFrameType() ~= nil end) then
            if hasFrameType then
              frames[name] = frame
              if objname then
                frameref[name] = obj
              end
              
              -- Recursive call with depth counter
              ScanFrames(frame, obj, depth + 1)
            end
          end
        end
      end
    end
  end
end

-- data[name] = { count, totalTime, totalMem, gcHits, minTime, maxTime }
--   [1] count     - total executions
--   [2] totalTime - sum of runtimes (seconds)
--   [3] totalMem  - sum of memory delta (kB, GC-corrected)
--   [4] gcHits    - how often a GC cycle was detected during this call
--   [5] minTime   - fastest single call (seconds)
--   [6] maxTime   - slowest single call (seconds)

local function MeasureFunction(func, name)
  local memBefore = gcinfo()
  local time = GetTime()

  local success = pcall(func)

  local runtime = GetTime() - time
  local memAfter = gcinfo()
  local runmem = memAfter - memBefore

  if runtime < 0 then runtime = 0 end

  -- Detect GC cycle: memory dropped during this call
  local gcHit = 0
  if memAfter < memBefore then
    gcHit = 1
    runmem = 0  -- don't count negative mem as consumption
  end
  if runmem < 0 or runmem > 10000 then runmem = 0 end

  if not data[name] then
    data[name] = { 1, runtime, runmem, gcHit, runtime, runtime }
  else
    data[name][1] = data[name][1] + 1
    data[name][2] = data[name][2] + runtime
    data[name][3] = data[name][3] + runmem
    data[name][4] = data[name][4] + gcHit
    if runtime < data[name][5] then data[name][5] = runtime end
    if runtime > data[name][6] then data[name][6] = runtime end
  end
end

--A little helper function to iterate over sorted pairs using "in pairs"
local function spairs(t, index, reverse)
  -- collect the keys
  local keys = {}
  for k in pairs(t) do keys[table.getn(keys)+1] = k end

  local order
  if reverse then
    order = function(t,a,b) return t[b][index] < t[a][index] end
  else
    order = function(t,a,b) return t[b][index] > t[a][index] end
  end
  table.sort(keys, function(a,b) return order(t, a, b) end)

  -- return the iterator function
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

-- round values
local function round(input, places)
  if not places then places = 0 end
  if type(input) == "number" and type(places) == "number" then
    local pow = 1
    for i = 1, places do pow = pow * 10 end
    return floor(input * pow + 0.5) / pow
  end
end

-- [[ Addon Identification ]]
-- Build a lookup: lowercase addon folder name -> display name
local addonNames = {}
local numAddons = GetNumAddOns and GetNumAddOns() or 0
for i = 1, numAddons do
  local name = GetAddOnInfo(i)
  if name then
    addonNames[string.lower(name)] = name
  end
end

-- Prefix map: short frame name prefix -> addon display name.
-- Many addons use a short prefix for all their frames (e.g. pfUI -> "pf" prefix).
-- We populate this from addon folder names, then override with known mappings.
local prefixMap = {}
for lower, display in pairs(addonNames) do
  prefixMap[lower] = display
end
-- Known short-prefix mappings (add more as needed)
local knownPrefixes = {
  -- pfUI and its modules
  ["pf"]              = "pfUI",
  -- Ace libraries
  ["ace"]             = "AceLibrary",
  -- CleveRoids
  ["cleve"]           = "CleveRoids",
  -- Rackensack
  ["rack"]            = "Rackensack",
  -- Blizzard FrameXML frames (expand as needed)
  ["uiparent"]        = "Blizzard",
  ["worldframe"]      = "Blizzard",
  ["blizzard"]        = "Blizzard",
  ["chatframe"]       = "Blizzard",
  ["minimap"]         = "Blizzard",
  ["questlog"]        = "Blizzard",
  ["gamemenu"]        = "Blizzard",
  ["gametime"]        = "Blizzard",
  ["paperdoll"]       = "Blizzard",
  ["character"]       = "Blizzard",
  ["spellbook"]       = "Blizzard",
  ["talent"]          = "Blizzard",
  ["friends"]         = "Blizzard",
  ["social"]          = "Blizzard",
  ["guild"]           = "Blizzard",
  ["raid"]            = "Blizzard",
  ["party"]           = "Blizzard",
  ["actionbar"]       = "Blizzard",
  ["multibar"]        = "Blizzard",
  ["mainmenubar"]     = "Blizzard",
  ["bag"]             = "Blizzard",
  ["container"]       = "Blizzard",
  ["inventory"]       = "Blizzard",
  ["loot"]            = "Blizzard",
  ["merchant"]        = "Blizzard",
  ["trade"]           = "Blizzard",
  ["auction"]         = "Blizzard",
  ["mail"]            = "Blizzard",
  ["bank"]            = "Blizzard",
  ["cast"]            = "Blizzard",
  ["target"]          = "Blizzard",
  ["player"]          = "Blizzard",
  ["focus"]           = "Blizzard",
  ["buff"]            = "Blizzard",
  ["debuff"]          = "Blizzard",
  ["tooltip"]         = "Blizzard",
  ["game"]            = "Blizzard",
  ["world"]           = "Blizzard",
  ["cinematic"]       = "Blizzard",
  ["loading"]         = "Blizzard",
  ["glyph"]           = "Blizzard",
  ["macro"]           = "Blizzard",
  ["keybinding"]      = "Blizzard",
  ["video"]           = "Blizzard",
  ["sound"]           = "Blizzard",
  ["interface"]       = "Blizzard",
  ["help"]            = "Blizzard",
  ["ticket"]          = "Blizzard",
  ["gmsurvey"]        = "Blizzard",
  ["stacksplit"]      = "Blizzard",
  ["durability"]      = "Blizzard",
  ["honor"]           = "Blizzard",
  ["pvp"]             = "Blizzard",
  ["battlefield"]     = "Blizzard",
  ["worldmap"]        = "Blizzard",
  ["taxiframe"]       = "Blizzard",
  ["gossip"]          = "Blizzard",
  ["greeting"]        = "Blizzard",
  ["npc"]             = "Blizzard",
  ["petition"]        = "Blizzard",
  ["tabard"]          = "Blizzard",
  ["inspect"]         = "Blizzard",
  ["stable"]          = "Blizzard",
  ["dressup"]         = "Blizzard",
  ["color"]           = "Blizzard",
  ["opaque"]          = "Blizzard",
  ["screenshot"]      = "Blizzard",
  ["errorframe"]      = "Blizzard",
  ["uierrors"]        = "Blizzard",
  ["systemmessage"]   = "Blizzard",
  ["achievement"]     = "Blizzard",
}
for k, v in pairs(knownPrefixes) do
  prefixMap[k] = v
end

-- Parse debugstack() to find the outermost AddOns\ caller that is not pfDebug.
-- Used once at scan time for anonymous frames (no recognisable name prefix).
local function GetAddonFromStack()
  if not debugstack then return nil end
  local stack = debugstack()
  local found = nil
  local pos = 1
  while true do
    local s, e, addonFolder = string.find(stack, "AddOns\\([^\\/]+)", pos)
    if not s then break end
    local lower = string.lower(addonFolder)
    if lower ~= "pfdebug" then
      found = addonFolder
    end
    pos = e + 1
  end
  if found then
    local lower = string.lower(found)
    return addonNames[lower] or found
  end
  return nil
end

local function GetAddonForFrame(dataKey)
  if not dataKey or dataKey == "" then return nil end
  -- 1. Cached result populated during Scan (most accurate)
  if frameAddon[dataKey] then return frameAddon[dataKey] end
  -- 2. Try progressively longer prefix matches (longest wins to avoid false matches)
  local lower = string.lower(dataKey)
  local best = nil
  local bestLen = 0
  for prefix, addon in pairs(prefixMap) do
    local plen = string.len(prefix)
    if plen > bestLen and string.sub(lower, 1, plen) == prefix then
      best = addon
      bestLen = plen
    end
  end
  return best
end
-- [[ GUI Code ]]
local mainwidth = 780
local analyzer = CreateFrame("Frame", "pfDebugAnalyzer", UIParent)
pfDebug.CreateBackdrop(analyzer)
analyzer:SetPoint("CENTER", 0, 0)
analyzer:SetHeight(380)
analyzer:SetWidth(mainwidth)
analyzer:SetMovable(true)
analyzer:EnableMouse(true)
analyzer:SetClampedToScreen(true)
analyzer:SetScript("OnMouseDown",function() this:StartMoving() end)
analyzer:SetScript("OnMouseUp",function() this:StopMovingOrSizing() end)
analyzer:Hide()
analyzer:SetFrameStrata("FULLSCREEN_DIALOG")
analyzer:SetScript("OnUpdate", function()
  if not this.active then return end
  this.timer = (this.timer or 0) + arg1
  this.elapsed = (this.elapsed or 0) + arg1
  if this.timer < 0.5 then return end
  local dt = this.timer
  this.timer = 0

  -- Rolling CPS history: cpsHistory[key] = ring buffer of last 5 dCount values
  -- Each slot = dCount over one 0.5s interval. Smoothed CPS = sum / (5 * dt)
  if not this.cpsHistory then this.cpsHistory = {} end
  if not this.cpsHistoryIdx then this.cpsHistoryIdx = {} end
  local HIST = 5  -- number of intervals to average over

  local i = 1
  local maxval = 0
  local sortby = this.sortby or 3
  local isDelta = analyzer.deltaMode
  local snap = this.snapshot or {}

  for frame, entry in spairs(data, sortby, true) do
    if i > 12 then break end
    -- Self-filter
    if hide_self and (strfind(frame, "pfDebug") or strfind(frame, "pfDebugAnalyzer")) then
      -- skip
    elseif ( analyzer.onupdate:GetChecked() and strfind(frame, ":OnUpdate") ) or
           ( analyzer.onevent:GetChecked() and strfind(frame, ":OnEvent") ) then

      -- Delta values (difference since last snapshot)
      local prev   = snap[frame]
      local dCount = entry[1] - (prev and prev[1] or 0)
      local dTime  = entry[2] - (prev and prev[2] or 0)
      local dMem   = entry[3] - (prev and prev[3] or 0)

      -- Smoothed CPS: rolling average of dCount over last HIST intervals
      local hist = this.cpsHistory[frame]
      if not hist then
        hist = {}
        for h = 1, HIST do hist[h] = 0 end
        this.cpsHistory[frame] = hist
        this.cpsHistoryIdx[frame] = 1
      end
      local idx = this.cpsHistoryIdx[frame]
      hist[idx] = dCount
      this.cpsHistoryIdx[frame] = math.mod(idx, HIST) + 1
      local sum = 0
      for h = 1, HIST do sum = sum + hist[h] end
      local cps = (dt > 0) and (sum / (HIST * dt)) or 0

      -- Which values to sort/display by
      local dispEntry
      if isDelta then
        dispEntry = { dCount, dTime, dMem, entry[4], entry[5], entry[6] }
      else
        dispEntry = entry
      end

      local sortVal = dispEntry[sortby]
      if i == 1 then maxval = sortVal end
      if maxval == 0 then maxval = 1 end  -- avoid div/0 on zero-activity frames

      analyzer.bars[i].data = entry  -- always full data for tooltip
      analyzer.bars[i].name = frame
      analyzer.bars[i].cps  = cps

      analyzer.bars[i]:SetMinMaxValues(0, maxval)
      analyzer.bars[i]:SetValue(sortVal)

      local text = gsub(frame, ":", "|cffaaaaaa:|r")
      text = gsub(text, "OnEvent%((%w+)%)", "|cffffcc00OnEvent|cffaaaaaa(|cffffaa00%1|cffaaaaaa)")
      text = gsub(text, "OnUpdate%(%)", "|cff33ffccOnUpdate|cffaaaaaa%(%)")
      local addonName = GetAddonForFrame(frame)
      if addonName then
        text = text .. " |cff888888[" .. addonName .. "]|r"
      end
      -- (CPS badge removed - unreliable for both OnUpdate=framerate and sparse OnEvent)
      analyzer.bars[i].left:SetText(text)

      if sortby == 1 then
        analyzer.bars[i].right:SetText(
          "|cffffffff" .. (isDelta and dCount or dispEntry[1]) .. "|cffaaaaaa x|r")
      elseif sortby == 2 then
        -- Time mode: total ms + avg ms/call
        local totalMs = round((isDelta and dTime or dispEntry[2])*1000, 2)
        local avgMs   = (entry[1] > 0) and round(entry[2]/entry[1]*1000, 3) or 0
        analyzer.bars[i].right:SetText(
          "|cffffffff" .. totalMs .. "|cffaaaaaa ms  avg " ..
          avgMs .. " ms|r")
      elseif sortby == 3 then
        -- Memory mode: total kB + avg kB/call + kB/s (delta-based rate)
        local totalKB = round((isDelta and dMem or dispEntry[3]), 1)
        local avgKB   = (entry[1] > 0) and round(entry[3]/entry[1], 4) or 0
        local rateKB  = (dt > 0) and round(dMem / dt, 2) or 0
        analyzer.bars[i].right:SetText(
          "|cffffffff" .. totalKB .. "|cffaaaaaa kB  " ..
          avgKB .. " kB/c  " ..
          rateKB .. " kB/s|r")
      end

      local perc = (maxval > 0) and (sortVal / maxval) or 0
      local r1, g1, b1, r2, g2, b2
      if perc <= 0.5 then
        perc = perc * 2
        r1, g1, b1 = 0, 1, 0
        r2, g2, b2 = 1, 1, 0
      else
        perc = perc * 2 - 1
        r1, g1, b1 = 1, 1, 0
        r2, g2, b2 = 1, 0, 0
      end
      analyzer.bars[i]:SetStatusBarColor(r1+(r2-r1)*perc, g1+(g2-g1)*perc, b1+(b2-b1)*perc, .2)
      i = i + 1
    end
  end

  -- Update snapshot for next delta interval
  this.snapshot = {}
  for k, v in pairs(data) do
    this.snapshot[k] = { v[1], v[2], v[3] }
  end

  -- hide remaining bars
  for j=i,12 do
    analyzer.bars[j]:SetValue(0)
    analyzer.bars[j].name = nil
    analyzer.bars[j].data = nil
    analyzer.bars[j].cps  = nil
    analyzer.bars[j].left:SetText("")
    analyzer.bars[j].right:SetText("")
  end
end)

analyzer.title = analyzer:CreateFontString(nil, "LOW", "GameFontWhite")
analyzer.title:SetFont(STANDARD_TEXT_FONT, 14)
analyzer.title:SetPoint("TOP", 0, -10)
analyzer.title:SetText("|cff33ffccpf|rDebug: |cffffcc00Analyzer")

analyzer.close = CreateFrame("Button", "pfDebugAnalyzerClose", analyzer, "UIPanelCloseButton")
analyzer.close:SetWidth(20)
analyzer.close:SetHeight(20)
analyzer.close:SetPoint("TOPRIGHT", 0,0)
analyzer.close:SetScript("OnClick", function()
  analyzer:Hide()
end)

analyzer.toolbar = CreateFrame("Frame", "pfDebugAnalyzerToolbar", analyzer)
pfDebug.CreateBackdrop(analyzer.toolbar)
analyzer.toolbar:SetWidth(mainwidth - 10)
analyzer.toolbar:SetHeight(25)
analyzer.toolbar:SetPoint("TOP", 0, -35)

analyzer.scan = CreateFrame("Button", "pfDebugAnalyzerAddHooks", analyzer.toolbar, "UIPanelButtonTemplate")
pfDebug.SkinButton(analyzer.scan)
analyzer.scan:SetHeight(20)
analyzer.scan:SetWidth(90)
analyzer.scan:SetPoint("LEFT", 3, 0)
analyzer.scan:SetText("Scan")
analyzer.scan:SetScript("OnClick", function()
  -- reset known frames
  scanned = {}
  frames = {}
  frameref = {}

  -- scan through all frames on _G
  ScanFrames(getfenv(), "", 0)

  -- calculate the findings
  local framecount = 0
  for _ in pairs(frames) do framecount = framecount + 1 end

  -- hide pfDebug from the stats
  if hide_self then
    frames[tostring(pfDebug)] = nil
    frames[tostring(pfDebugAnalyzer)] = nil
  end

  -- add hooks to functions
  local functioncount = 0
  for _, frame in pairs(frames) do
    if frame.GetScript and not frame.pfDEBUGHooked then
      frame.pfDEBUGHooked = true

      local name = (frame.GetName and type(frame.GetName) == "function" and frame:GetName()) and frame:GetName() or frameref[tostring(frame)] or tostring(frame)

      -- Detect addon ownership once at scan time.
      -- For named frames: use prefix map (longest match wins).
      -- For anonymous/unrecognised frames: fall back to debugstack() which at
      -- scan time still shows the addon that called SetScript originally via
      -- the frame table reference we found during ScanFrames.
      local detectedAddon = GetAddonForFrame(name)
      if not detectedAddon then
        -- Anonymous frame (name is a table address like "table: 0x...") -
        -- try to get the addon from the script handler's debug info
        if frame.GetScript then
          local handler = frame:GetScript("OnUpdate") or frame:GetScript("OnEvent")
          if handler then
            -- Use the function's debug string if available (SuperWoW/Nampower expose this)
            local info = tostring(handler)
            local _, _, addonFolder = string.find(info, "AddOns\\([^\\/\"]+)")
            if addonFolder then
              local lower = string.lower(addonFolder)
              detectedAddon = addonNames[lower] or addonFolder
            end
          end
        end
      end

      -- Collect frame metadata once at scan time (free, no runtime overhead)
      local frameType = "Frame"
      local parentName = nil
      pcall(function()
        frameType = frame:GetFrameType() or "Frame"
        local parent = frame:GetParent()
        if parent and parent.GetName then
          parentName = parent:GetName()
        end
      end)

      -- If parent frame belongs to a non-Blizzard addon, that addon "owns" this
      -- frame (e.g. pfUI skins ChatFrame1 as a child of pfChatLeft).
      -- Parent addon overrides name-prefix detection, but only when it is more
      -- specific (i.e. not Blizzard itself).
      if parentName and parentName ~= "" then
        local parentAddon = GetAddonForFrame(parentName)
        if parentAddon and parentAddon ~= "Blizzard" then
          detectedAddon = parentAddon
        end
      end

      -- Hook OnEvent with error protection
      local OnEvent = frame:GetScript("OnEvent")
      if OnEvent then
        functioncount = functioncount + 1
        local original = OnEvent
        local dataKey = name .. ":OnEvent"  -- base key for addon lookup
        frame:SetScript("OnEvent", function()
          local success, err = pcall(function()
            local evtName = event or "UNKNOWN"
            local key = name .. ":OnEvent(" .. evtName .. ")"
            MeasureFunction(original, key)
            -- Cache addon + frameInfo for this key (first time only)
            if not frameAddon[key] then
              if detectedAddon then frameAddon[key] = detectedAddon end
              frameInfo[key] = { frameType, parentName }
            end
          end)
          if not success then
            frame:SetScript("OnEvent", original)
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffDebug: Error hooking " .. name .. ":OnEvent - |cffff3333" .. tostring(err))
          end
        end)
      end

      -- Hook OnUpdate with error protection
      local OnUpdate = frame:GetScript("OnUpdate")
      if OnUpdate then
        functioncount = functioncount + 1
        local original = OnUpdate
        local key = name .. ":OnUpdate()"
        if detectedAddon then frameAddon[key] = detectedAddon end
        frameInfo[key] = { frameType, parentName }
        frame:SetScript("OnUpdate", function()
          local success, err = pcall(function()
            MeasureFunction(original, key)
          end)
          if not success then
            frame:SetScript("OnUpdate", original)
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffDebug: Error hooking " .. name .. ":OnUpdate - |cffff3333" .. tostring(err))
          end
        end)
      end
    end
  end

  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffDebug: Found |cff33ffcc" .. framecount .. "|r frames and hooked |cff33ffcc" .. functioncount .. "|r new functions.")
  analyzer.autoupate:Enable()
  analyzer.autoupate:Click()
end)

analyzer.autoupate = CreateFrame("Button", "pfDebugAnalyzerAutoUpdate", analyzer.toolbar, "UIPanelButtonTemplate")
pfDebug.SkinButton(analyzer.autoupate)
analyzer.autoupate:SetHeight(20)
analyzer.autoupate:SetWidth(140)
analyzer.autoupate:SetPoint("LEFT", 96, 0)
analyzer.autoupate:SetText("Auto-Update (|cffffaaaaOFF|r)")
analyzer.autoupate:Disable()
analyzer.autoupate:SetScript("OnClick", function()
  if analyzer.active then
    analyzer.active = false
    analyzer.autoupate:SetText("Auto-Update (|cffffaaaaOFF|r)")
  else
    analyzer.active = true
    analyzer.autoupate:SetText("Auto-Update (|cffaaffaaON|r)")
  end
end)

analyzer.count = CreateFrame("Button", "pfDebugAnalyzerSortTime", analyzer.toolbar, "UIPanelButtonTemplate")
pfDebug.SkinButton(analyzer.count)
analyzer.count:SetHeight(20)
analyzer.count:SetWidth(60)
analyzer.count:SetPoint("RIGHT", -3, 0)
analyzer.count:SetText("Count")
analyzer.count:SetScript("OnClick", function() analyzer.sortby = 1 end)
analyzer.count:SetScript("OnLeave", function() GameTooltip:Hide() end)
analyzer.count:SetScript("OnEnter", function()
  GameTooltip:ClearLines()
  GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 0)
  GameTooltip:AddLine("Order By Execution Count", 1,1,1,1)
  GameTooltip:Show()
end)

analyzer.time = CreateFrame("Button", "pfDebugAnalyzerSortTime", analyzer.toolbar, "UIPanelButtonTemplate")
pfDebug.SkinButton(analyzer.time)
analyzer.time:SetHeight(20)
analyzer.time:SetWidth(60)
analyzer.time:SetPoint("RIGHT", -66, 0)
analyzer.time:SetText("Time")
analyzer.time:SetScript("OnClick", function() analyzer.sortby = 2 end)
analyzer.time:SetScript("OnLeave", function() GameTooltip:Hide() end)
analyzer.time:SetScript("OnEnter", function()
  GameTooltip:ClearLines()
  GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 0)
  GameTooltip:AddLine("Order By Execution Time", 1,1,1,1)
  GameTooltip:Show()
end)

analyzer.memory = CreateFrame("Button", "pfDebugAnalyzerSortTime", analyzer.toolbar, "UIPanelButtonTemplate")
pfDebug.SkinButton(analyzer.memory)
analyzer.memory:SetHeight(20)
analyzer.memory:SetWidth(60)
analyzer.memory:SetPoint("RIGHT", -129, 0)
analyzer.memory:SetText("Memory")
analyzer.memory:SetScript("OnClick", function() analyzer.sortby = 3 end)
analyzer.memory:SetScript("OnLeave", function() GameTooltip:Hide() end)
analyzer.memory:SetScript("OnEnter", function()
  GameTooltip:ClearLines()
  GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 0)
  GameTooltip:AddLine("Order By Memory Consumption", 1,1,1,1)
  GameTooltip:Show()
end)

analyzer.onupdate = CreateFrame("CheckButton", "pfDebugAnalyzerShowUpdate", analyzer.toolbar, "UICheckButtonTemplate")
analyzer.onupdate:SetPoint("RIGHT", -195, 0)
analyzer.onupdate:SetWidth(16)
analyzer.onupdate:SetHeight(16)
analyzer.onupdate:SetChecked(true)
analyzer.onupdate:SetScript("OnLeave", function() GameTooltip:Hide() end)
analyzer.onupdate:SetScript("OnEnter", function()
  GameTooltip:ClearLines()
  GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 0)
  GameTooltip:AddLine("Display |cff33ffccOnUpdate", 1,1,1,1)
  GameTooltip:Show()
end)

analyzer.onevent = CreateFrame("CheckButton", "pfDebugAnalyzerShowEvent", analyzer.toolbar, "UICheckButtonTemplate")
analyzer.onevent:SetPoint("RIGHT", -215, 0)
analyzer.onevent:SetWidth(16)
analyzer.onevent:SetHeight(16)
analyzer.onevent:SetChecked(true)
analyzer.onevent:SetScript("OnLeave", function() GameTooltip:Hide() end)
analyzer.onevent:SetScript("OnEnter", function()
  GameTooltip:ClearLines()
  GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 0)
  GameTooltip:AddLine("Display |cffffcc00OnEvent", 1,1,1,1)
  GameTooltip:Show()
end)

analyzer.bars = {}
for i=1,12 do
  analyzer.bars[i] = CreateFrame("StatusBar", nil, analyzer)
  analyzer.bars[i]:SetPoint("TOP", 0, -i*26 -40)
  analyzer.bars[i]:SetWidth(mainwidth - 10)
  analyzer.bars[i]:SetHeight(22)
  analyzer.bars[i]:SetMinMaxValues(0,100)
  analyzer.bars[i]:SetValue(0)
  analyzer.bars[i]:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
  analyzer.bars[i]:EnableMouse(true)
  analyzer.bars[i]:SetScript("OnEnter", function()
    if not this.name or not this.data then return end
    local name = this.name
    local d = this.data
    local count    = "|cffffffff" .. d[1] .. "|cffaaaaaax"
    local time     = "|cffffffff" .. round(d[2]*1000, 5) .. " |cffaaaaaams"
    local time_avg = "|cffffffff" .. round(d[2]/d[1]*1000, 5) .. " |cffaaaaaams"
    local time_min = "|cffffffff" .. round((d[5] or 0)*1000, 5) .. " |cffaaaaaams"
    local time_max = "|cffffffff" .. round((d[6] or 0)*1000, 5) .. " |cffaaaaaams"
    local mem      = "|cffffffff" .. round(d[3], 5) .. " |cffaaaaaakB"
    local mem_avg  = "|cffffffff" .. round(d[3]/d[1], 5) .. " |cffaaaaaakB"
    local gcHits   = d[4] or 0

    name = gsub(name, ":", "|cffaaaaaa:|r")
    name = gsub(name, "OnEvent%((%w+)%)", "|cffffcc00OnEvent|cffaaaaaa(|cffffaa00%1|cffaaaaaa)")
    name = gsub(name, "OnUpdate%(%)", "|cff33ffccOnUpdate|cffaaaaaa%(%)")

    GameTooltip:ClearLines()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT", -10, -5)
    local addonName = GetAddonForFrame(this.name)
    if addonName then
      GameTooltip:AddLine(name .. " |cff888888[" .. addonName .. "]|r", 1,1,1,1)
    else
      GameTooltip:AddLine(name, 1,1,1,1)
    end

    -- Frame metadata
    local info = frameInfo[this.name]
    if info then
      local ftype  = info[1] or "?"
      local parent = info[2]
      GameTooltip:AddDoubleLine("Frame Type:", "|cffffffff" .. ftype .. "|r")
      if parent and parent ~= "" then
        GameTooltip:AddDoubleLine("Parent Frame:", "|cffffffff" .. parent .. "|r")
      end
    end
    GameTooltip:AddLine(" ")

    -- Execution stats
    GameTooltip:AddDoubleLine("Execution Count:", count)
    GameTooltip:AddDoubleLine("Overall Time:", time)
    GameTooltip:AddDoubleLine("Average Time:", time_avg)
    GameTooltip:AddDoubleLine("Min / Max Time:", time_min .. " |cffaaaaaa/ |r" .. time_max)
    GameTooltip:AddLine(" ")

    -- Memory stats
    GameTooltip:AddDoubleLine("Overall Memory:", mem)
    GameTooltip:AddDoubleLine("Average Memory:", mem_avg)

    -- GC info
    if gcHits > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("|cffff9900GC cycles during call:|r", "|cffff9900" .. gcHits .. "x|r")
    end

    GameTooltip:Show()
  end)

  analyzer.bars[i]:SetScript("OnLeave", function()
    if not this.name or not this.data then return end
    GameTooltip:Hide()
  end)
  analyzer.bars[i].left = analyzer.bars[i]:CreateFontString(nil, "HIGH", "GameFontWhite")
  analyzer.bars[i].left:SetPoint("LEFT", 5, 0)
  analyzer.bars[i].left:SetJustifyH("LEFT")

  analyzer.bars[i].right = analyzer.bars[i]:CreateFontString(nil, "HIGH", "GameFontWhite")
  analyzer.bars[i].right:SetPoint("RIGHT", -5, 0)
  analyzer.bars[i].right:SetJustifyH("RIGHT")

  pfDebug.CreateBackdrop(analyzer.bars[i])
end

-- Reset button — clears all accumulated data without re-scanning
analyzer.reset = CreateFrame("Button", "pfDebugAnalyzerReset", analyzer.toolbar, "UIPanelButtonTemplate")
pfDebug.SkinButton(analyzer.reset)
analyzer.reset:SetHeight(20)
analyzer.reset:SetWidth(90)
analyzer.reset:SetPoint("LEFT", 239, 0)
analyzer.reset:SetText("Reset")
analyzer.reset:SetScript("OnClick", function()
  for k in pairs(data) do data[k] = nil end
  analyzer.snapshot   = {}
  analyzer.elapsed    = 0
  analyzer.cpsHistory = {}
  analyzer.cpsHistoryIdx = {}
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfDebug:|r Analyzer data reset.")
end)
analyzer.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
analyzer.reset:SetScript("OnEnter", function()
  GameTooltip:ClearLines()
  GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 0)
  GameTooltip:AddLine("Clear all accumulated data", 1,1,1,1)
  GameTooltip:AddLine("|cffaaaaaaKeeps hooks active, just resets counters", 1,1,1,1)
  GameTooltip:Show()
end)

-- Delta mode button — shows activity since last 0.5s interval instead of totals
analyzer.deltaMode = false
analyzer.delta = CreateFrame("Button", "pfDebugAnalyzerDelta", analyzer.toolbar, "UIPanelButtonTemplate")
pfDebug.SkinButton(analyzer.delta)
analyzer.delta:SetHeight(20)
analyzer.delta:SetWidth(90)
analyzer.delta:SetPoint("LEFT", 332, 0)
analyzer.delta:SetText("Delta (|cffffaaaaOFF|r)")
analyzer.delta:SetScript("OnClick", function()
  analyzer.deltaMode = not analyzer.deltaMode
  if analyzer.deltaMode then
    analyzer.delta:SetText("Delta (|cffaaffaaON|r)")
  else
    analyzer.delta:SetText("Delta (|cffffaaaaOFF|r)")
  end
end)
analyzer.delta:SetScript("OnLeave", function() GameTooltip:Hide() end)
analyzer.delta:SetScript("OnEnter", function()
  GameTooltip:ClearLines()
  GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 0)
  GameTooltip:AddLine("Delta Mode: show activity per 0.5s interval", 1,1,1,1)
  GameTooltip:AddLine("|cffaaaaaaInstead of accumulated totals since Scan", 1,1,1,1)
  GameTooltip:Show()
end)

-- GC Cleanup log button
analyzer.gclog = CreateFrame("Button", "pfDebugAnalyzerGCLog", analyzer.toolbar, "UIPanelButtonTemplate")
pfDebug.SkinButton(analyzer.gclog)
analyzer.gclog:SetHeight(20)
analyzer.gclog:SetWidth(90)
analyzer.gclog:SetPoint("LEFT", 425, 0)
analyzer.gclog:SetText("GC Log")
analyzer.gclog:SetScript("OnClick", function()
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfDebug:|r GC Cleanup Log:")
  DEFAULT_CHAT_FRAME:AddMessage("  Total cleanups: |cffffffff" .. pfDebug.cleanupCount .. "|r  Total freed: |cffffffff" .. floor(pfDebug.cleanupTotal/1024*10+0.5)/10 .. " MB|r")
  if table.getn(pfDebug.cleanupLog) == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa(no cleanups recorded yet)|r")
  else
    for i, entry in ipairs(pfDebug.cleanupLog) do
      DEFAULT_CHAT_FRAME:AddMessage("  " .. i .. ". |cffffffff" .. entry.clocktime .. "|r  freed: |cff33ffcc" .. entry.freed .. " kB|r  (+" .. floor(entry.time) .. "s uptime)")
    end
  end
end)
analyzer.gclog:SetScript("OnLeave", function() GameTooltip:Hide() end)
analyzer.gclog:SetScript("OnEnter", function()
  GameTooltip:ClearLines()
  GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT", 0, 0)
  GameTooltip:AddLine("Print last " .. pfDebug.cleanupLogMax .. " GC cleanups to chat", 1,1,1,1)
  GameTooltip:Show()
end)

-- add analyzer GUI to pfDebug table
pfDebug.analyzer = analyzer