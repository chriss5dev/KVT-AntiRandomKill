#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <treason>
#include <clientprefs>

Handle g_hRdmCookie;
int g_RdmScore[MAXPLAYERS + 1];
int g_CurrentlyDyingClient = 0;
int g_CurrentlyKillingClient = 0;
char g_InflictorName[32];
bool g_InCombat[MAXPLAYERS + 1];
ConVar g_cvWarnScore;
ConVar g_cvPunishScore;
ConVar g_cvBanScore;
ConVar g_cvBanTime;
ConVar g_cvForgiveAmount;
ConVar g_cvPunishAmount;
ConVar g_cvPunishConfirmedInStages;
//ConVar g_cvStartPunishTime;
ConVar g_cvCombatCheckEnabled;
ConVar g_cvCombatCheckThreshold;
ConVar g_cvCombatCheckTime;
ConVar g_cvIgnoreGasNade;
ConVar g_cvIgnoreNade;
ConVar g_cvIgnoreBomb;
char nameBuffer[32];
char g_BoomSound[PLATFORM_MAX_PATH];
int g_ExplosionSprite = -1;
treasonRole g_KillerRole = TR_None;
treasonRole g_VictimRole = TR_None;
int g_KillerTeam = 0;
int g_VictimTeam = 0;
 
public Plugin myinfo =
{
	name = "AntiRandomKill",
	author = "chriss5",
	description = "Punishes random-killing in Treason.",
	version = "1.0",
	url = "https://github.com/chriss5dev/KVT-AntiRandomKill"
};

public void OnPluginStart()
{
	// register cookie
	g_hRdmCookie = RegClientCookie("treason_rdm_score", "Player random-kill score", CookieAccess_Private);
	
	CreateConVars();
	
	//hooks
	//HookEvent("round_start", E_RoundStart);
	//HookEvent("preround_start", E_PreRoundStart);
	HookEvent("player_death", E_PlayerDeath, EventHookMode_Pre);
	HookEvent("player_death", E_PlayerDeath_Post, EventHookMode_Post);
	
	//cmds
	RegAdminCmd("sm_forgiveall", CmdForgive, ADMFLAG_ROOT);
	RegConsoleCmd("sm_rdm", CmdCheckScore);
	//RegAdminCmd("sm_testrdm", CmdTestRdm, ADMFLAG_ROOT);
}

public void OnMapStart()
{
	LoadAllTranslations();
	
	GameData gameConfig = new GameData("explosions");
	if (gameConfig == null)
	{
		SetFailState("Unable to load game config explosions");
		return;
	}
	if (gameConfig.GetKeyValue("SoundBoom", g_BoomSound, sizeof(g_BoomSound)) && g_BoomSound[0])
	{
		char fullPath[PLATFORM_MAX_PATH];
		FormatEx(fullPath, sizeof(fullPath), "sound/%s", g_BoomSound);
		
		PrecacheSound(g_BoomSound, true);
		AddFileToDownloadsTable(fullPath);
	}
	char buffer[PLATFORM_MAX_PATH];
	if (gameConfig.GetKeyValue("SpriteExplosion", buffer, sizeof(buffer)) && buffer[0])
	{
		g_ExplosionSprite = PrecacheModel(buffer);
	}
	delete gameConfig;
}

public void LoadAllTranslations()
{
	LoadTranslations("antirdm.phrases.txt");
	LoadTranslations("es/antirdm.phrases.txt");
}

