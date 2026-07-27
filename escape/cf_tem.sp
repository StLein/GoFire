#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <cstrike_fire>

public Plugin myinfo =
{
    name = "CF Temple Escape Mode",
    author = "Dazai Nerau, SourceMod port by Codex",
    description = "Escape Mode converted from cf_tem.nut",
    version = "1.0.0",
    url = ""
};

// static const char g_Copyright[][192] =
// {
//     "\x01 \x10[权利管理信息] \x01 \x05 地图原始著作权人:\x01 Smilegate Corp.",
//     "\x01 \x10[权利管理信息] \x01 \x05 地图改编权人:\x01 哔哩哔哩-风流倜傥你杰森"
// };

static const char g_Tag[2][48] =
{
    "\x01\x04[Escape Mode]\x01",
    "\x01\x04[突围模式]\x01"
};

static const char g_TimeLeft[2][32] =
{
    "Timeleft ",
    "剩余时间 "
};

static const char g_EscapeCount[2][24] =
{
    "Escape ",
    "突围 "
};

static const char g_Subtitle[12][2][192] =
{
    {"A attacker has Escaped Successfully! Acquired ", "进攻方突围成功! 突围者增加了"},
    {" Kills!", " 杀敌数!"},
    {"A attacker has Escaped Successfully! HP ->", "进攻方突围成功！突围者生命值："},
    {"A Gate has been destroyed.", "障碍物被破坏!"},
    {"Defenders prevented a escape! Distance: ", "防守方阻止了一次突围！距离："},
    {"You can escape now.", "突围限制解除!"},
    {"Objective Successful", "突围成功"},
    {"Objective Failed", "突围失败"},
    {"Objective Successful", "防守成功"},
    {"Objective Failed", "防守失败"},
    {"Escape blocked, the positions of \nthe two sides will be exposed to each other's radar", "突围延迟，双方位置将互相暴露在对方雷达上！"},
    {"Game starts now!", "游戏现在开始！"}
};

static const char g_Weapons[31][32] =
{
    "",
    "weapon_awp",
    "weapon_scar20",
    "weapon_m4a1",
    "weapon_famas",
    "weapon_ssg08",
    "weapon_aug",
    "weapon_m249",
    "weapon_negev",
    "weapon_p90",
    "weapon_mp7",
    "weapon_mp5sd",
    "weapon_ump45",
    "weapon_xm1014",
    "weapon_nova",
    "weapon_deagle",
    "weapon_revolver",
    "weapon_tec9",
    "weapon_cz75a",
    "weapon_m4a1_silencer",
    "weapon_hegrenade",
    "weapon_smokegrenade",
    "weapon_flashbang",
    "weapon_decoy",
    "weapon_incgrenade",
    "weapon_g3sg1",
    "weapon_ak47",
    "weapon_galilar",
    "weapon_sg556",
    "weapon_usp_silencer",
    "weapon_molotov"
};

#define ESCAPE_SPAWN_T 0
#define ESCAPE_SPAWN_CT 1
#define MAX_ESCAPE_SPAWNS 256

char g_Dist[20][8];

int g_iTimeMinute = 8;
int g_iTimeSecond = 0;
int g_iEscTotalTimes = 9;
int g_iEscTimes = 9;

int g_iTHM = 8;
int g_iTHS = 0;
int g_iNum = 9;
int g_iTot = 9;

int g_iTK = 0;
int g_iCTK = 0;
int g_iDEF = 0;

int g_iRoundNum = 1;     // 1 = 上半场T攻CT守, 4 = 真换队后的下半场T攻CT守
int g_iLang = 1;         // 0 = Eng, 1 = Chn

int g_iBGMZEN = 1;
int g_iBGMGO = 1;
int g_iDLZ = 1;
int g_iDLG = 1;
int g_iSStop = 0;

int g_iTC = 5;
int g_iCS = 5;
int g_iCCS = 0;
int g_iPc = 12;
int g_iNowPc = 5;
int g_iCopyrightShown = 0;
bool g_bDoorWarned2[4];
bool g_bDoorWarned3[4];
bool g_bSecondHalfRoundRestartPending = false;
bool g_bFullCycleRoundRestartPending = false;
float g_fLastDeathHandled[MAXPLAYERS + 1];
float g_fLastKillHandled[MAXPLAYERS + 1];
float g_vEscapeSpawnOrigin[2][MAX_ESCAPE_SPAWNS][3];
float g_vEscapeSpawnAngles[2][MAX_ESCAPE_SPAWNS][3];
int g_iEscapeSpawnCount[2];
int g_iEscapeSpawnLast[2] = {-1, -1};
bool g_bEscapeSpawnsLoaded = false;
float g_fLastEscapeTouch[MAXPLAYERS + 1];

Handle g_hScoreTimer = null;
Handle g_hCheckTimer = null;
Handle g_hDistanceTimer = null;
Handle g_hSniperTimer = null;
Handle g_hStopTimer = null;
Handle g_hHalfTimer = null;

ConVar g_cvAutoTimers;
ConVar g_cvAutoBridge;
ConVar g_cvAutoMapSpawn;
ConVar g_cvFreezeTime;

Handle g_hGameConf = null;
Handle g_hConvertTeam = null;
Handle g_hUpdateTeamScore = null;
Handle g_hBotSetBreakthroughGoal = null;
Handle g_hBotClearBreakthroughGoal = null;

public void OnPluginStart()
{
    g_cvAutoTimers = CreateConVar("sm_cf_escape_auto_timers", "1", "自动运行 cf_tem.nut 原本的计时器逻辑。");
    g_cvAutoBridge = CreateConVar("sm_cf_escape_auto_bridge", "1", "尝试从实体触发中识别并调用 VScript 函数名。");
    g_cvAutoMapSpawn = CreateConVar("sm_cf_escape_auto_mapspawn", "1", "自动模拟地图 logic_auto 中的 RunScriptCode 开图调用。");
    g_cvFreezeTime = FindConVar("mp_freezetime");
    SetupConvertTeam();

    RegAdminCmd("sm_cf_tem", Command_CFTem, ADMFLAG_GENERIC, "sm_cf_tem <Function> [arg] [userid]");

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    // HookEvent("player_say", Event_PlayerSay, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

    HookEntityOutput("trigger_multiple", "OnStartTouch", Output_ScriptBridge);
    HookEntityOutput("trigger_once", "OnStartTouch", Output_ScriptBridge);
    HookEntityOutput("trigger_teleport", "OnStartTouch", Output_ScriptBridge);
    HookEntityOutput("func_button", "OnPressed", Output_ScriptBridge);
    HookEntityOutput("logic_timer", "OnTimer", Output_ScriptBridge);
    HookEntityOutput("logic_auto", "OnMapSpawn", Output_ScriptBridge);
    HookEntityOutput("trigger_brush", "OnUse", Output_ScriptBridge);
    HookEntityOutput("func_breakable", "OnHealthChanged", Output_ScriptBridge);
    HookEntityOutput("func_breakable", "OnBreak", Output_DoorBreak);
    HookEntityOutput("func_physbox", "OnBreak", Output_DoorBreak);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
            SDKHook(client, SDKHook_OnTakeDamage, OnClientTakeDamage);
    }
}

// 更新记分牌
bool UpdateTeamScore(int team, int round, int score)
{
    return SDKCall(g_hUpdateTeamScore, team, round, score);
}

void SetupConvertTeam()
{
    g_hGameConf = LoadGameConfigFile("game.fire");
    if (g_hGameConf == null)
        SetFailState("Failed to load gameconfig: game.fire");

    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "ConvertTeam");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    g_hConvertTeam = EndPrepSDKCall();
    if (g_hConvertTeam == null)
        SetFailState("Failed to create SDKCall for CCSPlayer::ConvertTeam");
        
    StartPrepSDKCall(SDKCall_GameRules);
    PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "UpdateTeamScore");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
    if ((g_hUpdateTeamScore = EndPrepSDKCall()) == null) 
        SetFailState("Failed to create SDKCall for CCSGameRules::UpdateTeamScore!");

    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "BotSetBreakthroughGoal");
    PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
    g_hBotSetBreakthroughGoal = EndPrepSDKCall();
    if (g_hBotSetBreakthroughGoal == null)
        SetFailState("Failed to create SDKCall for CCSBot::BotSetBreakthroughGoal");

    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "BotClearBreakthroughGoal");
    g_hBotClearBreakthroughGoal = EndPrepSDKCall();
    if (g_hBotClearBreakthroughGoal == null)
        SetFailState("Failed to create SDKCall for CCSBot::BotClearBreakthroughGoal");
}

