-- pfDebug:
-- A little tool to monitor the memory usage, peaks and garbage collection.
-- I haven't put too much effort in this. Don't expect to see rocket science here.



-- Small function to provide compatiblity to pfUI backdrops
local CreateBackdrop = pfUI and pfUI.api and pfUI.api.CreateBackdrop or function(frame)
  frame:SetBackdrop({
    bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
    edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
    insets = {left = -1, right = -1, top = -1, bottom = -1},
  })
  frame:SetBackdropColor(0,0,0,.75)
  frame:SetBackdropBorderColor(.1,.1,.1,1)
end

local SkinButton = pfUI and pfUI.api and pfUI.api.SkinButton or function(frame) return end

local pfDebug = CreateFrame("Button", "pfDebug", UIParent)

pfDebug.CreateBackdrop = CreateBackdrop
pfDebug.SkinButton = SkinButton

pfDebug.lastTime = GetTime()
pfDebug.lastMem = 999999999
pfDebug.curMem = 999999999

pfDebug.lastTimeMS = GetTime()
pfDebug.lastMemMS = 999999999
pfDebug.curMemMS = 999999999

pfDebug.gc = 0

-- GC Cleanup tracking
pfDebug.cleanupCount = 0
pfDebug.cleanupTotal = 0
pfDebug.cleanupLog = {}  -- ring buffer of last 5 cleanups: {time, freed, clocktime}
pfDebug.cleanupLogMax = 5

pfDebug:SetPoint("CENTER", 0, 0)
pfDebug:SetHeight(105)
pfDebug:SetWidth(200)
CreateBackdrop(pfDebug)
pfDebug:RegisterEvent("PLAYER_ENTERING_WORLD")
pfDebug:SetScript("OnEvent", function() this:Show() end)
pfDebug:Hide()

pfDebug:SetMovable(true)
pfDebug:EnableMouse(true)
pfDebug:SetClampedToScreen(true)
pfDebug:SetScript("OnMouseDown",function()
  if arg1 == "RightButton" then
    pfDebug.analyzer:Show()
  else
    this:StartMoving()
  end
end)
pfDebug:SetScript("OnMouseUp",function() this:StopMovingOrSizing() end)
pfDebug:SetScript("OnClick",function()
  pfDebug.bar:SetValue(0)
end)

pfDebug.rate = pfDebug:CreateFontString("pfDebugMemRate", "LOW", "GameFontWhite")
pfDebug.rate:SetPoint("TOPLEFT", 3, -3)

pfDebug.curmax = pfDebug:CreateFontString("pfDebugMemCurMax", "LOW", "GameFontWhite")
pfDebug.curmax:SetPoint("TOPLEFT", 3, -23)
pfDebug.last = pfDebug:CreateFontString("pfDebugMemLast", "LOW", "GameFontWhite")
pfDebug.last:SetPoint("TOPLEFT", 3, -43)

pfDebug.bar = CreateFrame("StatusBar", nil, pfDebug)
pfDebug.bar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
pfDebug.bar:SetStatusBarColor(1,.3,.3,1)
pfDebug.bar:SetPoint("BOTTOMLEFT", pfDebug, "BOTTOMLEFT", 1, 1)
pfDebug.bar:SetPoint("BOTTOMRIGHT", pfDebug, "BOTTOMRIGHT", -1, 1)
pfDebug.bar:SetHeight(20)
pfDebug.bar:SetMinMaxValues(0, 0)
pfDebug.bar:SetValue(20)

pfDebug.cleanups = pfDebug:CreateFontString("pfDebugMemCleanups", "LOW", "GameFontWhite")
pfDebug.cleanups:SetPoint("TOPLEFT", 3, -63)

pfDebug.barcap = pfDebug.bar:CreateFontString("pfDebugMemBarCap", "OVERLAY", "GameFontWhite")
pfDebug.barcap:SetPoint("LEFT", 2, 0)
pfDebug.barcap:SetTextColor(1,1,1)

pfDebug:SetScript("OnUpdate", function()
  -- OPTIMIZED: Track total time with arg1 for GetTime() replacements
  this.totalTime = (this.totalTime or 0) + arg1
  
  -- First throttle: 0.1s updates
  this.timerMS = (this.timerMS or 0) + arg1
  if this.timerMS >= 0.1 and this.totalTime > 2 then
    this.timerMS = 0
    this.lastMemMS = this.curMemMS
    this.curMemMS, this.gc = gcinfo()

    if this.lastMemMS > this.curMemMS then
      this.lastCleanUp = this.totalTime
      this.lastCleanUpTime = date("%H:%M:%S")
      -- Track GC cleanup stats
      local freed = this.lastMemMS - this.curMemMS
      -- Only count realistic GC values (ignore GC threshold artifacts > 500 MB)
      if freed > 0 and freed < 512000 then
        pfDebug.cleanupCount = pfDebug.cleanupCount + 1
        pfDebug.cleanupTotal = pfDebug.cleanupTotal + freed
        -- Add to ring buffer
        local log = pfDebug.cleanupLog
        if table.getn(log) >= pfDebug.cleanupLogMax then
          table.remove(log, 1)
        end
        table.insert(log, { time = this.totalTime, freed = freed, clocktime = this.lastCleanUpTime })
      end
    end

    local barval, newval = this.bar:GetValue(), ( this.curMemMS - this.lastMemMS )
    if newval > barval and newval > 0 then
      this.bar:SetMinMaxValues(0, newval)
      this.bar:SetValue(newval)
      this.barcap:SetText("|cff33ffccLast Peak (ms):|r " .. newval .. "|cffaaaaaa KB")
      pfDebug.bar:SetStatusBarColor(1,.3,.3, newval/10)
    else
      this.bar:SetValue(barval - .5)
      pfDebug.bar:SetStatusBarColor(1,.3,.3, barval/10)
    end
  end

  -- Second throttle: 1s updates
  this.timer1s = (this.timer1s or 0) + arg1
  if this.timer1s >= 1 then
    this.timer1s = 0
    if this.lastCleanUp and this.lastCleanUpTime then
      pfDebug:SetWidth(pfDebug.last:GetStringWidth() + 10)
      pfDebug.last:SetText("|cff33ffccLast Cleanup:|cffffffff " .. this.lastCleanUpTime .. " |cffaaaaaa(" .. SecondsToTime(this.totalTime - this.lastCleanUp) .. " ago)")
    end

    this.lastMem = this.curMem
    this.curMem, this.gc = gcinfo()

    if this.lastMem > this.curMem then
      pfDebug.last:SetText("|cff33ffccLast Cleanup:|cffffffff " .. date("%H:%M"))
    end

    this.curmax:SetText("|cff33ffccCurrent / Max:|cffffffff " .. floor(this.curMem/1024) .. " / " .. floor(this.gc/1024) .. "|cffaaaaaa MB")
    this.rate:SetText("|cff33ffccCurrent Rate:|cffffffff " .. this.curMem - this.lastMem .. "|cffaaaaaa kB/s")
    this.cleanups:SetText("|cff33ffccCleanups:|cffffffff " .. pfDebug.cleanupCount .. "|cffaaaaaa x  freed: " .. floor(pfDebug.cleanupTotal/1024*10+0.5)/10 .. "|cffaaaaaa MB total")
  end
end)
