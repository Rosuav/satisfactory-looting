# Signal notifications for your nation. Mostly this involves "go to this province". May expand this in the future.
import subprocess
import sys
import time
import json
import asyncio
from websockets.asyncio.client import connect # ImportError? pip install websockets
# First arg is server name/IP; the second could be a tag (eg "HAB") or a
# player name (eg "Rosuav").
# If --reconnect, will auto-retry until connection succeeds, ten-second
# retry delay. Will also reconnect after disconnection.
if len(sys.argv) < 3:
	print("USAGE: python3 %s ipaddress Name")
	sys.exit(0)
reconnect = "--reconnect" in sys.argv
if reconnect: sys.argv.remove("--reconnect")
host = sys.argv[1]
tag = " ".join(sys.argv[2:])

async def goto(provid):
	for retry in range(60):
		proc = await asyncio.create_subprocess_exec("xdotool", "getactivewindow", "getwindowname", stdout=subprocess.PIPE)
		if b"Europa Universalis IV" in (await proc.communicate())[0]:
			await asyncio.create_subprocess_exec("xdotool", "key", "--delay", "125", "f", *list(str(provid)), "Return")
			return
		await asyncio.sleep(0.5)
	print("Unable to find game window, not jumping to province")

async def client_connection():
	async with connect("wss://" + host + ":8087/ws") as sock:
		print("Connected, listening for province focus messages")
		await sock.send(json.dumps({"cmd": "init", "type": "tag", "group": "notify-" + tag}))
		async for msg in sock:
			msg = json.loads(msg)
			if msg["cmd"] == "update" and "prov" in msg:
				asyncio.create_task(goto(msg["prov"]))

while "reconnect":
	asyncio.run(client_connection())
	if not reconnect: break
	time.sleep(10)
