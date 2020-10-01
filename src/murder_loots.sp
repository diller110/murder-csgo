#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <steamworks>
#include <cstrike>
#include <csgo_colors>
#include <PTaH>
#include <smlib>

#undef  REQUIRE_PLUGIN 
#include <murder>
#define  REQUIRE_PLUGIN

public Plugin myinfo = {
	name = "Murder | Улики",
	author = "Rustgame",
	description = "Данный модуль добавляет на Murder улики, которые можно собрать и получить оружие.",
};

bool 	g_InUse[MAXPLAYERS+1];
int 	iColorOverride[4],
		iLootsUse[MAXPLAYERS+1],
		MaxCountToGive,
		iCountAllLoots;
char   	szWeapon[32];
float 	fCoolDownCreate;
char models[][] = {
	"models/props_junk/watermelon01.mdl",
	"models/props/cs_office/computer_caseb.mdl",
	"models/props/cs_office/file_box.mdl",
	"models/props/cs_office/microwave.mdl",
	"models/props_c17/oildrum001.mdl",
	"models/props/cs_office/phone.mdl",
	"models/props/cs_office/radio.mdl",
	"models/props/cs_office/snowman_face.mdl",
	"models/props/cs_office/trash_can.mdl",
	"models/props/cs_office/water_bottle.mdl"
};
ArrayList navPositions;
bool navMeshed = false;
Handle spawnClueTimer = null;

public void OnPluginStart()
{
	navPositions = new ArrayList(3);
	LoadTranslations("murder_loots.phrases");

	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);
	RegAdminCmd("sm_loot_add", AddLoot, ADMFLAG_ROOT);

	char 	szPath[256];
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/loot/configs.ini"); KeyValues KV_LootConfig = new KeyValues("Loots_Confings"); KV_LootConfig.ImportFromFile(szPath);
	KV_LootConfig.GetColor4("ColorLootGlow", iColorOverride);
	fCoolDownCreate = KV_LootConfig.GetFloat("CoolDownCreate");
	MaxCountToGive 	= KV_LootConfig.GetNum("MaxCountLoots");
	KV_LootConfig.GetString("GiveWeapon", szWeapon, sizeof(szWeapon));
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max) 
{
	LoadTranslations("murder.phrases");
	CreateNative("M_GetCountLoot", Native_M_GetCountLoot);
	CreateNative("M_SetCountLoot", Native_M_SetCountLoot);
	CreateNative("M_GetCountLoots", Native_M_GetCountLootFromMaps);

	return APLRes_Success;
}

