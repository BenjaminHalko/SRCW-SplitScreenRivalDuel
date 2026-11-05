local core = require("core")
local State, hook, try, valid = core.State, core.hook, core.try, core.valid

local PRE_RACE = "/Game/01_Union/Blueprint/Sequence/PreRace/BP_PreRaceSequence.BP_PreRaceSequence_C:"
local RUBBER_BAND_MESH = "SM_FX_Duel_RubberBand"
local STATIC_MESH_COMPONENT = "/Script/UnionSystem.UnionStaticMeshComponent"

-- Rival level, honour title and rank rows don't apply to a local duel. Hiding them lines the names up.
local VS_HIDE = {
  "PG_WS_RivalIcon", "PG_WBP_CMN_RivalLevel", "PG_WBP_HonorTitle_Plate", "PG_WBP_HonorTitle_Plate_1",
  "PG_WidgetSwitcher_0", "SizeBox_Rank_1",
}
-- Index of the plain-text label in the right player's label switcher.
local VS_RIGHT_LABEL_INDEX = 1

-- Runs at the start of every race setup.
hook(PRE_RACE .. "OnInitialize", function()
  State.raceFinished, State.finish = false, nil
  if not State.active then return end
  local r = core.RCDA()
  r:SetSelectedGameModeId(core.GM_RIVALDUEL)
  r:SetDuelMode(true)
  r:ClearRaceRivalDriverIds()
end)

-- Rival Duel layout without the rival rows, labelled P1 and P2.
local function patchVS(w)
  w:SetupVSWindowInfo(core.GM_RIVALDUEL)
  core.hideChildren(w, VS_HIDE)
  w.PG_TXT_YOU:SetText(FText("P1"))
  local sw = w.PG_WidgetSwitcher_RivalText
  sw:SetActiveWidgetIndex(VS_RIGHT_LABEL_INDEX)
  sw:GetWidgetAtIndex(VS_RIGHT_LABEL_INDEX):SetText(FText("P2"))
  -- Stop the menu music here, like 1P Rival Duel does.
  local sound = core.live("MenuSoundSubsystem")
  if valid(sound) then sound:StopBGM() end
end

-- Called by the race blueprint after it fills in the players.
core.hookAfter("/Script/UNION.DuelVSManagerActor:PlayVSWidgetInAnimation", function(ctx)
  if State.active then try("vs window", patchVS, ctx:get().VSWindowWidget) end
end)

-- Turn off red star rings. The flag is in the setup that the LoadAssets state passes on.
hook(core.raceState("LoadAssets") .. "OnInitState", function(ctx)
  if State.active then ctx:get().PreCreateParam.RedStarRingParam.bEnableRedStarRing = false end
end)

-- The duel lightning is drawn from P1's car to P2's and is owner-only, so P2 wouldn't see it.
local function shareRubberBands()
  local cls = StaticFindObject(STATIC_MESH_COMPONENT)
  for _, pawn in ipairs(FindAllOf("VehicleInRacePawn") or {}) do
    if valid(pawn) then
      for _, e in ipairs(pawn:K2_GetComponentsByClass(cls)) do
        local comp = e:get()
        local mesh = comp.StaticMesh
        if valid(mesh) and mesh:GetFName():ToString() == RUBBER_BAND_MESH and comp.bOnlyOwnerSee then
          comp:SetOnlyOwnerSee(false)
        end
      end
    end
  end
end

hook(core.raceState("Ready") .. "OnInitState", function()
  if not State.active then return end
  -- The game only marks P1 as a duel racer.
  for _, pc in ipairs(FindAllOf("AppPlayerController") or {}) do
    if valid(pc) and not pc.bIsDuelRace then pc:SetIsDuelRace(true) end
  end
  -- Deferred until the state has set up the cars' components.
  ExecuteInGameThread(function() try("lightning", shareRubberBands) end)
end)
