#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#define ESCAPE_CONFIG_ROOT "configs/escape_mod/maps"
#define MAX_ESCAPE_SPAWNS 128
#define BOT_GOAL_SPAWN_DELAY 0.88

enum EscapePhase
{
    EscapePhase_Disabled = 0,
    EscapePhase_WaitingFirst,
    EscapePhase_First,
    EscapePhase_Halftime,
    EscapePhase_WaitingSecond,
    EscapePhase_Second,
    EscapePhase_Finished
};

public Plugin myinfo =
{
    name = "GoFire Escape Mode",
    author = "Codex",
    description = "Map-independent two-half escape mode with per-map configuration",
    version = "1.2.1",
    url = ""
};

EscapePhase g_Phase = EscapePhase_Disabled;
bool g_bMapEnabled;
bool g_bInsideGoal[MAXPLAYERS + 1];
bool g_bDefenderGuard[MAXPLAYERS + 1];
bool g_bBotGoalPending[MAXPLAYERS + 1];
bool g_bRemoveObjectives;
bool g_bGoalBox;
bool g_bShowSuccessKillfeed;
bool g_bRefillAmmo;
bool g_bCooldownHudVisible;
bool g_bDefenderGuardEnabled;
bool g_bDefenderAnchorEnabled;

char g_sMap[PLATFORM_MAX_PATH];
char g_sDisplayName[96];
char g_sAttackerSpawnClass[64];
char g_sDefenderSpawnClass[64];

float g_vGoal[3];
float g_vGoalMins[3];
float g_vGoalMaxs[3];
float g_fGoalRadius;
float g_fGoalCooldown;
float g_fGoalBlockedUntil;
float g_fHalfEndsAt;
float g_fHalftimeDelay;
float g_fBotGoalRadius;
float g_fDefenseDistance;
float g_fNextHudUpdate;
float g_fDefenderGuardRatio;
float g_fDefenderGuardRange;

int g_iRoundSeconds;
int g_iEscapeTarget;
int g_iEscapeReward;
int g_iRadarRevealSeconds;
int g_iRemainingEscapes;
int g_iHalfEscaped;
int g_iFirstHalfEscaped;
int g_iSecondHalfSeconds;
int g_iSecondHalfTarget;
int g_iLastDisplayedSecond = -1;
int g_iDefenderGuardMin;
int g_iDefenderGuardMax;
int g_iDefenderAnchor;
int g_iBotGoalGeneration[MAXPLAYERS + 1];

float g_vAttackerSpawns[MAX_ESCAPE_SPAWNS][3];
float g_aAttackerSpawnAngles[MAX_ESCAPE_SPAWNS][3];
float g_vDefenderSpawns[MAX_ESCAPE_SPAWNS][3];
float g_aDefenderSpawnAngles[MAX_ESCAPE_SPAWNS][3];
int g_iAttackerSpawnCount;
int g_iDefenderSpawnCount;
int g_iLastAttackerSpawn = -1;
int g_iLastDefenderSpawn = -1;

Handle g_hThinkTimer;
Handle g_hHudSync;
Handle g_hCooldownHudSync;
Handle g_hFeedbackHudSync;

ConVar g_cvIgnoreWin;
ConVar g_cvRespawnT;
ConVar g_cvRespawnCT;
ConVar g_cvRespawnImmunity;
ConVar g_cvRadarShowAll;
ConVar g_cvFreezeTime;
bool g_bRuntimeCvarsApplied;
int g_iOldIgnoreWin;
int g_iOldRespawnT;
int g_iOldRespawnCT;
int g_iOldRadarShowAll;
float g_fOldRespawnImmunity;
float g_fOldFreezeTime;

public void OnPluginStart()
{
    RegAdminCmd("sm_escape_reload", Command_EscapeReload, ADMFLAG_CONFIG, "Reload the current escape map configuration.");
    RegConsoleCmd("sm_escape_status", Command_EscapeStatus, "Show escape mode status.");

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

    g_hHudSync = CreateHudSynchronizer();
    g_hCooldownHudSync = CreateHudSynchronizer();
    g_hFeedbackHudSync = CreateHudSynchronizer();
}

public void OnMapStart()
{
    StopThinkTimer();
    ClearAllHud();
    RestoreRuntimeCvars();
    ResetMapState();

    GetCurrentMap(g_sMap, sizeof(g_sMap));
    if (!LoadMapConfig())
    {
        g_Phase = EscapePhase_Disabled;
        return;
    }

    g_bMapEnabled = true;
    g_Phase = EscapePhase_WaitingFirst;
    ApplyRuntimeCvars();
    LoadMapSpawns();
    RequestFrame(Frame_RemoveObjectives);

    g_hThinkTimer = CreateTimer(0.10, Timer_EscapeThink, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(1.0, Timer_BeginFirstHalfFallback, _, TIMER_FLAG_NO_MAPCHANGE);

    LogMessage("[EscapeMod] enabled for %s: goal %.1f %.1f %.1f radius %.1f, spawns T=%d CT=%d",
        g_sMap, g_vGoal[0], g_vGoal[1], g_vGoal[2], g_fGoalRadius,
        g_iAttackerSpawnCount, g_iDefenderSpawnCount);
}

public void OnMapEnd()
{
    StopThinkTimer();
    ClearAllHud();
    ClearAllBotGoals();
    RestoreRuntimeCvars();
    ResetMapState();
    DoUnloadSelf();
}

public void OnClientDisconnect(int client)
{
    g_bInsideGoal[client] = false;
    g_bDefenderGuard[client] = false;
    CancelDelayedBotGoal(client);
    if (g_iDefenderAnchor == client)
        g_iDefenderAnchor = 0;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!g_bMapEnabled || !g_bRemoveObjectives)
        return;

    if (StrEqual(classname, "weapon_c4", false) || StrEqual(classname, "planted_c4", false))
        RequestFrame(Frame_KillEntity, EntIndexToEntRef(entity));
}