public void OnAllPluginsLoaded() {
	//PrintToServer("%t", "lPStartOk");
}
public void OnMapStart() {
	// Source: https://github.com/qubka/Zombie-Plague/
	Handle hConfig = LoadGameConfigFile("plugin.presents");
	Address TheNavAreas = GameConfGetAddress(hConfig, "TheNavAreas"); // Load other addresses
	if (TheNavAreas == Address_Null) SetFailState("Failed to load SDK address \"TheNavAreas\". Update address in \"plugin.presents\"");  // Validate address   
	int TheNavAreas_Count = view_as<int>(GameConfGetAddress(hConfig, "TheNavAreas::Count"));  // Validate count
	delete hConfig;
	if (TheNavAreas_Count <= 0) {
		PrintToServer("[Murder|Loot] Module unloaded on the current map. Generate \"nav_mesh\" to make it work!"); // Log info
		navMeshed = false;
		return;
	}
	//PrintToServer("[Murder|Loot] %d navmeshes", TheNavAreas_Count); // Log info
	
	navPositions.Clear();
	
	// Gets a random positions
	for (int i = 0; i < TheNavAreas_Count; ++i) {
		Address pNavArea = view_as<Address>(LoadFromAddress(TheNavAreas + view_as<Address>(i * 4), NumberType_Int32));
		if (pNavArea != Address_Null) {
			static float nwCorner[3]; static float seCorner[3]; static float vCenter[3];
			// Gets north-west corner point
			nwCorner[0] = view_as<float>(LoadFromAddress(pNavArea + view_as<Address>(4), NumberType_Int32));
			nwCorner[1] = view_as<float>(LoadFromAddress(pNavArea + view_as<Address>(8), NumberType_Int32));
			nwCorner[2] = view_as<float>(LoadFromAddress(pNavArea + view_as<Address>(12), NumberType_Int32));
			// Gets south-east corner point
			seCorner[0] = view_as<float>(LoadFromAddress(pNavArea + view_as<Address>(16), NumberType_Int32));
			seCorner[1] = view_as<float>(LoadFromAddress(pNavArea + view_as<Address>(20), NumberType_Int32));
			seCorner[2] = view_as<float>(LoadFromAddress(pNavArea + view_as<Address>(24), NumberType_Int32));
			// Check that the area is bigger than 50 units wide on both sides
			if ((seCorner[0] - nwCorner[0]) <= 50.0 || (seCorner[1] - nwCorner[1]) <= 50.0)
			continue;
			// Calculate area center position
			AddVectors(nwCorner, seCorner, vCenter);
			ScaleVector(vCenter, 0.5);
			navPositions.PushArray(vCenter, sizeof vCenter);
		}
	}
	if (!navPositions.Length) {
		navMeshed = false;
		return;
	}
	//PrintToServer("Valid meshes %d", navPositions.Length);
	navMeshed = true;
}
public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsValidClient(iClient)) return Plugin_Continue;
	if (!g_InUse[iClient] && buttons & IN_USE)
	{
		if(IsPlayerAlive(iClient))
		{
			g_InUse[iClient] = true;
			int aim = GetClientAimTarget(iClient, false);
			if (aim > MaxClients)
			{
				char 	class[128],
						targetname[128];
				GetEntityClassname(aim, class, sizeof(class));
				GetEntPropString(aim, Prop_Data, "m_iName", targetname, sizeof(targetname));
				if (StrEqual(class, "prop_dynamic") && StrEqual(targetname , "m_loots"))
				{
					if (iLootsUse[iClient]+1 == MaxCountToGive)
					{
						M_TakeAllLoots(iClient);
						GivePlayerItem(iClient, szWeapon);
						float Pos[3]; GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", Pos);
						EmitAmbientSound("*/murder/pickup_weapon.wav", Pos, iClient, 150)
						CGOPrintToChatAll("%t", "GiveWeaponNoMurder");
					}
					else
					{
						M_GiveLoot(iClient, 1);
					}

					iCountAllLoots--;

					float Pos[3]; GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", Pos);
					EmitAmbientSound("*/murder/pickup_loot.wav", Pos, iClient, 150)

					CGOPrintToChat(iClient, "%t", "PickUpEv");
					RemoveEdict(aim);
				}
			}
		}
	}
	else if(g_InUse[iClient] && !(buttons & IN_USE))
	{
		g_InUse[iClient] = false;
	}

	return Plugin_Continue;
}
public int Native_M_GetCountLootFromMaps(Handle hPlugin, int iNumParams) {
	return iCountAllLoots;
}
public int Native_M_GetCountLoot(Handle hPlugin, int iNumParams) {
	int iClient = GetNativeCell(1);
	return iLootsUse[iClient];
}
public int Native_M_SetCountLoot(Handle hPlugin, int iNumParams) {
	int iClient = GetNativeCell(1);
	int Count = GetNativeCell(2);
	iLootsUse[iClient] = Count;
}

public Action Timer_SpawnClueTimer(Handle timer, any data) {
	static float pos[3];
	FindRandomPosition(pos);
	SpawnClue(pos);
}
public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast) {
	iCountAllLoots=0;for(int i = 1; i <= MaxClients; ++i) {
		if (IsValidClient(i)) {
			iLootsUse[i] = 0;
		}
	}
	
	spawnClueTimer = CreateTimer(fCoolDownCreate, Timer_SpawnClueTimer, _, TIMER_REPEAT);
}
public Action OnRoundEnd(Handle event, const char[] name, bool dontBroadcast) {
	if(spawnClueTimer != null) {
		KillTimer(spawnClueTimer);
		spawnClueTimer = null;
	}
	
	for(int i = 1; i <= MaxClients; ++i) {
		if (IsValidClient(i)) { 
			M_SetCountLoot(i, 0);
		}
	}
}
/*
public void LoadLoots()
{
	char 	szPath[256],
			MapName[64];
	GetCurrentMap(MapName, sizeof(MapName));
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/loot/maps/%s.ini", MapName); KV_LootMaps = new KeyValues("Loots"); KV_LootMaps.ImportFromFile(szPath);
	KV_LootMaps.Rewind();
	KV_LootMaps.GotoFirstSubKey(false)
	PrintToServer("______________[ LogsUpload Loots ]______________");
	while(KV_LootMaps.GotoNextKey(false))
	{
		char 	sSectionName[64];
		float 	fVector[3];
		KV_LootMaps.GetSectionName(sSectionName, sizeof(sSectionName));
		KV_LootMaps.GetVector(NULL_STRING, fVector);
		fPropList_Vector[sizeArrayPropList] 	= fVector;
		szPropList_Models[sizeArrayPropList] 	= sSectionName;
		PrecacheModel(sSectionName);
		AddFileToDownloadsTable(sSectionName);
		PrintToServer("| > #%i [ %s ][[x%.2f][y%.2f][z%.2f]]", sizeArrayPropList, sSectionName, fVector[0], fVector[1], fVector[2])
		sizeArrayPropList++;
	}
	PrintToServer("________________________________________________");
	CreateTimer(fCoolDownCreate, CreateEntRandom, _, TIMER_REPEAT);
}
*/
public Action AddLoot(iClient, Args)
{
	if (Args < 1) {
		CGOPrintToChat(iClient, "%t", "addNoModels");
		return;
	}

	float 	Pos[3];
	char 	Model[256],
			MapName[64],
			szPath[512];
	GetCmdArg(1, Model, sizeof(Model));
	GetClientAbsOrigin(iClient, Pos)
	Pos[2] = Pos[2]+10.0;
	GetCurrentMap(MapName, sizeof(MapName));
	CGOPrintToChat(iClient, "%t", "addLoots");
	CGOPrintToChat(iClient, "{RED}Murder |{DEFAULT} %s | \"%s\" \"%.2f %.2f %.2f\"", MapName, Model, Pos[0], Pos[1], Pos[2]);
	BuildPath(Path_SM, szPath, sizeof(szPath), "configs/murder/loot/maps/%s.ini", MapName);
	//LogToFileEx(szPath, ");
	int 	Prop = CreateEntityByName("prop_dynamic_override");
	float vAngles[3];
	vAngles[1] = 135.0;
	DispatchKeyValue(Prop, 				"model", 		Model);
	DispatchKeyValueVector(Prop, 		"origin", 		Pos);
	DispatchKeyValueVector(Prop, 		"angles", 		vAngles);
	DispatchKeyValue(Prop, 				"solid", 		"6");
	DispatchKeyValue(Prop, 				"targetname", 	"m_loots");

	//SetEntProp(Prop, Prop_Send, "m_iGlowType", 3);
	//SetEntProp(Prop, Prop_Send, "m_glowColorOverride", intRGB(255,255,255));

	SetEntityMoveType(Prop, 			MOVETYPE_NONE);
	DispatchSpawn(Prop);
	AcceptEntityInput(Prop, 			"EnableCollision");
	iCountAllLoots++;
}

