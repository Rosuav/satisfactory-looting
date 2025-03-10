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
	mapping props = ([ /* 6 elements */
  "_keyorder": ({ /* 3 elements */
        "mSaveSessionName",
        "mLastAutoSaveId",
        "mStartingPointTagName"
    }),
  "_raw": "\21\0\0\0mSaveSessionName\0\f\0\0\0StrProperty\0\23\0\0\0\0\0\0\0\0\17\0\0\0Assembly First\0\20\0\0\0mLastAutoSaveId\0\r\0\0\0ByteProperty\0\1\0\0\0\0\0\0\0\5\0\0\0None\0\0\1\26\0\0\0mStartingPointTagName\0\r\0\0\0NameProperty\0\21\0\0\0\0\0\0\0\0\r\0\0\0Grass Fields\0\5\0\0\0None\0\0\0\0\0\0\0\0\0",
  "_residue": "\0\0\0\0\0\0\0\0",
  "mLastAutoSaveId": ([ /* 4 elements */
      "idx": 0,
      "subtype": "None",
      "type": "ByteProperty",
      "value": 1
    ]),
  "mSaveSessionName": ([ /* 3 elements */
      "idx": 0,
      "type": "StrProperty",
      "value": "Assembly First"
    ]),
  "mStartingPointTagName": ([ /* 3 elements */
      "idx": 0,
      "residue": "\r\0\0\0Grass Fields\0",
      "type": "NameProperty"
    ])
]);
	parser->encode_properties(Stdio.Buffer(), props); return;
	mapping save = parser->cached_parse_savefile("Assembly First_autosave_1.sav");
	write("Got save %O\n", indices(save->tree));
	string data = parser->reconstitute_savefile(save->tree);
	//Stdio.write_file(SATIS_SAVE_PATH + "/Reconstructed.sav", data);
	//write("Reconstituted save has %d bytes\n", sizeof(data));
}
