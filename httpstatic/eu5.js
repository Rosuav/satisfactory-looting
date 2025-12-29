import {lindt, replace_content, DOM, fix_dialogs} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, DETAILS, DIALOG, DIV, H1, H3, HEADER, IMG, LI, NAV, SECTION, SPAN, SUMMARY, UL} = lindt; //autoimport
const {P} = lindt; //Currently autoimport doesn't recognize the section() decorator

let defaultsection = null; //If nonnull, will autoopen this section

document.body.appendChild(replace_content(null, DIALOG({id: "tiledviewdlg"}, SECTION([
	HEADER([H3("Jump to section"), DIV(BUTTON({type: "button", class: "dialog_cancel"}, "x"))]),
	DIV({id: "tiledviewmain"}),
]))));
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: "formless"});

const sections = [];
function section(id, nav, lbl, render) {sections.push({id, nav, lbl, render});}

let max_interesting = { };

section("automated_systems", "Automation", "Automated Systems", state => [
	SUMMARY("Automated Systems"),
	P("TODO: Provide some recommendations"),
	UL(state.automated_systems.map(kwd => LI(kwd))),
]);

//function threeplace(n) {return (n / 1000).toFixed(2);} //Might need a fiveplace()?

export function render(state) {
	//Set up one-time structure. Every subsequent render will update within that.
	if (!DOM("#error")) replace_content("main", [
		NAV({id: "topbar"}, SPAN({id: "togglesidebarbox", class: "sbvis"},
			BUTTON({type: "button", id: "togglesidebar", title: "Show/hide sidebar"}, "Show/hide sidebar"),
		)),
		NAV({id: "sidebar", class: "vis"}, [
			UL([
				sections.map(s => s.nav && A({href: "#" + s.id}, LI(s.nav))),
				LI(""),
				LI(A({id: "collapseall", href: "#"}, "Collapse all")),
			]),
			A({href: "", id: "tiledview", title: "Jump to section (Alt+J)", accesskey: "j"}, "🌐"), //"Alt+J" might be wrong on other browsers though
		]),
		DIV({id: "error", className: "hidden"}),
		DIV({id: "menu", className: "hidden"}),
		DIV({id: "flagbg"}, IMG({className: "flag large", id: "playerflag", alt: "[flag of player's nation]"})),
		H1({id: "player"}),
		sections.map(s => DETAILS({id: s.id}, SUMMARY(s.lbl))),
		DIV({id: "options"}, [ //Positioned fixed in the top corner
			BUTTON({id: "optexpand", title: "Show options and notifications"}, "🖈"),
			UL({id: "interesting_details"}),
			UL({id: "notifications"}),
			DIV({id: "now_parsing", className: "hidden"}),
		]),
		//Always have DETAILS/SUMMARY nodes for every expandable, such that,
		//whenever content is updated, they remain in their open/closed state.
	]) && window.onresize();

	if (state.error) {
		replace_content("#error", [state.error, state.parsing > -1 ? state.parsing + "%" : ""]).classList.remove("hidden");
		return;
	}
	replace_content("#error", "").classList.add("hidden");
	if (state.name) replace_content("#player", state.name);
	if (state.bgcolor) DOM("#flagbg").style.background = state.bgcolor;
	sections.forEach(s => state[s.id] && replace_content("#" + s.id, s.render(state)));
	const is_interesting = [];
	Object.entries(max_interesting).forEach(([id, lvl]) => {
		const el = DOM("#" + id + " > summary");
		if (lvl) is_interesting.push(LI({className: "interesting" + lvl, "data-id": id}, el.innerText));
		el.className = "interesting" + lvl;
	});
	replace_content("#interesting_details", is_interesting);
	if (state.notifications) replace_content("#notifications", state.notifications.map(n => LI({className: "interesting2"}, ["🔔 ", render_text(n)])));

	//Quick hack: Show a specific section. TODO: Put this in the document fragment?
	if (defaultsection) {
		//TODO: Dedup with others?
		const sec = DOM("#" + defaultsection);
		defaultsection = null;
		if (sec) {
			sec.open = true;
			sec.scrollIntoView();
			sec.classList.add("jumphighlight");
			setTimeout(() => sec.classList.remove("jumphighlight"), 250);
		}
	}
}

on("click", "#togglesidebar", e => {
	DOM("nav#sidebar").classList.toggle("vis");
	DOM("#togglesidebarbox").classList.toggle("sbvis");
	window.onresize = null; //No longer automatically toggle as the window resizes.
});
on("click", "#optexpand", e => {
	DOM("#options").classList.toggle("vis");
	window.onresize = null; //Note that manually toggling either will stop both from autotoggling. Is this correct?
});
//On wide windows, default to having the sidebar visible.
window.onresize = () => {
	const sbvis = window.innerWidth > 600;
	DOM("nav#sidebar").classList.toggle("vis", sbvis);
	DOM("#togglesidebarbox").classList.toggle("sbvis", sbvis);
	DOM("#options").classList.toggle("vis", sbvis);
}

on("click", "#sidebar ul a, a.tiledviewtile", e => {
	e.preventDefault();
	const hash = new URL(e.match.href).hash;
	const sec = hash && DOM(hash);
	if (!sec) return;
	sec.open = true; //Ensure the target section is expanded
	sec.scrollIntoView();
	sec.classList.add("jumphighlight");
	setTimeout(() => sec.classList.remove("jumphighlight"), 250);
	DOM("#tiledviewdlg").close(); //Not applicable to sidebar but won't hurt
	//Open question: Should this also collapse other sections? It might make sense to
	//collapse some or all, to further focus on this one.
});

function TILE(id, color, lbl, icon) { //todo: impl color
	const attrs = {class: "tiledviewtile", "href": "#" + id};
	const parts = lbl.split("~");
	if (parts.length === 2) { //The label has a mnemonic in it
		lbl = [
			parts[0],
			SPAN({style: "text-decoration: underline"}, parts[1][0]),
			parts[1].slice(1),
		];
		attrs.accesskey = parts[1][0].toLowerCase();
	}
	return A(attrs, [
		DIV({class: "icon"}, icon),
		DIV({class: "label"}, lbl),
	]);
}

on("click", "#tiledview", e => {
	e.preventDefault();
	const dlg = DOM("#tiledviewdlg");
	if (dlg.open) {dlg.close(); return;} //Alt-J is a toggle
	replace_content("#tiledviewmain", [
		TILE("cot", "", "Ctrs of Trade", "💰"),
		TILE("trade_nodes", "", "Trade ~nodes", "💱"),
		TILE("monuments", "", "~Monuments", "🗼"),
		TILE("badboy_hatred", "", "Badboy", "🤯"),
		TILE("unguarded_rebels", "", "~Rebels", "🔥"),
		TILE("subjects", "", "~Subjects", "🧎"),
		TILE("colonization_targets", "", "Colonies", "🌎"),
		TILE("truces", "", "~Truces", "🏳"),
		TILE("cbs", "", "Casus Belli", "🔪"),
	]);
	dlg.showModal();
});

on("click", "#collapseall", e => {
	e.preventDefault();
	document.querySelectorAll("details").forEach(el => el.open = false);
});

//Prevent spurious activations of jump-to-section hotkeys
DOM("#tiledviewdlg").onclose = e => replace_content("#tiledviewmain", "");
