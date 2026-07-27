#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name = "CF Temple Escape Sprite",
    author = "Dazai Nerau, SourceMod port by Codex",
    description = "Escape Mode sprite/beam animation converted from cf_tem_spr.nut",
    version = "1.0.0",
    url = ""
};

#define CF_SPR_BEAM_COUNT 6

static const char g_BeamNames[][] =
{
    "beam",
    "ceam",
    "deam",
    "eeam",
    "feam",
    "geam"
};

bool g_bBlue = true;
bool g_bLoopsRunning = false;
Handle g_hLoopTimers[CF_SPR_BEAM_COUNT];

ConVar g_cvAutoStart;

public void OnPluginStart()
{
    g_cvAutoStart = CreateConVar("sm_cf_spr_autostart", "1", "自动启动 cf_tem_spr 的 6 个光圈循环。");

    RegAdminCmd("sm_cf_spr", Command_CFSPR, ADMFLAG_GENERIC, "sm_cf_spr <Beam|Ceam|Deam|Eeam|Feam|Geam|Isb|Nob|Start|Stop>");
}

public void OnMapStart()
{
    StopLoops();
    g_bBlue = true;

    if (g_cvAutoStart.BoolValue)
    {
        CreateTimer(0.1, Timer_AutoStart, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public void OnMapEnd()
{
    StopLoops();
    DoUnloadSelf();
}

public Action Timer_AutoStart(Handle timer)
{
    StartLoops();
    return Plugin_Stop;
}

public Action Command_CFSPR(int client, int args)
{
    if (args < 1)
    {
        ReplyToCommand(client, "Usage: sm_cf_spr <Beam|Ceam|Deam|Eeam|Feam|Geam|Isb|Nob|Start|Stop>");
        return Plugin_Handled;
    }

    char func[32];
    GetCmdArg(1, func, sizeof(func));
    RunSpriteFunction(func);
    return Plugin_Handled;
}

void RunSpriteFunction(const char[] func)
{
    if (StrEqual(func, "Isb", false))
    {
        g_bBlue = true;
        return;
    }

    if (StrEqual(func, "Nob", false))
    {
        g_bBlue = false;
        return;
    }

    if (StrEqual(func, "Start", false))
    {
        StartLoops();
        return;
    }

    if (StrEqual(func, "Stop", false))
    {
        StopLoops();
        return;
    }

    for (int i = 0; i < sizeof(g_BeamNames); i++)
    {
        if (StrEqual(func, g_BeamNames[i], false) || MatchesOriginalFunction(func, i))
        {
            AnimateBeam(i, false);
            return;
        }
    }
}

bool MatchesOriginalFunction(const char[] func, int index)
{
    static const char names[][] =
    {
        "Beam",
        "Ceam",
        "Deam",
        "Eeam",
        "Feam",
        "Geam"
    };

    return StrEqual(func, names[index], false);
}

void StartLoops()
{
    if (g_bLoopsRunning)
        return;

    g_bLoopsRunning = true;

    for (int i = 0; i < sizeof(g_BeamNames); i++)
    {
        float delay = float(i) * 0.16;
        if (delay <= 0.0)
        {
            AnimateBeam(i, true);
        }
        else
        {
            if (g_hLoopTimers[i] != null)
                KillTimer(g_hLoopTimers[i]);

            g_hLoopTimers[i] = CreateTimer(delay, Timer_StartBeam, i, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

void StopLoops()
{
    g_bLoopsRunning = false;

    for (int i = 0; i < sizeof(g_hLoopTimers); i++)
    {
        if (g_hLoopTimers[i] != null)
        {
            KillTimer(g_hLoopTimers[i]);
            g_hLoopTimers[i] = null;
        }
    }
}

void AnimateBeam(int index, bool scheduleNext)
{
    char entName[32];
    strcopy(entName, sizeof(entName), g_BeamNames[index]);

    FireByName(entName, "Alpha", "0", 0.0);
    FireByName(entName, "TurnOn", "", 0.01);
    if (g_bBlue)
        FireByName(entName, "AddOutput", "rendercolor 0 0 255", 0.0);
    else
        FireByName(entName, "AddOutput", "rendercolor 255 0 0", 0.0);

    FireByName(entName, "Alpha", "5", 0.05);
    FireByName(entName, "Alpha", "15", 0.07);
    FireByName(entName, "Alpha", "75", 0.09);
    FireByName(entName, "Alpha", "105", 0.11);
    FireByName(entName, "Alpha", "135", 0.13);
    FireByName(entName, "Alpha", "165", 0.15);

    if (index != 1)
    {
        FireByName(entName, "Alpha", "195", 0.17);
    }

    float colorDelay = (index == 1) ? 0.17 : 0.19;
    if (g_bBlue)
        FireByName(entName, "AddOutput", "rendercolor 112 197 255", colorDelay);
    else
        FireByName(entName, "AddOutput", "rendercolor 255 92 0", colorDelay);
    FireByName(entName, "Alpha", "225", 0.19);

    if (index == 1)
    {
        FireByName(entName, "Alpha", "235", 0.21);
        FireByName(entName, "Alpha", "245", 0.23);
        FireByName(entName, "Alpha", "255", 0.25);
        FireByName(entName, "Alpha", "245", 0.27);
        FireByName(entName, "Alpha", "235", 0.29);
        FireByName(entName, "Alpha", "225", 0.31);
        FireByName(entName, "Alpha", "195", 0.33);
        FireByName(entName, "Alpha", "165", 0.35);
        FireByName(entName, "Alpha", "135", 0.37);
        FireByName(entName, "Alpha", "105", 0.39);
        FireByName(entName, "Alpha", "75", 0.41);
        FireByName(entName, "Alpha", "15", 0.43);
        FireByName(entName, "Alpha", "5", 0.43);
    }
    else
    {
        FireByName(entName, "Alpha", "245", 0.21);
        FireByName(entName, "Alpha", "255", 0.23);
        FireByName(entName, "Alpha", "245", 0.25);
        FireByName(entName, "Alpha", "235", 0.27);
        FireByName(entName, "Alpha", "225", 0.29);
        FireByName(entName, "Alpha", "195", 0.31);
        FireByName(entName, "Alpha", "165", 0.33);
        FireByName(entName, "Alpha", "135", 0.35);
        FireByName(entName, "Alpha", "105", 0.37);
        FireByName(entName, "Alpha", "75", 0.39);
        FireByName(entName, "Alpha", "15", 0.41);
        FireByName(entName, "Alpha", "5", 0.43);
    }

    FireByName(entName, "TurnOff", "", 0.5);

    if (scheduleNext && g_bLoopsRunning)
    {
        if (g_hLoopTimers[index] != null)
            KillTimer(g_hLoopTimers[index]);

        g_hLoopTimers[index] = CreateTimer(3.0, Timer_BeamLoop, index, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_BeamLoop(Handle timer, any index)
{
    int beamIndex = view_as<int>(index);
    g_hLoopTimers[beamIndex] = null;

    if (!g_bLoopsRunning)
        return Plugin_Stop;

    AnimateBeam(beamIndex, true);
    return Plugin_Stop;
}

public Action Timer_StartBeam(Handle timer, any index)
{
    int beamIndex = view_as<int>(index);
    g_hLoopTimers[beamIndex] = null;

    if (!g_bLoopsRunning)
        return Plugin_Stop;

    AnimateBeam(beamIndex, true);
    return Plugin_Stop;
}

void FireByName(const char[] target, const char[] input, const char[] param = "", float delay = 0.0)
{
    if (delay > 0.0)
    {
        DataPack pack = new DataPack();
        pack.WriteString(target);
        pack.WriteString(input);
        pack.WriteString(param);
        CreateTimer(delay, Timer_FireByName, pack, TIMER_FLAG_NO_MAPCHANGE);
        return;
    }

    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "*")) != -1)
    {
        char name[128];
        GetEntPropString(ent, Prop_Data, "m_iName", name, sizeof(name));
        if (!StrEqual(name, target, false))
            continue;

        if (param[0] != '\0')
            SetVariantString(param);

        AcceptEntityInput(ent, input);
    }
}

public Action Timer_FireByName(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    char target[128];
    char input[64];
    char param[256];

    pack.Reset();
    pack.ReadString(target, sizeof(target));
    pack.ReadString(input, sizeof(input));
    pack.ReadString(param, sizeof(param));
    delete pack;

    FireByName(target, input, param, 0.0);
    return Plugin_Stop;
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
