# TF2-QuickSpec
Quickly spectate other players

## Commands
* **sm_spec \<OPTIONAL:target>** - Quickly spectate a player. (No optional: opens spec menu)
* **sm_speclock / sm_spec_ex \<OPTIONAL:target/OFF/0\>** - Consistently spectate a player, even through their death
* **sm_fspec \<target> \<OPTIONAL:targetToSpec>** - Quickly force a player to spec another player (No optional: forces target to spec you)
* **sm_fspecstop \<target>** - Return player to team and position from before `sm_fspec` was used

## ConVars
**sm_spec_restoreenabled "0"** //Enable location restoration pre-forcespec?  
**sm_spec_restoretimer "5.0"** //Time until restoration after respawning  
**sm_spec_allowforcebot "0"** //Enable the use of force spec commands on bots?  