public void CreateConVars()
{
	//score thresholds
	g_cvWarnScore = CreateConVar("t_rdm_score_warn", "6", "Score at which a user will be warned by notification messages.", _, true, 1.0);
	g_cvPunishScore = CreateConVar("t_rdm_score_punish", "9", "Score at which a user will be punished.", _, true, 1.0);
	g_cvBanScore = CreateConVar("t_rdm_score_ban", "12", "Score at which a user will be banned for a specified amount of time.", _, true, 1.0);
	//score amounts
	g_cvForgiveAmount = CreateConVar("t_rdm_amount_forgive", "2", "The amount of score to remove from a user that makes correct kills, whether intentional or not. -1 means reset score.", _, true, -1.0);
	g_cvPunishAmount = CreateConVar("t_rdm_amount_punish", "3", "The amount of score to add to a user that makes incorrect kills, whether intentional or not.", _, true, 0.0);
	//combat/aggression checking
	g_cvCombatCheckEnabled = CreateConVar("t_rdm_combat_enabled", "0", "When set to 1, attackers are marked as in-combat for a specified amount of time. Players that are in-combat will not be counted as an RDM if killed, due to self-defense.", _, true, 0.0);
	g_cvCombatCheckThreshold = CreateConVar("t_rdm_combat_mindmg", "50", "The minimum damage at which an attacker will be marked as in-combat.", _, true, 1.0);
	g_cvCombatCheckTime = CreateConVar("t_rdm_combat_time", "5", "How long attackers will be marked as in-combat, in seconds.", _, true, 0.5);
	//dmg sources to be ignored
	g_cvIgnoreGasNade = CreateConVar("t_rdm_ignore_gasnade", "1", "When set to 1, kills from gas grenades will not count towards RDM score.", _, true, 0.0);
	g_cvIgnoreNade = CreateConVar("t_rdm_ignore_henade", "1", "When set to 1, kills from high-explosive grenades will not count towards RDM score.", _, true, 0.0);
	g_cvIgnoreBomb = CreateConVar("t_rdm_ignore_bomb", "1", "When set to 1, kills from bombs will not count towards RDM score.", _, true, 0.0);
	//misc
	g_cvBanTime = CreateConVar("t_rdm_bantime", "10", "Time (in minutes) to ban users that surpass the ban score. 0 means permanent.", _, true, 0.0);
	g_cvPunishConfirmedInStages = CreateConVar("t_rdm_punish_confirmed_in_stages", "1", "When set to 1, confirmed roles that teamkill other confirmed roles will skip extra score levels and have their score set straight to the next stage. Default -> Warn -> Punish -> Ban", _, true, 0.0, true, 1.0);
	//g_cvStartPunishTime = CreateConVar("t_rdm_roundstart_time", "3", "0 means disabled. Seconds after the Don's body is found during which non-traitors will be immediately punished for killing. This is intended to prevent immediate RDM on round start, as it is unreasonable someone would know whether who the traitor is within 1-5 seconds.", _, true, 0.0, true, 30.0);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}

public void OnClientCookiesCached(int client)
{
    char value[PLATFORM_MAX_PATH];
    GetClientCookie(client, g_hRdmCookie, value, sizeof(value));
	if (value[0] != '\0')
    {
		int score = StringToInt(value);
		
		if(score < 0)
		{SetClientScore(client, 0);}
		else
		{g_RdmScore[client] = score;}
    }
	else
	{
		// apply default score 0
        g_RdmScore[client] = 0;
		SetClientCookie(client, g_hRdmCookie, "0");
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	// If the hit is going to kill them, store the victim index
    if (damage >= GetClientHealth(victim) && victim != 0 && attacker != 0)
    {
        g_CurrentlyDyingClient = victim;
		g_CurrentlyKillingClient = attacker;
		if(!GetEntityClassname(inflictor, g_InflictorName, sizeof(g_InflictorName)))
		{
			g_InflictorName = "invalid";
			LogError("[AntiRandomKill] GetEntityClassname of inflictor failed!");
		}
    }
	
	// If the hit is above or equal to the CombatCheckThreshold, mark the attacker as "InCombat"
	if (g_cvCombatCheckEnabled.IntValue == 1 && damage >= g_cvCombatCheckThreshold.IntValue && victim > 0 && attacker > 0 && IsClientInGame(victim) && IsClientInGame(attacker))
    {
		MarkClientInCombat(attacker);
    }
	
	return Plugin_Continue;
}

public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	// If the hit is going to kill them, store the victim index
    if (damage >= GetClientHealth(victim) && victim != 0 && attacker != 0)
    {
        g_CurrentlyDyingClient = victim;
		g_CurrentlyKillingClient = attacker;
		
		//also mark killing shots as in combat
		MarkClientInCombat(attacker);
    }
	
	// If the hit is above or equal to the CombatCheckThreshold, mark the attacker as "InCombat"
	if (damage >= g_cvCombatCheckThreshold.IntValue && victim > 0 && attacker > 0 && IsClientInGame(victim) && IsClientInGame(attacker))
    {
		MarkClientInCombat(attacker);
    }
}

public Action E_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if((g_CurrentlyKillingClient > 0 && g_CurrentlyKillingClient < MAXPLAYERS + 2) && (g_CurrentlyDyingClient > 0 && g_CurrentlyDyingClient < MAXPLAYERS + 2) && IsClientInGame(g_CurrentlyKillingClient) && IsClientInGame(g_CurrentlyDyingClient))
	{
		g_KillerRole = GetClientRole(g_CurrentlyKillingClient);
		g_VictimRole = GetClientRole(g_CurrentlyDyingClient);
		
		switch(g_KillerRole)
		{
			case TR_None: g_KillerTeam = 0;
			case TR_Innocent,TR_Detective,TR_Doctor: g_KillerTeam = 1;
			case TR_Traitor: g_KillerTeam = 2;
			default: g_KillerTeam = 0;
		}
		switch(g_VictimRole)
		{
			case TR_None: g_VictimTeam = 0;
			case TR_Innocent,TR_Detective,TR_Doctor: g_VictimTeam = 1;
			case TR_Traitor: g_VictimTeam = 2;
			default: g_VictimTeam = 0;
		}
	}
	return Plugin_Continue;
}