public Action Command_EscapeReload(int client, int args)
{
    if (g_bMapEnabled)
    {
        ClearAllBotGoals();
        RestoreRuntimeCvars();
    }

    StopThinkTimer();
    ClearAllHud();
    ResetMapState();
    GetCurrentMap(g_sMap, sizeof(g_sMap));

    if (!LoadMapConfig())
    {
        ReplyToCommand(client, "[EscapeMod] No enabled config for %s.", g_sMap);
        return Plugin_Handled;
    }

    g_bMapEnabled = true;
    g_Phase = EscapePhase_WaitingFirst;
    ApplyRuntimeCvars();
    LoadMapSpawns();
    RequestFrame(Frame_RemoveObjectives);
    g_hThinkTimer = CreateTimer(0.10, Timer_EscapeThink, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    BeginFirstHalf();
    ReplyToCommand(client, "[EscapeMod] Reloaded %s.", g_sMap);
    return Plugin_Handled;
}

public Action Command_EscapeStatus(int client, int args)
{
    if (!g_bMapEnabled)
    {
        ReplyToCommand(client, "[EscapeMod] Disabled on %s.", g_sMap);
        return Plugin_Handled;
    }

    int seconds = GetRemainingSeconds();
    ReplyToCommand(client,
        "[EscapeMod] %s phase=%d time=%02d:%02d escape=%d/%d goal=(%.0f %.0f %.0f) r=%.0f",
        g_sDisplayName, view_as<int>(g_Phase), seconds / 60, seconds % 60,
        g_iRemainingEscapes, CurrentEscapeTarget(), g_vGoal[0], g_vGoal[1], g_vGoal[2], g_fGoalRadius);
    return Plugin_Handled;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bMapEnabled)
        return Plugin_Continue;

    RequestFrame(Frame_RemoveObjectives);
    CreateTimer(0.20, Timer_ApplyRoundStart, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bMapEnabled)
        return Plugin_Continue;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client))
    {
        g_bInsideGoal[client] = false;
        CreateTimer(0.25, Timer_ApplyPlayerRole, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!IsLivePhase())
        return Plugin_Continue;

    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(victim))
        return Plugin_Continue;

    g_bInsideGoal[victim] = false;
    ClearBotGoal(victim);

    if (GetClientTeam(victim) == CS_TEAM_T && g_fDefenseDistance > 0.0)
    {
        float origin[3];
        GetClientAbsOrigin(victim, origin);
        float distance = GetDistanceToGoal(origin);
        if (distance <= g_fDefenseDistance)
        {
            int meters = RoundToCeil(distance * 0.0254);
            PrintToChatAll("\x01\x04[突围模式]\x01 防守方在距出口 \x03%d 米\x01处阻止了 \x04%N\x01！",
                meters, victim);
        }
    }

    return Plugin_Continue;
}

public Action Timer_BeginFirstHalfFallback(Handle timer)
{
    if (g_bMapEnabled && g_Phase == EscapePhase_WaitingFirst)
        BeginFirstHalf();
    return Plugin_Stop;
}

public Action Timer_ApplyRoundStart(Handle timer)
{
    if (!g_bMapEnabled)
        return Plugin_Stop;

    RequestFrame(Frame_RemoveObjectives);

    if (g_Phase == EscapePhase_WaitingFirst || g_Phase == EscapePhase_Finished)
        BeginFirstHalf();
    else if (g_Phase == EscapePhase_WaitingSecond)
        BeginSecondHalf();

    return Plugin_Stop;
}

public Action Timer_ApplyPlayerRole(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!g_bMapEnabled || !IsValidClient(client) || !IsPlayerAlive(client))
        return Plugin_Stop;

    ApplyPlayerRole(client);
    if (IsFakeClient(client) && IsLivePhase())
    {
        RefreshDefenderGuards();
        if (GetClientTeam(client) == CS_TEAM_T)
            ScheduleBotGoal(client);
        else if (IsDefenderGuard(client))
            ScheduleBotGoal(client);
    }
    return Plugin_Stop;
}

public Action Timer_EscapeThink(Handle timer)
{
    if (!g_bMapEnabled)
        return Plugin_Continue;

    if (!IsLivePhase())
        return Plugin_Continue;

    int remaining = GetRemainingSeconds();
    if (remaining != g_iLastDisplayedSecond)
    {
        g_iLastDisplayedSecond = remaining;
        ShowScoreHud(remaining);
        MaintainDefenderGuards();

        if (g_iRadarRevealSeconds > 0 && g_iHalfEscaped == 0
            && remaining <= g_iRadarRevealSeconds && g_cvRadarShowAll != null)
            g_cvRadarShowAll.SetInt(1);
    }

    float now = GetGameTime();
    if (now >= g_fNextHudUpdate)
    {
        g_fNextHudUpdate = now + 0.20;
        ShowCooldownHud(now);
    }

    CheckGoalEntrances();

    if (remaining <= 0 && IsLivePhase())
    {
        if (g_Phase == EscapePhase_First)
            CompleteFirstHalf(false);
        else
            FinishMatch(false);
    }

    return Plugin_Continue;
}

