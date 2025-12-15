int main() {
	string path = "/mnt/sata-ssd/.steam/steamapps/compatdata/3450310/pfx/drive_c/users/steamuser/Documents/Paradox Interactive/Europa Universalis V/save games";
	string data = Stdio.read_file(path + "/string_lookup"); //Or get it from the zip at the end of a save file
	object buf = Stdio.Buffer(data);
	[int unk1, int count, int unk3] = buf->sscanf("%c%-2c%-2c");
	write("Header %O %O %O\n", unk1, count, unk3);
	int i = 0;
	while (sizeof(buf)) {
		[string str] = buf->sscanf("%-2H");
		write("[%d] %O\n", ++i, str);
	}
	write("Total %d strings.\n", i);
}
