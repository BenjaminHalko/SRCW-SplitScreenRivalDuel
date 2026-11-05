local core = require("core")
local hud = require("hud")
local State, hook, try = core.State, core.hook, core.try

local RESULT_STATES = "/Game/01_Union/Blueprint/Sequence/Race/ResultState/"
local DUEL_RESULT = RESULT_STATES .. "BPC_RaceResultDuelResult.BPC_RaceResultDuelResult_C:"
local DUEL_MISSION_RESULT = RESULT_STATES .. "BPC_RaceResultDuelMissionResult.BPC_RaceResultDuelMissionResult_C:"
local GOAL_TEXT = "/Game/01_Union/UI/Race/WBP_Race_GoalText.WBP_Race_GoalText_C"
local GOAL_TEXT_PLAYER = { WBP_Race_GoalText_P1 = 0, WBP_Race_GoalText_P2 = 1 }
-- ERaceSequenceState values.
local RACE_STATE_DRIVE, RACE_STATE_GOAL, RACE_STATE_GADGET_PLATE, RACE_STATE_DUEL_RESULT_RIVAL = 14, 16, 28, 30
local WIN_LOSE_POSITION, WIN_LOSE_SCALE = { X = 0.5, Y = 0.42 }, 0.5
local FINISH_COUNTDOWN = 5
local SECOND_MS = 1000

local function paused()
  return core.statics():IsGamePaused(core.live("PlayerController"))
end

local function announce(pci, won)
  local at = { Minimum = WIN_LOSE_POSITION, Maximum = WIN_LOSE_POSITION }
  local w = hud.onPlayerScreen(pci, hud.WIN_LOSE, at, { X = 0.5, Y = 0.5 })
  w:SetRenderScale({ X = WIN_LOSE_SCALE, Y = WIN_LOSE_SCALE })
  if won then w:PlayWinAnimation() else w:PlayLoseAnimation() end
end

-- f.held: the game tried to go to Goal and was kept in Drive (see the last hook).
local function endRace(f)
  f.over = true
  if f.held then core.live("BPC_RaceSequenceStateDrive_C"):SetNextRaceSequenceState(RACE_STATE_GOAL) end
  announce(f.winner, true)
  announce(f.loser, false)
end

local function countDown(f, n)
  if State.finish ~= f or f.loserFinished or not core.valid(f.countdown) then return end
  if n == 0 then
    -- Show the game's FINISH for the loser, same as crossing the line.
    core.raceHud():FireFinishText(f.loser)
    return
  end
  -- Don't count down while paused.
  local still = paused()
  if not still then
    f.countdown.TXT_CountDown:SetText(FText(tostring(n)))
    f.countdown:PlayAnimation(f.countdown.OneCount_InOut, 0, 1, 0, 1, false)
  end
  ExecuteInGameThreadWithDelay(SECOND_MS, function() try("finish countdown", countDown, f, still and n or n - 1) end)
end

local function playerFinished(d, pci)
  local f = State.finish
  if not f then
    f = { winner = pci, loser = 1 - pci, countdown = d.countdowns[1 - pci], finishOver = {} }
    State.finish = f
    f.countdown:SetVisibility(core.VIS_SELF_HIT_TEST_INVISIBLE)
    countDown(f, FINISH_COUNTDOWN)
  elseif pci == f.loser and not f.loserFinished then
    f.loserFinished = true
    core.collapse(f.countdown)
  end
end

hud.onHudEvent("FireFinishText", function(d, pci)
  d.widget:PlayGoalCutIn(pci)
  d.finished[pci] = true
  hud.updateButton(d, pci)
  playerFinished(d, pci)
end)

-- A FINISH animation ended.
hook(GOAL_TEXT .. ":OnFinished", function(ctx)
  local f = State.finish
  if not (State.active and f) or f.over then return end
  local pci = GOAL_TEXT_PLAYER[ctx:get():GetFName():ToString()]
  if pci == nil then return end
  f.finishOver[pci] = true
  if f.finishOver[0] and f.finishOver[1] then try("race: end", endRace, f) end
end)

hook(core.raceState("Goal") .. "OnInitState", function()
  if not State.active then return end
  State.raceFinished = true
  try("race: hud out", hud.hideRaceHud)
end)

-- The results wait on Rival Duel's win/lose screen, so it stays but is invisible.
hook(DUEL_RESULT .. "CreateResultDuelWidget", function(ctx)
  if State.active then ctx:get().ResultDuelWidget:SetRenderOpacity(0) end
end)

-- No tickets for duel races. They're credited when the results start.
hook("/Script/UNION.PlayerLevelUtilityLibrary:AddDonpaTicket", function(_, amount)
  if State.active and State.raceFinished then amount:set(0) end
end)
-- Skip the honours screen.
hook(DUEL_MISSION_RESULT .. "OnInitState", function(ctx)
  if State.active then ctx:get():OnDuelResulDisplayEnd() end
end)

-- Skip Rival Duel's CPU rival result, and stay in Drive until both FINISH animations are done.
hook("/Script/UNION.RaceSequenceStateBase:SetNextRaceSequenceState", function(_, nextState)
  if not State.active then return end
  local state = nextState:get()
  if state == RACE_STATE_DUEL_RESULT_RIVAL then
    nextState:set(RACE_STATE_GADGET_PLATE)
  elseif state == RACE_STATE_GOAL then
    local f = State.finish
    if f and not f.over then
      f.held = true
      nextState:set(RACE_STATE_DRIVE)
    end
  end
end)
