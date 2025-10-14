#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <zombiereloaded>
#include <cstrike_fire>
#include <multicolors>

new bool:started;

public Plugin:myinfo =
{
	name = "SM ZR Force Teams",
	author = "Franc1sco franug",
	description = "",
	version = "1.1",
	url = "http://steamcommunity.com/id/franug"
};

Handle hGameConf;
Handle hConvertTeam;
bool CS_ConvertTeam(int client, int team)
{
	return SDKCall(hConvertTeam, client, team);
}

public OnPluginStart() 
{
	hGameConf = LoadGameConfigFile("game.fire");
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "ConvertTeam");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	if ((hConvertTeam = EndPrepSDKCall()) == null) 
		SetFailState("Failed to create SDKCall for CCSPlayer::ConvertTeam!");

	HookEvent("player_spawn", OnSpawn);
	HookEvent("round_start", EventRoundStart, EventHookMode_Pre);
}

public void OnMapEnd()
{
	// 插件自卸载
	DoUnloadSelf();  
}

public void DoUnloadSelf()
{
	Handle me = GetMyHandle();
	char file[PLATFORM_MAX_PATH];
	if (GetPluginFilename(me, file, sizeof(file)) && file[0])
	{
		ServerCommand("sm plugins unload \"%s\"", file);
		return;
	}
}

stock bool IsValidClient(client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

public Action:OnSpawn(Handle:event, const String:name[], bool:dontBroadcast) 
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!IsValidClient(client))
		return Plugin_Continue;
	
	int team = GetClientTeam(client);
	if (team != CS_TEAM_T && team != CS_TEAM_CT)
		return Plugin_Continue;

	// CPrintToChatAll("{red}[zombiereloaded]{green}client %d team:%d",client,GetClientTeam(client));
	if(started) return Plugin_Continue;
	CreateTimer(0.1, SpawnExcuted, client);
	return Plugin_Continue;
}

public Action SpawnExcuted(Handle timer, any client)
{
	if(!IsValidClient(client))
		return Plugin_Stop;

	if(IsClientConnected(client) && IsClientInGame(client))
	{
		if(GetClientTeam(client) == CS_TEAM_T) CS_ConvertTeam(client, CS_TEAM_CT);
	}
	return Plugin_Stop;
}


public Action:EventRoundStart(Handle:event, const String:name[], bool:dontBroadcast) 
{
	started = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientInGame(i))
		{
			if(GetClientTeam(i) == CS_TEAM_T) 
				CS_ConvertTeam(i, CS_TEAM_CT);
		}
	}

	ServerCommand("mp_tkpunish 0");
	ServerCommand("mp_autoteambalance 0");
	// CPrintToChatAll("{red}[zombiereloaded]{green}EventRoundStart");
}

public Action:ZR_OnClientInfect(&client, &attacker, &bool:motherInfect, &bool:respawnOverride, &bool:respawn)
{
	if(!started) started = true;
}