public void OnMapStart()
{
    ResetState();
    RequestFrame(Frame_HookEscapeTouchTriggers);
    RequestFrame(Frame_ScanDamageEntities);
    RequestFrame(Frame_DisableDelayedCTOriginTrigger);
    RequestFrame(Frame_LoadEscapeSpawns);

    if (g_cvAutoTimers.BoolValue)
    {
        StartAutoTimers();
    }

    if (g_cvAutoMapSpawn.BoolValue)
    {
        CreateTimer(0.1, Timer_ExecCMD, _, TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(0.1, Timer_Lang, _, TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(1.0, Timer_GameStart, _, TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(5.0, Timer_SayGS, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnMapEnd()
{
    StopAllTimers();
    DoUnloadSelf();
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnClientTakeDamage);
}

public void OnClientPostAdminCheck(int client)
{
    char auth[32];
    if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true))
        return;

    if (StrEqual(auth, "STEAM_1:1:53589709", false) || StrEqual(auth, "STEAM_0:1:53589709", false))
    {
        char name[MAX_NAME_LENGTH];
        GetClientName(client, name, sizeof(name));
        PrintToChatAll("\x01\x10[突围模式]\x01\x04 MOD作者 \x01 \x0b %s \x01 \x04 进入了服务器。", name);
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (StrEqual(classname, "func_breakable", false) || StrEqual(classname, "func_physbox", false))
    {
        SDKHook(entity, SDKHook_OnTakeDamagePost, OnEntityTakeDamagePost);
    }
    else if (StrEqual(classname, "trigger_multiple", false))
    {
        SDKHook(entity, SDKHook_StartTouch, OnEscapeTriggerStartTouch);
    }
}

public Action OnClientTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    return Plugin_Continue;
}

public void OnEntityTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
    char name[64];
    GetEntityName(victim, name, sizeof(name));

    if (StrEqual(name, "door1", false))
        DoorDmg(1);
    else if (StrEqual(name, "door2", false))
        DoorDmg(2);
    else if (StrEqual(name, "door3", false))
        DoorDmg(3);
}

public void Frame_ScanDamageEntities(any data)
{
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "func_breakable")) != -1)
    {
        SDKHook(ent, SDKHook_OnTakeDamagePost, OnEntityTakeDamagePost);
    }

    ent = -1;
    while ((ent = FindEntityByClassname(ent, "func_physbox")) != -1)
    {
        SDKHook(ent, SDKHook_OnTakeDamagePost, OnEntityTakeDamagePost);
    }
}

public void Frame_HookEscapeTouchTriggers(any data)
{
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "trigger_multiple")) != -1)
    {
        if (IsEscapeTouchTrigger(ent))
            SDKHook(ent, SDKHook_StartTouch, OnEscapeTriggerStartTouch);
    }
}

public void Frame_DisableDelayedCTOriginTrigger(any data)
{
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "trigger_multiple")) != -1)
    {
        if (GetEntityHammerId(ent) != 159488)
            continue;

        AcceptEntityInput(ent, "Disable");
    }
}

public void Frame_LoadEscapeSpawns(any data)
{
    LoadEscapeSpawnLists();
}

public Action Command_CFTem(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_cf_tem <Function> [arg] [userid]");
        return Plugin_Handled;
    }

    char func[64];
    GetCmdArg(1, func, sizeof(func));

    int arg = 0;
    if (args >= 2)
    {
        char buffer[32];
        GetCmdArg(2, buffer, sizeof(buffer));
        arg = StringToInt(buffer);
    }

    int activator = client;
    if (args >= 3)
    {
        char buffer[32];
        GetCmdArg(3, buffer, sizeof(buffer));
        int userid = StringToInt(buffer);
        int target = GetClientOfUserId(userid);
        if (target > 0)
            activator = target;
    }

    RunFunction(func, arg, activator);
    return Plugin_Handled;
}

public void Output_ScriptBridge(const char[] output, int caller, int activator, float delay)
{
    if (!g_cvAutoBridge.BoolValue)
        return;

    if (HandleEscapeTouch(caller, activator))
        return;

    int hammerid = GetEntityHammerId(caller);
    if (DispatchByHammerId(hammerid, output, activator))
        return;

    if (activator >= 1 && activator <= MaxClients && IsClientInGame(activator) && TryDispatchScriptFromEntity(caller, activator))
        return;

    char name[64];
    GetEntityName(caller, name, sizeof(name));

    if (StrEqual(name, "big_tele", false))
    {
        Bigt(activator);
    }
    else if (StrEqual(name, "game_start_te", false))
    {
        TX(2, activator);
    }
    else if (StrEqual(name, "game_start_ct", false))
    {
        TX(3, activator);
    }
    else if (StrEqual(name, "game_start_te2", false))
    {
        TXByCurrentTeam(activator);
    }
    else if (StrEqual(name, "game_start_ct2", false))
    {
        TXByCurrentTeam(activator);
    }
}

public Action OnEscapeTriggerStartTouch(int trigger, int other)
{
    HandleEscapeTouch(trigger, other);
    return Plugin_Continue;
}

public void Output_DoorBreak(const char[] output, int caller, int activator, float delay)
{
    char name[64];
    GetEntityName(caller, name, sizeof(name));

    if (StrEqual(name, "door1", false))
        DoorBrk(1);
    else if (StrEqual(name, "door2", false))
        DoorBrk(2);
    else if (StrEqual(name, "door3", false))
        DoorBrk(3);
}

public Action Event_PlayerSay(Event event, const char[] name, bool dontBroadcast)
{
    char text[192];
    event.GetString("text", text, sizeof(text));

    if (StrEqual(text, "!copyright", false) && g_iCopyrightShown == 0)
    {
        g_iCopyrightShown++;
        Cpr();
    }

    return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (victim > 0)
    {
        ClearBotBreakthroughGoal(victim);
        Playerdied(victim);
    }

    if (attacker > 0 && attacker != victim)
        Playerkill(attacker);

    return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        ClearBotBreakthroughGoal(client);
        RequestFrame(Frame_EscapeSpawnTeleport, GetClientUserId(client));
    }

    return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    RequestFrame(Frame_HookEscapeTouchTriggers);
    RequestFrame(Frame_ScanDamageEntities);
    RequestFrame(Frame_DisableDelayedCTOriginTrigger);

    if (g_bSecondHalfRoundRestartPending)
        CreateTimer(0.1, Timer_ApplySecondHalfRoundStart, _, TIMER_FLAG_NO_MAPCHANGE);
    else if (g_bFullCycleRoundRestartPending)
        CreateTimer(0.1, Timer_ApplyFullCycleRoundStart, _, TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Continue;
}

void ResetState()
{
    StopAllTimers();

    g_iTimeMinute = 8;
    g_iTimeSecond = 0;
    g_iEscTotalTimes = 9;
    g_iEscTimes = 9;
    g_iTHM = 8;
    g_iTHS = 0;
    g_iNum = 9;
    g_iTot = 9;
    g_iTK = 0;
    g_iCTK = 0;
    g_iDEF = 0;
    g_iRoundNum = 1;
    g_iLang = 1;
    g_iBGMZEN = 1;
    g_iBGMGO = 1;
    g_iDLZ = 1;
    g_iDLG = 1;
    g_iSStop = 0;
    g_iTC = 5;
    g_iCS = 5;
    g_iCCS = 0;
    g_iPc = 12;
    g_iNowPc = 5;
    g_iCopyrightShown = 0;
    g_bSecondHalfRoundRestartPending = false;
    g_bFullCycleRoundRestartPending = false;
    SetFreezeTime(3.0);
    for (int client = 1; client <= MaxClients; client++)
    {
        g_fLastEscapeTouch[client] = 0.0;
        ClearBotBreakthroughGoal(client);
    }

    for (int i = 0; i < sizeof(g_bDoorWarned2); i++)
    {
        g_bDoorWarned2[i] = false;
        g_bDoorWarned3[i] = false;
    }

    for (int i = 0; i < sizeof(g_Dist); i++)
    {
        strcopy(g_Dist[i], sizeof(g_Dist[]), " -");
    }
}

bool HandleEscapeTouch(int trigger, int activator)
{
    if (!IsEscapeTouchTrigger(trigger) || !IsValidClient(activator) || !IsPlayerAlive(activator))
        return false;

    if (!CanClientUseEscapeTrigger(trigger, activator))
        return false;

    float now = GetGameTime();
    if (now - g_fLastEscapeTouch[activator] < 1.0)
        return true;

    g_fLastEscapeTouch[activator] = now;
    Tuwei(activator);
    return true;
}

bool IsEscapeTouchTrigger(int ent)
{
    if (ent <= MaxClients || !IsValidEntity(ent))
        return false;

    char name[64];
    GetEntityName(ent, name, sizeof(name));
    if (StrEqual(name, "tar", false) || StrEqual(name, "tar2", false))
        return true;

    int hammerid = GetEntityHammerId(ent);
    return (hammerid == 148508 || hammerid == 149935);
}

bool CanClientUseEscapeTrigger(int trigger, int client)
{
    char name[64];
    GetEntityName(trigger, name, sizeof(name));

    if (StrEqual(name, "tar", false))
        return GetClientTeam(client) == CS_TEAM_T;

    if (StrEqual(name, "tar2", false))
        return GetClientTeam(client) == CS_TEAM_CT;

    int hammerid = GetEntityHammerId(trigger);
    if (hammerid == 148508)
        return GetClientTeam(client) == CS_TEAM_T;

    if (hammerid == 149935)
        return GetClientTeam(client) == CS_TEAM_CT;

    return false;
}