public Action Timer_StartSecondHalf(Handle timer)
{
    if (!g_bMapEnabled || g_Phase != EscapePhase_Halftime)
        return Plugin_Stop;

    SwapPlayerTeams();
    g_Phase = EscapePhase_WaitingSecond;
    CS_TerminateRound(1.0, CSRoundEnd_GameStart);
    return Plugin_Stop;
}

public void Frame_RemoveObjectives(any data)
{
    if (!g_bMapEnabled || !g_bRemoveObjectives)
        return;

    static const char objectiveClasses[][] =
    {
        "func_bomb_target",
        "func_hostage_rescue",
        "hostage_entity",
        "weapon_c4",
        "planted_c4"
    };

    for (int i = 0; i < sizeof(objectiveClasses); i++)
    {
        int entity = -1;
        while ((entity = FindEntityByClassname(entity, objectiveClasses[i])) != -1)
            AcceptEntityInput(entity, "Kill");
    }
}

public void Frame_KillEntity(any entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (entity > MaxClients && IsValidEntity(entity))
        AcceptEntityInput(entity, "Kill");
}

void BeginFirstHalf()
{
    if (!g_bMapEnabled)
        return;

    g_Phase = EscapePhase_First;
    g_iRemainingEscapes = g_iEscapeTarget;
    g_iHalfEscaped = 0;
    g_iFirstHalfEscaped = 0;
    g_iSecondHalfTarget = 0;
    g_iSecondHalfSeconds = 0;
    g_fHalfEndsAt = GetGameTime() + float(g_iRoundSeconds);
    g_fGoalBlockedUntil = 0.0;
    g_fNextHudUpdate = 0.0;
    g_bCooldownHudVisible = false;
    g_iLastDisplayedSecond = -1;
    ResetInsideGoalState();
    ResetRadar();
    ApplyRolesAndBotGoals();

    PrintToChatAll("\x01\x04[突围模式]\x01 %s：上半场开始，进攻方需在 %d:%02d 内突围 %d 次。",
        g_sDisplayName, g_iRoundSeconds / 60, g_iRoundSeconds % 60, g_iEscapeTarget);
}

void BeginSecondHalf()
{
    g_Phase = EscapePhase_Second;
    g_iRemainingEscapes = g_iSecondHalfTarget;
    g_iHalfEscaped = 0;
    g_fHalfEndsAt = GetGameTime() + float(g_iSecondHalfSeconds);
    g_fGoalBlockedUntil = 0.0;
    g_fNextHudUpdate = 0.0;
    g_bCooldownHudVisible = false;
    g_iLastDisplayedSecond = -1;
    ResetInsideGoalState();
    ResetRadar();
    ApplyRolesAndBotGoals();

    PrintToChatAll("\x01\x04[突围模式]\x01 下半场开始，新的进攻方需在 %d:%02d 内突围 %d 次。",
        g_iSecondHalfSeconds / 60, g_iSecondHalfSeconds % 60, g_iSecondHalfTarget);

    if (g_iSecondHalfTarget <= 0)
        FinishMatch(true);
}

void CompleteFirstHalf(bool completedTarget)
{
    if (g_Phase != EscapePhase_First)
        return;

    int remaining = GetRemainingSeconds();
    g_iFirstHalfEscaped = g_iHalfEscaped;
    g_iSecondHalfTarget = g_iFirstHalfEscaped;
    g_iSecondHalfSeconds = completedTarget ? (g_iRoundSeconds - remaining) : g_iRoundSeconds;
    if (g_iSecondHalfSeconds < 1)
        g_iSecondHalfSeconds = 1;

    g_Phase = EscapePhase_Halftime;
    ClearLiveHud();
    ClearAllBotGoals();
    ResetRadar();

    PrintToChatAll("\x01\x04[突围模式]\x01 上半场结束：共突围 %d 次。%0.0f 秒后交换攻守。",
        g_iFirstHalfEscaped, g_fHalftimeDelay);
    CreateTimer(g_fHalftimeDelay, Timer_StartSecondHalf, _, TIMER_FLAG_NO_MAPCHANGE);
}

void FinishMatch(bool attackersWon)
{
    if (g_Phase != EscapePhase_Second)
        return;

    g_Phase = EscapePhase_Finished;
    ClearLiveHud();
    ClearAllBotGoals();
    ResetRadar();

    if (attackersWon)
        PrintToChatAll("\x01\x04[突围模式]\x01 新进攻方完成目标，赢得本轮对抗！");
    else
        PrintToChatAll("\x01\x04[突围模式]\x01 时间耗尽，原进攻方的上半场成绩获胜！");

    CSRoundEndReason reason = attackersWon ? CSRoundEnd_TerroristWin : CSRoundEnd_CTWin;
    SwapPlayerTeams();
    g_Phase = EscapePhase_WaitingFirst;
    CS_TerminateRound(7.0, reason);
}

void CheckGoalEntrances()
{
    float now = GetGameTime();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != CS_TEAM_T)
        {
            g_bInsideGoal[client] = false;
            continue;
        }

        float origin[3];
        GetClientAbsOrigin(client, origin);
        bool inside = IsInsideGoal(origin);
        bool entered = inside && !g_bInsideGoal[client];
        g_bInsideGoal[client] = inside;

        if (!entered || now < g_fGoalBlockedUntil)
            continue;

        HandleEscapeSuccess(client);
        if (!IsLivePhase())
            return;
    }
}

