import {lindt, replace_content, DOM, fix_dialogs} from "https://rosuav.github.io/choc/factory.js";
const {A, H2, LI, UL} = lindt; //autoimport

export function render(data) {
	replace_content("main", [
		H2("Load EU4 save file"),
		UL(data.files.map(fn => LI(A({href: "/load/" + fn, class: "load", "data-fn": fn}, fn)))),
	]);
}

on("click", ".load", e => {
	e.preventDefault();
	ws_sync.send({cmd: "load", filename: e.match.dataset.fn});
});
