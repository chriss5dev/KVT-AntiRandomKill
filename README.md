# ConVars
`t_rdm_score_warn`
- Score at which a user will be warned by notification messages.

`t_rdm_score_punish`
- Score at which a user will be punished.

`t_rdm_score_ban`
- Score at which a user will be banned for a specified amount of time.

`t_rdm_amount_forgive`
- The amount of score to remove from a user that makes correct kills, whether intentional or not. -1 means reset score.

`t_rdm_amount_punish`
- The amount of score to add to a user that makes incorrect kills, whether intentional or not.

`t_rdm_combat_enabled`
- When set to 1, attackers are marked as in-combat for a specified amount of time. Players that are in-combat will not be counted as an RDM if killed, due to self-defense.

`t_rdm_combat_mindmg`
- The minimum damage at which an attacker will be marked as in-combat. Kills are automatically considered as in-combat.

`t_rdm_combat_time`
- How long attackers will be marked as in-combat, in seconds.

`t_rdm_ignore_gasnade`
- When set to 1, kills from gas grenades will not count towards RDM score.

`t_rdm_ignore_henade`
- When set to 1, kills from high-explosive grenades will not count towards RDM score.

`t_rdm_ignore_bomb`
- When set to 1, kills from bombs will not count towards RDM score.

`t_rdm_bantime`
- Time (in minutes) to ban users that surpass the ban score. 0 means permanent.

`t_rdm_punish_confirmed_in_stages`
- When set to 1, confirmed roles that teamkill other confirmed roles will skip extra score levels and have their score set straight to the next stage. Default -> Warn -> Punish -> Ban

# Design Logic
## RDM Score
#### Score events
- **Unconfirmed Incorrect Kills** are punished by adding `t_rdm_amount_punish` score to the killer.
- **Confirmed Incorrect Kills** are punished by setting the killer's score to the next level of escalation when `t_rdm_punish_confirmed_in_stages` is set to 1.
- **Correct Kills** are rewarded by removing `t_rdm_amount_forgive` score from the killer.
#### Warnings
- Players are **warned** when they reach a score of `t_rdm_score_warn`.
#### Punishments
- Players are **killed** (fake explosion) when they reach a score of `t_rdm_score_punish`.
#### Auto-Bans
- Players are **temporarily banned** for `t_rdm_bantime` minutes when they reach a score of `t_rdm_score_ban`.
## Avoiding false punishments
#### Ignored damage sources
- Gas Grenade damage is not considered a source of player damage when `t_rdm_ignore_gasnade` is set to 1.
- High-Explosive Grenade damage is not considered a source of player damage when `t_rdm_ignore_henade` is set to 1.
- Bomb (gadget) damage is not considered a source of player damage when `t_rdm_ignore_bomb` is set to 1.
#### Combat-Checking
- Players are marked as in-combat for `t_rdm_combat_time` seconds when they deal a minimum of `t_rdm_combat_mindmg` damage or kill another player, assuming `t_rdm_combat_enabled` is set to 1.
- This feature is not enabled by default, due to the risk of trolls abusing it.
- This feature tends to increase RDM judgement accuracy by ignoring crossfire and allowing players to eliminate those who kill others at random without consequence.