void HandleEscapeSuccess(int client)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client) || g_iRemainingEscapes <= 0)
        return;

    g_iRemainingEscapes--;
    g_iHalfEscaped++;
    g_fGoalBlockedUntil = GetGameTime() + g_fGoalCooldown;
    g_bInsideGoal[client] = false;

    int health = GetClientHealth(client);
    if (g_iEscapeReward > 0)
        SetEntProp(client, Prop_Data, "m_iFrags", GetClientFrags(client) + g_iEscapeReward);

    PrintToChatAll("\x01\x04[突围模式]\x01 \x03%N\x01 突围成功！奖励 \x04%d\x01 杀敌数，生命值 \x04%d\x01，还需 \x03%d/%d\x01 次。",
        client, g_iEscapeReward, health, g_iRemainingEscapes, CurrentEscapeTarget());
    ShowEscapeSuccessFeedback(client, health);
    if (g_bShowSuccessKillfeed)
        CreateEscapeKillfeed(client);

    SetEntityHealth(client, 100);
    if (FindSendPropInfo("CCSPlayer", "m_ArmorValue") != -1)
        SetEntProp(client, Prop_Send, "m_ArmorValue", 100);
    if (FindSendPropInfo("CCSPlayer", "m_bHasHelmet") != -1)
        SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);
    if (g_bRefillAmmo)
        RefillPlayerAmmo(client);

    ClearBotGoal(client);
    TeleportClientToTeamSpawn(client, true);
    CreateTimer(0.30, Timer_ApplyPlayerRole, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    if (g_iRemainingEscapes <= 0)
    {
        if (g_Phase == EscapePhase_First)
            CompleteFirstHalf(true);
        else
            FinishMatch(true);
    }
}

void ShowScoreHud(int remaining)
{
    SetHudTextParams(-1.0, 0.03, 1.10, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
            ShowSyncHudText(client, g_hHudSync, "突围模式  %02d:%02d  |  剩余 %d/%d",
                remaining / 60, remaining % 60, g_iRemainingEscapes, CurrentEscapeTarget());
    }
}

void ShowCooldownHud(float now)
{
    float remaining = g_fGoalBlockedUntil - now;
    if (remaining <= 0.0)
    {
        if (g_bCooldownHudVisible)
        {
            for (int client = 1; client <= MaxClients; client++)
            {
                if (IsClientInGame(client) && !IsFakeClient(client))
                    ClearSyncHud(client, g_hCooldownHudSync);
            }
            g_bCooldownHudVisible = false;
        }
        return;
    }

    g_bCooldownHudVisible = true;
    SetHudTextParams(-1.0, 0.20, 0.30, 255, 92, 0, 255, 0, 0.0, 0.0, 0.0);
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client))
            ShowSyncHudText(client, g_hCooldownHudSync, "突围点冷却 %.1f 秒", remaining);
    }
}

void ShowEscapeSuccessFeedback(int client, int health)
{
    char text[256];
    Format(text, sizeof(text), "%N 突围成功！\n奖励 +%d 杀敌数  |  剩余 %d/%d",
        client, g_iEscapeReward, g_iRemainingEscapes, CurrentEscapeTarget());

    SetHudTextParams(-1.0, 0.12, 3.0, 80, 255, 120, 255, 1, 0.15, 0.10, 0.25);
    for (int target = 1; target <= MaxClients; target++)
    {
        if (IsClientInGame(target) && !IsFakeClient(target))
            ShowSyncHudText(target, g_hFeedbackHudSync, "%s", text);
    }

    if (!IsFakeClient(client))
        PrintHintText(client, "突围成功！\n生命值：%d  奖励：+%d 杀敌数", health, g_iEscapeReward);
}

void CreateEscapeKillfeed(int client)
{
    char weaponName[64] = "knife";
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon > MaxClients && IsValidEntity(weapon))
    {
        GetEntityClassname(weapon, weaponName, sizeof(weaponName));
        ReplaceString(weaponName, sizeof(weaponName), "weapon_", "", false);
    }

    Event escapeEvent = CreateEvent("player_death", true);
    if (escapeEvent == null)
        return;

    escapeEvent.SetInt("userid", 0);
    escapeEvent.SetInt("attacker", GetClientUserId(client));
    escapeEvent.SetInt("assister", 0);
    escapeEvent.SetInt("dominated", 3);
    escapeEvent.SetBool("headshot", false);
    escapeEvent.SetString("weapon", weaponName);
    for (int target = 1; target <= MaxClients; target++)
    {
        if (IsClientInGame(target) && !IsFakeClient(target))
            escapeEvent.FireToClient(target);
    }
    delete escapeEvent;
}

void RefillPlayerAmmo(int client)
{
    // point_give_ammo in the Temple map only replenishes firearm ammunition.
    // Mirror that behavior for the primary and secondary weapon slots.
    for (int slot = 0; slot <= 1; slot++)
    {
        int weapon = GetPlayerWeaponSlot(client, slot);
        if (weapon <= MaxClients || !IsValidEntity(weapon))
            continue;
        if (FindDataMapInfo(weapon, "m_iPrimaryAmmoType") == -1)
            continue;

        int ammoType = GetEntProp(weapon, Prop_Data, "m_iPrimaryAmmoType");
        if (ammoType >= 0)
            GivePlayerAmmo(client, 999, ammoType, true);
    }
}

