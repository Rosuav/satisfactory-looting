import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {A, H1, H2, LI, UL} = choc; //autoimport

set_content("main", [
	H1("Satisfactory Looting"),
	H2("Sessions"),
	UL({id: "sessions"}),
	H2("Save files"),
	UL({id: "savefiles"}),
]);

export function render(state) {
	set_content("#sessions", state.sessions.map(sess => LI(A({href: "/session/" + encodeURIComponent(sess)}, sess))));
	set_content("#savefiles", state.files.map(file => LI(A({href: "/file/" + encodeURIComponent(file)}, file))));
}
