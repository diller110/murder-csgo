#include <steamworks>

#pragma semicolon 1
#pragma newdecls required

#include <cstrike>
#include <sdkhooks>
#include <csgo_colors>
#include <smlib>
#include <clientprefs>

#undef  REQUIRE_PLUGIN 
#include <murder>
#define  REQUIRE_PLUGIN

public Plugin myinfo = {
	name 		= "Murder | Ядро плагина",
	author 		= "Rustgame",
	description = "Murder - Является игровым режимом, где простым очевидцами придется выяснить кто убийца, и не стать его жертвой.",
	version		= "1.0a"
};

Murder_Role role[MAXPLAYERS + 1];
Murder_State state = Murder_Disabled;
int minPlayers;
ConVar	cvChangeNicknames = null,
		cvImposterKillCooldown = null;

int 	RagdollPlayer[MAXPLAYERS+1],
		sizeArray_Names = 0,
		sizeArray_Models = 0,
		m_flSimulationTime = -1,
		m_flProgressBarStartTime = -1,
		m_iProgressBarDuration = -1,
		m_iBlockingUseActionInProgress = -1,
		g_iIsAliveOffset,
		HideRagdoll_Price;
bool 	bKnifeUse[MAXPLAYERS+1];
char 	szNameList[PLATFORM_MAX_PATH][64],
		szModelList[PLATFORM_MAX_PATH][128],
		RoundSoundList[PLATFORM_MAX_PATH][128];
Handle 	HUDTimer[MAXPLAYERS+1],
		TimerGetKnife[MAXPLAYERS+1];

Handle 	CDTimer_Voice[MAXPLAYERS+1];



public void OnPluginStart() {
	cvChangeNicknames = CreateConVar("sm_murder_changenicknames", "1", "Change player nicknames");
	cvImposterKillCooldown = CreateConVar("sm_murder_killcooldown", "10", "Cooldown after imposter kill");
	
	LoadTranslations("murder.phrases");

	HookEvent("round_start",	Event_RoundStart,	EventHookMode_PostNoCopy);
	HookEvent("round_end",		Event_RoundEnd, 	EventHookMode_PostNoCopy);
	HookEvent("player_death",	Event_PlayerDeath,	EventHookMode_Pre);
	HookEvent("player_spawn",	Event_PlayerSpawn,	EventHookMode_Pre);
	HookEvent("player_shoot",	Event_PlayerShoot); 

	AddCommandListener(ToggleFlashlight, "+lookatweapon");
	AddCommandListener(ScoreOff, "+score");

	m_flProgressBarStartTime 		= FindSendPropInfo("CCSPlayer", "m_flProgressBarStartTime");
	m_iProgressBarDuration 			= FindSendPropInfo("CCSPlayer", "m_iProgressBarDuration");
	m_flSimulationTime 				= FindSendPropInfo("CBaseEntity", "m_flSimulationTime");
	m_iBlockingUseActionInProgress 	= FindSendPropInfo("CCSPlayer", "m_iBlockingUseActionInProgress");
	g_iIsAliveOffset 				= FindSendPropInfo("CCSPlayerResource", "m_bAlive");
	if (g_iIsAliveOffset == -1)
		SetFailState("CCSPlayerResource.m_bAlive offset is invalid"); 

	char szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/configs.ini");
	KeyValues KV_Config = new KeyValues("Murder");
	KV_Config.ImportFromFile(szPath);
	minPlayers = KV_Config.GetNum("MinPlayersToPlaying");
	KV_Config.GetString("RoundStart", 		RoundSoundList[0], sizeof(RoundSoundList));
	KV_Config.GetString("RoundWinMurder", 	RoundSoundList[1], sizeof(RoundSoundList));
	KV_Config.GetString("RoundNoWinMurder", RoundSoundList[2], sizeof(RoundSoundList));
	HideRagdoll_Price 	= KV_Config.GetNum("HideRagdoll_Price");

	PrintToServer(RoundSoundList[0]);
	PrintToServer(RoundSoundList[1]);
	PrintToServer(RoundSoundList[2]);
	LoadConfig_Names();

	RegConsoleCmd("sm_du", Stuck);

	for(int i = 1; i <= GetClientCount(); ++i) 
	{
		if (IsValidClient(i))
		{
			if (HUDTimer[i] == null)
			{
				HUDTimer[i] = CreateTimer(1.0, HUD, i, TIMER_REPEAT);
			}
		}
	}

	CreateTimer(1.0, StartThink);
}

