local core = require("core")
local State, hook, try, valid, child = core.State, core.hook, core.try, core.valid, core.child

local M = {}

local DUEL_HUD = "/Game/01_Union/UI/Race/WBP_Race_HUD_Player01_Duel.WBP_Race_HUD_Player01_Duel_C"
local DUEL_BUTTON = "/Game/01_Union/UI/Race/WBP_Race_HUD_Player01_Duel_DB_Btn.WBP_Race_HUD_Player01_Duel_DB_Btn_C"
M.WIN_LOSE = "/Game/01_Union/UI/ResultDuel/WBP_ResultDuel_Sub_WinLose.WBP_ResultDuel_Sub_WinLose_C"
-- Countdown online duels show after the first player finishes.
local COUNTDOWN = "/Game/01_Union/UI/Race/WBP_Race_HUD_Sub_Duel_CountDown.WBP_Race_HUD_Sub_Duel_CountDown_C"
local HUD_2P = "/Game/01_Union/UI/Race/WBP_Race_HUD_Player02.WBP_Race_HUD_Player02_C"
local RACE_UI = "/Script/UnionRun.UnionRaceUIInterface:"
local RACE_SEQUENCE = "/Game/01_Union/Blueprint/Sequence/Race/BP_RaceSequence.BP_RaceSequence_C:"

-- Parts of the duel HUD that the 2P HUD already has or that a local duel doesn't need.
local DUEL_HUD_HIDE = {
  "WBP_Race_HUD_Sub_ItemIconSet_Simple", "WBP_Race_HUD_Sub_ItemIcon_Simple_Duel", "RingBase_Rival",
  "WBP_Race_HUD_Sub_Ring_Duel", "WBP_Race_HUD_CourseMap", "WBP_Race_HUD_Sub_RSR_5rings_Simple", "WBP_Race_HUD_Sub_LAP",
  "CanvasPanel_ItemWarningArea", "WBP_Race_HUD_Player01_Duel_DB_Btn",
}

-- P2's item frame is a mirrored copy of P1's, using the red ring art.
local P1_ITEM_SET, P2_ITEM_SET = "WBP_Race_HUD_Sub_ItemIconSet_Simple_P1", "WBP_Race_HUD_Sub_ItemIconSet_Simple_P2"
local ITEM_SET_PADDING = { Left = 0, Top = -30, Right = 0, Bottom = 0 }
local P2_RING_TEXTURE = "/Game/01_Union/UI/Race/Texture/Duel/UI_Race_HUD_Duel_VSBase_ItemYou_Rev.UI_Race_HUD_Duel_VSBase_ItemYou_Rev"
local P2_FRAME_POSITION = { X = -74, Y = 320 }
local P2_RING_PADDING = { Left = 0, Top = 5, Right = -10, Bottom = 0 }
local ALIGN_TOP, ALIGN_CENTER, ALIGN_RIGHT = 1, 2, 3
local FLOW_RIGHT_TO_LEFT = 3
local TOP_RIGHT = { Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } }

-- Middle column Y positions, in 3840x2160 layout units from the centre.
local DISTANCE_Y = -640
local CUT_INS = { WBP_Race_HUD_Sub_DuelCutIn_P1 = 500, WBP_Race_HUD_Sub_DuelCutIn_Rival = 750 }
local CUT_IN_SCALE = 0.3
local CENTRE = { Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } }
local BUTTON_ANCHORS = { [0] = { X = 0.25, Y = 0.72 }, [1] = { X = 0.75, Y = 0.72 } }
-- Duel Boost prompt parts that get shown and hidden.
local BUTTON_PARTS = { "Overlay_Btn", "Overlay_Core", "BG_Light" }
local RANK_DISPLAYS = { [0] = "WBP_Race_HUD_Sub_Rank_P1", [1] = "WBP_Race_HUD_Sub_Rank_P2" }

-- Z order above the race HUD.
local PLAYER_SCREEN_Z = 20
local FILL = { Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } }

