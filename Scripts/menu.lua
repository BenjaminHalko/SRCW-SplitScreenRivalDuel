local core = require("core")
local State, hook, try, valid = core.State, core.hook, core.try, core.valid

-- Race Park's Custom preset, the Race Rules lines shown in a duel (speed, courses) by line index, and
-- the fixed values a duel uses.
local PRESET_CUSTOM = 5
local DUEL_RULE_LINES = { [0] = true, [8] = true }
local DUEL_RACE_COUNT, COMSPEED_NONE, GROUPING_INDIVIDUAL = 1, 0, 0
local BUTTON_FOCUS_SELECTABLE = 0
-- Race Park menu music ids, replaced with 1P Rival Duel's.
local BGM_PARTYRACE = { [4] = true, [5] = true }
local BGM_RIVALDUEL = 22

local BTN = "/Game/01_Union/UI/TopMenu/WBP_TopMenu_Sub_BtnMode_Offline.WBP_TopMenu_Sub_BtnMode_Offline_C:"
local TOPSEQ = "/Game/01_Union/Blueprint/Sequence/Menu/TopMenu/BP_TopMenuSequence.BP_TopMenuSequence_C:"
local PRESET_STATE = "/Game/01_Union/Blueprint/Sequence/Menu/PartyRace/State/BPC_MenuStatePartyRaceSelectPreset.BPC_MenuStatePartyRaceSelectPreset_C:"
local CUSTOM_RULE_STATE = "/Game/01_Union/Blueprint/Sequence/Menu/PartyRace/State/BPC_MenuStatePartyRaceCustomizeRule.BPC_MenuStatePartyRaceCustomizeRule_C:"
local MENU_SEQUENCE = "/Game/01_Union/Blueprint/Sequence/Menu/PartyRace/BP_PartyRaceMenuSequence.BP_PartyRaceMenuSequence_C:"
local CHARA_STATE = "/Game/01_Union/Blueprint/Sequence/Menu/CharaMachine/BPC_CharaMachineState.BPC_CharaMachineState_C:"
local SOUND_PLAY = "/Script/UnionSystem.UnionSystemBP:SoundPlay"
local CHARA_LEVEL = "/Game/01_Union/Map/Menu/CharaMachineSelect/SL_CharaMachineSelect.SL_CharaMachineSelect_C:"

-- Background: 1P Rival Duel's course select with most of it hidden. A local duel never uses that
-- screen, so it's free to borrow.
local DUEL_MENU = "WBP_CourseSelect_RivalDuel_C"
local DUEL_MENU_CLASS = "/Game/01_Union/UI/CourseSelect/WBP_CourseSelect_RivalDuel.WBP_CourseSelect_RivalDuel_C"
local DUEL_MENU_HIDE = {
  "WBP_CourseSelect_Sub_ThumbnailSelecter", "IconSelect", "LeftArrowOverlay", "RightArrowOverlay",
  "DSP_TimeTrial_TmbArrow", "WBP_CMN_Sub_RivalReward", "WBP_CourseSelect_Sub_RivalNext",
  "WBP_CMN_ControllerBtn", "ConnectLine", "Arrow",
  "WBP_CMN_Sub_SpeedClassInfo", "Overlay_ClassBtn", "ClassSelectMouseButton", "HorizontalBox_0",
}
local BACKDROP_Z = -10
-- The 1P Rival Duel background in character select.
local CHARA_BACKDROP = "BP_UnionWidgetActor_C_4"

local CUSTOM_MATCH = "WBP_PartyRace_Sub_Option_Finalconfirm_C"
local CUSTOM_MATCH_CLASS = "/Game/01_Union/UI/PartyRace/WBP_PartyRace_Sub_Option_Finalconfirm.WBP_PartyRace_Sub_Option_Finalconfirm_C"
local CUSTOM_MATCH_HIDE = {
  "BackgroundBlur_75", "BG", "BG_Window_Base", "BG_Window_Base_Outline", "BG_Border_Pattern",
  "BG_Border_PatternCover", "PAT_PresetIcon", "TXT_Title_RuleEdit", "TXT_PresetName",
}
-- Item Select isn't shown: duels use the default items.
local CUSTOM_MATCH_UNUSED = { "WBP_PartyRace_Sub_Option_Btn_ItemSwitch" }
-- Move Custom Match's buttons and confirm bar up into the space the popup frame used.
local OPTION_BUTTONS_OFFSET, CONFIRM_BAR_OFFSET = -270, -70
-- EUINavigation values.
local NAV_LEFT, NAV_RIGHT, NAV_UP, NAV_DOWN = 0, 1, 2, 3

local FADE_BLACK = 0
-- FadeIn fades to black, FadeOut fades back in.
local FADE_IN, FADE_OUT = 0, 1
local FADE_MS = 350

