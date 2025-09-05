#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
    name = "Tiaoyue Jump",
	author = "lein",
    description = "Converted from VScript, Implements tiaoyue.nut Jump()",
	version = "1.0.0.0",
	url = "https://github.com/StLein"
};

ConVar g_CvarJumpZ;

public void OnPluginStart()
{
    g_CvarJumpZ = CreateConVar("sm_tiaoyue_velocity", "650.0", "tiaoyue Jump Z velocity");
    HookEntityOutput("trigger_multiple", "OnStartTouch", OnTrigStartTouch);
}

public void OnClientPutInServer(int client)
{
    // 关闭坠落伤害
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePos[3])
{
    if (damagetype & DMG_FALL)
    {
        damage = 0.0;
        return Plugin_Changed;
    }
    return Plugin_Continue;
}

public void OnTrigStartTouch(const char[] output, int caller, int activator, float delay)
{
    if (!(1 <= activator <= MaxClients) || !IsClientInGame(activator))
        return;

    char m_value[64];
    GetEntPropString(caller, Prop_Data, "m_iszTouchValue", m_value, sizeof(m_value));
    // PrintToServer("[Tiaoyue] %s %s", output, m_value);
    if (StrContains(m_value, "Jump()", false) != -1)
        DoJump(activator);
}

void DoJump(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;

    float vel[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
    vel[2] = GetConVarFloat(g_CvarJumpZ); // 垂直速度
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
    
    // PrintToChat(client, "[Tiaoyue] You jumped!");
}

public void OnMapEnd()
{
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