float GetDistanceToGoal(const float origin[3])
{
    if (!g_bGoalBox)
    {
        float distance = GetVectorDistance(origin, g_vGoal) - g_fGoalRadius;
        return distance > 0.0 ? distance : 0.0;
    }

    float delta[3];
    for (int axis = 0; axis < 3; axis++)
    {
        if (origin[axis] < g_vGoalMins[axis])
            delta[axis] = g_vGoalMins[axis] - origin[axis];
        else if (origin[axis] > g_vGoalMaxs[axis])
            delta[axis] = origin[axis] - g_vGoalMaxs[axis];
    }
    return SquareRoot(delta[0] * delta[0] + delta[1] * delta[1] + delta[2] * delta[2]);
}

void ClearLiveHud()
{
    g_bCooldownHudVisible = false;
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || IsFakeClient(client))
            continue;
        if (g_hHudSync != null)
            ClearSyncHud(client, g_hHudSync);
        if (g_hCooldownHudSync != null)
            ClearSyncHud(client, g_hCooldownHudSync);
    }
}

void ClearAllHud()
{
    ClearLiveHud();
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && !IsFakeClient(client) && g_hFeedbackHudSync != null)
            ClearSyncHud(client, g_hFeedbackHudSync);
    }
}

int CurrentEscapeTarget()
{
    return (g_Phase == EscapePhase_Second || g_Phase == EscapePhase_WaitingSecond)
        ? g_iSecondHalfTarget : g_iEscapeTarget;
}

int GetRemainingSeconds()
{
    int remaining = RoundToCeil(g_fHalfEndsAt - GetGameTime());
    return remaining > 0 ? remaining : 0;
}

bool IsLivePhase()
{
    return g_bMapEnabled && (g_Phase == EscapePhase_First || g_Phase == EscapePhase_Second);
}

bool IsInsideGoal(const float origin[3])
{
    if (!g_bGoalBox)
        return GetVectorDistance(origin, g_vGoal) <= g_fGoalRadius;

    return origin[0] >= g_vGoalMins[0] && origin[0] <= g_vGoalMaxs[0]
        && origin[1] >= g_vGoalMins[1] && origin[1] <= g_vGoalMaxs[1]
        && origin[2] >= g_vGoalMins[2] && origin[2] <= g_vGoalMaxs[2];
}

void ApplyRolesAndBotGoals()
{
    ResetDefenderGuards();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client))
            continue;

        ApplyPlayerRole(client);
        ClearBotGoal(client);
    }

    RefreshDefenderGuards(false);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client) || !IsPlayerAlive(client) || !IsFakeClient(client))
            continue;

        if (GetClientTeam(client) == CS_TEAM_T)
            ScheduleBotGoal(client);
        else if (IsDefenderGuard(client))
            ScheduleBotGoal(client);
    }
}

void ResetDefenderGuards()
{
    g_iDefenderAnchor = 0;
    for (int client = 1; client <= MaxClients; client++)
    {
        g_bDefenderGuard[client] = false;
        CancelDelayedBotGoal(client);
    }
}

void RefreshDefenderGuards(bool applyNewGoals = true)
{
    bool newlySelected[MAXPLAYERS + 1];
    int previousAnchor = g_iDefenderAnchor;
    int eligible;
    int selected;

    for (int client = 1; client <= MaxClients; client++)
    {
        bool isEligible = IsValidClient(client)
            && IsFakeClient(client)
            && GetClientTeam(client) == CS_TEAM_CT;
        if (isEligible)
            eligible++;

        if (!g_bDefenderGuard[client])
            continue;

        if (!isEligible)
        {
            ClearBotGoal(client);
            g_bDefenderGuard[client] = false;
            continue;
        }
        selected++;
    }

    int desired;
    if (g_bDefenderGuardEnabled && eligible > 0)
    {
        desired = RoundToCeil(float(eligible) * g_fDefenderGuardRatio);
        if (desired < g_iDefenderGuardMin)
            desired = g_iDefenderGuardMin;
        if (g_iDefenderGuardMax > 0 && desired > g_iDefenderGuardMax)
            desired = g_iDefenderGuardMax;
        if (desired > eligible)
            desired = eligible;
    }

    for (int client = MaxClients; client >= 1 && selected > desired; client--)
    {
        if (!g_bDefenderGuard[client])
            continue;

        ClearBotGoal(client);
        g_bDefenderGuard[client] = false;
        if (g_iDefenderAnchor == client)
            g_iDefenderAnchor = 0;
        selected--;
    }

    int start = GetRandomInt(1, MaxClients);
    for (int offset = 0; offset < MaxClients && selected < desired; offset++)
    {
        int client = ((start - 1 + offset) % MaxClients) + 1;
        if (!IsValidClient(client) || !IsFakeClient(client)
            || GetClientTeam(client) != CS_TEAM_CT || g_bDefenderGuard[client])
            continue;

        g_bDefenderGuard[client] = true;
        newlySelected[client] = true;
        selected++;
    }

    if (!g_bDefenderAnchorEnabled || desired <= 0)
    {
        g_iDefenderAnchor = 0;
    }
    else if (g_iDefenderAnchor <= 0 || !g_bDefenderGuard[g_iDefenderAnchor])
    {
        g_iDefenderAnchor = 0;
        for (int client = 1; client <= MaxClients; client++)
        {
            if (g_bDefenderGuard[client])
            {
                g_iDefenderAnchor = client;
                break;
            }
        }
    }

    if (!applyNewGoals)
        return;

    for (int client = 1; client <= MaxClients; client++)
    {
        bool anchorRoleChanged = g_iDefenderAnchor != previousAnchor
            && (client == g_iDefenderAnchor || client == previousAnchor);
        if ((!newlySelected[client] && !anchorRoleChanged)
            || !g_bDefenderGuard[client] || !IsPlayerAlive(client))
            continue;

        ScheduleBotGoal(client);
    }
}

