#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2_stocks>
#include <sdktools>

#define PLUGIN_VERSION "2.1.0"
#define PLUGIN_DESCRIPTION "Easily target players for spectating."

enum {
	SAVE_NONE = 1,
	SAVE_RED,
	SAVE_BLUE
}

bool
	  g_bRestoring[MAXPLAYERS+1];
int
	  g_iSpecTarget[MAXPLAYERS+1]
	, g_iSaveTeam[MAXPLAYERS+1] = { SAVE_NONE, ...};
float
	  g_fSaveOrigin[MAXPLAYERS+1][3]
	, g_fSaveAngles[MAXPLAYERS+1][3];
ConVar
	  cvarVersion
	, cvarRestoreEnabled
	, cvarRestoreTimer
	, cvarAllowForceBot;

public Plugin myinfo =  {
	name = "[TF2] Quick Spectate (redux)",
	author = "JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://github.com/JoinedSenses"
};

// -------------- SM API

public void OnPluginStart() {
	cvarVersion = CreateConVar("sm_spec_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_NOTIFY|FCVAR_DONTRECORD);
	cvarRestoreEnabled = CreateConVar("sm_spec_restoreenabled", "0", "Enable location restoration pre-forcespec?", FCVAR_NONE, true, 0.0, true, 1.0);
	cvarRestoreTimer = CreateConVar("sm_spec_restoretimer", "5.0", "Time until restoration after respawning", FCVAR_NONE, true, 0.0);
	cvarAllowForceBot = CreateConVar("sm_spec_allowforcebot", "0", "Enable the use of force spec commands on bots?", FCVAR_NONE);
	cvarVersion.SetString(PLUGIN_VERSION);

	RegConsoleCmd("sm_spec", cmdSpec, "sm_spec <target> - Spectate a player.", COMMAND_FILTER_NO_IMMUNITY);
	RegConsoleCmd("sm_spec_ex", cmdSpecLock, "sm_spec_ex <target> - Consistently spectate a player, even through their death");
	RegConsoleCmd("sm_speclock", cmdSpecLock, "sm_speclock <target> - Consistently spectate a player, even through their death");

	RegAdminCmd("sm_fspec", cmdForceSpec, ADMFLAG_GENERIC, "sm_fspec <target> <targetToSpec>.");
	RegAdminCmd("sm_fspecstop", cmdForceSpecStop, ADMFLAG_GENERIC, "sm_fspecstop <target>");

	AddCommandListener(listenerJoinTeam, "jointeam");

	HookEvent("player_spawn", eventPlayerSpawn);

	LoadTranslations("common.phrases.txt");
}

public void OnClientDisconnect(int client) {
	g_iSpecTarget[client] = 0;
	g_iSaveTeam[client] = SAVE_NONE;

	for (int i = 1; i <= MaxClients; i++) {
		if (g_iSpecTarget[i] == client) {
			g_iSpecTarget[i] = 0;
		}
	}
}

// -------------- Commands

public Action cmdSpec(int client, int args) {
	if (client < 1) {
		ReplyToCommand(client, "Must be in-game to use this command");
		return Plugin_Handled;
	}

	if (args < 1) {
		menuSpec(client);
		return Plugin_Handled;
	}

	char targetName[MAX_NAME_LENGTH];
	GetCmdArg(1, targetName, sizeof(targetName));
	int target;
	if ((target = FindTarget(client, targetName, false, false)) < 1) {
		return Plugin_Handled;
	}

	if (target == client) {
		PrintToChat(client, "\x01[\x03Spec\x01] Unable to spectate yourself. That would be pretty weird.");
		return Plugin_Handled;
	}

	bool isInSpec;
	if (IsClientObserver(target)) {
		target = GetEntPropEnt(target, Prop_Send, "m_hObserverTarget");
		if (target < 1) {
			PrintToChat(client, "\x01[\x03Spec\x01] Target is in spec, but not spectating anyone.");
			return Plugin_Handled;
		}
		if (target == client) {
			PrintToChat(client, "\x01[\x03Spec\x01] Target is spectating you. Unable to spectate");
			return Plugin_Handled;
		}
		PrintToChat(client, "\x01[\x03Spec\x01] Target is in spec. Now spectating their target", target);
		isInSpec = true;
	}

	if (GetClientTeam(client) > 1) {
		ChangeClientTeam(client, 1);
	}

	if (!isInSpec) {
		PrintToChat(client, "\x01[\x03Spec\x01] Spectating \x03%N", target);
	}

	FakeClientCommand(client, "spec_player #%i", GetClientUserId(target));
	FakeClientCommand(client, "spec_mode 1");
	return Plugin_Handled;
}

public Action cmdSpecLock(int client, int args) {
	if (client < 1) {
		ReplyToCommand(client, "Must be in-game to use this command");
		return Plugin_Handled;
	}
	if (args < 1) {
		menuSpec(client, true);
		return Plugin_Handled;
	}

	char targetName[MAX_NAME_LENGTH];
	GetCmdArg(1, targetName, sizeof(targetName));

	if (StrEqual(targetName, "off", false) || StrEqual(targetName, "0", false)) {
		g_iSpecTarget[client] = 0;
		PrintToChat(client, "\x01[\x03Spec\x01] Spec lock disabled");
		return Plugin_Handled;
	}

	int target;
	if ((target = FindTarget(client, targetName, false, false)) < 1) {
		return Plugin_Handled;
	}

	if (target == client) {
		PrintToChat(client, "\x01[\x03Spec\x01] Unable to spectate yourself. That would be pretty weird.");
		return Plugin_Handled;
	}

	if (IsClientObserver(target)) {
		PrintToChat(client, "\x01[\x03Spec\x01] Target is in spec, will resume with spec when they spawn.");
		PrintToChat(client, "\x01[\x03Spec\x01] To disable, type\x03 /speclock 0");
	}

	if (GetClientTeam(client) > 1) {
		ChangeClientTeam(client, 1);
	}

	FakeClientCommand(client, "spec_player #%i", GetClientUserId(target));
	FakeClientCommand(client, "spec_mode 1");
	PrintToChat(client, "\x01[\x03Spec\x01] Spectating \x03%N", target);

	g_iSpecTarget[client] = target;
	return Plugin_Handled;
}

public Action cmdForceSpec(int client, int args) {
	if (client < 1) {
		ReplyToCommand(client, "Must be in-game to use this command");
		return Plugin_Handled;
	}
	if (args < 1) {
		PrintToChat(client, "sm_fspec <target> <OPTIONAL:targetToSpec>");
		return Plugin_Handled;
	}

	char targetName[MAX_NAME_LENGTH];
	GetCmdArg(1, targetName, sizeof(targetName));

	int target;
	if ((target = FindTarget(client, targetName, !cvarAllowForceBot.BoolValue, false)) < 1) {
		return Plugin_Handled;
	}

	char targetToSpecName[MAX_NAME_LENGTH];
	int targetToSpec;
	if (args == 2) {
		GetCmdArg(2, targetToSpecName, sizeof(targetToSpecName));
		if ((targetToSpec = FindTarget(client, targetToSpecName, false, false)) < 1) {
			return Plugin_Handled;
		}
		Format(targetToSpecName, sizeof(targetToSpecName), "%N", targetToSpec);
	}
	else {
		if (target == client) {
			PrintToChat(client, "\x01[\x03Spec\x01] Unable to spectate yourself. That would be pretty weird.");
			return Plugin_Handled;
		}
		Format(targetToSpecName, sizeof(targetToSpecName), "you");
		targetToSpec = client;
	}

	if (target == targetToSpec) {
		PrintToChat(client, "\x01[\x03Spec\x01] Can't force someone to spectate themselves. That would be weird.");
		return Plugin_Handled;
	}
	if (IsClientObserver(targetToSpec)) {
		PrintToChat(client, "\x01[\x03Spec\x01] Target\x03 %N\x01 must be alive.", targetToSpec);
		return Plugin_Handled;
	}

	int team;
	if ((team = GetClientTeam(target)) > 1) {
		if (cvarRestoreEnabled.BoolValue) {
			GetClientAbsOrigin(target, g_fSaveOrigin[target]);
			GetClientAbsAngles(target, g_fSaveAngles[target]);
			g_iSaveTeam[target] = team;
			PrintToChat(target, "\x01[\x03Spec\x01]\x03 Saving\x01 pre-spec state.");
		}
		ChangeClientTeam(target, 1);
	} 

	FakeClientCommand(target, "spec_player #%i", GetClientUserId(targetToSpec));
	FakeClientCommand(target, "spec_mode 1");
	PrintToChat(client, "\x01[\x03Spec\x01] Forced\x03 %N\x01 to spectate\x03 %s", target, targetToSpecName);
	PrintToChat(target, "\x01[\x03Spec\x01] You were forced to spectate\x03 %N", targetToSpec);
	return Plugin_Handled;
}

public Action cmdForceSpecStop(int client, int args) {
	if (client == 0) {
		ReplyToCommand(client, "Must be in-game to use this command");
		return Plugin_Handled;
	}
	if (args < 1) {
		PrintToChat(client, "sm_fspecstop <target>");
		return Plugin_Handled;
	}

	char targetName[MAX_NAME_LENGTH];
	GetCmdArg(1, targetName, sizeof(targetName));

	int target;
	if ((target = FindTarget(client, targetName, !cvarAllowForceBot.BoolValue, false)) < 1) {
		return Plugin_Handled;
	}

	int saveTeam;
	if ((saveTeam = g_iSaveTeam[target]) == SAVE_NONE || !IsClientObserver(target)) {
		PrintToChat(client, "\x01[\x03Spec\x01] Unable to restore\x03 %N\x01's state.", target);
		return Plugin_Handled;
	}

	ChangeClientTeam(target, saveTeam);
	PrintToChat(client, "\x01[\x03Spec\x01]\x03 %N\x01 returned to %s team", target, (saveTeam == SAVE_RED)?"red":"blue");

	return Plugin_Handled;
}

// -------------- Events

public Action eventPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	for (int i = 1; i <= GetMaxClients(); i++) {
		if (g_iSpecTarget[i] == client) {
			FakeClientCommand(i, "spec_player #%i", GetClientUserId(client));
			FakeClientCommand(i, "spec_mode 1");
		}
	}

	if (!cvarRestoreEnabled.BoolValue
	|| !cvarAllowForceBot.BoolValue && IsFakeClient(client)
	|| g_iSaveTeam[client] == SAVE_NONE
	|| g_bRestoring[client]) {
		return Plugin_Continue;
	}

	float seconds;
	if ((seconds = cvarRestoreTimer.FloatValue) >= 0.0) {
		g_bRestoring[client] = true;

		PrintToChat(client, "\x01[\x03Spec\x01]\x03 Restoring\x01 pre-spec location in\x03 %0.1f\x01 seconds", seconds);
		CreateTimer(cvarRestoreTimer.FloatValue, timerRestore, GetClientUserId(client));
	}

	return Plugin_Continue;
}

