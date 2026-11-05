local M = {}

-- pcall that logs the error, so one failing handler doesn't break the hook.
function M.try(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then print("[SplitScreenRivalDuel] " .. label .. " " .. tostring(err) .. "\n") end
  return ok
end

-- Game mode ids. The duel's menus run as Party, its races as Rival Duel.
M.GM_PARTY, M.GM_RIVALDUEL_TOP, M.GM_RIVALDUEL = 2, 8, 11
M.VIS_VISIBLE, M.VIS_COLLAPSED, M.VIS_HIDDEN, M.VIS_HIT_TEST_INVISIBLE, M.VIS_SELF_HIT_TEST_INVISIBLE = 0, 1, 2, 3, 4

M.State = { active = false, lastFocusType = -1, playerScreenWidgets = {} }

local cache = {}
function M.cdo(path)
  local o = cache[path]
  if not (o and o:IsValid()) then
    o = StaticFindObject(path)
    cache[path] = o
  end
  return o
end
function M.RCDA() return M.cdo("/Script/UNION.Default__AppRaceConfigDataAccessor") end
function M.PRU() return M.cdo("/Script/UNION.Default__PartyRaceUtility") end
function M.widgets() return M.cdo("/Script/UMG.Default__WidgetBlueprintLibrary") end
function M.statics() return M.cdo("/Script/Engine.Default__GameplayStatics") end

function M.valid(o) return o and o:IsValid() end
function M.inVP(w) return M.valid(w) and w:IsInViewport() end
function M.collapse(w)
  if M.valid(w) and w:GetVisibility() ~= M.VIS_COLLAPSED then w:SetVisibility(M.VIS_COLLAPSED) end
end

-- Widgets not marked as variables can only be found through the widget tree.
function M.child(w, name)
  local ok, prop = pcall(function() return w[name] end)
  if ok and prop and prop.IsValid and prop:IsValid() then return prop end
  if M.valid(w.WidgetTree) then
    return StaticFindObject(w.WidgetTree:GetFullName():match("^%S+ (.+)$") .. "." .. name)
  end
end

function M.hideChildren(w, names)
  for _, n in ipairs(names) do M.collapse(M.child(w, n)) end
end

function M.firstInViewport(class)
  for _, w in ipairs(FindAllOf(class) or {}) do
    if M.inVP(w) then return w end
  end
end

local VISIBLE, INVISIBLE = { R = 1, G = 1, B = 1, A = 1 }, { R = 1, G = 1, B = 1, A = 0 }

-- Uses colour alpha because the widgets' own animations set render opacity.
function M.setDrawn(class, drawn)
  for _, w in ipairs(FindAllOf(class) or {}) do
    if M.valid(w) then w:SetColorAndOpacity(drawn and VISIBLE or INVISIBLE) end
  end
end

-- First valid instance. Right after a level change FindFirstOf can return one from the old world.
function M.live(class)
  for _, o in ipairs(FindAllOf(class) or {}) do
    if o:IsValid() then return o end
  end
end

function M.playerController(index)
  return M.statics():GetPlayerController(M.live("PlayerController"), index)
end

function M.raceHud() return M.live("BP_RaceSequence_C"):GetRaceHUDRef() end

function M.raceState(name)
  local class = "BPC_RaceSequenceState" .. name
  return "/Game/01_Union/Blueprint/Sequence/Race/State/" .. class .. "." .. class .. "_C:"
end

-- Blueprint functions don't exist until their class is loaded, so failed hooks are retried whenever an
-- instance of the class is created. Each hook is only registered once.
local pendingHooks, watchedClasses = {}, {}
local RF_DEFAULT_OR_TEMPLATE = 0x30 -- RF_ClassDefaultObject | RF_ArchetypeObject
local function attachHooks()
  local still = {}
  for _, h in ipairs(pendingHooks) do
    if not (M.valid(StaticFindObject(h.path)) and pcall(RegisterHook, h.path, h.pre, h.post)) then
      still[#still + 1] = h
    end
  end
  pendingHooks = still
end

-- For /Script/ functions pre runs before the call and post after. For blueprint functions pre already
-- runs after.
function M.hook(path, pre, post)
  local class = path:match("^(/Game/.+):")
  pendingHooks[#pendingHooks + 1] = { path = path, pre = pre, post = post }
  attachHooks()
  if class and not watchedClasses[class] then
    watchedClasses[class] = true
    NotifyOnNewObject(class, function(o)
      if #pendingHooks > 0 and not o:HasAnyFlags(RF_DEFAULT_OR_TEMPLATE) then attachHooks() end
    end)
  end
end
function M.hookAfter(path, post) M.hook(path, function() end, post) end

return M