void MaintainDefenderGuards()
{
    RefreshDefenderGuards();
}

bool IsDefenderGuard(int client)
{
    return IsLivePhase()
        && g_bDefenderGuardEnabled
        && g_bDefenderGuard[client]
        && IsValidClient(client)
        && IsPlayerAlive(client)
        && IsFakeClient(client)
        && GetClientTeam(client) == CS_TEAM_CT;
}

bool IsDefenderAnchor(int client)
{
    return g_bDefenderAnchorEnabled
        && client == g_iDefenderAnchor
        && IsDefenderGuard(client);
}

void ApplyPlayerRole(int client)
{
    int team = GetClientTeam(client);
    if (team == CS_TEAM_T)
        DispatchKeyValue(client, "targetname", "rusher");
    else if (team == CS_TEAM_CT)
        DispatchKeyValue(client, "targetname", "def");
}

void SwapPlayerTeams()
{
    int oldTeams[MAXPLAYERS + 1];
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsValidClient(client))
            oldTeams[client] = GetClientTeam(client);
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client))
            continue;

        if (oldTeams[client] == CS_TEAM_T)
            CS_SwitchTeam(client, CS_TEAM_CT);
        else if (oldTeams[client] == CS_TEAM_CT)
            CS_SwitchTeam(client, CS_TEAM_T);
    }
}

void TeleportClientToTeamSpawn(int client, bool attacker)
{
    int count = attacker ? g_iAttackerSpawnCount : g_iDefenderSpawnCount;
    if (count <= 0)
        return;

    int start;
    if (attacker)
    {
        start = (g_iLastAttackerSpawn + GetRandomInt(1, 3) + count) % count;
        g_iLastAttackerSpawn = start;
    }
    else
    {
        start = (g_iLastDefenderSpawn + GetRandomInt(1, 3) + count) % count;
        g_iLastDefenderSpawn = start;
    }

    float origin[3];
    float angles[3];
    for (int offset = 0; offset < count; offset++)
    {
        int index = (start + offset) % count;
        if (attacker)
        {
            CopyVector(g_vAttackerSpawns[index], origin);
            CopyVector(g_aAttackerSpawnAngles[index], angles);
        }
        else
        {
            CopyVector(g_vDefenderSpawns[index], origin);
            CopyVector(g_aDefenderSpawnAngles[index], angles);
        }

        if (IsSpawnClear(client, origin) || offset == count - 1)
        {
            TeleportEntity(client, origin, angles, NULL_VECTOR);
            return;
        }
    }
}

bool IsSpawnClear(int client, float origin[3])
{
    float mins[3] = {-16.0, -16.0, 0.0};
    float maxs[3] = {16.0, 16.0, 72.0};
    Handle trace = TR_TraceHullFilterEx(origin, origin, mins, maxs, MASK_PLAYERSOLID, TraceFilter_Spawn, client);
    bool blocked = TR_DidHit(trace) || TR_StartSolid(trace) || TR_AllSolid(trace);
    delete trace;
    return !blocked;
}

public bool TraceFilter_Spawn(int entity, int contentsMask, any client)
{
    return entity != client;
}

void LoadMapSpawns()
{
    g_iAttackerSpawnCount = LoadSpawnClass(g_sAttackerSpawnClass, true);
    g_iDefenderSpawnCount = LoadSpawnClass(g_sDefenderSpawnClass, false);

    // GoFire can load both native Source maps and GoldSrc v30 maps. Keep a
    // Source classname fallback in case the BSP compatibility layer rewrites
    // the classic spawn entities before SourceMod scans them.
    if (g_iAttackerSpawnCount == 0 && !StrEqual(g_sAttackerSpawnClass, "info_player_terrorist", false))
        g_iAttackerSpawnCount = LoadSpawnClass("info_player_terrorist", true);
    if (g_iDefenderSpawnCount == 0 && !StrEqual(g_sDefenderSpawnClass, "info_player_counterterrorist", false))
        g_iDefenderSpawnCount = LoadSpawnClass("info_player_counterterrorist", false);

    if (g_iAttackerSpawnCount == 0 || g_iDefenderSpawnCount == 0)
        LogError("[EscapeMod] incomplete spawn scan for %s: T=%d CT=%d",
            g_sMap, g_iAttackerSpawnCount, g_iDefenderSpawnCount);
}