local function findBackdrop()
  local found
  for _, w in ipairs(FindAllOf(DUEL_MENU) or {}) do
    if valid(w) then
      if w:IsInViewport() then return w end
      found = found or w
    end
  end
  return found
end

local function hideBackdrop()
  local w = findBackdrop()
  if core.inVP(w) then w:RemoveFromParent() end
end

local function showBackdrop()
  local w = findBackdrop()
  if not w then
    local pc = core.live("PlayerController")
    local cls = StaticFindObject(DUEL_MENU_CLASS)
    if not valid(cls) then cls = LoadAsset(DUEL_MENU_CLASS) end
    w = core.widgets():Create(pc, cls, pc)
    w.bIsFocusable = true
    w:SetVisibility(core.VIS_HIT_TEST_INVISIBLE)
  end
  if not w:IsInViewport() then
    -- Construct runs inside AddToViewport, so hide the parts afterwards.
    w:AddToViewport(BACKDROP_Z)
    core.hideChildren(w, DUEL_MENU_HIDE)
    -- Customize Gadgets prompt (LB, see hubInput).
    local gadgets = core.child(w, "WBP_CMN_Sub_GadgetCustom")
    if valid(gadgets) then
      gadgets:PlayAnimation(gadgets.GadgetCustom_In, 0, 1, 0, 1, false)
      gadgets:PlayAnimation(gadgets.GadgetCustom_Loop, 0, 0, 0, 1, false)
    end
  end
  return w
end

local function fade(direction)
  local w = core.live("UnionUITransitionManager"):GetUIFadeWidget()
  if valid(w) then w:StartFade(FADE_BLACK, direction) end
end

-- Leaving the mode: show Race Park's screens again and restore its rival-team setting.
local function deactivate()
  if not State.active then return end
  State.active, State.fadedOut, State.hubEntered, State.toMachineSelect = false, false, false, false
  core.setDrawn("PartyRacePresetSelect", true)
  core.setDrawn("WBP_MachineCharaSelect_M2_C", true)
  core.PRU():SetPartyRaceRivalExists(State.raceParkRivalExists)
  hideBackdrop()
end

-- Turn off the rival team. Marking the current team as shown stops the hub's rival cut-in.
local function activate()
  if State.active then return end
  State.active = true
  local pru = core.PRU()
  State.raceParkRivalExists = pru:IsPartyRaceRivalExists()
  pru:SetPartyRaceRivalExists(false)
  pru:SetLastCutinRivalTeamId(pru:GetSelectedRivalTeamId())
end

-- In 2P, make the Rival Duel button selectable and point it at the Party menus.
hook(BTN .. "JudgeMenuClose", function(ctx)
  local b = ctx:get()
  if b.ButtonType ~= core.GM_RIVALDUEL_TOP then return end
  if core.RCDA():GetSelectedPlayerCount() == 2 then
    b.TopMenuGameMode = core.GM_PARTY
    b.ButtonFocusType = BUTTON_FOCUS_SELECTABLE
    b:StopAnimation(b.Btn_NonActive_Loop)
    b:PlayAnimation(b.Btn_Active_Loop, 0, 1, 0, 1, false)
  else
    b.TopMenuGameMode = core.GM_RIVALDUEL_TOP
  end
end)

-- In 2P both Rival Duel and Race Park open Party, so remember which button was used.
hook(BTN .. "OnFocusReceived", function(ctx) State.lastFocusType = ctx:get().ButtonType end)

hook(TOPSEQ .. "SetGameModeId", function(_, sel)
  if sel:get() == core.GM_PARTY and State.lastFocusType == core.GM_RIVALDUEL_TOP
      and core.RCDA():GetSelectedPlayerCount() == 2 then
    activate()
  end
end)
hook(TOPSEQ .. "OnInitStateSelectGameMode", deactivate)
hook(TOPSEQ .. "OnInitStateTopMenuTop", deactivate)

-- One race, no CPUs. The menu reapplies its preset in several places, so redo this after each.
local function forceDuelSettings()
  if not State.active then return end
  local r = core.RCDA()
  r:SetRaceSettingComSpeed(COMSPEED_NONE)
  r:SetRacerCount(r:GetSelectedPlayerCount())
  r:SetRaceSettingGrouping(GROUPING_INDIVIDUAL)
  r:SetRaceSettingRaceCount(DUEL_RACE_COUNT)
  r:SetMaxRaceCount(DUEL_RACE_COUNT, true)
  r:SetDuelMode(true)
