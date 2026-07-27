#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.0.0"
#define SKY_CONFIG_PATH "configs/custom_map_sky.cfg"

ConVar g_SkyName;
char g_OriginalSky[PLATFORM_MAX_PATH];
bool g_HasChangedSky;

public Plugin myinfo =
{
	name = "Custom Map Sky",
	author = "ChatGPT",
	description = "Loads sv_skyname overrides from a per-map config",
	version = PLUGIN_VERSION,
	url = "https://tieba.baidu.com/f?kw=gofire"
};

public void OnPluginStart()
{
	g_SkyName = FindConVar("sv_skyname");
	if (g_SkyName == null)
	{
		SetFailState("ConVar sv_skyname was not found.");
	}

	RegAdminCmd("sm_reload_mapsky", Command_ReloadMapSky, ADMFLAG_CONFIG,
		"Reloads configs/custom_map_sky.cfg for the current map.");

	if (IsServerProcessing())
	{
		ApplyMapSky();
	}
}

public void OnMapStart()
{
	ApplyMapSky();
}

public void OnMapEnd()
{
	RestoreOriginalSky();
}

public void OnPluginEnd()
{
	RestoreOriginalSky();
}

public Action Command_ReloadMapSky(int client, int args)
{
	RestoreOriginalSky();
	bool changed = ApplyMapSky();

	if (changed)
	{
		char currentSky[PLATFORM_MAX_PATH];
		g_SkyName.GetString(currentSky, sizeof(currentSky));
		ReplyToCommand(client, "[MapSky] 配置已重新加载，sv_skyname = %s", currentSky);
	}
	else
	{
		char currentSky[PLATFORM_MAX_PATH];
		g_SkyName.GetString(currentSky, sizeof(currentSky));
		ReplyToCommand(client, "[MapSky] 配置已重新加载，本地图没有天空覆盖（当前值：%s）。", currentSky);
	}

	return Plugin_Handled;
}

bool ApplyMapSky()
{
	char configPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, configPath, sizeof(configPath), SKY_CONFIG_PATH);

	KeyValues config = new KeyValues("CustomMapSky");
	if (!config.ImportFromFile(configPath))
	{
		LogError("无法读取天空配置：%s", configPath);
		delete config;
		return false;
	}

	char mapName[PLATFORM_MAX_PATH];
	GetCurrentMap(mapName, sizeof(mapName));

	char skyName[PLATFORM_MAX_PATH];
	config.GetString(mapName, skyName, sizeof(skyName));
	if (skyName[0] == '\0')
	{
		config.GetString("default", skyName, sizeof(skyName));
	}
	delete config;

	TrimString(skyName);
	if (skyName[0] == '\0')
	{
		return false;
	}

	if (!g_HasChangedSky)
	{
		g_SkyName.GetString(g_OriginalSky, sizeof(g_OriginalSky));
	}

	g_SkyName.SetString(skyName, true, true);
	g_HasChangedSky = true;
	LogMessage("地图 %s 使用自定义天空：%s", mapName, skyName);
	return true;
}

void RestoreOriginalSky()
{
	if (!g_HasChangedSky || g_SkyName == null)
	{
		return;
	}

	g_SkyName.SetString(g_OriginalSky, true, true);
	g_HasChangedSky = false;
}