public void E_PlayerDeath_Post(Event event, const char[] name, bool dontBroadcast)
{
	// not suicide and actually players
	if(g_CurrentlyKillingClient != 0 && g_CurrentlyDyingClient != 0 && g_CurrentlyDyingClient != g_CurrentlyKillingClient && IsClientInGame(g_CurrentlyKillingClient) && IsClientInGame(g_CurrentlyDyingClient))
	{
		if(g_KillerTeam + g_VictimTeam > 1 // both have to be at least 1, this means sum is greater than 1 if valid
		&& g_KillerTeam == g_VictimTeam) // if killer and victim are both innocent or both traitor
		{
			//if they are both traitor
			if(g_KillerTeam == 2 
			|| 	(
					//or both are special innocent
					(g_KillerRole == TR_Doctor || g_KillerRole == TR_Detective)
					&& (g_VictimRole == TR_Doctor || g_VictimRole == TR_Detective)
				)
			&&	(g_cvPunishConfirmedInStages.IntValue == 1)
			)
			// rdm confirmed
			{ ClientConfirmedRDM(g_CurrentlyKillingClient); }
			// rdm unconfirmed
			else 
			{
				if(g_cvCombatCheckEnabled.IntValue == 0 || !g_InCombat[g_CurrentlyKillingClient])
				{
					ClientRDM(g_CurrentlyKillingClient);
				}
			}
		}
		else if(g_KillerTeam + g_VictimTeam > 1 // both have to be at least 1, this means sum is greater than 1 if valid
		&& g_KillerTeam != g_VictimTeam) // if killer and victim are opposite role teams
		{
			ClientForgive(g_CurrentlyKillingClient);
		}
	}
	g_CurrentlyDyingClient = 0;
	g_CurrentlyKillingClient = 0;
}

public void ClientRDM(int client)
{
	g_CurrentlyDyingClient = 0;
	g_CurrentlyKillingClient = 0;
	int warnScore = g_cvWarnScore.IntValue;
	int punishScore = g_cvPunishScore.IntValue;
	int banScore = g_cvBanScore.IntValue;
	int banTime = g_cvBanTime.IntValue;
	int newScore = g_RdmScore[client] + g_cvPunishAmount.IntValue;
	GetClientName(client, nameBuffer, sizeof(nameBuffer));
	
	bool allow = true;
	if (g_cvIgnoreGasNade.IntValue == 1 && StrEqual(g_InflictorName, "gasnade_projectile", false))
	{
		allow = false;
		return;
	}
	if (g_cvIgnoreNade.IntValue == 1 && StrEqual(g_InflictorName, "henade_projectile", false))
	{
		allow = false;
		return;
	}
	if (g_cvIgnoreBomb.IntValue == 1 
		&& (
		StrEqual(g_InflictorName, "env_explosion", false))
		|| StrEqual(g_InflictorName, "env_fire", false)
		|| StrEqual(g_InflictorName, "trigger_hurt", false)
	)
	{
		allow = false;
		return;
	}

	// if score is now at or above the ban level
	if (allow && newScore >= banScore)
	{
		//ban
		SetClientScore(client, 0); // reset score to 0 because they got freaking BANNED
		TextBan();
		if(banTime == 0)
		{
			char message[128];
			Format(message, sizeof(message), "%T", "BannedForever", client);
			BanClient(client, banTime, BANFLAG_AUTO, "Random-Killing", message);
		}
		else if(banTime < 60)
		{
			char message[128];
			Format(message, sizeof(message), "%T", "BannedForMinutes", client, banTime);
			BanClient(client, banTime, BANFLAG_AUTO, "Random-Killing", message);
		}
		else if(banTime < 1440)
		{
			char message[128];
			Format(message, sizeof(message), "%T", "BannedForHours", client, banTime);
			BanClient(client, banTime, BANFLAG_AUTO, "Random-Killing", message);
		}
		else if(banTime >= 1440)
		{
			char message[128];
			Format(message, sizeof(message), "%T", "BannedForDays", client, banTime);
			BanClient(client, banTime, BANFLAG_AUTO, "Random-Killing", message);
		}
	}
	// if score is now at or above the punishment level
	else if (allow && newScore >= punishScore)
	{
		//punish
		SetClientScore(client, newScore); // accept new score
		TextPunishment(client);
		ExplodeClient(client);
	}
	// if score is now at or above the warning level
	else if(allow && newScore >= warnScore)
	{
		//warning
		SetClientScore(client, newScore); // accept new score
		TextWarning(client);
	}
	else if(allow)
	{
		//nothing
		SetClientScore(client, newScore); // accept new score
	}
}