int LoadSpawnClass(const char[] classname, bool attacker)
{
    int count;
    int entity = -1;
    while ((entity = FindEntityByClassname(entity, classname)) != -1 && count < MAX_ESCAPE_SPAWNS)
    {
        float origin[3];
        float angles[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
        if (FindDataMapInfo(entity, "m_angRotation") != -1)
            GetEntPropVector(entity, Prop_Data, "m_angRotation", angles);

        if (attacker)
        {
            CopyVector(origin, g_vAttackerSpawns[count]);
            CopyVector(angles, g_aAttackerSpawnAngles[count]);
        }
        else
        {
            CopyVector(origin, g_vDefenderSpawns[count]);
            CopyVector(angles, g_aDefenderSpawnAngles[count]);
        }
        count++;
    }
    return count;
}

bool LoadMapConfig()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "%s/%s.cfg", ESCAPE_CONFIG_ROOT, g_sMap);

    KeyValues kv = new KeyValues("EscapeMod");
    if (!kv.ImportFromFile(path))
    {
        delete kv;
        return false;
    }

    if (kv.GetNum("enabled", 1) == 0)
    {
        delete kv;
        return false;
    }

    kv.GetString("display_name", g_sDisplayName, sizeof(g_sDisplayName), g_sMap);
    kv.GetString("attacker_spawn_class", g_sAttackerSpawnClass, sizeof(g_sAttackerSpawnClass), "info_player_terrorist");
    kv.GetString("defender_spawn_class", g_sDefenderSpawnClass, sizeof(g_sDefenderSpawnClass), "info_player_counterterrorist");
    kv.GetVector("escape_origin", g_vGoal);

    char goalShape[16];
    kv.GetString("escape_shape", goalShape, sizeof(goalShape), "sphere");
    g_bGoalBox = StrEqual(goalShape, "box", false);
    if (g_bGoalBox)
    {
        kv.GetVector("escape_mins", g_vGoalMins);
        kv.GetVector("escape_maxs", g_vGoalMaxs);
    }

    g_fGoalRadius = kv.GetFloat("escape_radius", 128.0);
    g_fGoalCooldown = kv.GetFloat("escape_cooldown", 5.0);
    g_fHalftimeDelay = kv.GetFloat("halftime_delay", 5.0);
    g_fBotGoalRadius = kv.GetFloat("bot_goal_radius", 96.0);
    g_fDefenseDistance = kv.GetFloat("defense_distance", 507.0);
    g_fDefenderGuardRatio = kv.GetFloat("defender_guard_ratio", 0.45);
    g_fDefenderGuardRange = kv.GetFloat("defender_guard_range", 350.0);
    g_iRoundSeconds = kv.GetNum("round_time", 480);
    g_iEscapeTarget = kv.GetNum("escape_target", 9);
    g_iEscapeReward = kv.GetNum("escape_reward_kills", 5);
    g_iRadarRevealSeconds = kv.GetNum("radar_reveal_seconds", 120);
    g_iDefenderGuardMin = kv.GetNum("defender_guard_min", 2);
    g_iDefenderGuardMax = kv.GetNum("defender_guard_max", 4);

    g_bShowSuccessKillfeed = kv.GetNum("success_killfeed", 1) != 0;
    g_bRefillAmmo = kv.GetNum("refill_ammo", 1) != 0;
    g_bRemoveObjectives = kv.GetNum("remove_objectives", 1) != 0;
    g_bDefenderGuardEnabled = kv.GetNum("defender_guard_enabled", 0) != 0;
    g_bDefenderAnchorEnabled = kv.GetNum("defender_guard_anchor", 0) != 0;
    delete kv;

    if (g_fDefenderGuardRatio < 0.0)
        g_fDefenderGuardRatio = 0.0;
    else if (g_fDefenderGuardRatio > 1.0)
        g_fDefenderGuardRatio = 1.0;
    if (g_iDefenderGuardMin < 0)
        g_iDefenderGuardMin = 0;
    if (g_iDefenderGuardMax < 0)
        g_iDefenderGuardMax = 0;
    if (g_fDefenderGuardRange < 128.0)
        g_fDefenderGuardRange = 128.0;

    bool validGoal = g_bGoalBox
        ? (g_vGoalMaxs[0] > g_vGoalMins[0]
            && g_vGoalMaxs[1] > g_vGoalMins[1]
            && g_vGoalMaxs[2] > g_vGoalMins[2])
        : (g_fGoalRadius > 0.0);
    return g_iRoundSeconds > 0 && g_iEscapeTarget > 0 && validGoal;
}

void SetAttackerBotGoal(int client)
{
    if (!IsValidClient(client) || !IsFakeClient(client))
        return;

    SetVariantFloat(g_fBotGoalRadius);
    AcceptEntityInput(client, "SetBreakthroughGoalRadius");
    SetVariantVector3D(g_vGoal);
    AcceptEntityInput(client, "SetBreakthroughGoal");
}

void ScheduleBotGoal(int client)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client) || !IsFakeClient(client)
        || g_bBotGoalPending[client])
        return;

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return;

    g_bBotGoalPending[client] = true;
    int generation = ++g_iBotGoalGeneration[client];
    DataPack pack;
    CreateDataTimer(BOT_GOAL_SPAWN_DELAY, Timer_ApplyBotGoal, pack, TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(generation);
}

public Action Timer_ApplyBotGoal(Handle timer, DataPack pack)
{
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int generation = pack.ReadCell();

    if (!IsValidClient(client)
        || generation != g_iBotGoalGeneration[client]
        || !g_bBotGoalPending[client])
        return Plugin_Stop;

    g_bBotGoalPending[client] = false;
    if (!IsLivePhase() || !IsPlayerAlive(client) || !IsFakeClient(client))
        return Plugin_Stop;

    if (GetClientTeam(client) == CS_TEAM_T)
        SetAttackerBotGoal(client);
    else if (IsDefenderAnchor(client))
        SetDefenderAnchorGoal(client);
    else if (IsDefenderGuard(client))
        SetDefenderBotGoal(client);

    return Plugin_Stop;
}

void CancelDelayedBotGoal(int client)
{
    if (client < 1 || client > MaxClients)
        return;

    g_bBotGoalPending[client] = false;
    g_iBotGoalGeneration[client]++;
}