public Action StartThink(Handle timer) {
	int CSPlayerManagerIndex = FindEntityByClassname(0, "cs_player_manager");
	SDKHook(CSPlayerManagerIndex, SDKHook_ThinkPost, OnThinkPost);
}

public void OnClientDisconnect(int client) {
	if (Murder_GetClientRole(client) == Murder_Imposter) {
		CGOPrintToChatAll("%t", "MurderLeave");
		ServerCommand("mp_restartgame 1");
	}
}

public Action Stuck(int client, int args) {
	int aim = GetClientAimTarget(client, false);
	if (aim > MaxClients) {
		char class[128];
		GetEntityClassname(aim, class, sizeof(class));
	}
}
public void OnThinkPost(int entity) {
	if (entity < 0)return;
	static int isAlive[MAXPLAYERS+1];
    
	GetEntDataArray(entity, g_iIsAliveOffset, isAlive, sizeof isAlive);
	for (int i = 1; i <= MaxClients; ++i) {
		if (IsValidClient(i)) {
			isAlive[i] = true;
		}
	}
	SetEntDataArray(entity, g_iIsAliveOffset, isAlive, sizeof isAlive);
} 

public void Voice(int client) {
	float Pos[3];
	int iRandom = GetRandomInt(1, 16);
	char path[128];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", Pos);
	Format(path, sizeof(path), "*/murder/voice/vo_%i.wav", iRandom);
	EmitAmbientSound(path, Pos, client, 140, _, 0.4);
}
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("Murder_GetState", Native_GetState);
	CreateNative("Murder_GetClientRole", Native_GetClientRole);
	MarkNativeAsOptional("M_GetCountLoot");
	MarkNativeAsOptional("M_SetCountLoot");
	MarkNativeAsOptional("M_GetCountLoots");

	return APLRes_Success;
}
public int Native_GetState(Handle plugin, int numParams) {
	return view_as<int>(state);
}
public int Native_GetClientRole(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	return view_as<int>(role[client]);
}
public void LoadConfig_Sound() {
	char szPath[256], sSectionName[64], szPathS[64];
	BuildPath(Path_SM, szPath, sizeof szPath, "configs/murder/sounds.ini");
	KeyValues KV_Sounds = new KeyValues("Sounds");
	KV_Sounds.ImportFromFile(szPath); 
	KV_Sounds.Rewind();
	KV_Sounds.GotoFirstSubKey(false);
	
	int sizeArray_Sounds = 0;
	while(KV_Sounds.GotoNextKey(false))	{
		KV_Sounds.GetSectionName(sSectionName, sizeof sSectionName); 
		Format(szPathS, sizeof(szPathS), "*/%s", sSectionName);
		PrecacheSound(szPathS);
		sizeArray_Sounds++;
		Format(szPathS, sizeof szPathS, "sound/%s", sSectionName);
		AddFileToDownloadsTable(szPathS);
	}
	PrintToServer("[Murder] %i sounds loaded.", sizeArray_Sounds);

	delete KV_Sounds;
}
public void LoadConfig_Names() {
	char 	szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/names.ini");
	KeyValues KV_Names = new KeyValues("Male");
	KV_Names.ImportFromFile(szPath);
	KV_Names.Rewind();
	KV_Names.GotoFirstSubKey(false);
	while(KV_Names.GotoNextKey(false))
	{
		char sSectionName[64];
		KV_Names.GetSectionName(sSectionName, sizeof(sSectionName));
		szNameList[sizeArray_Names] = sSectionName;
		sizeArray_Names++;
	}
	PrintToServer("[Murder] %i names loaded.", sizeArray_Names);

	delete KV_Names;
}
public void LoadConfig_Models() {
	char szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/models.ini");
	KeyValues KV_Models = new KeyValues("Models");
	KV_Models.ImportFromFile(szPath); 
	KV_Models.Rewind();
	KV_Models.GotoFirstSubKey(false);
	while(KV_Models.GotoNextKey(false)) {
		char sSectionName[64]; 
		KV_Models.GetSectionName(sSectionName, sizeof(sSectionName)); 
		szModelList[sizeArray_Models] = sSectionName; 
		PrecacheModel(sSectionName);
		sizeArray_Models++;
		AddFileToDownloadsTable(sSectionName);
	}
	PrintToServer("[Murer] % models loaded.", sizeArray_Models);
	
	delete KV_Models;
}
public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    SetEntProp(client, Prop_Send, "m_iHideHUD", 1<<12);
}
public void OnClientPostAdminCheck(int client) {
	role[client] = Murder_Crewmate;
	HUDTimer[client] = CreateTimer(1.0, HUD, client, TIMER_REPEAT);
}
public Action HUD(Handle timer, int client) {
	if(!IsValidClient(client)) {
		HUDTimer[client] = null;
		return;
	}
	if (!IsPlayerAlive(client))return;

	static char HEXColorTeam[32], TeamText[64];
	
	switch(role[client]) {
		case Murder_Crewmate: {
			Format(TeamText, sizeof(TeamText), "%t", "noMurder");
			HEXColorTeam = "#00ffff";
		}
		case Murder_Imposter: {
			Format(TeamText, sizeof(TeamText), "%t", "tMurder"); 
			HEXColorTeam = "#ff0000";
		}
		case Murder_Officer: {
			Format(TeamText, sizeof(TeamText), "%t", "tPolice"); 
			HEXColorTeam = "#0000ff";
		}
	}
	
	char StringText[2048];	
	Format(StringText, sizeof(StringText), "<font color='#fff'>______________</font>[ <font color='#ff0000'>Murder</font> ]<font color='#fff'>______________</font>\
		\n%t<font color='%s'>%s</font> \	
		\n%t <font color='#9900ff'>%i шт.</font>", "HRole", HEXColorTeam, TeamText, "HEvidence", M_GetCountLoot(client));
	PrintHintText(client, StringText);

	
	SetHudTextParams(0.012, 0.48, 5.0, 255,255,255, 255, 0, 0.0, 0.5, 0.1);
	ShowHudText(client, -1, "Улик на локации: %i", M_GetCountLoots());
	SetHudTextParams(0.012, 0.5, 5.0, 255,255,255, 255, 0, 0.0, 0.5, 0.1);
	ShowHudText(client, -1, "%t R", "Voice");
	if (Murder_GetClientRole(client) == Murder_Imposter)
	{
		SetHudTextParams(0.012, 0.52, 5.0, 255,255,255, 255, 0, 0.0, 0.5, 0.1);
		if(bKnifeUse[client])
		{
			ShowHudText(client, -1, "%t", "HideKnife");
		}
		else
		{
			ShowHudText(client, -1, "%t", "UseKnife");
		}

		SetHudTextParams(0.012, 0.54, 5.0, 255,255,255, 255, 0, 0.0, 0.5, 0.1);
		ShowHudText(client, -1, "Спрятать тело: E + %i Улик(и)", HideRagdoll_Price);
	}

}
public Action EventItemPickup(int client, int entity) {
	static char Weapon[64];
	GetEntityClassname(entity, Weapon, sizeof(Weapon));
	if (role[client] == Murder_Imposter && StrEqual(Weapon, "weapon_deagle")) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
public void OnMapStart() {
	Handle 	HideName  = FindConVar("mp_playerid"),
			LimitTeam = FindConVar("mp_limitteams"),
			EnemyKill = FindConVar("mp_teammates_are_enemies"),
			WarTimers = FindConVar("mp_warmuptime");
	SetConVarInt(HideName, 2);
	SetConVarInt(LimitTeam, 30);
	SetConVarInt(EnemyKill, 1);
	SetConVarInt(WarTimers, 0);
	LoadConfig_Models();
	LoadConfig_Sound();
	CreateTimer(10.0, CheckAccessPlaying, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}
public Action CheckAccessPlaying(Handle timer) {
	if (GetClientCount() >= minPlayers) {
		state = Murder_InProgress;
		return Plugin_Stop;
	} else {
		state = Murder_Disabled;
		CGOPrintToChatAll("%t", "ChatNoPlayers", minPlayers);
		return Plugin_Continue;
	}
}
public Action ToggleFlashlight(int client, const char[] command, int args) {
	SetEntProp(client, Prop_Send, "m_fEffects", GetEntProp(client, Prop_Send, "m_fEffects") ^ 4);
}
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	SetEntProp(client, Prop_Data, "m_iFrags", 0);
	SetEntProp(client, Prop_Data, "m_iDeaths", 0);
	SetEntProp(attacker, Prop_Data, "m_iFrags", 0);
	SetEntProp(attacker, Prop_Data, "m_iDeaths", 0);
	
	static char buff[256];
	
	switch(role[client]) {
		case Murder_Imposter: {
			EmitSoundToAll(RoundSoundList[2],_,_,_,_,0.2);
			CS_TerminateRound(5.0, CSRoundEnd_CTStoppedEscape, false);
			CGOPrintToChatAll("%t", "noMurderWin");
			Format(buff, sizeof buff, "%t", "MurderBy");
			CGOPrintToChatAll("%s %N", buff, client);
			
			return Plugin_Changed;
		}
		default: {
			switch(role[attacker]) {
				case Murder_Officer: {
					ForcePlayerSuicide(attacker);
					CGOPrintToChat(attacker, "%t", "rdmKill");
				}
				default: {
					if (bKnifeUse[attacker] == true) {
						Client_RemoveWeapon(attacker, "weapon_knife", false);
						bKnifeUse[attacker] = false;
						TimerGetKnife[attacker] = INVALID_HANDLE;
					}
				}
			}
		}
	}

	int iAlive = 0;

	for(int i = 1; i <= MaxClients; ++i) {	
		if (IsValidClient(i) && IsPlayerAlive(i)) {
			iAlive++;
		}
	}

	if (iAlive <= 1) {
		CS_TerminateRound(5.0, CSRoundEnd_CTStoppedEscape, false);
		CGOPrintToChatAll("%t", "MurderWin");
		EmitSoundToAll(RoundSoundList[1],_,_,_,_,0.2);
	}

	int iRagdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if (iRagdoll > 0)
		AcceptEntityInput(iRagdoll, "Kill");
	CreateDeathRagdoll(client);
	SetEventBroadcast(event, true);

	return Plugin_Changed;
}
public Action ScoreOff(int client, const char[] command, int args) {
	return Plugin_Handled;
}
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	static _buttons[MAXPLAYERS + 1];
	if (!IsValidClient(client)) return Plugin_Continue;

	switch(role[client]) {
		case Murder_Imposter: {
			if(buttons & IN_ATTACK2 && !(_buttons[client] & IN_ATTACK2)) { // First click
				if (bKnifeUse[client] == true) {
					Client_RemoveWeapon(client, "weapon_knife", false);
					bKnifeUse[client]=false;
					TimerGetKnife[client] = INVALID_HANDLE;
				} else {
					if (TimerGetKnife[client] == null) {
						TimerGetKnife[client] 	= CreateTimer(2.0, GiveWeapon, client);
						float flGameTime 		= GetGameTime();
						SetEntData(client, m_iProgressBarDuration, 2, 4, true);
						SetEntDataFloat(client, m_flProgressBarStartTime, flGameTime - (float(2) - 2.0), true);
						SetEntDataFloat(client, m_flSimulationTime, flGameTime + 2.0, true);
						SetEntData(client, m_iBlockingUseActionInProgress, 0, 4, true);
					} else {
						SetEntDataFloat(client, m_flProgressBarStartTime, 0.0, true);
						SetEntData(client, m_iProgressBarDuration, 0, 1, true);
						delete TimerGetKnife[client];
					}
				}
			}
		}
	}

	if(buttons & IN_ATTACK && !(_buttons[client] & IN_ATTACK)) { // First click
		int aim = GetClientAimTarget(client, false);
		if (aim > MaxClients) {
			static char class[128];
			GetEntityClassname(aim, class, sizeof class);
			if (StrEqual(class, "prop_ragdoll")) {
				SetEntProp(aim, Prop_Data, "m_CollisionGroup", 1);
				CreateTimer(2.0, SetSolid, aim);
			}
		}
	}
	
	if(buttons & IN_RELOAD && !(_buttons[client] & IN_RELOAD)) { // First click
		if(IsPlayerAlive(client)) {	
			if (CDTimer_Voice[client] == null) {
				Voice(client);
				CDTimer_Voice[client] = CreateTimer(2.0, VoiceEnable, client);
			}
		}
	}

	if(buttons & IN_SCORE && !(_buttons[client] & IN_SCORE)) {
		StartMessageOne("ServerRankRevealAll", client, USERMSG_BLOCKHOOKS);
		EndMessage();
	}

	if(buttons & IN_USE && !(_buttons[client] & IN_USE)) {
		int aim = GetClientAimTarget(client, false);
		if (aim > MaxClients) {
			char class[128];
			GetEntityClassname(aim, class, sizeof(class));
			if (StrEqual(class, "prop_ragdoll", false))
			{
				int owner = GetClientOfUserId(GetEntProp(aim, Prop_Send, "m_hOwnerEntity"));
				char Tr[64];
				Format(Tr, sizeof(Tr), "%t ", "OwnerRandoll", owner);
				if (owner <= 0) CGOPrintToChat(client, "%t", "OwnerRandollDIS"); else CGOPrintToChat(client, "%s %N", Tr, owner);

				if (Murder_GetClientRole(client) == Murder_Imposter && M_GetCountLoot(client)>=HideRagdoll_Price)
				{	
					CGOPrintToChat(client, "{RED}Murder | {DEFAULT}Вы спрятали труп!");
					RemoveEntity(aim);
					M_TakeLoot(client, HideRagdoll_Price);
				}
				
			}
		}
	}

	_buttons[client] = buttons;
	return Plugin_Continue;
}

public Action VoiceEnable(Handle timer, int client) {
	CDTimer_Voice[client] = null;
	delete CDTimer_Voice[client];
}
public Action GiveWeapon(Handle timer,int client) {
	SetEntDataFloat(client, m_flProgressBarStartTime, 0.0, true);
	SetEntData(client, m_iProgressBarDuration, 0, 1, true);
	Client_GiveWeapon(client, "weapon_knife", true);
	bKnifeUse[client] = true;
}
public void CreateDeathRagdoll(int client) {
	RagdollPlayer[client] = CreateEntityByName("prop_ragdoll");
	if (RagdollPlayer[client] == -1) return;
	
	char sModel[PLATFORM_MAX_PATH];
	GetClientModel(client, sModel, sizeof(sModel));
	DispatchKeyValue(RagdollPlayer[client], "model", sModel);
	DispatchSpawn(RagdollPlayer[client]);
	ActivateEntity(RagdollPlayer[client]);
	SetEntProp(RagdollPlayer[client], Prop_Send, "m_hOwnerEntity", GetClientUserId(client));
	SetEntProp(RagdollPlayer[client], Prop_Data, "m_CollisionGroup", 1);
	CreateTimer(2.0, SetSolid, RagdollPlayer[client]);
	float vec[3];
	GetClientAbsOrigin(client, vec);
	TeleportEntity(RagdollPlayer[client], vec, NULL_VECTOR, NULL_VECTOR);
}

public Action SetSolid(Handle timer, int entity) {
	SetEntProp(entity, Prop_Data, "m_CollisionGroup", 6);
}
public Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast) {
	//CreateTimer(10.0, CheckAccessPlaying, _, TIMER_REPEAT);
	int clientCount = GetClientCount();
	
	int iRandom_Murder 	= GetRandomInt(1, clientCount),
		iRandom_Police 	= GetRandomInt(1, clientCount);

	int ent = -1; 
	while ((ent = FindEntityByClassname(ent, "func_buyzone")) > 0) {
		if (IsValidEntity(ent)) {
			AcceptEntityInput(ent, "kill");
		}
	}
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "hostage_entity")) != -1) {
		if (IsValidEntity(ent)) {
			AcceptEntityInput(ent, "kill");
		}
	}

	for(int i = 1; i <= clientCount; ++i)
		if (IsValidClient(i))
			Client_RemoveAllWeapons(i);
	if (iRandom_Police == iRandom_Murder) {
		iRandom_Police = GetRandomInt(0, clientCount);
	}

	for(int i = 1; i <= MAXPLAYERS; ++i) {
		if (IsValidClient(i)) {
			float Pos[3]; 
			GetEntPropVector(i, Prop_Send, "m_vecOrigin", Pos);
			EmitAmbientSound(RoundSoundList[0], Pos, i, 30, _, 1.0);
			SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
			SDKHook(i, SDKHook_WeaponEquip, EventItemPickup);
			OnClientPostAdminCheck(i);
			if(cvChangeNicknames.IntValue) {
				int iRandom_Name = GetRandomInt(0, sizeArray_Names - 1);
		 		SetClientInfo(i, "name", szNameList[iRandom_Name]);
				SetEntPropString(i, Prop_Data, "m_szNetname", szNameList[iRandom_Name]);
			}
			CS_SetClientClanTag(i, "");
			int iRandom_Models = GetRandomInt(0, sizeArray_Models - 1);
			SetEntityModel(i, szModelList[iRandom_Models]);
			int iMelee = GivePlayerItem(i, "weapon_fists");
			EquipPlayerWeapon(i, iMelee);
			if (iRandom_Murder == i) {	
				role[i] = Murder_Imposter;
				CGOPrintToChat(i, "%t", "cMurder");
			} else if (iRandom_Police == i) {
				role[i] = Murder_Officer;
				GivePlayerItem(i, "weapon_revolver");
				CGOPrintToChat(i, "%t", "cPolice");
			} else {
				role[i] = Murder_Crewmate;
				CGOPrintToChat(i, "%t", "cnoMurder");
			}
		}
	}
}
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	for(int i = 1; i <= MaxClients; ++i) {
		if (IsValidClient(i)) {
			role[i] = Murder_Crewmate;
		}
	}
}
public Action Event_PlayerShoot(Event event, char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	GetEntData(client, FindSendPropInfo("CCSPlayer", "m_iAmmo")+(1*4), 4);
}
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
	static char weapon[32];
	
	GetClientWeapon(inflictor, weapon, sizeof weapon);
	if(StrEqual(weapon, "weapon_fists")) {
		damage = 0.0;
	} else if(StrEqual(weapon, "weapon_knife") || StrEqual(weapon, "weapon_revolver")) {
		damage = 99999.0;
	} 
	
	return Plugin_Changed;
}