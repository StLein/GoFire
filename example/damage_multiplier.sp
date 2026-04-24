#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name        = "Damage Multiplier",
    author      = "Deepseek",
    description = "Multiplies all damage dealt to players",
    version     = "1.0",
    url         = ""
};

// 伤害倍率配置
ConVar g_cvDamageMultiplier;

// 是否启用插件
ConVar g_cvEnabled;

// 是否在日志中记录伤害修改
ConVar g_cvLogDamage;

public void OnPluginStart()
{
    // 创建配置变量
    g_cvDamageMultiplier = CreateConVar("sm_damage_multiplier", "2.0", "伤害倍率 (默认: 2.0)", 0, true, 0.1, true, 100.0);
    g_cvEnabled = CreateConVar("sm_damage_enabled", "1", "启用/禁用伤害翻倍插件 (1 = 启用, 0 = 禁用)");
    g_cvLogDamage = CreateConVar("sm_damage_log", "0", "是否在日志中记录伤害修改 (1 = 启用, 0 = 禁用)");
    
    // 自动执行配置文件的变量
    AutoExecConfig(true, "damage_multiplier");
    
    // 为所有现有客户端钩子伤害事件
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
}

public void OnClientPutInServer(int client)
{
    // 为每个加入服务器的玩家钩子伤害事件
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
    // 检查插件是否启用
    if (!g_cvEnabled.BoolValue)
        return Plugin_Continue;
    
    // 检查受害者是否为有效玩家
    if (!IsValidEntity(victim) || victim < 1 || victim > MaxClients)
        return Plugin_Continue;
    
    // 检查攻击者是否为有效玩家（防止世界伤害等）
    if (!IsValidEntity(attacker) || attacker < 1 || attacker > MaxClients)
        return Plugin_Continue;
    
    // 确保伤害值有效
    if (damage <= 0.0)
        return Plugin_Continue;
    
    // 获取伤害倍率
    float multiplier = g_cvDamageMultiplier.FloatValue;
    
    // 记录原始伤害值（用于日志）
    float originalDamage = damage;
    
    // 应用伤害倍率
    damage *= multiplier;
    
    // 如果启用日志记录，输出伤害修改信息
    if (g_cvLogDamage.BoolValue)
    {
        char victimName[MAX_NAME_LENGTH];
        char attackerName[MAX_NAME_LENGTH];
        GetClientName(victim, victimName, sizeof(victimName));
        GetClientName(attacker, attackerName, sizeof(attackerName));
        
        LogMessage("伤害翻倍: %s 对 %s 造成了 %.2f 点伤害 (原始: %.2f, 倍率: %.2fx)", 
                   attackerName, victimName, damage, originalDamage, multiplier);
    }
    
    // 返回 Plugin_Changed 表示已修改伤害值
    return Plugin_Changed;
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
