local core = require("core")
local hud = require("hud")
local State, hook, try, valid = core.State, core.hook, core.try, core.valid

local PAUSE_SEQUENCE = "/Game/01_Union/Blueprint/Sequence/Race/BP_RacePauseMenuSequence.BP_RacePauseMenuSequence_C:"
local END_MENU_SEQUENCE = "/Game/01_Union/Blueprint/Sequence/Race/BP_RaceEndMenuSequence.BP_RaceEndMenuSequence_C:"
-- Menu content ids (DT_CommonMenuContent) and end menu icon ids.
local MENU_CONTENT = {
  TO_GADGET = 4, RETURN_TOP = 5, PARTY_SELECT = 13, PARTY_CONTINUE = 14,
  RIVALDUEL_RETRY = 18, RIVALDUEL_COURSE_SELECT = 20, RIVALDUEL_CHARACTER_SELECT = 21,
}
local PARTY_EQUIVALENT = {
  [MENU_CONTENT.RIVALDUEL_COURSE_SELECT] = MENU_CONTENT.PARTY_SELECT,
  [MENU_CONTENT.RIVALDUEL_CHARACTER_SELECT] = MENU_CONTENT.PARTY_SELECT,
}
local END_MENU_BUTTONS = 5
local ICON_NEXT, ICON_RETURN, ICON_COURSE_SELECT, ICON_GARAGE, ICON_GADGETS = 1, 4, 6, 7, 9
local END_MENU_TEXT = "/Game/VoiceBridge/Text_Common/Common_EndMenu.Common_EndMenu"
local TOP_MENU_TEXT = "/Game/VoiceBridge/Text_ModeSelect/ModeSelect_TopMenu.ModeSelect_TopMenu"

-- The game acts on the last chosen menu entry for the current game mode, so store it as a Party
-- choice.
local function carryOutAsParty(contentId)
  core.cdo("/Script/UNION.Default__AppMenuDataAccessor"):SetLastSelectedRaceMenu(contentId)
  local race = core.live("BP_RaceSequence_C")
  if valid(race) then race.RaceEndMenuContentId = contentId end
  core.RCDA():SetSelectedGameModeId(core.GM_PARTY)
end

-- Remove Retry from the pause menu.
hook(PAUSE_SEQUENCE .. "OnInitStateSelect", function()
  if not State.active then return end
  for _, b in ipairs(FindAllOf("CommonRaceMenuButtonBase") or {}) do
    if valid(b) and b:IsVisible() and b:GetContentId() == MENU_CONTENT.RIVALDUEL_RETRY then core.collapse(b) end
  end
end)

hook(PAUSE_SEQUENCE .. "OnInitStateExit", function(ctx)
  if not (State.active and core.RCDA():GetSelectedGameModeId() == core.GM_RIVALDUEL) then return end
  local mapped = PARTY_EQUIVALENT[ctx:get().SelectedContentId]
  if mapped then carryOutAsParty(mapped) end
end)

local function localText(tableId, key)
  return core.cdo("/Script/Engine.Default__KismetTextLibrary"):TextFromStringTable(FName(tableId), key)
end

local function endMenuEntry(contentId, iconId, text)
  return { ContentID = contentId, IconId = iconId, ContentText = text, bDoesNeedToPopupWarning = false,
    PopupWarningMessage = FText("") }
end

-- End menu: Play Again, Course Select (back to Custom Match), Character & Machine, Customize Gadgets,
-- Main Menu. Keeps the "new" marks.
local function useDuelEndMenu(menu)
  local flagged = {}
  for i = 1, END_MENU_BUTTONS do
    local b = menu["WBP_EndMenu_Sub_Btn_0" .. i]
    if valid(b) and b:GetVisibility() ~= core.VIS_COLLAPSED then
      flagged[b:GetContentDef().ContentID] = core.child(b, "DSP_NewIconWave"):GetVisibility() ~= core.VIS_COLLAPSED
    end
  end
  local entries = {
    endMenuEntry(MENU_CONTENT.PARTY_CONTINUE, ICON_NEXT, localText(END_MENU_TEXT, "ui_playagain")),
    endMenuEntry(MENU_CONTENT.PARTY_SELECT, ICON_COURSE_SELECT, localText(END_MENU_TEXT, "ui_courseselect")),
    endMenuEntry(MENU_CONTENT.RIVALDUEL_CHARACTER_SELECT, ICON_GARAGE, localText(TOP_MENU_TEXT, "topmenu_sub_charaselect")),
    endMenuEntry(MENU_CONTENT.TO_GADGET, ICON_GADGETS, localText(END_MENU_TEXT, "ui_gadgetcustom")),
    endMenuEntry(MENU_CONTENT.RETURN_TOP, ICON_RETURN, localText(END_MENU_TEXT, "ui_topmenu")),
  }
  for i, e in ipairs(entries) do
    local b = menu["WBP_EndMenu_Sub_Btn_0" .. i]
    b:SetupContent(core.GM_PARTY, e)
    b:SetVisibility(core.VIS_VISIBLE)
    b:SetNewIconVisible(flagged[e.ContentID] == true)
  end
end

hook(END_MENU_SEQUENCE .. "OnInitStateSelect", function()
  if not State.active then return end
  -- Results are done, so tickets from elsewhere (e.g. gadget customization) count again.
  State.raceFinished = false
  local menu = core.firstInViewport("WBP_EndMenu_C")
  if menu then try("race: end menu", useDuelEndMenu, menu) end
end)

-- Character & Machine goes back through the duel's menu, which then opens character select.
hook(END_MENU_SEQUENCE .. "OnInitStateExit", function(ctx)
  if not State.active then return end
  hud.clearPlayerScreens()
  local chosen = ctx:get().SelectedContentId
  State.toMachineSelect = chosen == MENU_CONTENT.RIVALDUEL_CHARACTER_SELECT
  carryOutAsParty(PARTY_EQUIVALENT[chosen] or chosen)
end)
