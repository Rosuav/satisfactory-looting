@"This help information":
void help() {
	write("\nUSAGE: pike stillebot --exec=ACTION\nwhere ACTION is one of the following:\n");
	array names = indices(this), annot = annotations(this);
	sort(names, annot);
	foreach (annot; int i; multiset|zero annot)
		foreach (annot || (<>); mixed anno;)
			if (stringp(anno)) write("%-15s: %s\n", names[i], anno);
}

@"Edited as needed, does what's needed":
void test() {
	object parser = G->bootstrap("modules/parser.pike");
	program ObjectRef = parser->ObjectRef;
	mapping props = ([ /* 8 elements */
  "KilledOnDayNr": ([ /* 3 elements */
      "idx": 0,
      "type": "IntProperty",
      "value": 4294967295
    ]),
  "NumTimesKilled": ([ /* 3 elements */
      "idx": 0,
      "type": "IntProperty",
      "value": 0
    ]),
  "WasKilled": ([ /* 3 elements */
      "idx": 0,
      "type": "BoolProperty",
      "value": 0
    ]),
  "_keyorder": ({ /* 4 elements */
        "creature",
        "WasKilled",
        "NumTimesKilled",
        "KilledOnDayNr"
    }),
  "_path": "/Game/FactoryGame/Character/Creature/BP_CreatureSpawner.BP_CreatureSpawner_C --> mSpawnData",
  "_raw": "\t\0\0\0creature\0\17\0\0\0ObjectProperty\0\b\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\n"
    "\0\0\0WasKilled\0\r\0\0\0BoolProperty\0\0\0\0\0\0\0\0\0\0\0\17\0\0\0NumTimesKilled\0\f\0\0\0IntProperty\0\4\0\0\0\0\0\0\0\0\0\0\0\0\16\0\0\0KilledOnDayNr\0\f\0\0\0IntProperty\0\4\0\0\0\0\0\0\0\0\377\377\377\377\5\0\0\0None\0\t\0\0\0creature\0\17\0\0\0ObjectProperty\0\b\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\n"
    "\0\0\0WasKilled\0\r\0\0\0BoolProperty\0\0\0\0\0\0\0\0\0\0\0\17\0\0\0NumTimesKilled\0\f\0\0\0IntProperty\0\4\0\0\0\0\0\0\0\0\0\0\0\0\16\0\0\0KilledOnDayNr\0\f\0\0\0IntProperty\0\4\0\0\0\0\0\0\0\0\377\377\377\377\5\0\0\0None\0",
  "_type": "SpawnData",
  "creature": ([ /* 3 elements */
      "idx": 0,
      "type": "ObjectProperty",
      "value": ObjectRef("", "")
    ])
]);
	//~ parser->encode_properties(Stdio.Buffer(), props); return;
	//~ werror("Reparsed: %O\n", parser->parse_properties(Stdio.Buffer(props->_raw), 0, 0, "")); return;
	mapping save = parser->cached_parse_savefile("Assembly First_autosave_1.sav");
	write("Got save %O\n", indices(save->tree));
	string data = parser->reconstitute_savefile(save->tree);
	//Stdio.write_file(SATIS_SAVE_PATH + "/Reconstructed.sav", data);
	//write("Reconstituted save has %d bytes\n", sizeof(data));
}