end
local RACE_CONFIG = "/Script/UNION.AppRaceConfigDataAccessor:"
-- Straight after the custom settings are applied: the CPU racers are drawn right after that.
core.hookAfter(RACE_CONFIG .. "SetCustomRaceSettingBP", forceDuelSettings)
-- Deferred: this one is called before its preset is applied.
hook(RACE_CONFIG .. "SetSelectedRaceParkPresetId", function()
  if State.active then ExecuteInGameThread(forceDuelSettings) end
end)

-- Hide the Race Rules lines a duel doesn't use, whenever the screen sets up or updates them.
local function tweakRuleScreen(scene)
  scene.SettingLineArr:ForEach(function(_, e)
    local line = e:get()
    if not DUEL_RULE_LINES[line.SettingLineIndex] then core.collapse(line) end
  end)
end
for _, fn in ipairs({ "SetPresetSetting", "SetPresetSettingFromSave", "DisableLineInCertainCondition" }) do
  core.hookAfter("/Script/UNION.CustomRaceDetailRuleScene:" .. fn, function(ctx)
    if State.active then try("race rules", tweakRuleScreen, ctx:get()) end
  end)
end

local function useCharaBackdrop()
  for _, a in ipairs(FindAllOf("BP_UnionWidgetActor_C") or {}) do
    if valid(a) and a:GetFullName():find("SL_CharaMachineSelect", 1, true) then
      local hide = a:GetFName():ToString() ~= CHARA_BACKDROP
      if a.bHidden ~= hide then a:SetActorHiddenInGame(hide) end
    end
  end
end

-- The level picks its background in Setup, every time character select is entered.
hook(CHARA_LEVEL .. "Setup", function()
  if State.active then try("duel backdrop", useCharaBackdrop) end
end)

-- Lay Custom Match out as a full screen instead of a popup, before its intro shows the popup frame.
local function styleCustomMatch(w)
  core.hideChildren(w, CUSTOM_MATCH_HIDE)
  core.hideChildren(w, CUSTOM_MATCH_UNUSED)
  local buttons, bar = core.child(w, "Horizonal_SubBtn"), core.child(w, "WBP_PartyRace_Sub_Option_Btn_OK")
  buttons:SetRenderTranslation({ X = 0, Y = OPTION_BUTTONS_OFFSET })
  bar:SetRenderTranslation({ X = 0, Y = CONFIRM_BAR_OFFSET })
  -- Navigation that led to the hidden Item Select goes to the buttons either side of it instead.
  local rules = core.child(w, "WBP_PartyRace_Sub_Option_Btn_RuleSetting")
  local crossWorlds = core.child(w, "WBP_PartyRace_Sub_Option_Btn_TeavelCouseSwitch")
  bar:SetNavigationRuleExplicit(NAV_UP, rules)
  bar:SetNavigationRuleExplicit(NAV_DOWN, rules)
  rules:SetNavigationRuleExplicit(NAV_RIGHT, crossWorlds)
  crossWorlds:SetNavigationRuleExplicit(NAV_LEFT, rules)
end
hook(CUSTOM_MATCH_CLASS .. ":Construct", function(ctx)
  if State.active then try("custom match layout", styleCustomMatch, ctx:get()) end
end)

hook("/Script/UNION.MenuSoundSubsystem:PlayBGMMenu", function(_, bgm)
  if State.active and BGM_PARTYRACE[bgm:get()] then bgm:set(BGM_RIVALDUEL) end
end)

-- Mute the select sound when the mod presses a hub button.
hook(SOUND_PLAY, function(_, sound)
  if State.silent then sound:set(CreateInvalidObject()) end
end)

-- Presses the hub's Custom button.
local function openCustomMatch()
  local hub = core.firstInViewport("PartyRacePresetSelect")
  local st = core.live("BPC_MenuStatePartyRaceSelectPreset_C")
  if not (hub and valid(st)) then return end
  hub.PresetButtonArr:ForEach(function(i, e)
    local b = e:get()
    if b._Preset == PRESET_CUSTOM then
      -- ForEach counts from 1; the button index from 0.
      State.silent = true
      local ok, err = pcall(st.OnButtonDecision, st, b, 0, i - 1)
      State.silent = false
      assert(ok, err)
    end
  end)
end

-- Same as Back on the hub (to character and machine select). The event is bound on the menu sequence.
local function backToMachineSelect(menuSequence)
  menuSequence:BndEvt__BP_PartyRaceMenuSequence_BPC_MenuStatePartyRaceSelectPreset_K2Node_ComponentBoundEvent_0_OnBackStateDelegate__DelegateSignature(0)
end

