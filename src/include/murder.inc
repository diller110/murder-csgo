#if defined _murder_included_
   #endinput 
#endif 
#define _murder_included_

enum Murder_Role {
	Murder_Unknown = -1,
	Murder_Crewmate,
	Murder_Imposter,
	Murder_Officer
}

enum Murder_State {
	Murder_Disabled = -1,
	Murder_InProgress = 1,
}

native Murder_State Murder_GetState(); 
native Murder_Role Murder_GetClientRole(int client);


//		Murder - Loots 	| murder_loots.smx

native int M_GetCountLoot(int client);					// Вернет количество подобранных улик
native int M_SetCountLoot(int client, int iCount); 	// Установит указанное количество улик
native int M_GetCountLoots();							// Вернет количество улик на карте
public void M_GiveLoot(int client, int Count) { // Выдать определенное количество улик
	int iCounts = M_GetCountLoot(client);
	M_SetCountLoot(client, iCounts+Count);
} 	
public void M_TakeLoot(int client, int Count) { // Отнять определенное количество улик
	int iCounts = M_GetCountLoot(client);
	M_SetCountLoot(client, iCounts-Count);
}	
public void M_TakeAllLoots(int client) { // Отнять все улики у игрока
	M_SetCountLoot(client, 0);
}															

// 					Основное

stock bool CheckDistance(int client, int attacker, int distance) {
	float cd, ad;
	GetClientAbsOrigin(client, cd);
	GetClientAbsOrigin(attacker, ad);
	int cDistance = GetVectorDistance(cd, ad);
	if (cDistance <= distance){
		return true
	} else {
		return false;
	}
}
public bool TraceEntityFilterSolid(int entity, int contentsMask) {
	return entity > 1;
}
stock bool IsValidClient(int client) {
	if (client <= 0 || client > MaxClients) return false;
	if (!IsClientInGame(client) || !IsClientConnected(client)) return false;
	return true;
}