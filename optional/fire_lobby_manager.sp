#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

ConVar g_MinPlayers;
ConVar g_BotFills;
ConVar g_MinBots;
ConVar g_MaxPlayers;

Handle g_UpdateTimer = null;
bool g_GameStarting;
int g_LastHumanCount;

public Plugin myinfo =
{
	name = "GoFire Lobby Manager",
	author = "lein",
	description = "简单服务器管理插件: 入服欢迎语和BOT填充设置, 聊天日志记录",
	version = "1.0.0",
	url = "https://pd.qq.com/g/pd65983752"
};

public void OnPluginStart()
{
	// Bot 配额设置
	g_MinBots = CreateConVar("fire_min_bots", "0", "填充的最小 Bot 数量");
	g_MaxPlayers = CreateConVar("fire_max_players", "0", "服务器玩家数超过该数量后会自动踢出 Bot，0 表示不限制");
	g_MinPlayers = FindConVar("fire_min_players"); // 游戏的最小开局人数，一般模式是2人，多人生化模式最少3人
	g_BotFills = FindConVar("fire_bot_fills");	// 填充的 Bot 数量，默认值是24，按需修改，推荐12以上吧

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	g_LastHumanCount = CountHumans();
}

public void OnMapStart()
{
	g_UpdateTimer = null;
	g_GameStarting = false;
	g_LastHumanCount = CountHumans();
}

public void OnMapEnd()
{
	g_GameStarting = false;
	CancelUpdateTimer();
}

public void OnClientPutInServer(int client)
{
	char auth[64];
	GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth), true);
	PrintToServer("OnClientPutInServer %N auth=%s", client, auth);

	if (!IsDedicatedServer())
	{
		return;
	}

	// 记录进服日志
	if (!IsFakeClient(client))
	{
		char steamId[32];
		char ip[64];
		GetClientIP(client, ip, sizeof(ip), true);
		GetClientAuthId(client, AuthId_SteamID64, steamId, sizeof(steamId), true);
		LogAction(client, -1, "\"%L\" (%s) PutInServer : %s.", client, steamId, ip);

		CreateTimer(1.0, Timer_Welcome, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}

	ScheduleLobbyUpdate();
}

public void OnClientDisconnect(int client)
{
	if (IsDedicatedServer())
	{
		ScheduleLobbyUpdate();
	}
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] args)
{
	if (client <= 0 || !IsClientInGame(client))
	{
		return;
	}

	// 记录聊天日志
	LogMessage("%s %N: %s", StrEqual(command, "say_team") ? "[TEAM]" : "[All]", client, args);
}

public Action Timer_Welcome(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
	{
		return Plugin_Stop;
	}

	int minHumans = GetMinHumanCount();
	if (minHumans > 0 && CountHumans() < minHumans)
	{
		PrintToChat(client, "\x04[GoFire]\x01 欢迎进入群服，玩家人数达到\x03%d\x01人时，游戏自动开始。", minHumans);
	}

	return Plugin_Stop;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (IsDedicatedServer())
	{
		CreateTimer(0.5, Timer_EnsureBots, 0, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_UpdateLobbyState(Handle timer, any data)
{
	g_UpdateTimer = null;

	int minHumans = GetMinHumanCount();
	int humans = CountHumans();
	if (humans < minHumans)
	{
		if (g_LastHumanCount >= minHumans)
		{
			PrintToChatAll("\x04[GoFire]\x01 对局人数不足，请等待玩家加入。 (当前\x03%d\x01/\x03%d\x01)", humans, minHumans);
		}

		g_GameStarting = false;
		EnsureBotFill();
		g_LastHumanCount = humans;
		return Plugin_Stop;
	}

	if (!g_GameStarting && g_LastHumanCount < minHumans)
	{
		const int delay = 3;
		PrintToChatAll("\x04[GoFire]\x01 玩家人数已达\x03%d\x01，游戏将在\x03%d\x01 秒后自动开始。", humans, delay);
		g_GameStarting = true;
		ServerCommand("mp_restartgame %d", delay);
		LogMessage("GameStarting with human %d", humans);
	}

	EnsureBotFill();
	g_LastHumanCount = humans;
	return Plugin_Stop;
}

public Action Timer_EnsureBots(Handle timer, any data)
{
	EnsureBotFill();
	if (CountHumans() < GetMinHumanCount())
	{
		g_GameStarting = false;
	}
	return Plugin_Stop;
}

void ScheduleLobbyUpdate()
{
	CancelUpdateTimer();
	g_UpdateTimer = CreateTimer(0.2, Timer_UpdateLobbyState, 0, TIMER_FLAG_NO_MAPCHANGE);
}

void CancelUpdateTimer()
{
	if (g_UpdateTimer != null)
	{
		delete g_UpdateTimer;
		g_UpdateTimer = null;
	}
}

void EnsureBotFill()
{
	int minHumans = GetMinHumanCount();
	int fillSlots = g_BotFills != null ? g_BotFills.IntValue : 0;
	int minBots = g_MinBots.IntValue;
	int maxPlayers = g_MaxPlayers.IntValue;

	if (fillSlots < 0)
	{
		fillSlots = 0;
	}
	if (minBots < 0)
	{
		minBots = 0;
	}
	if (maxPlayers < 0)
	{
		maxPlayers = 0;
	}

	int humans = CountHumans();
	int bots = CountBots();
	if (humans < minHumans)
	{
		g_GameStarting = false;
		if (bots > 0)
		{
			ServerCommand("bot_quota 0");
		}
		return;
	}

	int targetBots = fillSlots;
	if (maxPlayers > 0 && humans + targetBots > maxPlayers)
	{
		targetBots = maxPlayers - humans;
	}
	if (targetBots < 0)
	{
		targetBots = 0;
	}
	if (targetBots < minBots)
	{
		targetBots = minBots;
	}

	if (bots != targetBots)
	{
		ServerCommand("bot_quota %d", targetBots);
	}
}

int GetMinHumanCount()
{
	return g_MinPlayers != null ? g_MinPlayers.IntValue : 0;
}

int CountHumans()
{
	int humans;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && !IsFakeClient(client))
		{
			humans++;
		}
	}
	return humans;
}

int CountBots()
{
	int bots;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && IsFakeClient(client))
		{
			bots++;
		}
	}
	return bots;
}