-- Custom Match is opened from Race Park's hub (which loads the custom rules). The hub is drawn
-- invisible, and its button is pressed once the hub has finished starting up so none of that ends up
-- on Custom Match. After Character & Machine on the end menu, go to character select instead.
local function hubStarted()
  if not State.hubEntered then return end
  State.hubEntered = false
  ExecuteInGameThread(function()
    if State.toMachineSelect then
      State.toMachineSelect = false
      try("back to machine select", backToMachineSelect, core.live("BP_PartyRaceMenuSequence_C"))
    else
      try("open custom match", openCustomMatch)
    end
    -- The hidden hub would steal focus from Custom Match. It's shown again on the next visit.
    core.collapse(core.firstInViewport("PartyRacePresetSelect"))
  end)
end

hook(PRESET_STATE .. "OnInitState", function(ctx)
  if not State.active then return end
  State.hubEntered = true
  -- Never draw the hub, and skip its intro.
  core.setDrawn("PartyRacePresetSelect", false)
  core.setDrawn("WBP_MachineCharaSelect_M2_C", false)
  local hub = core.firstInViewport("PartyRacePresetSelect")
  local intro = hub and hub.PartyRace_In
  if valid(intro) then hub:SetAnimationCurrentTime(intro, intro:GetEndTime()) end
  ExecuteInGameThread(function() try("show backdrop", showBackdrop) end)
  -- Coming back from Customize Gadgets, the hub finishes starting up inside this call.
  if valid(ctx:get().SubInputReceiver) then hubStarted() end
end)

-- Coming from character select, it finishes later.
hook(PRESET_STATE .. "InitSubCommand", function()
  if State.active then hubStarted() end
end)

hook(CHARA_STATE .. "OnInitState", function()
  if not State.active then return end
  State.hubEntered = false
  core.setDrawn("WBP_MachineCharaSelect_M2_C", true)
  try("hide backdrop", hideBackdrop)
  -- Undo the fade to black from Back on Custom Match.
  if State.fadedOut then
    State.fadedOut = false
    fade(FADE_OUT)
  end
end)

-- The hub turns off its LB (Customize Gadgets) input when Custom Match opens, so turn it back on while
-- Custom Match is open. RB (rival teams) does nothing without a rival. InitSubCommand replaces any
-- existing input.
local function hubInput(on)
  local st = core.live("BPC_MenuStatePartyRaceSelectPreset_C")
  if not valid(st) then return end
  if on then st:InitSubCommand() else st:FinalizeSubCommand() end
end

-- Also runs when returning from one of Custom Match's popups.
hook(CUSTOM_RULE_STATE .. "OnInitState", function()
  if not State.active then return end
  ExecuteInGameThread(function()
    try("hub input", hubInput, true)
    try("show backdrop", showBackdrop)
    local custom = core.firstInViewport(CUSTOM_MATCH)
    if custom then core.hideChildren(custom, CUSTOM_MATCH_UNUSED) end
  end)
end)

hook(CUSTOM_RULE_STATE .. "OnExitState", function()
  if not State.active then return end
  try("hub input", hubInput, false)
end)

-- Race Rules, CrossWorld Select and the final check open over Custom Match in the same state, and
-- leaving for Customize Gadgets from one of them leaves its screen behind. So LB is off while one is
-- open.
hook(CUSTOM_RULE_STATE .. "OnPartyRaceConfirmDecision", function()
  if State.active then try("hub input", hubInput, false) end
end)
for _, fn in ipairs({ "OnPartyRaceCustomFinalConfirmScene", "OnFinalCheckCencel" }) do
  hook(CUSTOM_RULE_STATE .. fn, function()
    if State.active then ExecuteInGameThread(function() try("hub input", hubInput, true) end) end
  end)
end

-- Back: hold the popup's out animation on its first frame while fading to black, then let it play.
hook(CUSTOM_RULE_STATE .. "OnFinalConfirmCancel", function()
  if not State.active then return end
  local w = core.firstInViewport(CUSTOM_MATCH)
  local out = w and w.PartyRace_Option_Out
  if not valid(out) then return end
  -- If Back is pressed during the intro, jump to its end first. Otherwise the end of the intro runs
  -- after Custom Match is gone.
  local intro = w.PartyRace_Option_In
  if valid(intro) and w:IsAnimationPlaying(intro) then w:SetAnimationCurrentTime(intro, intro:GetEndTime()) end
  w:PauseAnimation(out)
  fade(FADE_IN)
  State.fadedOut = true
  ExecuteInGameThreadWithDelay(FADE_MS, function()
    local custom = core.firstInViewport(CUSTOM_MATCH)
    local anim = custom and custom.PartyRace_Option_Out
    if valid(anim) then custom:PlayAnimation(anim, custom:GetAnimationCurrentTime(anim), 1, 0, 1, false) end
  end)
end)

-- Back on Custom Match asks for the hub; go to character select instead.
hook(MENU_SEQUENCE .. "OnCustomizeRuleCancelEvent", function(ctx)
  if State.active then try("back to machine select", backToMachineSelect, ctx:get()) end
end)
