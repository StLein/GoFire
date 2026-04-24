#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>


public Plugin myinfo = {
    name        = "nano_buffmodify",
    author      = "lein",
    version     = "1.0.0",
    description = "nano buff modify",
    url         = "https://github.com/StLein"
};

public void OnPluginStart()
{
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    CreateTimer(1.0, Timer_ChangeBuffer);
    return Plugin_Continue;
}

public Action Timer_ChangeBuffer(Handle timer, any data)
{
	GameRules_SetProp("m_iAttribute1", 1); // 致命一击
	GameRules_SetProp("m_iAttribute2", 8); // 额外提供红色补给箱
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