void StartAutoTimers()
{
    if (g_hScoreTimer == null)
        g_hScoreTimer = CreateTimer(1.0, Timer_ShowScoreBar, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    if (g_hCheckTimer == null)
        g_hCheckTimer = CreateTimer(0.5, Timer_Checkmatch, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    if (g_hDistanceTimer == null)
        g_hDistanceTimer = CreateTimer(0.2, Timer_Think, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    if (g_hSniperTimer == null)
        g_hSniperTimer = CreateTimer(1.0, Timer_CheckSniper, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void StopAllTimers()
{
    KillTimerSafe(g_hScoreTimer);
    KillTimerSafe(g_hCheckTimer);
    KillTimerSafe(g_hDistanceTimer);
    KillTimerSafe(g_hSniperTimer);
    KillTimerSafe(g_hStopTimer);
    KillTimerSafe(g_hHalfTimer);
}

void KillTimerSafe(Handle &timer)
{
    if (timer != null)
    {
        KillTimer(timer);
        timer = null;
    }
}

public Action Timer_ShowScoreBar(Handle timer)
{
    ShowScoreBar();
    return Plugin_Continue;
}

public Action Timer_Checkmatch(Handle timer)
{
    Checkmatch();
    return Plugin_Continue;
}

public Action Timer_Think(Handle timer)
{
    Think();
    return Plugin_Continue;
}

public Action Timer_CheckSniper(Handle timer)
{
    CheckSniper();
    return Plugin_Continue;
}

public Action Timer_ShowStopMsg(Handle timer)
{
    bool done = ShowStopMsg();
    if (done)
    {
        g_hStopTimer = null;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public Action Timer_TeamChange(Handle timer)
{
    if (TeamChange())
    {
        g_hHalfTimer = null;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

public Action Timer_Stips(Handle timer)
{
    Stips();
    return Plugin_Stop;
}

public Action Timer_Trt(Handle timer)
{
    Trt();
    return Plugin_Stop;
}

public Action Timer_GameStart(Handle timer)
{
    GameStart();
    return Plugin_Stop;
}

public Action Timer_ApplySecondHalfRoundStart(Handle timer)
{
    if (g_bSecondHalfRoundRestartPending)
    {
        g_bSecondHalfRoundRestartPending = false;
        ApplySecondHalfRoundStart();
    }

    return Plugin_Stop;
}

public Action Timer_ApplyFullCycleRoundStart(Handle timer)
{
    if (g_bFullCycleRoundRestartPending)
    {
        ApplyFullCycleRoundStart();
    }

    return Plugin_Stop;
}

public Action Timer_ExecCMD(Handle timer)
{
    ExecCMD();
    return Plugin_Stop;
}

public Action Timer_Lang(Handle timer)
{
    Lang();
    return Plugin_Stop;
}

public Action Timer_SayGS(Handle timer)
{
    SayGS();
    return Plugin_Stop;
}

public void Frame_EscapeSpawnTeleport(any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !IsPlayerAlive(client))
        return;

    TeleportClientToEscapeSpawn(client);
}

void RunFunction(const char[] func, int arg, int activator)
{
    if (StrEqual(func, "SayGS", false))
        SayGS();
    else if (StrEqual(func, "GameStart", false))
        GameStart();
    else if (StrEqual(func, "Stips", false))
        Stips();
    else if (StrEqual(func, "Tuwei", false))
        Tuwei(activator);
    else if (StrEqual(func, "Checkmatch", false))
        Checkmatch();
    else if (StrEqual(func, "StartHF", false))
        StartHF();
    else if (StrEqual(func, "TX", false))
        TX(arg, activator);
    else if (StrEqual(func, "Bigt", false))
        Bigt(activator);
    else if (StrEqual(func, "Trt", false))
        Trt();
    else if (StrEqual(func, "TTTTT", false))
        g_iEscTimes = 1;
    else if (StrEqual(func, "TeamChange", false))
        TeamChange();
    else if (StrEqual(func, "STC", false))
        STC();
    else if (StrEqual(func, "Think", false))
        Think();
    else if (StrEqual(func, "Playerdied", false))
        Playerdied(activator);
    else if (StrEqual(func, "Playerkill", false))
        Playerkill(activator);
    else if (StrEqual(func, "ShowScoreBar", false))
        ShowScoreBar();
    else if (StrEqual(func, "ShowStopMsg", false))
        ShowStopMsg();
    else if (StrEqual(func, "Door1Dmg", false))
        DoorDmg(1);
    else if (StrEqual(func, "Door1Brk", false))
        DoorBrk(1);
    else if (StrEqual(func, "Door2Dmg", false))
        DoorDmg(2);
    else if (StrEqual(func, "Door2Brk", false))
        DoorBrk(2);
    else if (StrEqual(func, "Door3Dmg", false))
        DoorDmg(3);
    else if (StrEqual(func, "Door3Brk", false))
        DoorBrk(3);
    else if (StrEqual(func, "EscSuccess", false))
        EscSuccess();
    else if (StrEqual(func, "PCCHECK", false))
        PCCHECK(arg);
    else if (StrEqual(func, "Lang", false))
        Lang();
    else if (StrEqual(func, "Cpr", false))
        Cpr();
    else if (StrEqual(func, "ExecCMD", false))
        ExecCMD();
    else if (StrEqual(func, "CheckSniper", false))
        CheckSniper();
    else if (StrEqual(func, "GetWeapon", false))
        GetWeapon(arg, activator);
    else if (StrEqual(func, "Isb", false) || StrEqual(func, "Nob", false))
        ServerCommand("sm_cf_spr %s", func);
}

bool DispatchByHammerId(int hammerid, const char[] output, int activator)
{
    switch (hammerid)
    {
        case 147346:
        {
            // logic_auto: cf_tem_spr starts itself; main mapspawn work is done from OnMapStart.
            return g_cvAutoMapSpawn.BoolValue;
        }
        case 148508, 149935:
        {
            Tuwei(activator);
            return true;
        }
        case 148529:
        {
            if (g_cvAutoTimers.BoolValue)
                return true;
            Think();
            return true;
        }
        case 148536:
        {
            if (g_cvAutoTimers.BoolValue)
                return true;
            ShowScoreBar();
            return true;
        }
        case 148570:
        {
            if (StrEqual(output, "OnBreak", false))
                DoorBrk(1);
            else
                DoorDmg(1);
            return true;
        }
        case 149460:
        {
            if (g_cvAutoTimers.BoolValue)
                return true;
            ShowStopMsg();
            return true;
        }
        case 149773:
        {
            if (g_cvAutoTimers.BoolValue)
                return true;
            Checkmatch();
            return true;
        }
        case 149811:
        {
            if (g_cvAutoTimers.BoolValue)
                return true;
            TeamChange();
            return true;
        }
        case 149833:
        {
            Bigt(activator);
            return true;
        }
        case 150546:
        {
            Playerdied(activator);
            return true;
        }
        case 150548:
        {
            Playerkill(activator);
            return true;
        }
        case 150584:
        {
            if (StrEqual(output, "OnBreak", false))
                DoorBrk(2);
            else
                DoorDmg(2);
            return true;
        }
        case 150718:
        {
            if (StrEqual(output, "OnBreak", false))
                DoorBrk(3);
            else
                DoorDmg(3);
            return true;
        }
        case 151495:
        {
            // logic_auto: Lang() and SayGS() are scheduled in OnMapStart.
            return g_cvAutoMapSpawn.BoolValue;
        }
        case 151512:
        {
            return false;
        }
        case 154630:
        {
            if (g_cvAutoTimers.BoolValue)
                return true;
            CheckSniper();
            return true;
        }
        case 158777:
        {
            Cpr();
            return true;
        }
    }

    int weapon = GetWeaponIdForButtonHammer(hammerid);
    if (weapon > 0)
    {
        GetWeapon(weapon, activator);
        return true;
    }

    return false;
}

int GetWeaponIdForButtonHammer(int hammerid)
{
    switch (hammerid)
    {
        case 153512, 155207:
            return 1;
        case 153588:
            return 2;
        case 153756:
            return 3;
        case 153804:
            return 4;
        case 153854, 155245:
            return 5;
        case 153896:
            return 6;
        case 153924:
            return 7;
        case 153981:
            return 8;
        case 154001, 155277:
            return 9;
        case 154045, 155286:
            return 10;
        case 154087, 155295:
            return 11;
        case 154157, 155304:
            return 12;
        case 154204, 155313:
            return 13;
        case 154231, 155322:
            return 14;
        case 154268, 157224:
            return 15;
        case 154369, 157236:
            return 16;
        case 154406, 157247:
            return 17;
        case 154430, 157262:
            return 18;
        case 154456:
            return 19;
        case 154473, 157284:
            return 20;
        case 154490, 157294:
            return 21;
        case 154534, 157302:
            return 22;
        case 154557, 157315:
            return 23;
        case 154570:
            return 24;
        case 155214:
            return 25;
        case 155227:
            return 26;
        case 155232:
            return 27;
        case 155250:
            return 28;
        case 157270:
            return 29;
        case 157323:
            return 30;
    }

    return 0;
}

void SayGS()
{
    PrintToChatAll("%s\x01 %s", g_Tag[g_iLang], g_Subtitle[11][g_iLang]);
}

void GameStart()
{
    for (float t = 3.0; t <= 15.0; t += 1.0)
    {
        CreateTimer(t, Timer_Stips, _, TIMER_FLAG_NO_MAPCHANGE);
    }

    FireByName("cmd", "Command", "say [Map] Map by 哔哩哔哩-风流倜傥你杰森, Escape MOD by Dazai Nerau.", 2.0);
}

void Stips()
{
    if (g_iRoundNum == 1)
    {
        if (g_iLang == 0)
        {
            PrintCenterTeam(CS_TEAM_T, "In %d minutes %d seconds, %d attackers must enter the portal before time runs out!", g_iTimeMinute, g_iTimeSecond, g_iEscTimes);
            PrintCenterTeam(CS_TEAM_CT, "Prevent %d attackers from entering the portal until time runs out!", g_iEscTimes);
        }
        else
        {
            PrintCenterTeam(CS_TEAM_T, "进攻方任务：在%d分%d秒内突围%d名!", g_iTimeMinute, g_iTimeSecond, g_iEscTimes);
            PrintCenterTeam(CS_TEAM_CT, "防守方任务：在%d分%d秒内尽可能阻止突围!", g_iTimeMinute, g_iTimeSecond);
        }
    }
    else if (g_iRoundNum == 4)
    {
        if (g_iLang == 0)
        {
            PrintCenterTeam(CS_TEAM_T, "In %d minutes %d seconds, %d attackers must enter the portal before time runs out!", g_iTHM, g_iTHS, g_iNum);
            PrintCenterTeam(CS_TEAM_CT, "Prevent %d attackers from entering the portal until time runs out!", g_iNum);
        }
        else
        {
            PrintCenterTeam(CS_TEAM_T, "进攻方任务：在%d分%d秒内突围%d名!", g_iTHM, g_iTHS, g_iNum);
            PrintCenterTeam(CS_TEAM_CT, "防守方任务：在%d分%d秒内尽可能阻止突围!", g_iTHM, g_iTHS);
        }
    }
}

void Tuwei(int activator)
{
    if (!IsValidClient(activator))
        return;

    FireByName("cmd", "Command", "mp_radar_showall 0");
    StartStopTimer();

    FireByName("kinjite", "ShowSprite");
    FireByName("kinjite", "HideSprite", "", 5.0);
    FireByName("helloworld", "AddOutput", "rendercolor 255 92 0");
    FireByName("helloworld", "Alpha", "25", 0.01);
    FireByName("helloworld", "AddOutput", "rendercolor 255 255 255", 5.0);
    FireByName("helloworld", "Alpha", "25", 5.01);
    FireByName("wth", "AddOutput", "rendercolor 255 92 0");
    FireByName("wth", "AddOutput", "rendercolor 0 255 255", 5.0);
    ServerCommand("sm_cf_spr Nob");
    CreateTimer(5.0, Timer_SprIsBlue, _, TIMER_FLAG_NO_MAPCHANGE);
    FireByName("mdf_esc_1", "SetMaterialVar", "1");
    FireByName("mdf_esc_2", "SetMaterialVar", "1");
    FireByName("mdf_esc_1", "SetMaterialVar", "0", 5.0);
    FireByName("mdf_esc_2", "SetMaterialVar", "0", 5.0);
    FireByName("escsmk", "TurnOn");
    FireByName("escsmk", "TurnOff", "", 3.0);
    FireByName("fader", "Fade", "", 0.0, activator);
    FireByName("fader", "FadeReverse", "", 0.3, activator);

    if (g_iRoundNum == 1)
    {
        if (g_iEscTimes >= 1)
            g_iEscTimes--;
        else
            g_iEscTimes = 0;

        float dest[3] = {-3743.98, 1868.0, 281.47};
        DoEscapeSuccess(activator, dest, true);
    }
    else if (g_iRoundNum == 4)
    {
        if (g_iNum >= 1)
            g_iNum--;
        else
            g_iNum = 0;

        float dest[3] = {-3743.98, 1868.0, 281.47};
        DoEscapeSuccess(activator, dest, false);
    }
}

public Action Timer_SprIsBlue(Handle timer)
{
    ServerCommand("sm_cf_spr Isb");
    return Plugin_Stop;
}

void DoEscapeSuccess(int client, const float dest[3], bool firstHalf)
{
    bool isBot = IsClientInGame(client) && IsFakeClient(client);
    if (isBot)
        ClearBotBreakthroughGoal(client);
    else
        TeleportEntity(client, dest, NULL_VECTOR, NULL_VECTOR);

    int hp = GetClientHealth(client);

    char text[256];
    Format(text, sizeof(text), "%s%d%s", g_Subtitle[0][g_iLang], g_iNowPc, g_Subtitle[1][g_iLang]);
    GameText("tips", text);

    Format(text, sizeof(text), "hint_caption %s%d", g_Subtitle[2][g_iLang], hp);
    FireByName("hint_esc", "AddOutput", text);
    FireByName("hint_esc", "ShowHint", "", 0.1);

    if (g_iLang == 0)
    {
        PrintToChatAll("%s\x01  A attacker has Escaped Successfully! Acquired\x01 \x04%d\x01 Extra Kills, HP: \x01 \x04%d", g_Tag[g_iLang], g_iNowPc, hp);
    }
    else
    {
        PrintToChatAll("%s\x01 进攻方突围成功! 突围者增加了\x01 \x04%d\x01 杀敌数, 突围者生命值:\x01\x04%d", g_Tag[g_iLang], g_iNowPc, hp);
    }

    AddClientKills(client, g_iNowPc);
    CreateEscapeMsg(client);

    if (firstHalf)
        g_iTK += g_iNowPc;
    else
        g_iCTK += g_iNowPc;

    UpdateTeamScore( CS_TEAM_T, 0, g_iTK );

    FireByName("equiper", "TriggerForActivatedPlayer", "item_assaultsuit", 0.0, client);
    FireByName("ammogiver", "GiveAmmo", "", 0.0, client);
    SetEntityHealth(client, 100);
    SetEntProp(client, Prop_Send, "m_ArmorValue", 100);
    SetEntProp(client, Prop_Send, "m_bHasHelmet", 1);

    if (isBot)
        TeleportClientToEscapeSpawn(client);
}

void CreateEscapeMsg(int client)
{
    if (!IsValidClient(client) || !IsClientInGame(client))
        return;


    Event hEvent = CreateEvent("player_death", true);
    if (hEvent == null)
        return;

    char ClassName[30];
    int WeaponIndex = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (WeaponIndex > 0 && IsValidEdict(WeaponIndex))
    {
        GetEntityClassname(WeaponIndex, ClassName, sizeof(ClassName));
        ReplaceString(ClassName, sizeof(ClassName), "weapon_", "", false);
    }
    else
    {
        strcopy(ClassName, sizeof(ClassName), "knife"); // fallback
    }

    hEvent.SetInt("userid", 0); // victim = 0
    hEvent.SetInt("attacker", GetClientUserId(client));
    hEvent.SetInt("dominated", 3);
    hEvent.SetString("weapon", ClassName);
    for (int i = 1; i <= MaxClients; i++)
    {
        //只发送给真人玩家 和在游戏中的 客户端
        if (IsClientInGame(i) && !IsFakeClient(i)) 
            hEvent.FireToClient(i); // 只发送给特定客户端 不经过其他hook
    }
    hEvent.Close();
}

void Checkmatch()
{
    if (g_iRoundNum == 1)
    {
        if (g_iEscTimes <= 4 && g_iBGMZEN == 1)
        {
            g_iBGMZEN = 0;
            FireByName("bgm", "PlaySound");
            FireByName("bgm", "Volume", "8");
        }

        if (g_iTimeMinute <= 2 && g_iDLZ == 1 && g_iEscTimes == g_iEscTotalTimes)
        {
            GameText("tips2", g_Subtitle[10][g_iLang]);
            g_iDLZ = 0;
            FireByName("cmd", "Command", "mp_radar_showall 1");
            PrintToChatAll("%s\x01  %s", g_Tag[g_iLang], g_Subtitle[10][g_iLang]);
        }

        if (g_iEscTimes == 0)
        {
            g_iRoundNum = 2;
            if (g_iTimeSecond == 0)
            {
                g_iTHS = 0;
                g_iTHM = 8 - g_iTimeMinute;
            }
            else
            {
                g_iTHS = 60 - g_iTimeSecond;
                g_iTHM = 7 - g_iTimeMinute;
            }
            g_iNum = g_iEscTotalTimes;
            StartHF();
        }
        else if (g_iTimeMinute == 0 && g_iTimeSecond == 0)
        {
            g_iRoundNum = 3;
            g_iTHM = 8;
            g_iTHS = 0;
            g_iNum = g_iEscTotalTimes - g_iEscTimes;
            StartHF();
        }
    }
    else if (g_iRoundNum == 4)
    {
        if (g_iNum <= 4 && g_iBGMGO == 1)
        {
            g_iBGMGO = 0;
            FireByName("bgm", "PlaySound");
            FireByName("bgm", "Volume", "8");
        }

        if (g_iTHM <= 2 && g_iDLG == 1 && g_iNum == g_iTot)
        {
            GameText("tips2", g_Subtitle[10][g_iLang]);
            g_iDLG = 0;
            FireByName("cmd", "Command", "mp_radar_showall 1");
            PrintToChatAll("%s\x01  %s", g_Tag[g_iLang], g_Subtitle[10][g_iLang]);
        }

        if (g_iNum == 0 && g_iSStop == 0)
        {
            if (g_iLang == 0)
                PrintToChatAll("%s\x01  Mission Success! Terrorists win!", g_Tag[g_iLang]);
            else
                PrintToChatAll("%s\x01  任务完成! 恐怖分子队伍胜利!", g_Tag[g_iLang]);
            g_iSStop = 1;
            QueueFullCycleRestart(CSRoundEnd_TerroristWin);
        }
        else if (g_iTHM == 0 && g_iTHS == 0 && g_iSStop == 0)
        {
            if (g_iLang == 0)
                PrintToChatAll("%s\x01  Time ran out! Counter Terrorists win!", g_Tag[g_iLang]);
            else
                PrintToChatAll("%s\x01  时间耗尽! 反恐精英队伍胜利!", g_Tag[g_iLang]);
            g_iSStop = 1;
            QueueFullCycleRestart(CSRoundEnd_CTWin);
        }
    }
}

void StartHF()
{
    if (g_iLang == 0)
        PrintToChatAll("%s\x01  Halftime Stage, please wait...", g_Tag[g_iLang]);
    else
        PrintToChatAll("%s\x01  半场阶段，请等待...", g_Tag[g_iLang]);

    KillTimerSafe(g_hScoreTimer);
    SetFreezeTime(999.0);
    ClearAllBotBreakthroughGoals();
    FireByName("timer", "Disable");
    FireByName("timer_scorebar", "Disable");
    CreateTimer(5.1, Timer_Trt, _, TIMER_FLAG_NO_MAPCHANGE);

    if (g_hHalfTimer == null)
        g_hHalfTimer = CreateTimer(1.0, Timer_TeamChange, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    FireByName("timer_hf", "Enable");
    FireByName("ct_tele_1", "Disable");
    FireByName("t_tele_1", "Disable");
    FireByName("big_tele", "Enable", "", 0.5);
    FireByName("halfview", "Enable");
    FireByName("tar", "Disable");
    FireByName("tar", "Disable", "", 7.0);
    FireByName("tar2", "Disable");
    FireByName("game_start_te", "Disable");
    FireByName("game_start_ct", "Disable");
    FireByName("game_start_te2", "Disable");
    FireByName("game_start_ct2", "Disable");

    g_iTot = g_iEscTotalTimes - g_iEscTimes;
    SetMessage("t_1_m", g_iTHM);
    SetMessage("t_1_s", g_iTHS);
    SetMessage("t_2", g_iNum);
    SetMessage("t_3", g_iDEF);
    SetMessage("t_4", g_iTK);
    SetMessage("t_5", g_iCTK);

    FireByName("bgm", "StopSound");
    FireByName("bgm", "Volume", "0");
}

void TX(int n, int activator)
{
    if (!IsValidClient(activator))
        return;

    if (n == 2)
        SetTargetname(activator, "rusher");
    else if (n == 3)
        SetTargetname(activator, "def");
}

void TXByCurrentTeam(int activator)
{
    if (!IsValidClient(activator))
        return;

    int team = GetClientTeam(activator);
    if (team == CS_TEAM_T)
        SetTargetname(activator, "rusher");
    else if (team == CS_TEAM_CT)
        SetTargetname(activator, "def");
}

void Bigt(int activator)
{
    if (!IsValidClient(activator))
        return;

    float dest[3];
    if (GetClientTeam(activator) == CS_TEAM_T)
    {
        dest[0] = -3743.98;
        dest[1] = 1868.0;
        dest[2] = 281.47;
    }
    else if (GetClientTeam(activator) == CS_TEAM_CT)
    {
        dest[0] = -3002.0;
        dest[1] = 1885.0;
        dest[2] = 281.47;
    }
    else
    {
        return;
    }

    TeleportEntity(activator, dest, NULL_VECTOR, NULL_VECTOR);
}

void RestorePlayerView(int client)
{
    FireByName("halfview", "Disable");
    FireByName("fader", "FadeReverse", "", 0.0, client);
    SetClientViewEntity(client, client);
}

void TeleportClientToEscapeSpawn(int client)
{
    int spawnList = GetEscapeSpawnListForClient(client);
    if (spawnList == -1)
        return;

    if (!g_bEscapeSpawnsLoaded)
        LoadEscapeSpawnLists();

    ApplyEscapeRoleTargetname(client, spawnList);
    RestorePlayerView(client);

    float origin[3];
    float angles[3];
    if (SelectEscapeSpawnPoint(client, spawnList, origin, angles))
    {
        TeleportEntity(client, origin, angles, NULL_VECTOR);
        CreateTimer(0.6, Timer_SetBotBreakthroughGoal, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_SetBotBreakthroughGoal(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsAttackerBot(client))
        return Plugin_Stop;

    int target = FindEntityByTargetname("tar");
    if (target <= 0)
        return Plugin_Stop;

    float targetOrigin[3];
    GetEntityOrigin(target, targetOrigin);
    SetBotBreakthroughGoal(client, targetOrigin, 96.0);
    return Plugin_Stop;
}

int GetEscapeSpawnListForClient(int client)
{
    int team = GetClientTeam(client);

    if (team == CS_TEAM_T)
        return ESCAPE_SPAWN_T;

    if (team == CS_TEAM_CT)
        return ESCAPE_SPAWN_CT;

    return -1;
}

void ApplyEscapeRoleTargetname(int client, int spawnList)
{
    if (spawnList == ESCAPE_SPAWN_T)
        SetTargetname(client, "rusher");
    else
        SetTargetname(client, "def");
}

void LoadEscapeSpawnLists()
{
    g_bEscapeSpawnsLoaded = true;
    g_iEscapeSpawnCount[ESCAPE_SPAWN_T] = 0;
    g_iEscapeSpawnCount[ESCAPE_SPAWN_CT] = 0;
    g_iEscapeSpawnLast[ESCAPE_SPAWN_T] = -1;
    g_iEscapeSpawnLast[ESCAPE_SPAWN_CT] = -1;

    char map[64];
    GetCurrentMap(map, sizeof(map));

    LoadEscapeSpawnFile(ESCAPE_SPAWN_T, map, "t_spawn");
    LoadEscapeSpawnFile(ESCAPE_SPAWN_CT, map, "ct_spawn");

    if (g_iEscapeSpawnCount[ESCAPE_SPAWN_T] == 0)
        LoadEscapeEntityFallback(ESCAPE_SPAWN_T, "t_1_des", "info_player_terrorist");

    if (g_iEscapeSpawnCount[ESCAPE_SPAWN_CT] == 0)
        LoadEscapeEntityFallback(ESCAPE_SPAWN_CT, "ct_1_des", "info_player_counterterrorist");

    LogMessage("[EscapeSpawn] loaded T=%d CT=%d for %s", g_iEscapeSpawnCount[ESCAPE_SPAWN_T], g_iEscapeSpawnCount[ESCAPE_SPAWN_CT], map);
}

bool LoadEscapeSpawnFile(int spawnList, const char[] map, const char[] suffix)
{
    char path[PLATFORM_MAX_PATH];
    Format(path, sizeof(path), "cfg/escape/%s.%s.txt", map, suffix);

    File file = OpenFile(path, "r");
    if (file == null)
        file = OpenFile(path, "r", true);

    if (file == null)
        return false;

    char line[512];
    while (!file.EndOfFile() && g_iEscapeSpawnCount[spawnList] < MAX_ESCAPE_SPAWNS)
    {
        file.ReadLine(line, sizeof(line));
        ParseEscapeSpawnLine(spawnList, line);
    }

    delete file;
    return true;
}

void ParseEscapeSpawnLine(int spawnList, char[] line)
{
    int comment = StrContains(line, "//");
    if (comment != -1)
        line[comment] = 0;

    comment = StrContains(line, "#");
    if (comment != -1)
        line[comment] = 0;

    comment = StrContains(line, ";");
    if (comment != -1)
        line[comment] = 0;

    ReplaceString(line, 512, "\t", " ");
    while (ReplaceString(line, 512, "  ", " ") > 0) {}
    TrimString(line);

    if (line[0] == 0)
        return;

    char parts[6][32];
    int fields = ExplodeString(line, " ", parts, sizeof(parts), sizeof(parts[]));
    if (fields < 3)
        return;

    float origin[3];
    float angles[3];
    origin[0] = StringToFloat(parts[0]);
    origin[1] = StringToFloat(parts[1]);
    origin[2] = StringToFloat(parts[2]);
    angles[0] = (fields >= 4) ? StringToFloat(parts[3]) : 0.0;
    angles[1] = (fields >= 5) ? StringToFloat(parts[4]) : 0.0;
    angles[2] = (fields >= 6) ? StringToFloat(parts[5]) : 0.0;

    AddEscapeSpawn(spawnList, origin, angles);
}

int LoadEscapeEntityFallback(int spawnList, const char[] targetname, const char[] classname)
{
    int added = LoadEscapeSpawnsByTargetname(spawnList, targetname);
    if (added > 0)
        return added;

    return LoadEscapeSpawnsByClassname(spawnList, classname);
}

int LoadEscapeSpawnsByTargetname(int spawnList, const char[] targetname)
{
    int added = 0;
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "*")) != -1 && g_iEscapeSpawnCount[spawnList] < MAX_ESCAPE_SPAWNS)
    {
        if (!HasTargetname(ent, targetname))
            continue;

        float origin[3];
        float angles[3];
        GetEntityOrigin(ent, origin);
        GetEntityAnglesSafe(ent, angles);
        AddEscapeSpawn(spawnList, origin, angles);
        added++;
    }

    return added;
}

int LoadEscapeSpawnsByClassname(int spawnList, const char[] classname)
{
    int added = 0;
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, classname)) != -1 && g_iEscapeSpawnCount[spawnList] < MAX_ESCAPE_SPAWNS)
    {
        float origin[3];
        float angles[3];
        GetEntityOrigin(ent, origin);
        if (IsZeroVector(origin))
            continue;

        GetEntityAnglesSafe(ent, angles);
        AddEscapeSpawn(spawnList, origin, angles);
        added++;
    }

    return added;
}

void AddEscapeSpawn(int spawnList, float origin[3], float angles[3])
{
    int index = g_iEscapeSpawnCount[spawnList];
    if (index >= MAX_ESCAPE_SPAWNS)
        return;

    CopyVector(origin, g_vEscapeSpawnOrigin[spawnList][index]);
    CopyVector(angles, g_vEscapeSpawnAngles[spawnList][index]);
    g_iEscapeSpawnCount[spawnList]++;
}

bool SelectEscapeSpawnPoint(int client, int spawnList, float outOrigin[3], float outAngles[3])
{
    int count = g_iEscapeSpawnCount[spawnList];
    if (count <= 0)
        return false;

    int start = g_iEscapeSpawnLast[spawnList];
    if (start < 0)
        start = GetRandomInt(0, count - 1);
    else
        start = (start + GetRandomInt(1, 2)) % count;

    for (int i = 0; i < count; i++)
    {
        int index = (start + i) % count;
        if (!IsSpawnPointClear(client, g_vEscapeSpawnOrigin[spawnList][index]))
            continue;

        CopyVector(g_vEscapeSpawnOrigin[spawnList][index], outOrigin);
        CopyVector(g_vEscapeSpawnAngles[spawnList][index], outAngles);
        g_iEscapeSpawnLast[spawnList] = index;
        return true;
    }

    for (int i = 0; i < count; i++)
    {
        int index = (start + i) % count;
        if (!FindNearbyEmptySpawnSpot(client, g_vEscapeSpawnOrigin[spawnList][index], outOrigin))
            continue;

        CopyVector(g_vEscapeSpawnAngles[spawnList][index], outAngles);
        g_iEscapeSpawnLast[spawnList] = index;
        return true;
    }

    return false;
}

bool FindNearbyEmptySpawnSpot(int client, float base[3], float outOrigin[3])
{
    float zOffsets[5] = {0.0, 18.0, 38.0, 76.0, 114.0};
    float step = 36.0;

    for (int radius = 1; radius <= 6; radius++)
    {
        for (int x = -radius; x <= radius; x++)
        {
            for (int y = -radius; y <= radius; y++)
            {
                if (x != -radius && x != radius && y != -radius && y != radius)
                    continue;

                for (int z = 0; z < sizeof(zOffsets); z++)
                {
                    float candidate[3];
                    candidate[0] = base[0] + (float(x) * step);
                    candidate[1] = base[1] + (float(y) * step);
                    candidate[2] = base[2] + zOffsets[z];

                    if (!IsSpawnPointClear(client, candidate))
                        continue;

                    CopyVector(candidate, outOrigin);
                    return true;
                }
            }
        }
    }

    return false;
}

bool IsSpawnPointClear(int client, float origin[3])
{
    float mins[3] = {-16.0, -16.0, 0.0};
    float maxs[3] = {16.0, 16.0, 72.0};

    Handle trace = TR_TraceHullFilterEx(origin, origin, mins, maxs, MASK_PLAYERSOLID, TraceFilter_EscapeSpawn, client);
    bool blocked = TR_DidHit(trace) || TR_StartSolid(trace) || TR_AllSolid(trace);
    delete trace;

    return !blocked;
}

public bool TraceFilter_EscapeSpawn(int entity, int contentsMask, any data)
{
    if (entity == data)
        return false;

    if (entity >= 1 && entity <= MaxClients)
        return IsClientInGame(entity) && IsPlayerAlive(entity);

    return true;
}

void Trt()
{
    if (g_iRoundNum == 2)
    {
        PrintCenterTeam(CS_TEAM_T, "%s", g_Subtitle[6][g_iLang]);
        PrintCenterTeam(CS_TEAM_CT, "%s", g_Subtitle[9][g_iLang]);
    }
    else if (g_iRoundNum == 3)
    {
        PrintCenterTeam(CS_TEAM_T, "%s", g_Subtitle[7][g_iLang]);
        PrintCenterTeam(CS_TEAM_CT, "%s", g_Subtitle[8][g_iLang]);
    }
}

bool TeamChange()
{
    if (g_iTC <= 0)
    {
        g_iTC = 0;
        STC(true);
        return true;
    }

    char text[256];
    if (g_iLang == 0)
    {
        Format(text, sizeof(text), "           TEAM CHANGE\nGame will start after switching \nattackers & defenders in %d seconds", g_iTC);
    }
    else
    {
        Format(text, sizeof(text), "               换组\n        剩余时间%d秒!\n    双方玩家攻守交换", g_iTC);
    }

    GameText("scorebar", text);
    FireByName("amb_bip", "PlaySound");
    g_iTC--;
    return false;
}

void STC(bool fromHalfTimer = false)
{
    bool shouldSwapTeams = (g_iRoundNum != 4);

    if (g_iLang == 0)
        PrintToChatAll("%s\x01  The second half begins!", g_Tag[g_iLang]);
    else
        PrintToChatAll("%s\x01  下半场开始！", g_Tag[g_iLang]);

    if (!fromHalfTimer)
        KillTimerSafe(g_hHalfTimer);
    SetFreezeTime(3.0);
    ClearAllBotBreakthroughGoals();
    FireByName("timer_hf", "Disable");
    FireByName("halfview", "Disable");

    g_iRoundNum = 4;
    if (shouldSwapTeams)
        SwapPlayerTeamsForSecondHalf(false);

    g_bSecondHalfRoundRestartPending = true;
    CS_TerminateRound(1.0, CSRoundEnd_GameStart);
}

void ApplySecondHalfRoundStart()
{
    FireByName("timer_hf", "Disable");
    FireByName("big_tele", "Disable");
    FireByName("ct_tele_1", "AddOutput", "target ct_1_des");
    FireByName("t_tele_1", "AddOutput", "target t_1_des");
    FireByName("tar", "Enable", "", 0.5);
    FireByName("tar2", "Disable");
    FireByName("game_start_te", "Enable", "", 0.1);
    FireByName("game_start_ct", "Enable", "", 0.1);
    FireByName("game_start_te2", "Disable");
    FireByName("game_start_ct2", "Disable");
    FireByName("ct_tele_1", "Enable", "", 0.5);
    FireByName("t_tele_1", "Enable", "", 0.5);
    FireByName("halfview", "Disable", "", 0.5);

    if (g_hScoreTimer == null)
        g_hScoreTimer = CreateTimer(1.0, Timer_ShowScoreBar, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    FireByName("timer", "Enable");
    FireByName("timer_scorebar", "Enable");

    CreateTimer(5.0, Timer_GameStart, _, TIMER_FLAG_NO_MAPCHANGE);
    FireByName("timer_check", "Enable");
    FireByName("mdf1", "SetMaterialVar", "0", 1.5);
    FireByName("mdf2", "SetMaterialVar", "0", 1.5);
    FireByName("mdf3", "SetMaterialVar", "0", 1.5);
}

void QueueFullCycleRestart(CSRoundEndReason reason)
{
    KillTimerSafe(g_hHalfTimer);
    ClearAllBotBreakthroughGoals();
    SetFreezeTime(3.0);

    if (!g_bFullCycleRoundRestartPending)
    {
        SwapPlayerTeamsForSecondHalf(false);
        g_bFullCycleRoundRestartPending = true;
    }

    CS_TerminateRound(7.0, reason);
}

void ApplyFullCycleRoundStart()
{
    ResetState();

    if (g_cvAutoTimers.BoolValue)
        StartAutoTimers();

    if (g_cvAutoMapSpawn.BoolValue)
    {
        CreateTimer(0.1, Timer_ExecCMD, _, TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(0.1, Timer_Lang, _, TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(1.0, Timer_GameStart, _, TIMER_FLAG_NO_MAPCHANGE);
        CreateTimer(5.0, Timer_SayGS, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

void SwapPlayerTeamsForSecondHalf(bool respawnAfterSwap = true)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client))
            continue;

        int team = GetClientTeam(client);
        if (team == CS_TEAM_T)
        {
            SDKCall(g_hConvertTeam, client, CS_TEAM_CT);
        }
        else if (team == CS_TEAM_CT)
        {
            SDKCall(g_hConvertTeam, client, CS_TEAM_T);
        }
    }

    if (respawnAfterSwap)
        CreateTimer(0.2, Timer_RespawnAfterTeamSwap, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RespawnAfterTeamSwap(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client))
            continue;

        int team = GetClientTeam(client);
        if (team != CS_TEAM_T && team != CS_TEAM_CT)
            continue;

        CS_RespawnPlayer(client);
    }

    return Plugin_Stop;
}

void Think()
{
    int target = FindEntityByTargetname("tar");
    if (target <= 0)
        return;

    float targetOrigin[3];
    GetEntityOrigin(target, targetOrigin);

    int thresholds[20] = {39, 78, 117, 156, 195, 235, 273, 312, 351, 390, 429, 468, 507, 546, 585, 624, 663, 702, 741, 780};
    int index = -1;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client) || !IsPlayerAlive(client) || !HasTargetname(client, "rusher"))
            continue;

        float origin[3];
        GetClientAbsOrigin(client, origin);
        int dist = RoundToFloor(GetVectorDistance(origin, targetOrigin));

        for (int i = 0; i < sizeof(thresholds); i++)
        {
            if (dist <= thresholds[i])
            {
                if (index == -1 || i < index)
                    index = i;
                break;
            }
        }
    }

    for (int i = 0; i < sizeof(g_Dist); i++)
    {
        strcopy(g_Dist[i], sizeof(g_Dist[]), " -");
    }

    int color = 0;
    if (index >= 0)
    {
        for (int i = index; i < sizeof(g_Dist); i++)
        {
            strcopy(g_Dist[i], sizeof(g_Dist[]), " O");
        }

        if (index <= 3)
            color = 1;
        else if (index <= 10)
            color = 2;
        else if (index <= 15)
            color = 3;
    }

    char label[192];
    strcopy(label, sizeof(label), "20m ");
    for (int i = 0; i < sizeof(g_Dist); i++)
    {
        StrCat(label, sizeof(label), g_Dist[i]);
    }

    GameText("disbar", label);

    if (color == 0)
        FireByName("disbar", "AddOutput", "color 255 255 255");
    else if (color == 3)
        FireByName("disbar", "AddOutput", "color 250 252 73");
    else if (color == 2)
        FireByName("disbar", "AddOutput", "color 240 148 51");
    else if (color == 1)
        FireByName("disbar", "AddOutput", "color 255 81 3");
}

void Playerdied(int client)
{
    if (!IsValidClient(client))
        return;

    float now = GetGameTime();
    if (now - g_fLastDeathHandled[client] < 0.1)
        return;
    g_fLastDeathHandled[client] = now;

    int target = FindEntityByTargetname("tar");
    if (target > 0)
    {
        float targetOrigin[3], origin[3];
        GetEntityOrigin(target, targetOrigin);
        GetClientAbsOrigin(client, origin);

        int rawDistance = RoundToFloor(GetVectorDistance(origin, targetOrigin));
        int meterDistance = RoundToFloor(float(rawDistance) * 2.54 / 100.0);

        if (rawDistance < 507 && HasTargetname(client, "rusher"))
        {
            char text[256];
            Format(text, sizeof(text), "%s%dm", g_Subtitle[4][g_iLang], meterDistance);
            GameText("tips", text);
            g_iDEF++;
            PrintToChatAll("%s\x01  %s \x01 \x04 %dm", g_Tag[g_iLang], g_Subtitle[4][g_iLang], meterDistance);
        }
    }

    SetTargetname(client, "");
}

void Playerkill(int client)
{
    if (!IsValidClient(client))
        return;

    float now = GetGameTime();
    if (now - g_fLastKillHandled[client] < 0.1)
        return;
    g_fLastKillHandled[client] = now;

    if (GetClientTeam(client) == CS_TEAM_T)
        g_iTK++;
    else
        g_iCTK++;
}

void ShowScoreBar()
{
    if (g_iRoundNum == 1)
    {
        DecrementClock(g_iTimeMinute, g_iTimeSecond);

        char text[192];
        Format(text, sizeof(text), "%s%02d : %02d  |  %s %d/%d", g_TimeLeft[g_iLang], g_iTimeMinute, g_iTimeSecond, g_EscapeCount[g_iLang], g_iEscTimes, g_iEscTotalTimes);
        GameText("scorebar", text);
    }
    else if (g_iRoundNum == 4)
    {
        DecrementClock(g_iTHM, g_iTHS);

        char text[192];
        Format(text, sizeof(text), "%s%02d : %02d  |  %s %d/%d", g_TimeLeft[g_iLang], g_iTHM, g_iTHS, g_EscapeCount[g_iLang], g_iNum, g_iTot);
        GameText("scorebar", text);
    }
}

void DecrementClock(int &minutes, int &seconds)
{
    if (seconds <= 0 && minutes > 0)
    {
        seconds = 59;
        minutes--;
    }
    else if (seconds <= 0)
    {
        minutes = 0;
        seconds = 0;
    }
    else
    {
        seconds--;
    }
}

void StartStopTimer()
{
    g_iCS = 5;
    g_iCCS = 0;
    KillTimerSafe(g_hStopTimer);
    FireByName("timerstop", "Enable");
    g_hStopTimer = CreateTimer(0.05, Timer_ShowStopMsg, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool ShowStopMsg()
{
    if (g_iCCS <= 0 && g_iCS > 0)
    {
        g_iCCS = 95;
        g_iCS--;
    }
    else if (g_iCCS <= 0)
    {
        g_iCS = 5;
        g_iCCS = 0;
        FireByName("timerstop", "Disable");

        char text[256];
        Format(text, sizeof(text), "message <font color='#00FF00'>%s", g_Subtitle[5][g_iLang]);
        FireByName("hudmsg", "AddOutput", text);
        FireByName("hudmsg", "ShowMessage", "", 0.001);
        return true;
    }
    else
    {
        g_iCCS -= 5;
    }

    char text[256];
    if (g_iLang == 0)
    {
        Format(text, sizeof(text), "message <font color='#FF0000'>You are not able to enter escape exit for %d.%02d seconds !", g_iCS, g_iCCS);
    }
    else
    {
        Format(text, sizeof(text), "message <font color='#FF0000'>%d.%02d 秒之内，不可突围！！", g_iCS, g_iCCS);
    }

    FireByName("hudmsg", "AddOutput", text);
    FireByName("hudmsg", "ShowMessage", "", 0.001);
    return false;
}

void DoorDmg(int door)
{
    char doorName[16];
    Format(doorName, sizeof(doorName), "door%d", door);

    int ent = FindEntityByTargetname(doorName);
    if (ent <= 0)
        return;

    int hp = GetEntProp(ent, Prop_Data, "m_iHealth", 4, 0);
    if (hp >= 4000)
        DoorMaterial(door, 1, 0, false);
    else if (hp >= 2000)
        DoorMaterial(door, 3, 2, true);
    else
        DoorMaterial(door, 5, 4, true);
}

void DoorMaterial(int door, int matOn, int matOff, bool burst)
{
    char mdf[16];
    Format(mdf, sizeof(mdf), "mdf%d", door);

    bool doBurst = false;
    if (burst && matOn == 3 && !g_bDoorWarned2[door])
    {
        g_bDoorWarned2[door] = true;
        doBurst = true;
    }
    else if (burst && matOn == 5 && !g_bDoorWarned3[door])
    {
        g_bDoorWarned3[door] = true;
        doBurst = true;
    }

    if (doBurst)
        DoorFx(door, false);

    char value[8];
    IntToString(matOn, value, sizeof(value));
    FireByName(mdf, "SetMaterialVar", value);
    IntToString(matOff, value, sizeof(value));
    FireByName(mdf, "SetMaterialVar", value, 0.05);
}

void DoorBrk(int door)
{
    DoorFx(door, true);
    GameText("tips", g_Subtitle[3][g_iLang]);
    g_bDoorWarned2[door] = false;
    g_bDoorWarned3[door] = false;
}

void DoorFx(int door, bool broken)
{
    char name[32];

    if (broken)
        Format(name, sizeof(name), "d%dbrkamb", door);
    else
        Format(name, sizeof(name), "d%damb", door);
    FireByName(name, "PlaySound");
    Format(name, sizeof(name), "exp%d", door);
    FireByName(name, "Explode");
    Format(name, sizeof(name), "smk%d", door);
    FireByName(name, "TurnOn");
    FireByName(name, "TurnOff", "", 3.0);
    Format(name, sizeof(name), "ske%d", door);
    FireByName(name, "StartShake");
}

void EscSuccess()
{
    FireByName("hint_def", "AddOutput", "hint_color 255 255 0");
    FireByName("hint_def", "AddOutput", "hint_caption 突围方一名玩家成功突围，生命值：32 !");
    FireByName("hint_def", "ShowHint", "", 0.1);
}

void PCCHECK(int newPc)
{
    if (newPc > 0)
        g_iPc = newPc;

    if (g_iPc < 6)
        g_iNowPc = 1;
    else if (g_iPc < 10)
        g_iNowPc = 3;
    else if (g_iPc < 12)
        g_iNowPc = 4;
    else
        g_iNowPc = 5;
}

void Lang()
{
    int ent = FindEntityByClassname(-1, "point_viewcontrol");
    if (ent > 0)
    {
        char name[16];
        GetEntityName(ent, name, sizeof(name));
        int lang = StringToInt(name);
        if (lang == 0 || lang == 1)
            g_iLang = lang;
    }

    if (g_iLang == 0)
    {
        FireByName("brusheng", "Enable");
        FireByName("brushchn", "Disable");
    }
    else
    {
        FireByName("brusheng", "Disable");
        FireByName("brushchn", "Enable");
    }
}

void Cpr()
{
    // for (int i = 0; i < sizeof(g_Copyright); i++)
    // {
    //     PrintToChatAll("%s", g_Copyright[i]);
    // }
}

void ExecCMD()
{
    // ServerCommand("bot_quota 0");
    SetFreezeTime(3.0);
    ServerCommand("mp_friendlyfire 0");
    ServerCommand("mp_limitteams 1");
    ServerCommand("mp_maxrounds 15");
    ServerCommand("mp_radar_showall 0");
    ServerCommand("mp_respawn_immunitytime 3");
    ServerCommand("mp_respawn_on_death_ct 1");
    ServerCommand("mp_respawn_on_death_t 1");
    ServerCommand("mp_timelimit 999");
    ServerCommand("mp_autokick 0");
    ServerCommand("mp_autoteambalance 1");
    ServerCommand("ammo_grenade_limit_total 1");
    ServerCommand("sv_maxvelocity 2400");
    ServerCommand("sv_maxspeed 350");
    ServerCommand("sv_enablebunnyhopping 0");
}

void CheckSniper()
{
    int tAwp = 0;
    int tAuto = 0;
    int ctAwp = 0;
    int ctAuto = 0;

    int gun = -1;
    while ((gun = FindEntityByClassname(gun, "*")) != -1)
    {
        char classname[64];
        GetEntityClassname(gun, classname, sizeof(classname));
        if (StrContains(classname, "weapon_", false) != 0)
            continue;

        int owner = GetEntPropEnt(gun, Prop_Send, "m_hOwnerEntity");
        if (!IsValidClient(owner))
            continue;

        char ownerName[64];
        GetEntityName(owner, ownerName, sizeof(ownerName));

        if (StrEqual(classname, "weapon_awp", false))
        {
            if (StrEqual(ownerName, "rusher", false))
                tAwp++;
            else if (StrEqual(ownerName, "def", false))
                ctAwp++;
        }
        else if (StrEqual(classname, "weapon_g3sg1", false) || StrEqual(classname, "weapon_scar20", false))
        {
            if (StrEqual(ownerName, "rusher", false))
                tAuto++;
            else if (StrEqual(ownerName, "def", false))
                ctAuto++;
        }
    }

    SetSniperState("button_awp", "ctawp", "mdlctawp", ctAwp >= 2, "idleOff", "idleOn");
    SetSniperState("button_scar", "ctscar", "mdlctgay", ctAuto >= 1, "idleOff", "idleOn");
    SetSniperState("button_awpt", "tawp", "mdltawp", tAwp >= 2, "idleOff", "idleOn");
    SetSniperState("button_g3sg1t", "tg3sg1", "mdltgay", tAuto >= 1, "idleOff", "idleOn");
}

void SetSniperState(const char[] button, const char[] textEnt, const char[] model, bool locked, const char[] offAnim, const char[] onAnim)
{
    if (locked)
    {
        FireByName(button, "Lock");
        FireByName(textEnt, "AddOutput", "message X");
        FireByName(textEnt, "AddOutput", "color 255 0 0");
        FireByName(model, "SetAnimation", offAnim);
    }
    else
    {
        FireByName(button, "Unlock");
        FireByName(textEnt, "AddOutput", "message O");
        FireByName(textEnt, "AddOutput", "color 0 255 0");
        FireByName(model, "SetAnimation", onAnim);
    }
}

void GetWeapon(int n, int activator)
{
    if (!IsValidClient(activator) || n <= 0 || n >= sizeof(g_Weapons))
        return;

    FireByName("eqp", "TriggerForActivatedPlayer", g_Weapons[n], 0.0, activator);
    FireByName("eqp", "TriggerForActivatedPlayer", "item_heaveassault", 0.0, activator);

    GivePlayerItem(activator, g_Weapons[n]);
    SetEntProp(activator, Prop_Send, "m_ArmorValue", 100);
    SetEntProp(activator, Prop_Send, "m_bHasHelmet", 1);
}

bool TryDispatchScriptFromEntity(int caller, int activator)
{
    char code[256];

    if (TryGetDataString(caller, "m_iszTouchValue", code, sizeof(code)) && StrContains(code, "(", false) != -1)
        return DispatchScriptCode(code, activator);

    if (TryGetDataString(caller, "m_iszResponseContext", code, sizeof(code)) && StrContains(code, "(", false) != -1)
        return DispatchScriptCode(code, activator);

    return false;
}

bool DispatchScriptCode(const char[] rawCode, int activator)
{
    char code[256];
    strcopy(code, sizeof(code), rawCode);
    TrimString(code);

    if (StrContains(code, "SayGS", false) != -1)
    {
        SayGS();
        return true;
    }
    if (StrContains(code, "GameStart", false) != -1)
    {
        GameStart();
        return true;
    }
    if (StrContains(code, "Stips", false) != -1)
    {
        Stips();
        return true;
    }
    if (StrContains(code, "Tuwei", false) != -1)
    {
        Tuwei(activator);
        return true;
    }
    if (StrContains(code, "TX", false) != -1)
    {
        TX(ParseFirstInt(code), activator);
        return true;
    }
    if (StrContains(code, "Bigt", false) != -1)
    {
        Bigt(activator);
        return true;
    }
    if (StrContains(code, "GetWeapon", false) != -1)
    {
        GetWeapon(ParseFirstInt(code), activator);
        return true;
    }
    if (StrContains(code, "PCCHECK", false) != -1)
    {
        PCCHECK(ParseFirstInt(code));
        return true;
    }
    if (StrContains(code, "Door1Dmg", false) != -1)
    {
        DoorDmg(1);
        return true;
    }
    if (StrContains(code, "Door2Dmg", false) != -1)
    {
        DoorDmg(2);
        return true;
    }
    if (StrContains(code, "Door3Dmg", false) != -1)
    {
        DoorDmg(3);
        return true;
    }
    if (StrContains(code, "Door1Brk", false) != -1)
    {
        DoorBrk(1);
        return true;
    }
    if (StrContains(code, "Door2Brk", false) != -1)
    {
        DoorBrk(2);
        return true;
    }
    if (StrContains(code, "Door3Brk", false) != -1)
    {
        DoorBrk(3);
        return true;
    }
    if (StrContains(code, "Nob", false) != -1 || StrContains(code, "Isb", false) != -1)
    {
        if (StrContains(code, "Nob", false) != -1)
            ServerCommand("sm_cf_spr Nob");
        else
            ServerCommand("sm_cf_spr Isb");
        return true;
    }

    return false;
}

int ParseFirstInt(const char[] code)
{
    int start = FindCharInString(code, '(');
    if (start == -1)
        return 0;

    char number[32];
    int out = 0;
    for (int i = start + 1; i < strlen(code) && out < sizeof(number) - 1; i++)
    {
        if ((code[i] >= '0' && code[i] <= '9') || code[i] == '-')
            number[out++] = code[i];
        else if (out > 0)
            break;
    }
    number[out] = '\0';
    return StringToInt(number);
}

void FireByName(const char[] target, const char[] input, const char[] param = "", float delay = 0.0, int activator = -1, int caller = -1)
{
    if (delay > 0.0)
    {
        DataPack pack = new DataPack();
        pack.WriteString(target);
        pack.WriteString(input);
        pack.WriteString(param);
        pack.WriteCell(activator > 0 ? EntIndexToEntRef(activator) : -1);
        pack.WriteCell(caller > 0 ? EntIndexToEntRef(caller) : -1);
        CreateTimer(delay, Timer_FireByName, pack, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    if (StrEqual(input, "RunScriptCode", false))
    {
        DispatchScriptCode(param, activator);
        return;
    }

    bool fired = false;
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "*")) != -1)
    {
        char name[128];
        GetEntityName(ent, name, sizeof(name));
        if (!StrEqual(name, target, false))
            continue;

        if (param[0] != '\0')
            SetVariantString(param);

        AcceptEntityInput(ent, input, activator, caller);
        fired = true;
    }

    if (!fired && StrEqual(input, "Command", false) && param[0] != '\0')
    {
        ServerCommand("%s", param);
    }
}

public Action Timer_FireByName(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    char target[128];
    char input[64];
    char param[256];

    pack.Reset();
    pack.ReadString(target, sizeof(target));
    pack.ReadString(input, sizeof(input));
    pack.ReadString(param, sizeof(param));
    int activatorRef = pack.ReadCell();
    int callerRef = pack.ReadCell();
    delete pack;

    int activator = EntRefToEntIndex(activatorRef);
    int caller = EntRefToEntIndex(callerRef);
    FireByName(target, input, param, 0.0, activator, caller);
    return Plugin_Stop;
}

void GameText(const char[] target, const char[] text)
{
    SetGameTextMessage(target, text);
    FireByName(target, "SetText", text);
    FireByName(target, "Display", "", 0.05);
}

void SetGameTextMessage(const char[] target, const char[] text)
{
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "*")) != -1)
    {
        if (!HasTargetname(ent, target))
            continue;

        DispatchKeyValue(ent, "message", text);

        char output[512];
        Format(output, sizeof(output), "message %s", text);
        SetVariantString(output);
        AcceptEntityInput(ent, "AddOutput");
    }
}

void SetMessage(const char[] target, int value)
{
    char output[64];
    Format(output, sizeof(output), "message %d", value);
    FireByName(target, "AddOutput", output);
}

void PrintCenterTeam(int team, const char[] format, any ...)
{
    char text[256];
    VFormat(text, sizeof(text), format, 3);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client) && GetClientTeam(client) == team)
        {
            PrintCenterText(client, "%s", text);
        }
    }
}

