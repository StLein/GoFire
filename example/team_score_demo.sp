#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

public Plugin myinfo =
{
	name        = "team_score_demo",
	author      = "lein, Codex",
	description = "Demo plugin for CCSGameRules::UpdateTeamScore",
	version     = "1.0.0",
	url         = ""
};

Handle g_hGameConf = null;
Handle g_hUpdateTeamScore = null;

bool UpdateTeamScore(int team, int round, int score)
{
	return SDKCall(g_hUpdateTeamScore, team, round, score);
}

public void OnPluginStart()
{
	g_hGameConf = LoadGameConfigFile("game.fire");
	if (g_hGameConf == null)
		SetFailState("Failed to load gameconfig: game.fire");

	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "UpdateTeamScore");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_ByValue);
	g_hUpdateTeamScore = EndPrepSDKCall();
	if (g_hUpdateTeamScore == null)
		SetFailState("Failed to create SDKCall for CCSGameRules::UpdateTeamScore!");

	RegAdminCmd("sm_teamscore", Command_TeamScore, ADMFLAG_GENERIC, "sm_teamscore <t|ct|2|3> <round> <score>");
	RegAdminCmd("sm_teamscore_add", Command_TeamScoreAdd, ADMFLAG_GENERIC, "sm_teamscore_add <t|ct|2|3> <delta>");
}

public Action Command_TeamScore(int client, int args)
{
	if (args < 3)
	{
		ReplyToCommand(client, "Usage: sm_teamscore <t|ct|2|3> <round> <score>");
		return Plugin_Handled;
	}

	char teamArg[16];
	GetCmdArg(1, teamArg, sizeof(teamArg));

	int team = ParseTeamArg(teamArg);
	if (team == -1)
	{
		ReplyToCommand(client, "Invalid team: use t, ct, 2, or 3.");
		return Plugin_Handled;
	}

	char arg[16];
	GetCmdArg(2, arg, sizeof(arg));
	int round = StringToInt(arg);

	GetCmdArg(3, arg, sizeof(arg));
	int score = StringToInt(arg);

	bool updated = UpdateTeamScore(team, round, score);
	ReplyToCommand(client, "UpdateTeamScore(team=%d, round=%d, score=%d) => %s", team, round, score, updated ? "true" : "false");
	return Plugin_Handled;
}

public Action Command_TeamScoreAdd(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "Usage: sm_teamscore_add <t|ct|2|3> <delta>");
		return Plugin_Handled;
	}

	char teamArg[16];
	GetCmdArg(1, teamArg, sizeof(teamArg));

	int team = ParseTeamArg(teamArg);
	if (team == -1)
	{
		ReplyToCommand(client, "Invalid team: use t, ct, 2, or 3.");
		return Plugin_Handled;
	}

	char arg[16];
	GetCmdArg(2, arg, sizeof(arg));
	int delta = StringToInt(arg);
	int score = CS_GetTeamScore(team) + delta;

	bool updated = UpdateTeamScore(team, 0, score);
	ReplyToCommand(client, "UpdateTeamScore(team=%d, round=0, score=%d) => %s", team, score, updated ? "true" : "false");
	return Plugin_Handled;
}

int ParseTeamArg(const char[] teamArg)
{
	if (StrEqual(teamArg, "t", false) || StrEqual(teamArg, "terrorist", false) || StrEqual(teamArg, "2"))
		return CS_TEAM_T;

	if (StrEqual(teamArg, "ct", false) || StrEqual(teamArg, "counter", false) || StrEqual(teamArg, "3"))
		return CS_TEAM_CT;

	return -1;
}

public void OnMapEnd()
{
	Handle me = GetMyHandle();
	char file[PLATFORM_MAX_PATH];
	if (GetPluginFilename(me, file, sizeof(file)) && file[0])
		ServerCommand("sm plugins unload \"%s\"", file);
}
