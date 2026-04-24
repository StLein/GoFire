#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

public Plugin myinfo = {
    name        = "dm_random",
    author      = "lein",
    version     = "1.0.0",
    description = "dm random transform plugin",
    url         = "https://github.com/StLein"
};

Handle g_hGameConf = null;
Handle g_hOnPlayerSelect = null;
Handle g_hConvertTeam = null;
int g_iFireMenu;

stock bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

stock void RandomSwitchTeamOnDeath(int client)
{
    if (!IsValidClient(client))
        return;

    int currentTeam = GetClientTeam(client);
    if (currentTeam != CS_TEAM_T && currentTeam != CS_TEAM_CT)
        return;

    int randomTeam = GetRandomInt(0, 1) ? CS_TEAM_T : CS_TEAM_CT;
    if (randomTeam == currentTeam)
        randomTeam = (currentTeam == CS_TEAM_T) ? CS_TEAM_CT : CS_TEAM_T;

    SDKCall(g_hConvertTeam, client, randomTeam);
}

stock void CallOnPlayerSelectRandom(int client)
{
    if (!IsValidClient(client))
        return;
    if (g_hOnPlayerSelect == null)
        return;

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return;

    int select = GetRandomInt(1, 6);
    SDKCall(g_hOnPlayerSelect, client, select);
}

stock void SetClientiFireMenu(int client, int iFireMenu)
{
    SetEntData(client, g_iFireMenu, iFireMenu, 4);
}

public void OnPluginStart()
{
    // 从 game.fire.txt 加载签名和偏移
    g_hGameConf = LoadGameConfigFile("game.fire");
    if (g_hGameConf == null)
        SetFailState("Failed to load gameconfig: game.fire");

    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "ConvertTeam");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    g_hConvertTeam = EndPrepSDKCall();
    if (g_hConvertTeam == null)
        SetFailState("Failed to create SDKCall for CCSPlayer::ConvertTeam!");

    StartPrepSDKCall(SDKCall_GameRules);
    PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "OnPlayerSelect");
    PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    g_hOnPlayerSelect = EndPrepSDKCall();
    if (g_hOnPlayerSelect == null)
        SetFailState("Failed to create SDKCall for CCSGameRules::OnPlayerSelect!");

    g_iFireMenu = GameConfGetOffset(g_hGameConf,"iFireMenu");
    if (g_iFireMenu == -1)
        SetFailState("Failed to get Offset for CCSPlayer::iFireMenu!");

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    // 死后随机切换队伍
    int client = GetClientOfUserId(event.GetInt("userid"));
    RandomSwitchTeamOnDeath(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
        return;

    // 每次复活随机成为大终结或者猎手
    CreateTimer(0.1, Timer_CallOnPlayerSelect, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

#define MenuSelectSuperNano 2
#define MenuSelectSuperHero 3
public Action Timer_CallOnPlayerSelect(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);
    if (!IsValidClient(client)) return Plugin_Stop;
    if (GetClientTeam(client) == CS_TEAM_T ) SetClientiFireMenu(client,MenuSelectSuperNano);
    else  SetClientiFireMenu(client,MenuSelectSuperHero);
    CallOnPlayerSelectRandom(client);
    return Plugin_Stop;
}

public void OnMapEnd()
{
	// 插件自卸载
    Handle me = GetMyHandle();
    char file[PLATFORM_MAX_PATH];
    if (GetPluginFilename(me, file, sizeof(file)) && file[0])
    {
        ServerCommand("sm plugins unload \"%s\"", file);
        return;
    }
}
