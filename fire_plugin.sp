#include <sourcemod>
#include <sdktools>
#include <cstrike>

ConVar g_lightStyle;
ConVar g_cvarMySlapDamage = null;

public Plugin myinfo =
{
	name = "Fire First Plugin",
	author = "lein",
	description = "Fire first plugin ever",
	version = "1.0.0.0",
	url = "https://github.com/StLein"
}

public void OnPluginStart()
{
	RegConsoleCmd( "sm_whoami", CmdWho, "debug client");

	RegConsoleCmd( "sm_test", CmdTest, "test");
	RegConsoleCmd( "sm_get_mvps",    get_mvps    );
	RegConsoleCmd( "sm_get_score",   get_score   );
	RegConsoleCmd( "sm_get_clantag", get_clantag );
	RegConsoleCmd( "sm_get_teamscore", get_teamscore );
	
	RegAdminCmd("sm_myslap", Command_MySlap, ADMFLAG_SLAY);
	LoadTranslations("common.phrases.txt");

	g_cvarMySlapDamage = CreateConVar("sm_myslap_damage", "5", "Default slap damage");
	//AutoExecConfig(true, "plugin_myslap");

	g_lightStyle = CreateConVar("fire_lightStyle", "", "地图亮度设置: a最黑,b普通,n最亮");
	HookConVarChange(g_lightStyle, OnChangeLight);
}

public void OnMapStart()
{
	char lightStyle[8];
	GetConVarString(g_lightStyle, lightStyle, sizeof(lightStyle));
	if(lightStyle[0])
		SetLightStyle(0, lightStyle);
}

public void OnMapEnd()
{
	SetConVarString(g_lightStyle, "");
}


public OnChangeLight(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (StrEqual(oldValue, newValue))
		return;

	// PrintToServer("[OnChangeLight]oldValue=%s newValue=%s", oldValue, newValue);
	if (newValue[0])
		SetLightStyle(0, newValue);
}

public void OnClientPostAdminCheck(int client)    { PrintToServer("PostAdminCheck %N flags=%x", client, GetUserFlagBits(client)); }
public void OnClientAuthorized(int client, const char[] auth)	{  PrintToServer("Authorized %N auth=%s", client, auth); }

public Action CmdWho(int client, int args)
{
	char s2[64], s3[64], s64[32], ip[64];
	GetClientAuthId(client, AuthId_Steam2, s2, sizeof s2, true);
	GetClientAuthId(client, AuthId_Steam3, s3, sizeof s3, true);
	GetClientAuthId(client, AuthId_SteamID64, s64, sizeof s64, true);
	GetClientIP(client, ip, sizeof ip, true);
	PrintToServer("[DBG] c=%d Steam2=%s Steam3=%s Steam64=%s IP=%s", client, s2, s3, s64, ip);
	ReplyToCommand(client, "[DBG] Steam2=%s | Steam3=%s | IP=%s", s2, s3, ip);
	return Plugin_Handled;
}

public Action CmdTest(int client, int args)
{
	PrintToServer("[SM] client %d MaxClients %d",client, MaxClients);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i)){
			char user_id[12];
			char name[MAX_NAME_LENGTH];
			GetClientName(i, name, sizeof(name));
			IntToString(GetClientUserId(i), user_id, sizeof(user_id));
			PrintToServer("[SM] %s.[%s] IsPlayerInGame %d", user_id, name, IsClientInGame(i));
			
			PrintToServer("[SM] IsFakeClient %d IsPlayerAlive %d health %d", IsFakeClient(i), IsPlayerAlive(i), GetClientHealth(i));
			PrintToServer("[SM] IsClientConnected %d IsClientInKickQueue %d ", IsClientInGame(i), IsClientInKickQueue(i));
		}
	}

	CS_TerminateRound(1.0,CSRoundEnd_CTWin);
	ReplyToCommand(client, "[CS_TerminateRound] client=%d", client);
	return Plugin_Handled;
}

public Action:get_mvps( client, argc )
{
	ReplyToCommand( client, "Your MVP count is %d", CS_GetMVPCount( client ) );
	
	return Plugin_Handled;
}
public Action:get_score( client, argc )
{
	if( GetEngineVersion() != Engine_CSGO )
	{
		ReplyToCommand( client, "This command is only intended for CS:GO" );
		return Plugin_Handled;
	}
	
	ReplyToCommand( client, "Your contribution score is %d", CS_GetClientContributionScore( client ) );

	return Plugin_Handled;
}
public Action:get_clantag( client, argc )
{
	decl String:tag[64];

	CS_GetClientClanTag( client, tag, sizeof(tag) );
	ReplyToCommand( client, "Your clan tag is: %s", tag );

	return Plugin_Handled;
}
public Action:get_teamscore( client, argc )
{
	new tscore = CS_GetTeamScore( CS_TEAM_T );
	new ctscore = CS_GetTeamScore( CS_TEAM_CT );

	ReplyToCommand( client, "Team Scores: T = %d, CT = %d", tscore, ctscore );

	return Plugin_Handled;
}

public Action Command_MySlap(int client, int args)
{
	char arg1[32], arg2[32];
	int damage = g_cvarMySlapDamage.IntValue;

	/* Get the first argument */
	GetCmdArg(1, arg1, sizeof(arg1));

	/* If there are 2 or more arguments, and the second argument fetch 
	* is successful, convert it to an integer.
	*/
	if (args >= 2 && GetCmdArg(2, arg2, sizeof(arg2)))
	{
		damage = StringToInt(arg2);
	}

	/**
	 * target_name - stores the noun identifying the target(s)
	 * target_list - array to store clients
	 * target_count - variable to store number of clients
	 * tn_is_ml - stores whether the noun must be translated
	 */
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;

	if ((target_count = ProcessTargetString(
			arg1,
			client,
			target_list,
			MAXPLAYERS,
			COMMAND_FILTER_ALIVE, /* Only allow alive players */
			target_name,
			sizeof(target_name),
			tn_is_ml)) <= 0)
	{
		/* This function replies to the admin with a failure message */
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	for (int i = 0; i < target_count; i++)
	{
		SlapPlayer(target_list[i], damage);
		LogAction(client, target_list[i], "\"%L\" slapped \"%L\" (damage %d)", client, target_list[i], damage);
	}

	if (tn_is_ml)
	{
		ShowActivity2(client, "[SM] ", "Slapped %t for %d damage!", target_name, damage);
	}
	else
	{
		ShowActivity2(client, "[SM] ", "Slapped %s for %d damage!", target_name, damage);
	}

	return Plugin_Handled;
}