public Action listenerJoinTeam(int client, const char[] command, int args) {
	if (g_bRestoring[client]) {
		PrintToChat(client, "\x01[\x03Spec\x01] Can't change team while restoring location");
		return Plugin_Handled;
	}
	if (TF2_GetPlayerClass(client) == TFClass_Unknown) {
		return Plugin_Continue;
	}
	int newTeam;
	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));
	if (StrEqual(arg, "spectate", false)) {
		newTeam = SAVE_NONE;
	}
	else if (StrEqual(arg, "red", false)) {
		newTeam = SAVE_RED;
	}
	else if (StrEqual(arg, "blue", false)) {
		newTeam = SAVE_BLUE;
	}
	else if ((StrEqual(arg, "auto", false))) {
		return Plugin_Handled;
	}
	else {
		return Plugin_Handled;
	}
	if (g_iSaveTeam[client] != SAVE_NONE) {
		newTeam = g_iSaveTeam[client];
	}
	DataPack dp = new DataPack();
	dp.WriteCell(client);
	dp.WriteCell(newTeam);
	RequestFrame(framerequestChangeTeam, dp);
	return Plugin_Handled;
}

// -------------- Timers

void framerequestChangeTeam(DataPack dp) {
	dp.Reset();
	int client = dp.ReadCell();
	int team = dp.ReadCell();
	delete dp;
	//if (GetClientTeam(client) < 2) {
	SetEntProp(client, Prop_Send, "m_lifeState", 1);
	//}
	ChangeClientTeam(client, team);
}

