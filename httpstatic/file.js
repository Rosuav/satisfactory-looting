import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV, FIGURE, H1, H2, IMG, LABEL, LI, OPTGROUP, OPTION, P, SELECT, STYLE, UL} = choc; //autoimport

set_content("main", [
	H1("Satisfactory Looting - " + ws_group),
	P({id: "mtime"}),
	H2("Search for:"),
	P(LABEL([
		"Reference location: ",
		SELECT({id: "refloc"}, OPTION({value: ""}, "Please select...")),
	])),
	P(LABEL([
		"Item: ",
		SELECT({id: "itemtype"}, OPTION({value: ""}, "Please select...")),
	])),
	H2("Results"),
	DIV({id: "searchresults"}, "Select location and item above"),
	STYLE(`
		#searchresults figure {
			max-width: 1000px;
			max-height: 600px;
			overflow: scroll;
		}
	`),
]);

let savefile_mtime;
setInterval(() => {
	const age = new Date/1000 - savefile_mtime;
	if (age < 0) set_content("#mtime", "File age: Unknown");
	else if (age >= 86400*2) set_content("#mtime", ["File age: ", Math.floor(age / 86400), " days"]);
	else if (age >= 86400) set_content("#mtime", "File age: Yesterday");
	else if (age >= 3600*2) set_content("#mtime", ["File age: ", Math.floor(age / 3600), " hours"]);
	else if (age >= 3600) set_content("#mtime", "File age: An hour");
	//The most interesting timestamps are the ones for active, current files. These are worth having the ticker for.
	else set_content("#mtime", [
		"File age: ",
		("0" + Math.floor(age / 60)).slice(-2),
		":",
		("0" + Math.floor(age % 60)).slice(-2),
	]);
}, 1000);
		
export function render(state) {
	savefile_mtime = state.mtime;
	const refloc = DOM("#refloc").value;
	set_content("#refloc", [
		OPTION({value: ""}, "Please select..."),
		OPTGROUP({label: "Players"}, state.players.map(p => OPTION({value: "P-" + p[0], ".ref_coords": p[1]}, p[0]))),
		OPTGROUP({label: "POIs"}, state.pois.map(p => OPTION({value: "P-" + p[0], ".ref_coords": p[1]}, p[0]))),
		OPTGROUP({label: "Markers"}, state.mapmarkers.map(m => OPTION({value: "M-" + m.MarkerID, ".ref_coords": m.Location}, m.Name))),
		//TODO: "Other" option, allowing user to enter arbitrary coordinates
	]).value = refloc;
	const itemtype = DOM("#itemtype").value;
	//TODO: Scroll such that the reference location is in view (will require the refloc to be echoed back from the server)
	set_content("#itemtype", [
		OPTION({value: ""}, "Please select..."),
		state.total_loot.map(([id, name, num]) => OPTION({value: id}, name + " (" + num + ")")),
	]).value = itemtype;
	update_image();
}

on("change", "select", update_image);
function update_image() {
	const refloc = DOM("#refloc option:checked").ref_coords;
	const itemtype = DOM("#itemtype").value;
	if (refloc && itemtype) ws_sync.send({cmd: "findloot", refloc, itemtype});
}

export function sockmsg_findloot(msg) {
	set_content("#searchresults", [
		UL(
			msg.found.length ? msg.found.map(f => LI(f))
			: LI("None found (savefile may have changed??)")
		),
		FIGURE([
			IMG({src: msg.img}),
			//FIGCAPTION("Do we need a caption?"),
		]),
	]);
}
