-- Netskope two-step email auto-fill for Hammerspoon (v7)
-- Step 1: Netskope page  -> email 1 -> AX-press "Continue"
-- Step 2: Microsoft page -> email 2 -> Enter
-- Key events are sent DIRECTLY to the Netskope process (can't leak to other apps).
-- Timers are stored globally so they can't be garbage-collected (v6 step-2 bug).
--
-- Hotkeys (fallback): Cmd+Alt+1 = step 1, Cmd+Alt+2 = step 2

local APP_NAME = "Netskope Client"
-- Step 2 now triggers by detecting the Microsoft page (no static delay)

local STEP1 = {
  name = "step1",
  email = "<user email>@kkpfg.com",
  buttonPattern = "continue",
  fieldX = 0.50, fieldY = 0.68,
  buttonX = 0.50, buttonY = 0.78,
}
local STEP2 = {
  name = "step2",
  email = "<user email>@phatrasec.com",
  useEnter = true,               -- Microsoft page submits on Enter
  fieldX = 0.50, fieldY = 0.24,
}

local ax = require("hs.axuielement")

-- Global holders so timers/filters survive garbage collection
autofillTimers = {}
local function after(delay, fn)
  local t
  t = hs.timer.doAfter(delay, function()
    autofillTimers[t] = nil
    fn()
  end)
  autofillTimers[t] = t
  return t
end

local function findElement(root, matchFn, depth)
  depth = depth or 0
  if depth > 25 or not root then return nil end
  local ok, role = pcall(function() return root:attributeValue("AXRole") end)
  if ok and role and matchFn(root, role) then return root end
  local children = root:attributeValue("AXChildren")
  if children then
    for _, child in ipairs(children) do
      local found = findElement(child, matchFn, depth + 1)
      if found then return found end
    end
  end
  return nil
end

local function clickAt(win, fx, fy)
  local ok, f = pcall(function() return win:frame() end)
  if not ok or not f then return end
  hs.eventtap.leftClick({x = f.x + f.w * fx, y = f.y + f.h * fy})
end

local function currentNetskopeWindow()
  local app = hs.application.get(APP_NAME)
  if app then return app:focusedWindow() or app:mainWindow() end
  return nil
end

local function runStep(step)
  local app = hs.application.get(APP_NAME)
  local win = currentNetskopeWindow()
  if not app or not win then
    print("[netskope-autofill] " .. step.name .. ": no Netskope app/window, skipping")
    return
  end
  print("[netskope-autofill] " .. step.name .. ": starting, window=" .. tostring(win:title()))
  pcall(function() win:focus() end)

  after(0.4, function()
    local axWin = ax.windowElement(win)
    local field = findElement(axWin, function(el, role)
      return role == "AXTextField" or role == "AXTextArea"
    end)
    local button = nil
    if step.buttonPattern then
      button = findElement(axWin, function(el, role)
        if role ~= "AXButton" then return false end
        local title = tostring(el:attributeValue("AXTitle") or el:attributeValue("AXDescription") or ""):lower()
        return title:find(step.buttonPattern) ~= nil
      end)
    end

    if field then
      print("[netskope-autofill] " .. step.name .. ": AX focusing field")
      field:setAttributeValue("AXFocused", true)
    else
      print("[netskope-autofill] " .. step.name .. ": no AX field, clicking position")
      clickAt(win, step.fieldX, step.fieldY)
    end

    after(0.4, function()
      -- keys go directly to the Netskope process
      hs.eventtap.keyStroke({"cmd"}, "a", 0, app)
      hs.eventtap.keyStrokes(step.email, app)
      print("[netskope-autofill] " .. step.name .. ": typed email")

      if step.useEnter then
        after(0.6, function()
          print("[netskope-autofill] " .. step.name .. ": submitting with Enter")
          hs.eventtap.keyStroke({}, "return", 0, app)
        end)
        return
      end

      -- Otherwise wait for the button to enable, then AX-press it
      local attempts = 0
      local pressTimer
      pressTimer = hs.timer.doEvery(0.4, function()
        attempts = attempts + 1
        local enabled = button and button:attributeValue("AXEnabled")
        if enabled or attempts >= 8 then
          pressTimer:stop()
          autofillTimers[pressTimer] = nil
          if button and enabled then
            print("[netskope-autofill] " .. step.name .. ": AX pressing '" .. step.buttonPattern .. "'")
            button:performAction("AXPress")
          else
            print("[netskope-autofill] " .. step.name .. ": fallback click on button position")
            clickAt(win, step.buttonX, step.buttonY)
          end
        end
      end)
      autofillTimers[pressTimer] = pressTimer
    end)
  end)
end

-- Detect the Microsoft page by its content ("Next" button or "Sign in" text)
local function microsoftPageVisible()
  local win = currentNetskopeWindow()
  if not win then return false end
  local axWin = ax.windowElement(win)
  local found = findElement(axWin, function(el, role)
    if role == "AXButton" then
      local t = tostring(el:attributeValue("AXTitle") or el:attributeValue("AXDescription") or ""):lower()
      if t:find("next") then return true end
    end
    if role == "AXStaticText" or role == "AXHeading" then
      local v = tostring(el:attributeValue("AXValue") or el:attributeValue("AXTitle") or ""):lower()
      if v:find("sign in") then return true end
    end
    return false
  end)
  return found ~= nil
end

-- Poll until the Microsoft page appears, then run step 2 immediately
local function waitThenRunStep2()
  local elapsed = 0
  local pollTimer
  pollTimer = hs.timer.doEvery(0.3, function()
    elapsed = elapsed + 0.3
    if microsoftPageVisible() then
      pollTimer:stop()
      autofillTimers[pollTimer] = nil
      print("[netskope-autofill] Microsoft page detected after " .. elapsed .. "s")
      after(0.4, function() runStep(STEP2) end)  -- tiny settle time for the field
    elseif elapsed >= 20 then
      pollTimer:stop()
      autofillTimers[pollTimer] = nil
      print("[netskope-autofill] Microsoft page not detected in 20s, running step 2 anyway")
      runStep(STEP2)
    end
  end)
  autofillTimers[pollTimer] = pollTimer
end

local lastFired = 0

local function runSequence()
  if hs.timer.secondsSinceEpoch() - lastFired < 30 then return end
  lastFired = hs.timer.secondsSinceEpoch()

  after(1.0, function()
    runStep(STEP1)
    after(1.5, waitThenRunStep2)  -- start watching shortly after Continue is pressed
  end)
end

netskopeFilter = hs.window.filter.new(false)
  :setAppFilter(APP_NAME, {allowRoles = "*", visible = true})

netskopeFilter:subscribe(
  {hs.window.filter.windowCreated, hs.window.filter.windowVisible, hs.window.filter.windowFocused},
  function(win, appName, event)
    print("[netskope-autofill] event=" .. tostring(event) .. " title=" .. tostring(win and win:title()))
    runSequence()
  end
)

hs.hotkey.bind({"cmd", "alt"}, "1", function() runStep(STEP1) end)
hs.hotkey.bind({"cmd", "alt"}, "2", function() runStep(STEP2) end)

print("[netskope-autofill] v7 loaded, watching for: " .. APP_NAME)