public void ClientConfirmedRDM(int client)
{
	g_CurrentlyDyingClient = 0;
	g_CurrentlyKillingClient = 0;
	int warnScore = g_cvWarnScore.IntValue;
	int punishScore = g_cvPunishScore.IntValue;
	int banScore = g_cvBanScore.IntValue;
	int banTime = g_cvBanTime.IntValue;
	int score = g_RdmScore[client];
	GetClientName(client, nameBuffer, sizeof(nameBuffer));

	bool allow = true;
	if (g_cvIgnoreGasNade.IntValue == 1 && StrEqual(g_InflictorName, "gasnade_projectile", false))
	{
		allow = false;
		return;
	}
	if (g_cvIgnoreNade.IntValue == 1 && StrEqual(g_InflictorName, "henade_projectile", false))
	{
		allow = false;
		return;
	}
	if (g_cvIgnoreBomb.IntValue == 1 
		&& (
		StrEqual(g_InflictorName, "env_explosion", false))
		|| StrEqual(g_InflictorName, "env_fire", false)
		|| StrEqual(g_InflictorName, "trigger_hurt", false)
	)
	{
		allow = false;
		return;
	}

	// if score is now at or above the warning level
	if(allow && score < warnScore)
	{
		//warning
		SetClientScore(client, warnScore); // accept new score
		TextWarning(client);
	}
	// if score is now at or above the punishment level
	else if (allow && score < punishScore)
	{
		//punish
		SetClientScore(client, punishScore); // accept new score
		TextPunishment(client);
		ExplodeClient(client);
	}
	// if score is now at or above the ban level
	else if (allow && score < banScore)
	{
		//ban
		SetClientScore(client, 0); // reset score to 0 because they got freaking BANNED
		TextBan();
		if(banTime == 0)
		{
			char message[128];
			Format(message, sizeof(message), "%T", "BannedForever", client);
			BanClient(client, banTime, BANFLAG_AUTO, "Random-Killing", message);
		}
		else if(banTime < 60)
		{
			char message[128];
			Format(message, sizeof(message), "%T", "BannedForMinutes", client, banTime);
			BanClient(client, banTime, BANFLAG_AUTO, "Random-Killing", message);
		}
		else if(banTime < 1440)
		{
			char message[128];
			Format(message, sizeof(message), "%T", "BannedForHours", client, banTime);
			BanClient(client, banTime, BANFLAG_AUTO, "Random-Killing", message);
		}
		else if(banTime >= 1440)
		{
			char message[128];
			Format(message, sizeof(message), "%T", "BannedForDays", client, banTime);
			BanClient(client, banTime, BANFLAG_AUTO, "Random-Killing", message);
		}
	}
	else if(allow)
	{
		//score > banScore
		SetClientScore(client, 0); // reset score
	}
}

public void ClientForgive(int client)
{
	int forgiveAmount = g_cvForgiveAmount.IntValue;
	
	if(forgiveAmount == -1)
	{ 
		SetClientScore(client, 0);
	}
	else
	{
		int newScore = g_RdmScore[client] - g_cvForgiveAmount.IntValue;
		if(newScore < 0)
		{SetClientScore(client, 0);}
		else
		{SetClientScore(client, newScore);}
	}
}

// HUD TEXTS

public void TextWarning(int client)
{
	char warningPunish[128];
	Format(warningPunish, sizeof(warningPunish), "%T", "WarningPunish", client);
	
	SetHudTextParams(ABOVECENTERTEXT_X, ABOVECENTERTEXT_Y, 7.0, 255, 255, 0, 255);
	ShowHudText(client, AUTO_CHANNEL, warningPunish);
	PrintToChatAll("Client language: %d", GetClientLanguage(client));
	TextNotifyRDMCommand();
}

