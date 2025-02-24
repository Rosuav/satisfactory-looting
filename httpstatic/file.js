import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {DIV, FIGURE, H1, H2, IMG, LABEL, LI, OPTGROUP, OPTION, P, SELECT, STYLE, UL} = choc; //autoimport

set_content("main", [
	H1("Satisfactory Looting - " + ws_group),
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

export function render(state) {
	const refloc = DOM("#refloc").value;
	set_content("#refloc", [
		OPTION({value: ""}, "Please select..."),
		OPTGROUP({label: "Players"}, state.players.map(p => OPTION({value: "P-" + p[0], ".ref_coords": p[1]}, p[0]))),
		OPTGROUP({label: "Markers"}, state.mapmarkers.map(m => OPTION({value: "M-" + m.MarkerID, ".ref_coords": m.Location}, m.Name))),
		//TODO: "Other" option, allowing user to enter arbitrary coordinates
	]).value = refloc;
	const itemtype = DOM("#itemtype").value;
	//TODO: Scroll such that the reference location is in view (will require the refloc to be echoed back from the server)
	set_content("#itemtype", [
		OPTION({value: ""}, "Please select..."),
		state.total_loot.map(([id, name, num]) => OPTION({value: id}, name + " (" + num + ")")),
	]).value = refloc;
}

on("change", "select", e => {
	const refloc = DOM("#refloc option:checked").ref_coords;
	const itemtype = DOM("#itemtype").value;
	if (refloc && itemtype) ws_sync.send({cmd: "findloot", refloc, itemtype});
});

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
