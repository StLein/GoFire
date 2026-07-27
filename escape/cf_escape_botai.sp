#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

public Plugin myinfo =
{
    name = "CF Escape Bot Door AI",
    author = "Codex",
    description = "Makes Escape Mode attacker bots shoot breakable objective doors.",
    version = "1.0.0",
    url = ""
};

ConVar g_cvEnable;
ConVar g_cvDistance;
ConVar g_cvFov;
ConVar g_cvForwardDistance;
ConVar g_cvForwardSpeed;
ConVar g_cvAttackCooldown;
ConVar g_cvBlockGrenades;
ConVar g_cvLockTime;
ConVar g_cvFreezeTime;

float g_fNextAttack[MAXPLAYERS + 1];
int g_iLockedDoor[MAXPLAYERS + 1];
float g_fLockedDoorUntil[MAXPLAYERS + 1];

public void OnPluginStart()
{
    g_cvEnable = CreateConVar("sm_cf_escape_botai_enable", "1", "开启突围模式 BOT 攻击障碍门逻辑。", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvDistance = CreateConVar("sm_cf_escape_botai_distance", "880.0", "BOT 搜索 door1/door2/door3 的最大距离。", FCVAR_NOTIFY, true, 64.0, false);
    g_cvFov = CreateConVar("sm_cf_escape_botai_fov", "100.0", "BOT 只攻击视野角度内的门。", FCVAR_NOTIFY, true, 10.0, true, 180.0);
    g_cvForwardDistance = CreateConVar("sm_cf_escape_botai_forward_distance", "260.0", "BOT 距离门超过该距离时会向前移动。", FCVAR_NOTIFY, true, 0.0, false);
    g_cvForwardSpeed = CreateConVar("sm_cf_escape_botai_forward_speed", "230.0", "BOT 向门移动的速度。", FCVAR_NOTIFY, true, 0.0, false);
    g_cvAttackCooldown = CreateConVar("sm_cf_escape_botai_attack_cooldown", "0.08", "BOT 对门开火的最小间隔。", FCVAR_NOTIFY, true, 0.01, false);
    g_cvBlockGrenades = CreateConVar("sm_cf_escape_botai_block_grenades", "1", "BOT 面对门时强制切回主武器，避免捏雷发呆。", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvLockTime = CreateConVar("sm_cf_escape_botai_lock_time", "0.6", "BOT 找到门后保持瞄准目标的时间，减少原生 AI 抢视角导致的低头抖动。", FCVAR_NOTIFY, true, 0.05, false);
    g_cvFreezeTime = FindConVar("mp_freezetime");
}

public void OnClientDisconnect(int client)
{
    g_fNextAttack[client] = 0.0;
    g_iLockedDoor[client] = -1;
    g_fLockedDoorUntil[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!IsAttackerBot(client))
        return Plugin_Continue;

    if (IsFreezeTimeActive())
    {
        buttons &= ~(IN_ATTACK | IN_ATTACK2);
        vel[0] = 0.0;
        vel[1] = 0.0;
        vel[2] = 0.0;
        g_iLockedDoor[client] = -1;
        g_fLockedDoorUntil[client] = 0.0;
        return Plugin_Changed;
    }

    if (!g_cvEnable.BoolValue)
        return Plugin_Continue;

    int activeWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
    if (!IsValidEntity(activeWeapon))
        return Plugin_Continue;

    if (g_cvBlockGrenades.BoolValue && IsBadDoorWeapon(client, activeWeapon))
    {
        int primary = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
        if (IsValidEntity(primary))
        {
            SwitchWeapon(client, primary);
            activeWeapon = primary;
        }
    }

    float aimPos[3];
    int door = GetLockedDoorTarget(client, aimPos);
    if (door <= 0)
        door = FindDoorTarget(client, aimPos);

    if (door <= 0)
        return Plugin_Continue;

    g_iLockedDoor[client] = EntIndexToEntRef(door);
    g_fLockedDoorUntil[client] = GetGameTime() + g_cvLockTime.FloatValue;

    LookAtPosition(client, aimPos, angles);

    float eyePos[3];
    GetClientEyePosition(client, eyePos);
    float distance = GetVectorDistance(eyePos, aimPos);
    if (distance > g_cvForwardDistance.FloatValue)
    {
        vel[0] = g_cvForwardSpeed.FloatValue;
    }

    int clip = GetEntProp(activeWeapon, Prop_Data, "m_iClip1");
    if (clip == 0)
        return Plugin_Changed;

    float now = GetGameTime();
    if (now >= g_fNextAttack[client])
    {
        buttons |= IN_ATTACK;
        g_fNextAttack[client] = now + g_cvAttackCooldown.FloatValue;
    }

    return Plugin_Changed;
}

int GetLockedDoorTarget(int client, float outAimPos[3])
{
    if (g_fLockedDoorUntil[client] < GetGameTime())
        return -1;

    int door = EntRefToEntIndex(g_iLockedDoor[client]);
    if (door <= 0 || !IsEscapeDoor(door))
        return -1;

    GetEntityCenter(door, outAimPos);

    float eyePos[3];
    GetClientEyePosition(client, eyePos);
    if (GetVectorDistance(eyePos, outAimPos) > g_cvDistance.FloatValue)
        return -1;

    if (!CanSeeDoor(client, door, outAimPos))
        return -1;

    return door;
}

bool IsAttackerBot(int client)
{
    if (client <= 0 || client > MaxClients)
        return false;

    if (!IsClientInGame(client) || !IsPlayerAlive(client) || !IsFakeClient(client))
        return false;

    int team = GetClientTeam(client);
    if (team != CS_TEAM_T && team != CS_TEAM_CT)
        return false;

    char targetname[64];
    GetEntPropString(client, Prop_Data, "m_iName", targetname, sizeof(targetname));
    return StrEqual(targetname, "rusher", false);
}

bool IsFreezeTimeActive()
{
    if (g_cvFreezeTime == null)
        g_cvFreezeTime = FindConVar("mp_freezetime");

    return g_cvFreezeTime != null && g_cvFreezeTime.FloatValue > 30.0;
}

bool IsBadDoorWeapon(int client, int weapon)
{
    int primary = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
    if (IsValidEntity(primary) && weapon == primary)
        return false;

    int secondary = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
    if (IsValidEntity(secondary) && weapon == secondary)
        return false;

    return true;
}

int FindDoorTarget(int client, float outAimPos[3])
{
    float eyePos[3];
    GetClientEyePosition(client, eyePos);

    int bestDoor = -1;
    float bestDistance = -1.0;
    float maxDistance = g_cvDistance.FloatValue;

    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "func_breakable")) != -1)
    {
        if (!IsEscapeDoor(ent))
            continue;

        float aimPos[3];
        GetEntityCenter(ent, aimPos);

        float distance = GetVectorDistance(eyePos, aimPos);
        if (distance > maxDistance)
            continue;

        if (!IsPositionInClientHorizontalFov(client, aimPos, g_cvFov.FloatValue))
            continue;

        if (!CanSeeDoor(client, ent, aimPos))
            continue;

        if (bestDistance >= 0.0 && distance >= bestDistance)
            continue;

        bestDoor = ent;
        bestDistance = distance;
        CopyVector(aimPos, outAimPos);
    }

    return bestDoor;
}