bool IsValidClient(int client)
{
    return (client >= 1 && client <= MaxClients && IsClientInGame(client));
}

bool IsAttackerBot(int client)
{
    return IsValidClient(client) && IsPlayerAlive(client) && IsFakeClient(client) && HasTargetname(client, "rusher");
}

void SetBotBreakthroughGoal(int client, const float origin[3], float radius)
{
    if (g_hBotSetBreakthroughGoal == null || !IsAttackerBot(client))
        return;

    SDKCall(g_hBotSetBreakthroughGoal, client, origin[0], origin[1], origin[2], radius);
}

void ClearBotBreakthroughGoal(int client)
{
    if (g_hBotClearBreakthroughGoal == null || !IsValidClient(client) || !IsFakeClient(client))
        return;

    SDKCall(g_hBotClearBreakthroughGoal, client);
}

void ClearAllBotBreakthroughGoals()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        ClearBotBreakthroughGoal(client);
    }
}

void SetFreezeTime(float seconds)
{
    if (g_cvFreezeTime == null)
        g_cvFreezeTime = FindConVar("mp_freezetime");

    if (g_cvFreezeTime != null)
        g_cvFreezeTime.SetFloat(seconds);
    else
        ServerCommand("mp_freezetime %.0f", seconds);
}

void AddClientKills(int client, int kills)
{
    if (!IsValidClient(client))
        return;

    SetEntProp(client, Prop_Data, "m_iFrags", GetClientFrags(client) + kills);
}