public void TextPunishment(int client)
{
	char warningBan[128];
	Format(warningBan, sizeof(warningBan), "%T", "WarningBan", client);
	
	SetHudTextParams(ABOVECENTERTEXT_X, ABOVECENTERTEXT_Y, 7.0, 255, 0, 0, 255);
	ShowHudText(client, AUTO_CHANNEL, warningBan);
	
	for(int i = 0; i <= MaxClients; i++)
	{
		PrintToChat(i, "%t", "NotifyExplode", nameBuffer);
	}
	
	TextNotifyRDMCommand();
}

public void TextBan()
{
	for(int i = 0; i <= MaxClients; i++)
	{
		PrintToChat(i, "%t", "NotifyBan", nameBuffer);
	}
	
	TextInsult();
}

public void TextNotifyRDMCommand()
{
	int random = GetRandomInt(0,1);
	if(random==1)
	{
		for(int i = 0; i <= MaxClients; i++)
		{
			char notifyRDMCommand[128];
			Format(notifyRDMCommand, sizeof(notifyRDMCommand), "%T", "NotifyRDMCommand", i);
			PrintToChat(i, notifyRDMCommand);
		}
	}
}

public void TextInsult()
{
	char message[128];
	int random = GetRandomInt(1,3);
	for(int i = 0; i <= MaxClients; i++)
	{
		switch(random)
		{
			case 1: Format(message, sizeof(message), "%T", "Insult1", i, nameBuffer);
			case 2: Format(message, sizeof(message), "%T", "Insult2", i);
			case 3: Format(message, sizeof(message), "%T", "Insult3", i, nameBuffer);
		}
		PrintToChat(i, message);
	}
}

public void SetClientScore(int client, int score)
{
	g_RdmScore[client] = score;
	char buffer[8];
	IntToString(score, buffer, sizeof(buffer));
	SetClientCookie(client, g_hRdmCookie, buffer);
}

public void ExplodeClient(int client)
{
	//get Vector3 client position
	float vec[3];
	GetClientEyePosition(client, vec);
	
	if (g_ExplosionSprite > -1)
	{
		TE_SetupExplosion(vec, g_ExplosionSprite, 5.0, 1, 0, 100, 5000);
		TE_SendToAll();
	}
	if (g_BoomSound[0])
	{
		EmitAmbientSound(g_BoomSound, vec, client, SNDLEVEL_RAIDSIREN);
	}
	
	SlapPlayer(client, 300, false);
	return;
}

public Action CmdTestRdm(int client, int args)
{
	ClientRDM(client);
	return Plugin_Handled;
}

public Action CmdCheckScore(int client, int args)
{
	int punishScore = g_cvPunishScore.IntValue;
	int banScore = g_cvBanScore.IntValue;
	int forgiveAmount = g_cvForgiveAmount.IntValue;
	
	char message[128];
	char message2[128];
	Format(message, sizeof(message), "%T", "ScoreCheck", client, g_RdmScore[client], punishScore, banScore);
	PrintToChat(client, message);
	
	if(forgiveAmount==-1)
	{
		Format(message2, sizeof(message2), "%T", "ScoreForgiveReset", client);
		PrintToChat(client, message2);
	}
	else
	{
		Format(message2, sizeof(message2), "%T", "ScoreForgive", client, forgiveAmount);
		PrintToChat(client, message2);
	}
	if(g_cvPunishConfirmedInStages.IntValue==1)
	{
		Format(message2, sizeof(message2), "%T", "ScorePunishmentStages", client);
		PrintToChat(client, message2);
	}
	
	return Plugin_Handled;
}

public Action CmdForgive(int client, int args)
{
	//ClientCommandAll sim
	for (int i = 1; i <= MaxClients; i++)
	{	
		if (IsClientInGame(i))
		{
			ClientForgive(i);
		}
	}
	PrintToChat(client, "Forgave the RDM score of all current clients by the configured amount.");
	return Plugin_Handled;
}

public void MarkClientInCombat(int client)
{
	if(!g_InCombat[client])
	{
		g_InCombat[client] = true;
		CreateTimer(g_cvCombatCheckTime.FloatValue, Timer_UnMarkClientInCombat, client);
	}
}

public Action Timer_UnMarkClientInCombat(Handle timer, any client)
{
    g_InCombat[client] = false;
    return Plugin_Stop;
}