# Summarizes a WoW combat log (Logs/WoWCombatLog-*.txt) for the player and their group.
# POSIX awk (works with gawk, mawk, BSD awk). Usage:
#   awk -f combatlog.awk [-v me="Name"] [-v from="14:16"] [-v to="14:41"] WoWCombatLog-*.txt
#   me    part of your character name (default: the first player with "mine" affiliation)
#   from  / to   HH:MM[:SS] time window (compared as text on the time of day)
#
# Line format: "MM/DD/YYYY HH:MM:SS.ffff  EVENT,field,field,..."
# Base fields: 2 srcGUID 3 srcName 4 srcFlags 5 srcRaidFlags 6 dstGUID 7 dstName 8 dstFlags 9 dstRaidFlags
# Spell events add 10 spellId 11 spellName 12 school. With advanced logging 19 more unit fields follow
# (info GUID, owner, hp, maxhp, ap, sp, armor, absorb, power type/cur/max/cost, x, y, uiMapID, facing, level),
# so the amount is field 29 for SWING_*, 32 for SPELL_*/RANGE_*; without advanced logging 10 / 13.
# Flags: last hex digit = affiliation (1 mine, 2 party, 4 raid, 8 outsider).

BEGIN { FS = "," }

function affil(flags) { return substr(flags, length(flags), 1) }
function ingroup(flags,   a) { a = affil(flags); return a == "1" || a == "2" || a == "4" }
function isAdv(f) { return f ~ /^(0000000000000000|Player-|Creature-|Pet-|Vehicle-|GameObject-)/ }
function clean(s) { gsub(/"/, "", s); return s }
function short(s) { s = clean(s); sub(/-.*$/, "", s); return s }
# players are "Name-Realm-Region": drop the realm; creature names may contain "-" and stay intact
function nm(guid, s) { return (guid ~ /^Player-/) ? short(s) : clean(s) }

{
  sp = index($0, "  ")
  if (!sp) next
  ts = substr($0, 1, sp - 1)
  split(ts, tp, " "); tod = tp[2]
  if (from != "" && tod < from) next
  if (to != "" && substr(tod, 1, length(to)) > to) next
  ev = substr($1, sp + 2)
  if (first == "") first = ts
  last = ts

  if (ev == "ZONE_CHANGE") { zones = zones "\n  " tod "  " clean($3); next }
  if (ev == "ENCOUNTER_START") { enc = enc "\n  " tod "  start  " clean($3); encStart[clean($3)] = tod; next }
  if (ev == "ENCOUNTER_END") { enc = enc "\n  " tod "  end    " clean($3) (($6 == "1") ? "  (kill)" : "  (wipe)"); next }

  # remember group players and pick "me"
  if ($2 ~ /^Player-/ && ingroup($4)) { grp[$2] = short($3); if (meGUID == "" && ((me != "" && index($3, me)) || (me == "" && affil($4) == "1"))) meGUID = $2 }

  amt = 0; spell = ""
  if (ev == "SWING_DAMAGE") { amt = isAdv($10) ? $29 : $10; spell = "Melee" }
  else if (ev == "SPELL_DAMAGE" || ev == "SPELL_PERIODIC_DAMAGE" || ev == "RANGE_DAMAGE" || ev == "DAMAGE_SHIELD") { amt = isAdv($13) ? $32 : $13; spell = clean($11) }
  else if (ev == "SPELL_HEAL" || ev == "SPELL_PERIODIC_HEAL") {
    a = isAdv($13) ? 32 : 13
    eff = $(a) - $(a + 2)
    if ($2 ~ /^Player-/ && ingroup($4)) { heal[$2] += eff; overheal[$2] += $(a + 2) }
    if ($2 == meGUID) { myHeal[clean($11)] += eff; myHealN[clean($11)]++ }
    next
  }
  else if (ev == "SWING_MISSED" && $2 ~ /^Creature-/ && $6 ~ /^Player-/ && ingroup($8)) { aggro[$6]++; next }
  else if (ev == "UNIT_DIED" && $6 ~ /^Player-/ && ingroup($8)) {
    deaths[$6]++
    dl = dl "\n  " tod "  " short($7) " died. Last hits:"
    if (h1[$6] != "") dl = dl "\n      " h1[$6]
    if (h2[$6] != "") dl = dl "\n      " h2[$6]
    if (h3[$6] != "") dl = dl "\n      " h3[$6]
    h1[$6] = h2[$6] = h3[$6] = ""
    next
  }
  else next

  if (amt == "" || amt == "nil") amt = 0
  # damage done by group players (pets count for their owner only if the log links them: skipped)
  if ($2 ~ /^Player-/ && ingroup($4)) {
    dmg[$2] += amt
    if ($2 == meGUID) { myDmg[spell] += amt; myDmgN[spell]++ }
  }
  # damage taken by group players
  if ($6 ~ /^Player-/ && ingroup($8)) {
    taken[$6] += amt
    if ($2 ~ /^Creature-/ && spell == "Melee") aggro[$6]++
    if ($6 == meGUID) { src = nm($2, $3); if (spell != "Melee") src = src " / " spell; myTaken[src] += amt }
    # keep the last three hits for death reports
    h1[$6] = h2[$6]; h2[$6] = h3[$6]; h3[$6] = tod " " nm($2, $3) " " spell " " amt
  }
}

END {
  print "Log: " first " .. " last
  if (zones != "") print "Zones:" zones
  if (enc != "") print "Encounters:" enc
  print ""
  print "Group: damage / effective healing / overheal / damage taken / creature melee attacks taken / deaths"
  cmd = "sort -k3 -rn"
  for (g in grp) {
    tag = (g == meGUID) ? "*" : ""
    printf "  %-22s dmg %8d  heal %7d  over %7d  taken %8d  hits %5d  deaths %d\n", grp[g] tag, dmg[g], heal[g], overheal[g], taken[g], aggro[g], deaths[g] | cmd
    totalHits += aggro[g]
  }
  close(cmd)
  if (meGUID != "") print "  (* = me)"
  if (meGUID != "" && totalHits > 0) printf "  Tank share: %.0f%% of creature melee attacks on the group hit %s\n", 100 * aggro[meGUID] / totalHits, grp[meGUID]
  if (meGUID != "") {
    cmd = "sort -rn"
    print ""; print "My damage by ability:"
    for (s in myDmg) printf "  %8d  %5d hits  %s\n", myDmg[s], myDmgN[s], s | cmd
    close(cmd)
    print ""; print "My healing by ability:"
    for (s in myHeal) printf "  %8d  %5d casts  %s\n", myHeal[s], myHealN[s], s | cmd
    close(cmd)
    print ""; print "Damage taken by me, top sources:"
    for (s in myTaken) printf "  %8d  %s\n", myTaken[s], s | "sort -rn | head -12"
    close("sort -rn | head -12")
  }
  if (dl != "") { print ""; print "Deaths:" dl }
}
