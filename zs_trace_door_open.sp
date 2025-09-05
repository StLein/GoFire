#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "zs_trace_door_open",
    author      = "lein",
    description = "zs_trace_door_open",
    version     = "1.0",
	url         = "https://github.com/StLein"
};

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

public void OnPluginStart()
{
    // Key:classname Value:func_button 
    HookEntityOutput("func_button",       "OnPressed",   OutputHook);
}

public void OutputHook(const char[] output, int caller, int activator, float delay)
{
    // 手动开门 
    char name[64]; name[0] = '\0';
    GetEntityNameOrClass(caller, name, sizeof(name));
	int hammerid = GetEntProp(caller, Prop_Data, "m_iHammerID");
    // PrintToServer("[Output] %s hammerid=%d output=%s caller=%d activator=%d delay=%.1f", name, hammerid, output, caller, activator, delay);

    if(hammerid == 9166) {
		int ent = -1;
        while ((ent = FindEntityByClassname(ent, "func_door")) != -1)
        {    
            if(GetEntProp(ent, Prop_Data, "m_iHammerID") == 6743){
                AcceptEntityInput(ent, "Open"); // door1
                break;
            }
        }
    } else if(hammerid == 9188) {
		int ent = -1;
        while ((ent = FindEntityByClassname(ent, "func_door")) != -1)
        {
            if(GetEntProp(ent, Prop_Data, "m_iHammerID") == 6780){
                AcceptEntityInput(ent, "Open"); // door3
                break;
            }
        }
    } else if(hammerid == 9199) {
		int ent = -1;
        while ((ent = FindEntityByClassname(ent, "func_door")) != -1)
        {
            // door4
            if(GetEntProp(ent, Prop_Data, "m_iHammerID") == 7600){
                AcceptEntityInput(ent, "Open"); 
            }
            if(GetEntProp(ent, Prop_Data, "m_iHammerID") == 7675){
                AcceptEntityInput(ent, "Open"); // door4
            }
        }
        // point_template
        // Key:OnPressed Value:start_e_3Kill0-1 
        // if(GetEntProp(ent, Prop_Data, "m_iHammerID") == 57572){
        //     AcceptEntityInput(ent, "Open"); // door4
        // }
    } else if(hammerid == 9210) {
		int ent = -1;
        while ((ent = FindEntityByClassname(ent, "func_button")) != -1)
        {
            // shortcut1_button
            if(GetEntProp(ent, Prop_Data, "m_iHammerID") == 8040){
                AcceptEntityInput(ent, "Unlock"); 
            }
        }
    } else if(hammerid == 9177){
		int ent = -1;
        // Key:OnPressed Value:fake1_e_expExplode0-1 
        while ((ent = FindEntityByClassname(ent, "env_explosion")) != -1)
        {
            if(GetEntProp(ent, Prop_Data, "m_iHammerID") == 9365){
                AcceptEntityInput(ent, "Explode"); // fake1_e_exp
                break;
            }
        }
    } else if(hammerid == 6751)
    {
		int ent = -1;
        // Key:OnPressed Value:start_exp_1Explode0-1 
        while ((ent = FindEntityByClassname(ent, "env_explosion")) != -1)
        {
            if(GetEntProp(ent, Prop_Data, "m_iHammerID") == 26835){
                AcceptEntityInput(ent, "Explode");
                break;
            }
        }
    }
}

void GetEntityNameOrClass(int ent, char[] buffer, int maxlen)
{
    if (ent <= 0 || !IsValidEntity(ent))
    {
        strcopy(buffer, maxlen, "开关");
        return;
    }
    GetEntPropString(ent, Prop_Data, "m_iName", buffer, maxlen);
    if (buffer[0] == '\0')
    {
        GetEntityClassname(ent, buffer, maxlen);
    }
}
