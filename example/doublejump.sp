#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

public Plugin myinfo =
{
	name        = "doublejump",
	author      = "chatgpt",
	version     = "1.0.0",
	description = "Simple double jump plugin",
	url         = "https://tieba.baidu.com/f?kw=gofire"
};

ConVar g_cvEnable;
ConVar g_cvTeam;
ConVar g_cvExtraJumps;
ConVar g_cvJumpVelocity;
ConVar g_cvCooldown;
ConVar g_cvNoFallDamage;
ConVar g_cvAnnounce;

int g_iJumpsUsed[MAXPLAYERS + 1];
int g_iLastButtons[MAXPLAYERS + 1];
float g_fNextJumpTime[MAXPLAYERS + 1];
bool g_bAnnounced[MAXPLAYERS + 1];

public void OnPluginStart()
{
	g_cvEnable       = CreateConVar("sm_doublejump_enable", "1", "Enable nano double jump.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTeam         = CreateConVar("sm_doublejump_team", "0", "Allowed team: 0=all, 2=T, 3=CT.", FCVAR_NOTIFY, true, 0.0, true, 3.0);
	// sm_doublejump_extra 表示额外空中跳跃次数：1 = 二段跳，2 = 三段跳，以此类推。
	g_cvExtraJumps   = CreateConVar("sm_doublejump_extra", "1", "Extra air jumps per airtime.", FCVAR_NOTIFY, true, 1.0, true, 5.0);
	g_cvJumpVelocity = CreateConVar("sm_doublejump_velocity", "300.0", "Vertical velocity for the air jump.", FCVAR_NOTIFY, true, 100.0, true, 1000.0);
	g_cvCooldown     = CreateConVar("sm_doublejump_cooldown", "0.12", "Minimum seconds between air jumps.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvNoFallDamage = CreateConVar("sm_doublejump_nofalldamage", "0", "Block fall damage while this plugin is loaded.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAnnounce     = CreateConVar("sm_doublejump_announce", "1", "Print a short hint once per spawn.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	// 插件热加载时，已经在服务器内的玩家也要补上 hook 和初始状态。
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientPutInServer(client);
		}
	}
}

public void OnClientPutInServer(int client)
{
	ResetClient(client);

	// 只在 sm_doublejump_nofalldamage 开启时真正拦截摔落伤害。
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
	ResetClient(client);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			ResetClient(client);
		}
	}

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	ResetClient(client);

	// 延迟 1 秒提示，避免玩家出生瞬间聊天信息太多导致看不到。
	if (g_cvAnnounce.BoolValue && IsAllowedClient(client))
	{
		CreateTimer(1.0, Timer_Announce, GetClientUserId(client));
	}

	return Plugin_Continue;
}

public Action Timer_Announce(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!IsValidClient(client) || !IsPlayerAlive(client) || g_bAnnounced[client] || !IsAllowedClient(client))
	{
		return Plugin_Stop;
	}

	// 每次出生只提示一次，避免刷屏
	g_bAnnounced[client] = true;
	PrintToChat(client, "[Nano] Double jump is ready. Press jump again in the air.");
	return Plugin_Stop;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePos[3])
{
	// 默认不免疫摔伤；如果地图需要高空连跳，再打开这个 cvar。
	if (!g_cvEnable.BoolValue || !g_cvNoFallDamage.BoolValue)
	{
		return Plugin_Continue;
	}

	if ((damagetype & DMG_FALL) == 0)
	{
		return Plugin_Continue;
	}

	if (!IsAllowedClient(victim))
	{
		return Plugin_Continue;
	}

	damage = 0.0;
	return Plugin_Changed;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnable.BoolValue || !IsValidClient(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	// 记录上一帧按键，用来判断“刚刚按下跳跃”，避免按住空格连续触发。
	int lastButtons = g_iLastButtons[client];
	g_iLastButtons[client] = buttons;

	// 不符合队伍限制，或处于梯子/水中/noclip 时，不保留空中跳跃次数。
	if (!IsAllowedClient(client) || IsInNoJumpState(client))
	{
		g_iJumpsUsed[client] = 0;
		return Plugin_Continue;
	}

	bool onGround = ((GetEntityFlags(client) & FL_ONGROUND) != 0);
	if (onGround)
	{
		// 落地后恢复额外跳跃次数。
		g_iJumpsUsed[client] = 0;
		return Plugin_Continue;
	}

	// 只响应“按下跳跃的瞬间”，按住空格不会一直触发。
	bool jumpPressed = ((buttons & IN_JUMP) != 0 && (lastButtons & IN_JUMP) == 0);
	if (!jumpPressed)
	{
		return Plugin_Continue;
	}

	if (g_iJumpsUsed[client] >= g_cvExtraJumps.IntValue)
	{
		return Plugin_Continue;
	}

	// 检查下一次允许触发二段跳的游戏时间，给一个很短的冷却防止按键抖动。
	float now = GetGameTime();
	if (now < g_fNextJumpTime[client])
	{
		return Plugin_Continue;
	}

	DoAirJump(client);
	g_iJumpsUsed[client]++;
	g_fNextJumpTime[client] = now + g_cvCooldown.FloatValue;

	return Plugin_Continue;
}

void DoAirJump(int client)
{
	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);

	// 保留玩家当前水平速度，只替换向上的 Z 速度，手感更像正常二段跳。
	velocity[2] = g_cvJumpVelocity.FloatValue;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
}

bool IsAllowedClient(int client)
{
	if (!IsValidClient(client))
	{
		return false;
	}

	int allowedTeam = g_cvTeam.IntValue;
	if (allowedTeam == 0)
	{
		return true;
	}

	return (GetClientTeam(client) == allowedTeam);
}

bool IsInNoJumpState(int client)
{
	MoveType moveType = GetEntityMoveType(client);
	if (moveType == MOVETYPE_LADDER || moveType == MOVETYPE_NOCLIP)
	{
		return true;
	}

	if (GetEntProp(client, Prop_Data, "m_nWaterLevel") >= 2)
	{
		// WaterLevel>=2 说明玩家基本在水里，交给游戏自己的游泳逻辑。
		return true;
	}

	return false;
}

bool IsValidClient(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

void ResetClient(int client)
{
	g_iJumpsUsed[client] = 0;
	g_iLastButtons[client] = 0;
	g_fNextJumpTime[client] = 0.0;
	g_bAnnounced[client] = false;
}

public void OnMapEnd()
{
	// 插件自卸载
	DoUnloadSelf();
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
