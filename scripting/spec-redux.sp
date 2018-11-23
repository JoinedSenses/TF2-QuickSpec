#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2>

#define PLUGIN_VERSION "2.0.0"

int g_iSpecTarget[MAXPLAYERS+1];

public Plugin myinfo = {
	name = "[TF2] Quick Spectate (redux)",
	author = "JoinedSenses",
	description = "Easily target players for spectating.",
	version = PLUGIN_VERSION,
	url = "https://github.com/JoinedSenses"
};

// -------------- SM API

public void OnPluginStart() {
	RegConsoleCmd("sm_spec", cmdSpec, "sm_spec <target> - Spectate a player.", COMMAND_FILTER_NO_IMMUNITY);
	RegConsoleCmd("sm_spec_ex", cmdSpecLock, "sm_spec_ex <target> - Consistently spectate a player, even through their death");
	RegConsoleCmd("sm_speclock", cmdSpecLock, "sm_speclock <target> - Consistently spectate a player, even through their death");

	RegAdminCmd("sm_fspec", cmdForceSpec, ADMFLAG_GENERIC, "sm_fspec <target> <targetToSpec>.");

	HookEvent("player_spawn", eventPlayerSpawn, EventHookMode_Pre);

	LoadTranslations("common.phrases.txt");
}

public void OnClientDisconnect(int client) {
	g_iSpecTarget[client] = 0;
	
	for (int i = 1; i <= MaxClients; i++) {
		if (g_iSpecTarget[i] == client) {
			g_iSpecTarget[i] = 0;
		}
	}
}

// -------------- Commands

public Action cmdSpec(int client, int args) {
	if (!client) {
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
	if (!(target = FindTarget(client, targetName, false, false))) {
		return Plugin_Handled;
	}

	if (GetClientTeam(client) > 1) {
		ChangeClientTeam(client, 1);
	}

	FakeClientCommand(client, "spec_player #%i", GetClientUserId(target));
	FakeClientCommand(client, "spec_mode 1");
	PrintToChat(client, "\x01[\x03Spec\x01] Spectating \x03%N", target);
	return Plugin_Handled;
}

public Action cmdSpecLock(int client, int args) {
	if (!client) {
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
	if (!(target = FindTarget(client, targetName, false, false))) {
		return Plugin_Handled;
	}
	if (GetClientTeam(client) > 1) {
		ChangeClientTeam(client, 1);
		TF2_RespawnPlayer(client);
	}

	FakeClientCommand(client, "spec_player #%i", GetClientUserId(target));
	FakeClientCommand(client, "spec_mode 1");
	PrintToChat(client, "\x01[\x03Spec\x01] Spectating \x03%N", target);

	g_iSpecTarget[client] = target;
	return Plugin_Handled;
}

public Action cmdForceSpec(int client, int args) {
	if (args < 1) {
		PrintToChat(client, "sm_fspec <target> <OPTIONAL:targetToSpec>");
		return Plugin_Handled;
	}
	char targetName[MAX_NAME_LENGTH];
	GetCmdArg(1, targetName, sizeof(targetName));

	int target;
	if ((target = FindTarget(client, targetName, false, false)) < 1) {
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
		Format(targetToSpecName, sizeof(targetToSpecName), "you");
		targetToSpec = client;
	}

	if (GetClientTeam(target) > 1) {
		ChangeClientTeam(target, 1);
		TF2_RespawnPlayer(target);
	}
	FakeClientCommand(target, "spec_player #%i", GetClientUserId(targetToSpec));
	FakeClientCommand(target, "spec_mode 1");
	PrintToChat(client, "\x01[\x03Spec\x01] Forced \x03%N\x01 to spectate \x03%s", target, targetToSpecName);
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
	return Plugin_Continue;
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
	menu.Display(client, MENU_TIME_FOREVER);
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
				TF2_RespawnPlayer(param1);
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
				TF2_RespawnPlayer(param1);
			}
			FakeClientCommand(param1, "spec_player #%i", userid);
			FakeClientCommand(param1, "spec_mode 1");
			PrintToChat(param1, "\x01[\x03Spec\x01] Spectating \x03%N", target);
			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
			return 0;
		}
		case MenuAction_DrawItem: {
			char targetid[6];
			menu.GetItem(param2, targetid, sizeof(targetid));
			int target = GetClientOfUserId(StringToInt(targetid));
			if (IsClientObserver(param1) && GetEntPropEnt(param1, Prop_Send, "m_hObserverTarget") == target) {
				return ITEMDRAW_DISABLED;
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_Exit) {
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
			if ((target = GetClientOfUserId(userid)) == 0) {
				PrintToChat(param1, "\x01[\x03Spec\x01] Player no longer in game");
				menuSpec(param1);
				delete menu;
				return 0;
			}
			if (GetClientTeam(param1) > 1) {
				ChangeClientTeam(param1, 1);
				TF2_RespawnPlayer(param1);
			}
			FakeClientCommand(param1, "spec_player #%i", userid);
			FakeClientCommand(param1, "spec_mode 1");
			PrintToChat(param1, "\x01[\x03Spec\x01] Spectating \x03%N", target);
			g_iSpecTarget[param1] = target;
			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
			return 0;
		}
		case MenuAction_DrawItem: {
			char targetid[6];
			menu.GetItem(param2, targetid, sizeof(targetid));
			int target = GetClientOfUserId(StringToInt(targetid));
			if (IsClientObserver(param1) && GetEntPropEnt(param1, Prop_Send, "m_hObserverTarget") == target) {
				return ITEMDRAW_DISABLED;
			}
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_Exit) {
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