-- Adds a widget to one player's half of the screen. It isn't part of the race HUD, so it stays when
-- the HUD is hidden. clearPlayerScreens removes it.
function M.onPlayerScreen(pci, class, anchors, alignment)
  local pc = core.playerController(pci)
  local w = core.widgets():Create(pc, StaticFindObject(class), pc)
  w:SetAnchorsInViewport(anchors)
  w:SetAlignmentInViewport(alignment)
  w:AddToPlayerScreen(PLAYER_SCREEN_Z)
  State.playerScreenWidgets[#State.playerScreenWidgets + 1] = w
  return w
end

function M.clearPlayerScreens()
  for _, w in ipairs(State.playerScreenWidgets) do
    if valid(w) then w:RemoveFromParent() end
  end
  State.playerScreenWidgets = {}
end

local function addItemSet(frame, set)
  -- The 2P HUD scales item sets to 0.8.
  set:SetRenderScale({ X = 1, Y = 1 })
  local s = frame:AddChildToOverlay(set)
  s:SetHorizontalAlignment(ALIGN_CENTER)
  s:SetVerticalAlignment(ALIGN_CENTER)
  s:SetPadding(ITEM_SET_PADDING)
end

local function placeItemSets(hud, duel)
  addItemSet(child(duel, "Self_Overlay_Item"), child(hud, P1_ITEM_SET))

  local frame = child(duel, "Rival_Overlay_Item")
  local fs = frame.Slot
  fs:SetAnchors(TOP_RIGHT)
  fs:SetAlignment({ X = 1, Y = 0 })
  fs:SetAutoSize(true)
  fs:SetPosition(P2_FRAME_POSITION)
  local ring = child(duel, "ItemIconBase_Rival")
  ring:SetBrushFromTexture(StaticFindObject(P2_RING_TEXTURE), false)
  -- The ring art is for the left side. Flipping it puts the ring in the mirrored spot.
  local scale = ring.RenderTransform.Scale
  ring:SetRenderScale({ X = -scale.X, Y = scale.Y })
  ring.Slot:SetHorizontalAlignment(ALIGN_RIGHT)
  ring.Slot:SetVerticalAlignment(ALIGN_TOP)
  ring.Slot:SetPadding(P2_RING_PADDING)
  local p2 = child(hud, P2_ITEM_SET)
  addItemSet(frame, p2)
  -- Right to left with the main item on the right, to mirror P1's set.
  p2.FlowDirectionPreference = FLOW_RIGHT_TO_LEFT
  child(p2, "ItemnIcon_01").Slot:SetHorizontalAlignment(ALIGN_RIGHT)
end

local function fillDuelHud(hud, duel)
  local slot = child(hud, "CanvasPanel_0"):AddChildToCanvas(duel)
  slot:SetAnchors(FILL)
  slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
  duel:SetVisibility(core.VIS_SELF_HIT_TEST_INVISIBLE)
  duel:InitializeOnConstruct()
  core.hideChildren(duel, DUEL_HUD_HIDE)

  placeItemSets(hud, duel)

  local column
  for name, y in pairs(CUT_INS) do
    local c = child(duel, name)
    c.Slot:SetPosition({ X = 0, Y = y })
    c:SetRenderScale({ X = CUT_IN_SCALE, Y = CUT_IN_SCALE })
    column = c:GetParent()
  end
  -- Move the distance counter from the top bar to the middle column.
  local distance = column:AddChildToCanvas(duel.WidgetSwitcher_Distance:GetParent():GetParent())
  distance:SetAnchors(CENTRE)
  distance:SetAlignment({ X = 0.5, Y = 0.5 })
  distance:SetAutoSize(true)
  distance:SetPosition({ X = 0, Y = DISTANCE_Y })

  local buttons, countdowns = {}, {}
  local root = child(duel, "CanvasPanel_0")
  for i = 0, 1 do
    -- Created with the player's controller so the prompt shows that player's button.
    local b = core.widgets():Create(duel, StaticFindObject(DUEL_BUTTON), core.playerController(i))
    local bs = root:AddChildToCanvas(b)
    bs:SetAnchors({ Minimum = BUTTON_ANCHORS[i], Maximum = BUTTON_ANCHORS[i] })
    bs:SetAlignment({ X = 0.5, Y = 0.5 })
    bs:SetAutoSize(true)
    for _, n in ipairs(BUTTON_PARTS) do core.collapse(b[n]) end
    buttons[i] = b
    -- The countdown widget is designed full screen.
    countdowns[i] = M.onPlayerScreen(i, COUNTDOWN, FILL, { X = 0, Y = 0 })
    core.collapse(countdowns[i])
  end
  return {
    widget = duel, buttons = buttons, countdowns = countdowns,
    ranks = { [0] = child(hud, RANK_DISPLAYS[0]), [1] = child(hud, RANK_DISPLAYS[1]) },
    shown = {}, allowed = {}, charged = {}, boosting = {}, finished = {},
  }
end

-- If building fails, remove the partly built duel HUD.
local function buildDuelHud(hud)
  local duel = core.widgets():Create(hud, StaticFindObject(DUEL_HUD), core.playerController(0))
  local ok, result = pcall(fillDuelHud, hud, duel)
  if not ok then
    duel:RemoveFromParent()
    error(result)
  end
  State.duelHud = result
end

-- The start countdown fills in names, portraits and P2's gadget plate. P1's plate is set here, and the
-- gauge's charge count is available by now.
local function initAtStart(d)
  d.widget:InitializeOnCountdown()
  d.chargeRate = 1 / d.widget:GetDuelGaugeSplitCount()
  local p1 = child(d.widget, "WBP_Race_HUD_Sub_GadgetIcon_Simple_P1")
  p1:SetVisibility(core.VIS_SELF_HIT_TEST_INVISIBLE)
  p1:SetPlateData(0, false, {})
end

-- Built at CreateRace: both player controllers exist by then (on Play Again P2's is only created after
-- LoadAssets), and nobody has an item yet (a starting item gets lost when its item set is moved).
-- LoadAsset can't run inside a hook, hence ExecuteInGameThread below.
local function addDuelHud()
  assert(valid(core.playerController(0)) and valid(core.playerController(1)), "a player controller is missing")
  for _, path in ipairs({ DUEL_HUD, DUEL_BUTTON, M.WIN_LOSE, COUNTDOWN, P2_RING_TEXTURE }) do
    if not valid(StaticFindObject(path)) then LoadAsset(path) end
  end
  buildDuelHud(core.raceHud())
end

-- Runs however the race is left, including from the pause menu.
hook(RACE_SEQUENCE .. "ReceiveEndPlay", function()
  M.clearPlayerScreens()
  State.duelHud, State.finish = nil, nil
end)

hook(core.raceState("CreateRace") .. "OnInitState", function()
  if State.active then ExecuteInGameThread(function() try("race: duel hud", addDuelHud) end) end
end)

hook(core.raceState("Ready") .. "OnInitState", function()
  if State.active and State.duelHud then try("race: duel hud start", initAtStart, State.duelHud) end
end)
-- Duel events the 2P HUD doesn't handle are hooked on the race UI interface. Ones its blueprint does
-- handle are hooked on the blueprint, since interface hooks miss them. Only plain values are read
-- because the game also sends these to HUDs that are being destroyed. None of these events has more
-- than three parameters.
local function onEvent(path, fn)
  hook(path, function(_, a, b, c)
    local d = State.duelHud
    if d then try(path, fn, d, a and a:get(), b and b:get(), c and c:get()) end
  end)
end
local function onDuelEvent(event, fn) onEvent(RACE_UI .. event, fn) end
function M.onHudEvent(event, fn) onEvent(HUD_2P .. ":" .. event, fn) end

-- Show the prompt when a boost is charged and allowed; hide it while boosting and after finishing.
function M.updateButton(d, pci)
  local b = d.buttons[pci]
  local on = (d.allowed[pci] and d.charged[pci] and not (d.boosting[pci] or d.finished[pci])) == true
  if not b or d.shown[pci] == on then return end
  d.shown[pci] = on
  local vis = on and core.VIS_SELF_HIT_TEST_INVISIBLE or core.VIS_COLLAPSED
  for _, n in ipairs(BUTTON_PARTS) do b[n]:SetVisibility(vis) end
  b:SetDispOn(on)
  if on then
    b:OnCharged()
    b.WidgetSwitcher_Btn:SetActiveWidget(b.WBP_Race_Sub_BtnGuide)
    -- Set up like the game's own duel button: the labels for this player's controller and their duel
    -- boost key.
    local guide = b.WBP_Race_Sub_BtnGuide
    guide.PlayerControllerIndex = pci
    guide:SetBtnText(pci)
    guide:DuelUltimateGuideOn(pci)
  else
    b.WBP_Race_Sub_BtnGuide:DuelUltimateGuideOff()
  end
end

onDuelEvent("SetDuelGaugeRate", function(d, pci, rate, dt)
  d.widget:UpdateGaugeRate(pci, rate, dt)
  d.charged[pci] = d.chargeRate ~= nil and rate >= d.chargeRate
  M.updateButton(d, pci)
end)
onDuelEvent("SetDuelGaugeBoostRate", function(d, pci, rate) d.widget:UpdateBoostRemainRate(pci, rate) end)
onDuelEvent("ChangeDuelGaugeToBoost", function(d, pci)
  d.widget:StartBoostMode(pci)
  d.boosting[pci] = true
  M.updateButton(d, pci)
end)
onDuelEvent("ChangeDuelGaugeToNormal", function(d, pci)
  d.widget:FinishBoostMode(pci)
  d.boosting[pci] = false
  M.updateButton(d, pci)
end)
onDuelEvent("SetControlDuelUltimateVisibility", function(d, pci, on)
  d.allowed[pci] = on
  M.updateButton(d, pci)
end)
onDuelEvent("DuelUseUltimate", function(d, pci)
  d.widget:OnUseUltimate(pci)
  d.buttons[pci]:OnUsed()
end)
onDuelEvent("DuelUseItem", function(d, pci, item) d.widget:PlayItemUseCutIn(pci, item) end)
onDuelEvent("FireDuelAttackItemHitInfo", function(d, info) d.widget:PlayItemHitCutIn(info) end)
onDuelEvent("FireDuelAttackItemGuardInfo", function(d, info) d.widget:PlayItemGuardCutIn(info) end)

-- The distance only shows while both players' rank displays do. The value is from P1's side
-- (negative when P1 is behind); the minus sign is dropped since the colour already shows who leads.
onDuelEvent("SetDuelDistanceToRival", function(d, pci, dist)
  local both = d.ranks[0]:GetVisibility() ~= core.VIS_COLLAPSED
    and d.ranks[1]:GetVisibility() ~= core.VIS_COLLAPSED
  if d.distanceShown ~= both then
    d.distanceShown = both
    d.widget:SetEnableDistanceToRival(both)
  end
  d.widget:SetDistanceToRival(pci, dist)
  if dist >= 0 then return end
  local text = d.widget.WidgetSwitcher_Distance:GetActiveWidget()
  local s = text:GetText():ToString()
  if s:sub(1, 1) == "-" then text:SetText(FText(s:sub(2))) end
end)
-- The crown follows P1's rank.
M.onHudEvent("SetRankIndex", function(d, pci, rank) if pci == 0 then d.widget:UpdateRank(rank) end end)

-- Hide the HUD completely once the out animation ends. Otherwise the results play the out animation
-- again, which shows the HUD for a moment.
function M.hideRaceHud()
  local d = State.duelHud
  if d then
    d.widget:HideRaceUIDuelWidget()
    for _, b in pairs(d.buttons) do core.collapse(b) end
  end
  local hud = core.raceHud()
  hud:PlayAnimation(hud.HUD_Out, 0, 1, 0, 1, false)
  ExecuteInGameThreadWithDelay(math.ceil(hud.HUD_Out:GetEndTime() * 1000), function()
    try("race: hud hidden", function()
      local seq = core.live("BP_RaceSequence_C")
      if valid(seq) then seq:GetRaceHUDRef():SetVisibility(core.VIS_HIDDEN) end
    end)
  end)
end

return M