//int intRGB(int r, int g, int b){return (r+(g*256)+(b*65536));}
/*
public Action CreateEntRandom(Handle timer)
{
	int 	iRandom = GetRandomInt(0, sizeArrayPropList-1);
	int 	Prop = CreateEntityByName("prop_dynamic_override");
	float vAngles[3];
	vAngles[1] = 135.0;
	DispatchKeyValue(Prop, 				"model", 		szPropList_Models[iRandom]);
	DispatchKeyValueVector(Prop, 		"origin", 		fPropList_Vector[iRandom]);
	DispatchKeyValueVector(Prop, 		"angles", 		vAngles);
	DispatchKeyValue(Prop, 				"solid", 		"6");
	SetEntityMoveType(Prop, 			MOVETYPE_NONE);
	DispatchKeyValue(Prop, 				"targetname", 	"m_loots");

	//SetEntProp(Prop, Prop_Send, "m_iGlowType", 3);
	//SetEntProp(Prop, Prop_Send, "m_glowColorOverride", intRGB(255,255,255));

	DispatchSpawn(Prop);
	AcceptEntityInput(Prop, 			"EnableCollision");

	iCountAllLoots++;
	//PrintToServer("Улика #%i [ %s ][[x%.2f][y%.2f][z%.2f]]",iRandom,szPropList_Models[iRandom],fPropList_Vector[iRandom][0],fPropList_Vector[iRandom][1],fPropList_Vector[iRandom][2])
}
*/
void SpawnClue(float pos[3], float ang[3] = NULL_VECTOR) {
	int ent = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(ent, "model", models[GetRandomInt(0, sizeof models - 1)]);
	DispatchKeyValueVector(ent, "origin", pos);
	if(!IsNullVector(ang)) DispatchKeyValueVector(ent, "angles", ang);
	DispatchKeyValue(ent, "solid", "6");
	SetEntityMoveType(ent, MOVETYPE_NONE);
	DispatchKeyValue(ent, "targetname", "m_loots");
	DispatchSpawn(ent);
	AcceptEntityInput(ent, "EnableCollision");

	iCountAllLoots++;
}

/**
 * @brief Find the random position from the navigation mesh.
 *       
 * @param vPosition         (Optional) The position output.
 * @return                  True on no colission, false otherwise.
 **/
stock bool FindRandomPosition(float vPosition[3]) {
    navPositions.GetArray(GetRandomInt(0, navPositions.Length - 1), vPosition, sizeof vPosition);
    static float vCenter[3]; vCenter = vPosition;
    static const float vMins[3] = { -30.0, -30.0, 0.0   }; 
    static const float vMaxs[3] = {  30.0,  30.0, 30.0  }; 
    vCenter[2] += vMaxs[2] / 2.0; /// Move center of hull upward
    TR_TraceHull(vCenter, vCenter, vMins, vMaxs, MASK_SOLID);
    return !TR_DidHit();
}