Action timerRestore(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (client < 1) {
		return Plugin_Handled;
	}
	if (GetClientTeam(client) != g_iSaveTeam[client]) {
		PrintToChat(client, "\x01[\x03Spec\x01] Restoration\x03 cancelled\x01: Unexpected team change.");
	}
	else {
		TeleportEntity(client, g_fSaveOrigin[client], g_fSaveAngles[client], NULL_VECTOR);
		PrintToChat(client, "\x01[\x03Spec\x01] Your location has been restored");		
	}
	g_bRestoring[client] = false;
	g_iSaveTeam[client] = SAVE_NONE;
	return Plugin_Handled;
}

// -------------- Menus

void menuSpec(int client, bool lock = false) {
	Menu menu = new Menu(lock ? menuHandler_SpecLock : menuHandler_Spec, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem);
	menu.SetTitle("Spectate Menu");

	if (GetClientTeam(client) > 1 && !lock) {
		menu.AddItem("", "QUICK SPEC");
	}
	if (lock && g_iSpecTarget[client] > 0) {
		menu.AddItem("", "DISABLE LOCK");
	}

	int id;
	char userid[6];
	char clientName[MAX_NAME_LENGTH];
	for (int i = 1; i <= MaxClients; i++) {
		if ((id = isValidClient(i)) > 0 && client != i) {
			Format(userid, sizeof(userid), "%i", id);
			Format(clientName, sizeof(clientName), "%N", i);
			menu.AddItem(userid, clientName);
		}
	}
	if (menu.ItemCount > 0) {
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else {
		PrintToChat(client, "\x01[\x03Spec\x01] No targets to add to menu.");
		delete menu;
	}
}

int menuHandler_Spec(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char targetid[6];
			menu.GetItem(param2, targetid, sizeof(targetid));
			int userid = StringToInt(targetid);
			int target;
			if (userid == 0) {
				ChangeClientTeam(param1, 1);
				PrintToChat(param1, "\x01[\x03Spec\x01] Sent to spec");
				delete menu;
				return 0;
			}
			if ((target = GetClientOfUserId(userid)) == 0) {
				PrintToChat(param1, "\x01[\x03Spec\x01] Player no longer in game");
				menuSpec(param1);
				delete menu;
				return 0;
			}
			if (GetClientTeam(param1) > 1) {
				ChangeClientTeam(param1, 1);
			}
			FakeClientCommand(param1, "spec_player #%i", userid);
			FakeClientCommand(param1, "spec_mode 1");
			PrintToChat(param1, "\x01[\x03Spec\x01] Spectating \x03%N", target);
			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
		}
		case MenuAction_DrawItem: {
			char targetid[6];
			menu.GetItem(param2, targetid, sizeof(targetid));
			int target = GetClientOfUserId(StringToInt(targetid));
			if (IsClientObserver(param1) && GetEntPropEnt(param1, Prop_Send, "m_hObserverTarget") == target) {
				return ITEMDRAW_DISABLED;
			}
			return ITEMDRAW_DEFAULT;
		}
		case MenuAction_End: {
			if (param2 != MenuEnd_Selected) {
				delete menu;
			}
		}
	}
	return 0;
}