void SetDefenderBotGoal(int client)
{
    if (!IsValidClient(client) || !IsFakeClient(client))
        return;

    SetVariantFloat(g_fDefenderGuardRange);
    AcceptEntityInput(client, "SetGuardGoalRange");
    SetVariantVector3D(g_vGoal);
    AcceptEntityInput(client, "SetGuardGoal");
}

void SetDefenderAnchorGoal(int client)
{
    if (!IsValidClient(client) || !IsFakeClient(client))
        return;

    // The single anchor guard uses direct navigation so it remains on the
    // escape platform instead of selecting a nearby hiding spot.
    SetVariantFloat(32.0);
    AcceptEntityInput(client, "SetBreakthroughGoalRadius");
    SetVariantVector3D(g_vGoal);
    AcceptEntityInput(client, "SetBreakthroughGoal");
}

void ClearBotGoal(int client)
{
    CancelDelayedBotGoal(client);

    if (!IsValidClient(client) || !IsFakeClient(client))
        return;

    AcceptEntityInput(client, "ClearBreakthroughGoal");
    AcceptEntityInput(client, "ClearGuardGoal");
}

void ClearAllBotGoals()
{
    for (int client = 1; client <= MaxClients; client++)
        ClearBotGoal(client);
}

void ApplyRuntimeCvars()
{
    if (g_bRuntimeCvarsApplied)
        return;

    g_cvIgnoreWin = FindConVar("mp_ignore_round_win_conditions");
    g_cvRespawnT = FindConVar("mp_respawn_on_death_t");
    g_cvRespawnCT = FindConVar("mp_respawn_on_death_ct");
    g_cvRespawnImmunity = FindConVar("mp_respawn_immunitytime");
    g_cvRadarShowAll = FindConVar("mp_radar_showall");
    g_cvFreezeTime = FindConVar("mp_freezetime");

    if (g_cvIgnoreWin != null) { g_iOldIgnoreWin = g_cvIgnoreWin.IntValue; g_cvIgnoreWin.SetInt(1); }
    if (g_cvRespawnT != null) { g_iOldRespawnT = g_cvRespawnT.IntValue; g_cvRespawnT.SetInt(1); }
    if (g_cvRespawnCT != null) { g_iOldRespawnCT = g_cvRespawnCT.IntValue; g_cvRespawnCT.SetInt(1); }
    if (g_cvRespawnImmunity != null) { g_fOldRespawnImmunity = g_cvRespawnImmunity.FloatValue; g_cvRespawnImmunity.SetFloat(3.0); }
    if (g_cvRadarShowAll != null) { g_iOldRadarShowAll = g_cvRadarShowAll.IntValue; g_cvRadarShowAll.SetInt(0); }
    if (g_cvFreezeTime != null) { g_fOldFreezeTime = g_cvFreezeTime.FloatValue; g_cvFreezeTime.SetFloat(3.0); }
    g_bRuntimeCvarsApplied = true;
}

void RestoreRuntimeCvars()
{
    if (!g_bRuntimeCvarsApplied)
        return;

    if (g_cvIgnoreWin != null) g_cvIgnoreWin.SetInt(g_iOldIgnoreWin);
    if (g_cvRespawnT != null) g_cvRespawnT.SetInt(g_iOldRespawnT);
    if (g_cvRespawnCT != null) g_cvRespawnCT.SetInt(g_iOldRespawnCT);
    if (g_cvRespawnImmunity != null) g_cvRespawnImmunity.SetFloat(g_fOldRespawnImmunity);
    if (g_cvRadarShowAll != null) g_cvRadarShowAll.SetInt(g_iOldRadarShowAll);
    if (g_cvFreezeTime != null) g_cvFreezeTime.SetFloat(g_fOldFreezeTime);
    g_bRuntimeCvarsApplied = false;
}

void ResetRadar()
{
    if (g_cvRadarShowAll != null)
        g_cvRadarShowAll.SetInt(0);
}

void StopThinkTimer()
{
    if (g_hThinkTimer != null)
    {
        KillTimer(g_hThinkTimer);
        g_hThinkTimer = null;
    }
}

void ResetInsideGoalState()
{
    for (int client = 1; client <= MaxClients; client++)
        g_bInsideGoal[client] = false;
}

void ResetMapState()
{
    g_bMapEnabled = false;
    g_bRemoveObjectives = false;
    g_bGoalBox = false;
    g_bShowSuccessKillfeed = false;
    g_bRefillAmmo = false;
    g_bCooldownHudVisible = false;
    g_bDefenderGuardEnabled = false;
    g_bDefenderAnchorEnabled = false;
    g_Phase = EscapePhase_Disabled;
    g_iAttackerSpawnCount = 0;
    g_iDefenderSpawnCount = 0;
    g_iLastAttackerSpawn = -1;
    g_iLastDefenderSpawn = -1;
    g_iLastDisplayedSecond = -1;
    g_fHalfEndsAt = 0.0;
    g_fGoalBlockedUntil = 0.0;
    g_fNextHudUpdate = 0.0;
    ResetInsideGoalState();
    ResetDefenderGuards();
}

bool IsValidClient(int client)
{
    return client >= 1 && client <= MaxClients && IsClientInGame(client);
}

void CopyVector(const float source[3], float destination[3])
{
    destination[0] = source[0];
    destination[1] = source[1];
    destination[2] = source[2];
}

void DoUnloadSelf()
{
    Handle me = GetMyHandle();
    char file[PLATFORM_MAX_PATH];
    if (GetPluginFilename(me, file, sizeof(file)) && file[0])
        ServerCommand("sm plugins unload \"%s\"", file);
}
