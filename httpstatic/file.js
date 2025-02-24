import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {H1, H2, OPTGROUP, OPTION, SELECT} = choc; //autoimport

set_content("main", [
	H1("Satisfactory Looting - " + ws_group),
	H2("Reference location"),
	SELECT({id: "refloc"}, OPTION({value: ""}, "Please select...")),
]);

export function render(state) {
	const refloc = DOM("#refloc").value;
	set_content("#refloc", [
		OPTION({value: ""}, "Please select..."),
		OPTGROUP({label: "Players"}, state.players.map(p => OPTION({value: "P-" + p[0], ".ref-coords": p[1]}, p[0]))),
		OPTGROUP({label: "Markers"}, state.mapmarkers.map(m => OPTION({value: "M-" + m.MarkerID, ".ref-coords": m.Location}, m.Name))),
		//TODO: "Other" option, allowing user to enter arbitrary coordinates
	]).value = refloc;
}