void GetEntityName(int ent, char[] buffer, int size)
{
    buffer[0] = '\0';
    if (ent > 0 && IsValidEntity(ent))
        GetEntPropString(ent, Prop_Data, "m_iName", buffer, size);
}

bool HasTargetname(int ent, const char[] targetname)
{
    char name[64];
    GetEntityName(ent, name, sizeof(name));
    return StrEqual(name, targetname, false);
}

void SetTargetname(int ent, const char[] targetname)
{
    if (ent > 0 && IsValidEntity(ent))
        DispatchKeyValue(ent, "targetname", targetname);
}

int FindEntityByTargetname(const char[] targetname)
{
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "*")) != -1)
    {
        if (HasTargetname(ent, targetname))
            return ent;
    }

    return -1;
}

void GetEntityOrigin(int ent, float origin[3])
{
    if (ent >= 1 && ent <= MaxClients)
    {
        GetClientAbsOrigin(ent, origin);
        return;
    }

    GetEntPropVector(ent, Prop_Send, "m_vecOrigin", origin);
}

void GetEntityAnglesSafe(int ent, float angles[3])
{
    angles[0] = 0.0;
    angles[1] = 0.0;
    angles[2] = 0.0;

    if (ent > 0 && IsValidEntity(ent) && FindDataMapInfo(ent, "m_angRotation") != -1)
        GetEntPropVector(ent, Prop_Data, "m_angRotation", angles);
}

void CopyVector(float source[3], float dest[3])
{
    dest[0] = source[0];
    dest[1] = source[1];
    dest[2] = source[2];
}

bool IsZeroVector(float vec[3])
{
    return (vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0);
}

bool TryGetDataString(int ent, const char[] prop, char[] buffer, int size)
{
    buffer[0] = '\0';
    if (ent <= 0 || !IsValidEntity(ent) || FindDataMapInfo(ent, prop) == -1)
        return false;

    GetEntPropString(ent, Prop_Data, prop, buffer, size);
    return buffer[0] != '\0';
}

int GetEntityHammerId(int ent)
{
    if (ent <= 0 || !IsValidEntity(ent) || FindDataMapInfo(ent, "m_iHammerID") == -1)
        return 0;

    return GetEntProp(ent, Prop_Data, "m_iHammerID");
}

void DoUnloadSelf()
{
    Handle me = GetMyHandle();
    char file[PLATFORM_MAX_PATH];
    if (GetPluginFilename(me, file, sizeof(file)) && file[0])
    {
        ServerCommand("sm plugins unload \"%s\"", file);
    }
}