int menuHandler_SpecLock(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char targetid[6];
			menu.GetItem(param2, targetid, sizeof(targetid));
			int userid = StringToInt(targetid);
			int target;
			if (userid == 0) {
				g_iSpecTarget[param1] = 0;
				PrintToChat(param1, "\x01[\x03Spec\x01] Spec lock is now disabled");
				delete menu;
				return 0;
			}
			if ((target = GetClientOfUserId(userid)) < 0) {
				PrintToChat(param1, "\x01[\x03Spec\x01] Player no longer in game");
				menuSpec(param1);
				delete menu;
				return 0;
			}
			if (GetClientTeam(param1) > 1) {
				ChangeClientTeam(param1, 1);
			}
			FakeClientCommand(param1, "spec_player #%i", userid);
			FakeClientCommand(param1, "spec_mode 1");
			PrintToChat(param1, "\x01[\x03Spec\x01] Spectating \x03%N", target);
			g_iSpecTarget[param1] = target;
			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
		}
		case MenuAction_DrawItem: {
			char targetid[6];
			menu.GetItem(param2, targetid, sizeof(targetid));
			int target = GetClientOfUserId(StringToInt(targetid));
			if (IsClientObserver(param1) && GetEntPropEnt(param1, Prop_Send, "m_hObserverTarget") == target) {
				return ITEMDRAW_DISABLED;
			}
		}
		case MenuAction_End: {
			if (param2 != MenuEnd_Selected) {
				delete menu;
			}
		}
	}
	return 0;
}

// -------------- Stocks

int isValidClient(int client) {
	if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
		return 0;
	}
	return GetClientUserId(client);
}