bool IsEscapeDoor(int ent)
{
    if (!IsValidEntity(ent))
        return false;

    if (FindDataMapInfo(ent, "m_iHealth") != -1 && GetEntProp(ent, Prop_Data, "m_iHealth") <= 0)
        return false;

    char targetname[32];
    GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));
    return StrEqual(targetname, "door1", false) || StrEqual(targetname, "door2", false) || StrEqual(targetname, "door3", false);
}

void GetEntityCenter(int ent, float center[3])
{
    GetEntPropVector(ent, Prop_Send, "m_vecOrigin", center);

    char netclass[64];
    if (!GetEntityNetClass(ent, netclass, sizeof(netclass)))
    {
        center[2] += 48.0;
        return;
    }

    if (FindSendPropInfo(netclass, "m_vecMins") == -1 || FindSendPropInfo(netclass, "m_vecMaxs") == -1)
    {
        center[2] += 48.0;
        return;
    }

    float mins[3];
    float maxs[3];
    GetEntPropVector(ent, Prop_Send, "m_vecMins", mins);
    GetEntPropVector(ent, Prop_Send, "m_vecMaxs", maxs);

    center[0] += (mins[0] + maxs[0]) * 0.5;
    center[1] += (mins[1] + maxs[1]) * 0.5;
    center[2] += (mins[2] + maxs[2]) * 0.5;
}

bool IsPositionInClientHorizontalFov(int client, const float position[3], float fov)
{
    float eyePos[3];
    float eyeAngles[3];
    float toTarget[3];
    float targetAngles[3];

    GetClientEyePosition(client, eyePos);
    GetClientEyeAngles(client, eyeAngles);

    eyePos[2] = 0.0;
    MakeVectorFromPoints(eyePos, position, toTarget);
    toTarget[2] = 0.0;
    GetVectorAngles(toTarget, targetAngles);

    return FloatAbs(NormalizeAngle(eyeAngles[1] - targetAngles[1])) <= (fov * 0.5);
}

bool CanSeeDoor(int client, int door, const float aimPos[3])
{
    float eyePos[3];
    GetClientEyePosition(client, eyePos);

    Handle trace = TR_TraceRayFilterEx(eyePos, aimPos, MASK_SHOT, RayType_EndPoint, TraceFilter_DoorSight, client);
    bool canSee = false;

    if (TR_DidHit(trace))
    {
        canSee = (TR_GetEntityIndex(trace) == door);
    }

    delete trace;
    return canSee;
}

public bool TraceFilter_DoorSight(int entity, int contentsMask, any data)
{
    if (entity == data)
        return false;

    if (entity >= 1 && entity <= MaxClients)
        return false;

    return true;
}

void LookAtPosition(int client, const float position[3], float cmdAngles[3])
{
    float eyePos[3];
    float direction[3];
    float aimAngles[3];

    GetClientEyePosition(client, eyePos);
    MakeVectorFromPoints(eyePos, position, direction);
    GetVectorAngles(direction, aimAngles);

    cmdAngles[0] = aimAngles[0];
    cmdAngles[1] = aimAngles[1];
    cmdAngles[2] = 0.0;
    TeleportEntity(client, NULL_VECTOR, cmdAngles, NULL_VECTOR);
}

void SwitchWeapon(int client, int weapon)
{
    if (!IsValidEntity(weapon))
        return;

    char classname[64];
    GetEntityClassname(weapon, classname, sizeof(classname));
    FakeClientCommand(client, "use %s", classname);
}

float NormalizeAngle(float angle)
{
    while (angle > 180.0)
        angle -= 360.0;

    while (angle < -180.0)
        angle += 360.0;

    return angle;
}

void CopyVector(const float source[3], float dest[3])
{
    dest[0] = source[0];
    dest[1] = source[1];
    dest[2] = source[2];
}
