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
	mapping props = ([
"_raw": "\v\0\0\0mSortRules\0\16\0\0\0ArrayProperty\0d\2\0\0\0\0\0\0\17\0\0\0StructProperty\0\0\3\0\0\0\v\0\0\0mSortRules\0\17\0\0\0StructProperty\0\20\2\0\0\0\0\0\0\21\0\0\0SplitterSortRule\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\n"
"\0\0\0ItemClass\0\17\0\0\0ObjectProperty\0P\0\0\0\0\0\0\0\0\0\0\0\0H\0\0\0/Game/FactoryGame/Resource/FilteringRules/Desc_Wildcard.Desc_Wildcard_C\0\f\0\0\0OutputIndex\0\f\0\0\0IntProperty\0\4\0\0\0\0\0\0\0\0\0\0\0\0\5\0\0\0None\0\n"
"\0\0\0ItemClass\0\17\0\0\0ObjectProperty\0P\0\0\0\0\0\0\0\0\0\0\0\0H\0\0\0/Game/FactoryGame/Resource/FilteringRules/Desc_Wildcard.Desc_Wildcard_C\0\f\0\0\0OutputIndex\0\f\0\0\0IntProperty\0\4\0\0\0\0\0\0\0\0\2\0\0\0\5\0\0\0None\0\n"
"\0\0\0ItemClass\0\17\0\0\0ObjectProperty\0P\0\0\0\0\0\0\0\0\0\0\0\0H\0\0\0/Game/FactoryGame/Resource/FilteringRules/Desc_Overflow.Desc_Overflow_C\0\f\0\0\0OutputIndex\0\f\0\0\0IntProperty\0\4\0\0\0\0\0\0\0\0\1\0\0\0\5\0\0\0None\0\25\0\0\0mItemToLastOutputMap\0\f\0\0\0MapProperty\0Y\0\0\0\0\0\0\0\17\0\0\0ObjectProperty\0\r\0\0\0ByteProperty\0\0\0\0\0\0\1\0\0\0\0\0\0\0H\0\0\0/Game/FactoryGame/Resource/FilteringRules/Desc_Wildcard.Desc_Wildcard_C\0\0\21\0\0\0mLastOutputIndex\0\f\0\0\0IntProperty\0\4\0\0\0\0\0\0\0\0\1\0\0\0\21\0\0\0mBufferInventory\0\17\0\0\0ObjectProperty\0~\0\0\0\0\0\0\0\0\21\0\0\0Persistent_Level\0e\0\0\0Persistent_Level:PersistentLevel.Build_ConveyorAttachmentSplitterSmart_C_2146639573.StorageInventory\0\23\0\0\0mCustomizationData\0\17\0\0\0StructProperty\0\233\0\0\0\0\0\0\0\31\0\0\0FactoryCustomizationData\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\v\0\0\0SwatchDesc\0\17\0\0\0ObjectProperty\0g\0\0\0\0\0\0\0\0\0\0\0\0_\0\0\0/Game/FactoryGame/Buildable/-Shared/Customization/Swatches/SwatchDesc_Slot0.SwatchDesc_Slot0_C\0\5\0\0\0None\0\21\0\0\0mBuiltWithRecipe\0\17\0\0\0ObjectProperty\0|\0\0\0\0\0\0\0\0\0\0\0\0t\0\0\0/Game/FactoryGame/Recipes/Buildings/Recipe_ConveyorAttachmentSplitterSmart.Recipe_ConveyorAttachmentSplitterSmart_C\0\5\0\0\0None\0\0\0\0\0"
]);
	//~ parser->encode_properties(Stdio.Buffer(), props); return;
	//~ mapping p = parser->parse_properties(Stdio.Buffer(props->_raw), 0, 0, ""); werror("Reparsed: %O\n", p); werror("Encoded: %O\n", parser->encode_properties(Stdio.Buffer(), p)); return;
	mapping save = parser->cached_parse_savefile("Assembly First_autosave_2.sav");
	write("Got save %O\n", indices(save->tree));
	string data = parser->reconstitute_savefile(save->tree);
	Stdio.write_file(SATIS_SAVE_PATH + "/Reconstructed.sav", data);
	//write("Reconstituted save has %d bytes\n", sizeof(data));
}
