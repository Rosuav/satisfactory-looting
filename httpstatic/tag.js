import {lindt, replace_content, DOM, fix_dialogs} from "https://rosuav.github.io/choc/factory.js";
const {A, ABBR, B, BR, BUTTON, DETAILS, DIALOG, DIV, FORM, H1, H3, H4, HEADER, IMG, INPUT, LABEL, LI, NAV, OPTGROUP, OPTION, P, SECTION, SELECT, SPAN, STRONG, SUMMARY, TABLE, TD, TH, THEAD, TR, UL} = lindt; //autoimport
const {BLOCKQUOTE, I, PRE} = lindt; //Currently autoimport doesn't recognize the section() decorator

let defaultsection = null; //If nonnull, will autoopen this section

document.body.appendChild(choc.STYLE({id: "ideafilterstyles"}));
document.body.appendChild(replace_content(null, DIALOG({id: "customnationsdlg"}, SECTION([
	HEADER([H3("Custom nations"), DIV(BUTTON({type: "button", class: "dialog_cancel"}, "x"))]),
	DIV([
		DIV({id: "customnationmain"}),
		P([
			BUTTON({class: "dialog_close"}, "Close"),
			SPAN({id: "custompwd", hidden: ""}, [
				" Enter password to save: ",
				INPUT({type: "password", autocomplete: "off", id: "savecustom_password"}),
				BUTTON({id: "savecustom"}, "Save"),
			]),
		]),
	]),
]))));
document.body.appendChild(replace_content(null, DIALOG({id: "customideadlg"}, SECTION([
	HEADER([H3("Pick custom idea"), DIV(BUTTON({type: "button", class: "dialog_cancel"}, "x"))]),
	DIV({id: "customideamain"}),
]))));
document.body.appendChild(replace_content(null, DIALOG({id: "customflagdlg"}, SECTION([
	HEADER([H3("Modify flag"), DIV(BUTTON({type: "button", class: "dialog_cancel"}, "x"))]),
	DIV({id: "customflagmain"}),
]))));
document.body.appendChild(replace_content(null, DIALOG({id: "tiledviewdlg"}, SECTION([
	HEADER([H3("Jump to section"), DIV(BUTTON({type: "button", class: "dialog_cancel"}, "x"))]),
	DIV({id: "tiledviewmain"}),
]))));
document.body.appendChild(replace_content(null, DIALOG({id: "detailsdlg"}, SECTION([
	HEADER([H3("Detailed relations breakdown"), DIV(BUTTON({type: "button", class: "dialog_cancel"}, "x"))]),
	DIV({id: "detailsmain"}),
]))));
document.body.appendChild(replace_content(null, DIALOG({id: "battlesdlg"}, SECTION([
	HEADER([H3("Combat analysis"), DIV(BUTTON({type: "button", class: "dialog_cancel"}, "x"))]),
	TABLE([
		TR([
			TD({id: "battles_nation_0"}), //Will be populated with flags
			TH("Nations"),
			TD({id: "battles_nation_1"}),
		]),
		TR([
			TD(SELECT({id: "battles_army_0"}, OPTION({value: ""}, "Select..."))),
			TH("Armies"),
			TD(SELECT({id: "battles_army_1"}, OPTION({value: ""}, "Select..."))),
		]),
		TR([
			TD(LABEL([INPUT({type: "radio", checked: true, name: "battles_attacker", value: "1"}), "Attacking"])),
			TH("Direction"),
			TD(LABEL([INPUT({type: "radio", name: "battles_attacker", value: "2"}), "Attacking"])),
		]),
		TR([
			TD([
				SELECT({id: "battles_terrain"}, [
					OPTION({value: 0}, "No terrain penalty"),
					OPTION({value: 1}, "Hills, forest, etc (1)"),
					OPTION({value: 2}, "Mountains (2)"),
				]), BR(),
				SELECT({id: "battles_crossing"}, [
					OPTION({value: 0}, "No crossing"),
					OPTION({value: 1}, "River (1)"),
					OPTION({value: 2}, "Strait/landing (2)"),
				]),
			]),
		]),
	]),
	DIV({id: "battlesmain"}),
]))));
fix_dialogs({close_selector: ".dialog_cancel,.dialog_close", click_outside: "formless"});

function cmp(a, b) {return a < b ? -1 : a > b ? 1 : 0;}
function cell_compare_recursive(a, b, is_numeric) {
	if (!a && !b) return 0; //All types of "empty" count equally
	else if (!a) return -1;
	else if (!b) return 1;
	if (typeof a === "string" || typeof a === "number") { //Assumes that b is the same type
		if (is_numeric) return cmp(+a, +b);
		return cmp(a, b);
	}
	let ret = cmp(a.attributes["data-sortkey"], b.attributes["data-sortkey"], is_numeric);
	for (let i = 0; i < a.children.length && i < b.children.length && !ret; ++i)
		ret = cell_compare_recursive(a.children[i], b.children[i], is_numeric);
	return ret;
}
function cell_compare(sortcol, direction, is_numeric) { //direction s/be 1 or -1 for reverse sort
	if (is_numeric) direction = -direction; //Reverse numeric sorts by default
	return (a, b) => cell_compare_recursive(a.children[sortcol], b.children[sortcol], is_numeric) * direction;
}

//To be functional, a sortable MUST have an ID. It may have other attrs.
const sort_selections = { };
function numeric_sort_header(h) {return (typeof h === "string" && h[0] === '#') || h?.dataset?.numeric;}
function sortable(attrs, headings, rows) {
	if (!attrs || !attrs.id) console.error("BAD SORTABLE, NEED ID", attrs, headings, rows);
	if (typeof headings === "string") headings = headings.split(" ");
	let sortcol = sort_selections[attrs.id];
	const reverse = sortcol && sortcol[0] === '-'; //Note that this is done with strings; "-0" means "column zero but reversed".
	if (reverse) sortcol = sortcol.slice(1);
	const is_numeric = numeric_sort_header(headings[sortcol]);
	const headrow = THEAD(TR(headings.map((h, i) => TH({class: "sorthead", "data-idx": i}, numeric_sort_header(h) ? h.slice(1) : h))));
	rows.forEach((r, i) => r.key = r.key || "row-" + i);
	if (sortcol !== undefined) rows.sort(cell_compare(sortcol, reverse ? -1 : 1, is_numeric));
	const tb = DOM("#" + attrs.id);
	const ret = tb ? replace_content(tb, [headrow, rows]) //TODO: Handle any changes of attributes
		: replace_content(null, TABLE(attrs, [headrow, rows]));
	ret._sortable_config = [attrs, headings, rows];
	return ret;
}

let curgroup = [], provgroups = { }, provelem = { }, pinned_provinces = { }, province_info = { };
let selected_provgroup = "", selected_prov_cycle = [];
function proventer(kwd) {
	curgroup.push(kwd);
	const g = curgroup.join("/");
	provgroups[g] = [];
	return provelem[g] = SPAN({
		className: "provgroup size-" + curgroup.length + (selected_provgroup === g ? " selected" : ""),
		"data-group": g, title: "Select cycle group " + g,
	}, "📜");
}
function provleave() { //Can safely be put into a DOM array (will be ignored)
	const g = curgroup.join("/");
	if (!provgroups[g].length) {
		const el = provelem[g];
		el.children[0] = "📃"; //FIXME: Don't monkeypatch.
		el.attributes.title = "No provinces in group " + g;
		el.className += " empty";
	}
	curgroup.pop();
}
function GOTOPROV(id) {
	const info = province_info[id] || { }, disc = info.discovered;
	return SPAN({className: "goto-province provbtn", title: (disc ? "Go to #" : "Terra Incognita, cannot goto #") + id, "data-provid": id}, disc ? "🔭" : "🌐")
}
function PROV(id, nameoverride, namelast) {
	let g, current = "";
	for (let kwd of curgroup) {
		if (g) g += "/" + kwd; else g = kwd;
		if (provgroups[g].indexOf(id) < 0) provgroups[g].push(id);
		//TODO: If we've never asked for "next province", show nothing as selected.
		//May require retaining a "last selected province" marker.
		if (g === selected_provgroup && id === selected_prov_cycle[selected_prov_cycle.length - 1]) current = " selected";
	}
	const pin = pinned_provinces[id], info = province_info[id] || { };
	if (!nameoverride && nameoverride !== "") nameoverride = info?.name || "";
	return SPAN({className: "province" + current}, [
		!namelast && nameoverride,
		info.wet && "🌊",
		GOTOPROV(id),
		SPAN({className: "pin-province provbtn", title: (pin ? "Unpin #" : "Pin #") + id, "data-provid": id}, pin ? "⛳" : "📌"),
		namelast && nameoverride,
		info.owner && [" ", COUNTRY(info.owner, " ")], //No flag if unowned
		//What if info.controller !== info.owner? Should we show some indication? Currently not bothering.
	]);
}

let countrytag = "", hovertag = ""; //The country we're focusing on (usually a player-owned one) and the one highlighted.
let country_info = { };
function COUNTRY(tag, nameoverride) {
	if (tag === "") return "";
	const c = country_info[tag] || {name: tag, flag: tag};
	return SPAN({className: "country", "data-tag": tag}, [
		IMG({className: "flag small", src: "/flags/" + c.flag + ".png", alt: "[flag of " + c.name + "]"}),
		" ", nameoverride || c.name,
		c.overlord && SPAN({title: "Is a " + c.subject_type + " of " + country_info[c.overlord].name}, "🙏"),
		c.truce && SPAN({title: "Truce until " + c.truce}, " 🏳"),
	]);
}
let _saved_miltech = null;
function update_hover_country(tag) {
	const c = country_info[hovertag = tag];
	const me = country_info[countrytag] || {tech: [0,0,0]};
	document.querySelectorAll("#miltech .interesting2").forEach(el => el.classList.remove("interesting2"));
	const miltb = DOM("#miltech table"); if (miltb) miltb.classList.add("hoverinactive");
	if (!c) {
		replace_content("#hovercountry", "").classList.add("hidden");
		return;
	}
	function attrs(n) {
		if (n > 0) return {className: "tech above", title: n + " ahead of you"};
		if (n < 0) return {className: "tech below", title: -n + " behind you"};
		return {className: "tech same", title: "Same as you"};
	}
	replace_content("#hovercountry", [
		DIV({className: "close"}, "☒"),
		A({href: "/tag/" + hovertag, target: "_blank"}, [
			IMG({className: "flag large", src: "/flags/" + c.flag + ".png", alt: "[flag of " + c.name + "]"}),
			H3(c.name),
		]),
		UL([
			LI(["Tech: ", ["Adm", "Dip", "Mil"].map((cat, i) => [SPAN(
				attrs(c.tech[i] - me.tech[i]),
				cat + " " + c.tech[i],
			), " "])]),
			LI(["Capital: ", PROV(c.capital, c.capitalname, 1)]),
			LI(["Provinces: " + c.province_count + " (",
				SPAN({title: "Total province development, modified by local autonomy"}, c.development + " dev"), ")"]),
			LI(["Institutions embraced: ", SPAN(attrs(c.institutions - me.institutions), ""+c.institutions)]),
			LI(["Opinion: ", B({title: "Their opinion of you"}, c.opinion_theirs),
				" / ", B({title: "Your opinion of them"}, c.opinion_yours)]),
			LI(["Mil units: ", SPAN(attrs(c.armies - me.armies), c.armies + " land"),
				" ", SPAN(attrs(c.navies - me.navies), c.navies + " sea")]),
			c.subjects && LI("Subject nations: " + c.subjects),
			c.alliances && LI("Allied with: " + c.alliances),
			c.hre && LI("HRE member 👑"),
			c.overlord && LI([B(c.subject_type), " of ", COUNTRY(c.overlord)]),
			c.truce && LI([B("Truce"), " until " + c.truce + " 🏳"]),
		]),
		//Note that this button carries the tag with it, allowing for potential direct-access
		//buttons that go straight to battle analysis.
		P(BUTTON({class: "analyzebattles", "data-tag": hovertag, style: "display: block; margin: auto"}, "Analyze/predict battles")),
	]).classList.remove("hidden");
	if (_saved_miltech) {
		DOM("#miltech table").classList.remove("hoverinactive");
		replace_content("#miltech th.hovercountry", c.name);
		const sel = '#miltech tr[data-tech="' + c.tech[2] + '"]';
		if (!DOM(sel).classList.contains("interesting1")) DOM(sel).classList.add("interesting2");
		document.querySelectorAll("#miltech td.hovercountry").forEach(el => replace_content(el, [
			_saved_miltech(+el.dataset.tech, c.unit_type + "_infantry", "_infantry"), " / ",
			_saved_miltech(+el.dataset.tech, c.unit_type + "_cavalry", "_cavalry"), " / ",
			_saved_miltech(+el.dataset.tech, "0_artillery"),
		]));
	}
}
//Once you point to a country, it will remain highlighted (even through savefile updates),
//for a few seconds or indefinitely if you hover over the expanded info box.
let hovertimeout = 0;
on("mouseover", ".country:not(#hovercountry .country)", e => {
	e.match.classList.add("retained");
	clearTimeout(hovertimeout);
	if (e.match.dataset.tag !== countrytag) update_hover_country(e.match.dataset.tag);
});
on("click", "#hovercountry .country", e => update_hover_country(e.match.dataset.tag));
//The hovered country can be removed with its little Close button.
on("click", "#hovercountry .close", e => update_hover_country(""));
on("mouseover", "#hovercountry", e => {
	e.match.classList.add("retained");
	clearTimeout(hovertimeout);
});
on("mouseout", ".country:not(#hovercountry .country)", e => {
	DOM("#hovercountry").classList.remove("retained");
	hovertimeout = setTimeout(update_hover_country, 5000, "");
});

on("click", ".goto-province", e => {
	ws_sync.send({cmd: "goto", tag: countrytag, province: e.match.dataset.provid});
});

on("click", ".pin-province", e => {
	ws_sync.send({cmd: "pin", province: e.match.dataset.provid});
});

on("click", ".provgroup", e => {
	ws_sync.send({cmd: "cyclegroup", cyclegroup: e.match.dataset.group});
});
on("click", ".provnext", e => {
	ws_sync.send({cmd: "cyclenext", tag: countrytag});
});

on("click", "#interesting_details li", e => {
	const el = document.getElementById(e.match.dataset.id);
	el.open = true;
	el.scrollIntoView({block: "start", inline: "nearest"});
});

on("change", "#highlight_options", e => ws_sync.send({cmd: "highlight", building: e.match.value}));
on("change", "#fleetpower", e => ws_sync.send({cmd: "fleetpower", power: e.match.value}));

let search_allow_change = 0;
on("input", "#searchterm", e => {
	search_allow_change = 1000 + +new Date;
	ws_sync.send({cmd: "search", term: e.match.value});
});

let max_interesting = { };

function upgrade(upg, tot) {
	if (!tot) return TD("");
	return TD({className: upg ? "interesting1" : ""}, upg + "/" + tot);
}

const sections = [];
function section(id, nav, lbl, render) {sections.push({id, nav, lbl, render});}

function province_list(prov) {
	if (Array.isArray(prov)) {
		if (typeof prov[0] === "string") return LI([prov[0], UL(prov.slice(1).map(province_list))]);
		return prov.map(province_list);
	}
	if (typeof prov === "number") return LI(PROV(prov));
	return LI(""+prov);
}

const rank_lbl = ["unranked", "1st", "2nd", "3rd"];
const render_mission = {
	confirm_thalassocracy: mission => TABLE({border: "1"}, mission.trade_nodes.map(([label, nodes]) => 
		TR([TH(label), nodes.map(node => TD({class: node.rank === 1 ? "interesting1" : ""}, [
			PROV(node.loc, node.name), BR(),
			node.percent + "% (" + (rank_lbl[node.rank] || node.rank + "th") + ")",
		]))]),
	)),
	"": mission => UL(mission.provinces.map(province_list)),
};

section("decisions_missions", "", "Decisions and Missions", state => [
	SUMMARY(`Decisions and Missions [${state.decisions_missions.length}]`),
	state.decisions_missions.map(mission => [
		H3([proventer(mission.id), mission.name]),
		(render_mission[mission.id] || render_mission[""])(mission),
		provleave(),
	]),
]);

section("cot", "CoTs", "Centers of Trade", state => {
	const content = [SUMMARY(`Centers of Trade (${state.cot.level3}/${state.cot.max} max level)`), proventer("cot")];
	for (let kwd of ["upgradeable", "developable"]) {
		const cots = state.cot[kwd];
		if (!cots.length) continue;
		//TODO: Make sortable() able to handle a pre-heading row that's part of the THEAD
		content.push(TABLE({id: kwd, border: "1"}, [
			TR(TH({colSpan: 5}, [proventer(kwd), `${kwd[0].toUpperCase()}${kwd.slice(1)} CoTs:`])),
			cots.map(cot => TR([
				TD(PROV(cot.id, cot.name)),
				TD([
					province_info[cot.id].has_port
						? SPAN({title: "Coastal COT"}, "🏖️")
						: SPAN({title: "Inland COT"}, "🏜️"),
					" ", cot.tradenode
				]),
				TD("Lvl "+cot.level), TD("Dev "+cot.dev), TD(cot.noupgrade)
			])),
		]));
		provleave();
	}
	provleave();
	return content;
});

function threeplace(n) {return (n / 1000).toFixed(2);}
function intify(n) {return ""+Math.floor(n / 1000);}
function money(n) {return SPAN({style: "color: #770"}, threeplace(n));}

function tradenode_order(a, b) {
	if (a.passive_income < 0) return -1; //Any "incalculable" entries get pushed to the start to get your attention.
	if (b.passive_income < 0) return 1;
	//Otherwise, sort by the improvement that a merchant gives.
	return (b.active_income - b.passive_income) - (a.active_income - a.passive_income);
}

section("trade_nodes", "Trade nodes", "Trade nodes", state => [
	SUMMARY("Trade nodes"),
	DETAILS([SUMMARY("Explanatory notes"), UL([
		LI([
			"This tool assumes that you collect ONLY in your home trade node, and in all other nodes, transfer trade ",
			"towards your home. It attempts to maximize the profit in such a situation, but does not take into account ",
			"the impact on your neighbours; you may consider it beneficial to wrest trade value from your rivals, while ",
			"avoiding impairing your allies and subjects, but that is outside the scope of this tool.",
		]),
		LI([
			"During war, these stats may be inaccurate due to the inherent limitations of savefile reading. Besieged and ",
			"occupied provinces have trade power penalties, making these estimates less accurate (both directions, if you ",
			"occupy other nations' lands). Make peace before depending on these figures.",
		]),
		LI([
			"Node value and total power should correspond with the respective values in F1, 5, the Trade tab. Each node ",
			"is identified with the number of downstream nodes from it - 0 indicates an end node, 1 a transfer node, ",
			"and 2 or more a decider node, where the direction of trade steering makes a difference.",
		]),
		LI([
			"Your share - if the trade in this node is increased by 1 ducat/month, how much would you gain? Includes ",
			"all downstream profit, including trade efficiency bonuses. Based on current stats only; your share can and ",
			"usually will increase when you send traders around. Always steer trade towards a node where you have a ",
			"high share of the profits. Note that, as the game goes on, this value will tend to increase across the ",
			"board, as trade efficiency bonuses accumulate; it is most valuable to focus on the variances between nodes.",
		]),
		LI([
			"Passive - What happens if you do nothing? At your home node, this means passive collection; anywhere else, ",
			"it means passive transfer, where your trade power attempts to pull trade away from the node, but without ",
			"choosing a destination (and without boosting the trade link).",
		]),
		LI([
			"Active - What happens if you have a merchant here? At your home node, this means adding 2 trade power, ",
			"permitting a trade policy (which defaults to giving 5% more trade power), and adding 10% trade efficiency ",
			"at this node only. Anywhere else, it means steering trade towards whichever downstream node you have the ",
			"highest share of revenue in, along with the same increases in trade power (but not efficiency).",
		]),
		LI([
			"Benefit - the difference between Active and Passive. Nodes are sorted with the highest benefit first.",
		]),
		LI([
			"Caution: If you collect from trade at any node other than your home, this tool will give no useful data ",
			"for that node, showing only 'Incalculable' for all estimates. However, the collection at this node WILL ",
			"be factored into the estimates of value for other nodes. Make your own decisions about where to collect, ",
			"and then use this tool to help you position your transferring merchants. Aside from your home node, it is ",
			"likely beneficial only to collect at an end node where you have considerable trade power.",
		]),
	])]),
	P(LABEL(["Light ship fleet power: ", INPUT({id: "fleetpower", type: "number", value: "" + state.fleetpower / 1000})])),
	sortable({id: "tradenodes", border: "1"},
		["Node name", "#Node value", "#Total power", "#Your share",
			"Currently", "#Passive", "#Active", "#Benefit", "#Fleet"],
		state.trade_nodes.sort(tradenode_order).map(node => {
			return TR({class: "hh-reset " + node.id}, [
				TD([
					B(node.name), " ",
					ABBR({
						class: node.downstreams.length ? "hoverhighlight" : "",
						"data-selector": node.downstreams.map(ds => "." + ds).join(","),
						title: !node.downstreams.length ? "End node, no downstreams"
							: "Downstreams: " + node.downstreams, //TODO: Show this more nicely
					}, "(" + node.downstreams.length + ")"),
					" ", GOTOPROV(node.province, ""),
				]),
				TD(threeplace(node.total_value)),
				TD(threeplace(node.total_power)),
				TD(threeplace(node.received)),
				TD([
					node.has_capital && "Home ", //TODO: Emoji?
					node.trader && " - " + node.trader,
					node.current_collection && [
						" ",
						money(node.current_collection),
					],
				]),
				...(node.passive_income < 0 ? [1,2,3,4].map(() => TD({"data-sortkey": -1}, "Incalculable")) : [
					TD({"data-sortkey": node.passive_income}, money(node.passive_income)),
					TD({"data-sortkey": node.active_income}, money(node.active_income)),
					TD({"data-sortkey": node.active_income - node.passive_income}, money(node.active_income - node.passive_income)),
					TD({"data-sortkey": node.fleet_benefit}, node.fleet_benefit < 0 ? "" : money(node.fleet_benefit)),
				]),
			]);
		}),
	),
]);

function clearhh(par) {par.querySelectorAll(".hh-reset").forEach(el => el.classList.remove("interesting2"));}
on("mouseover", ".hoverhighlight", e => {
	const parent = DOM("#tradenodes"); //If this is to be reused, parameterize this somehow.
	clearhh(parent);
	parent.querySelectorAll(e.match.dataset.selector).forEach(el => el.classList.add("interesting2"));
});

on("mouseout", ".hoverhighlight", e => clearhh(DOM("#tradenodes")));

section("monuments", "Monuments", "Monuments", state => [
	SUMMARY(`Monuments [${state.monuments.length}]`),
	sortable({id: "monumentlist", border: "1"},
		[[proventer("monuments"), "Province"], "Tier", "Project", "Upgrading", "Requires"],
		state.monuments.map(m => TR([
			TD(PROV(m.province)),
			TD("Lvl " + m.tier),
			TD(m.name),
			TD(m.upgrading && [
				m.upgrading === "moving" && "Moving: ",
				Math.floor(m.progress / 10) + "%, due ",
				m.completion,
			]),
			TD({
				style: "background: " + ["unset", "#ded", "#ddf", "#ccc"][m.req_achieved],
				"data-sortkey": m.req_achieved + m.requirements,
			}, m.requirements),
		])),
	),
	provleave(),
]);

section("coal_provinces", "Coal", "Coal provinces", state => {
	max_interesting.coal_provinces = 0;
	const content = [
		SUMMARY(`Coal-producing provinces [${state.coal_provinces.length}]`),
		sortable({id: "coalprovs", border: "1"},
			[[proventer("coal_provinces"), "Province"], "Manufactory", "Dev", "Buildings"],
			state.coal_provinces.map(m => TR({className: m.status ? "" : "interesting" + (max_interesting.coal_provinces = 1)},
				//TODO: set the sort key to a sortable date if it's a date, else the status
				[TD(PROV(m.id, m.name)), TD({"data-sortkey": m.status}, m.status), TD(m.dev+""), TD(m.buildings + "/" + m.slots)])),
		),
	];
	provleave();
	return content;
});

section("favors", "", "Favors", state => {
	let free = 0, owed = 0, owed_total = 0;
	function compare(val, base) {
		if (val <= base) return val.toFixed(3);
		return ABBR({title: val.toFixed(3) + " before cap"}, base.toFixed(3));
	}
	const cooldowns = state.favors.cooldowns.map(cd => {
		if (cd[1] === "---") ++free;
		return TR(cd.slice(1).map(d => TD(d)));
	});
	const countries = Object.entries(state.favors.owed).sort((a,b) => b[1][0] - a[1][0]).map(([c, f]) => {
		++owed_total; if (f[0] >= 10) ++owed;
		return TR([TD(COUNTRY(c)), f.map((n,i) => TD(compare(n, i ? +state.favors.cooldowns[i-1][4] : n)))]);
	});
	return [
		SUMMARY(`Favors [${free}/3 available, ${owed}/${owed_total} owe ten]`),
		P("NOTE: Yield estimates are often a bit wrong, but can serve as a guideline."),
		TABLE({border: "1"}, cooldowns),
		sortable({id: "favor_effects", border: "1"},
			"Country Favors Ducats Manpower Sailors",
			countries,
		),
	];
});

function find_country(name) {
	for (let [t, c] of Object.entries(country_info))
		if (c.name === name) return COUNTRY(t);
	return name; //Not found? Return the name itself as flat text (eg if the country has changed name, or formed something else)
}
function war_rumours(pending) {
	return sortable({id: "warrumours", border: "1"},
		"Atk Def Rumoured Declared",
		pending.map(r => TR([
			TD(find_country(r.atk)),
			TD(find_country(r.def)),
			TD(r.rumoured),
			TD(r.declared ? [r.declared, " - ", r.war] : ""),
		])),
	);
}
section("wars", "Wars", "Wars", state => [SUMMARY("Wars: " + (state.wars.current.length || "None")), [
	DIV({id: "war_rumours"}, war_rumours(state.wars.rumoured)),
	state.wars.current.map(war => {
		//For each war, create or update its own individual DETAILS/SUMMARY. This allows
		//individual wars to be collapsed as uninteresting without disrupting others.
		let id = "warinfo-" + war.name.toLowerCase().replace(/[^a-z]/g, " ").replace(/ +/g, "-");
		//It's possible that a war involving "conquest of X" might collide with another war
		//involving "conquest of Y" if the ASCII alphabetics in the province names are identical.
		//While unlikely, this would be quite annoying, so we add in the province ID when a
		//conquest CB is used. TODO: Check this for other CBs eg occupy/retain capital.
		if (war.cb) id += "-" + war.cb.type + "-" + (war.cb.province||"no-province");
		//NOTE: The atk and def counts refer to all players. Even if you aren't interested in
		//wars involving other players but not yourself, they'll still have their "sword" or
		//"shield" indicator given based on any player involvement.
		const atkdef = (war.atk ? "\u{1f5e1}\ufe0f" : "") + (war.def ? "\u{1f6e1}\ufe0f" : "");
		return DETAILS({open: true}, [
			SUMMARY(atkdef + " " + war.name),
			sortable({id: "army" + id, border: "1"},
				["Country", "Infantry", "Cavalry", "Artillery",
					ABBR({title: "Merc infantry"}, "Inf $$"),
					ABBR({title: "Merc cavalry"}, "Cav $$"),
					ABBR({title: "Merc artillery"}, "Art $$"),
					"Total", "Manpower", ABBR({title: "Army professionalism"}, "Prof"),
					ABBR({title: "Army tradition"}, "Trad"),
				],
				war.armies.map(army => TR({className: army[0].replace(",", "-")}, [TD(COUNTRY(army[1])), army.slice(2).map(x => TD(x ? ""+x : ""))])),
			),
			sortable({id: "navy" + id, border: "1"},
				["Country", "Heavy", "Light", "Galley", "Transport", "Total", "Sailors",
					ABBR({title: "Navy tradition"}, "Trad"),
				],
				war.navies.map(navy => TR({className: navy[0].replace(",", "-")}, [TD(COUNTRY(navy[1])), navy.slice(2).map(x => TD(x ? ""+x : ""))])),
			),
		]);
	}),
]]);

on("click", ".analyzebattles", e => ws_sync.send({cmd: "analyzebattles", tag: e.match.dataset.tag}));
//ws_sync.send({cmd: "analyzebattles", tag: "D00"}); //HACK
let battledata = null;
export function sockmsg_analyzebattles(msg) {
	battledata = msg;
	msg.countries.forEach((country, which) => {
		replace_content("#battles_nation_" + which, COUNTRY(country.tag));
		replace_content("#battles_army_" + which, [
			OPTION({value: ""}, "Select..."),
			country.armies.map((army, i) => OPTION({value: i}, [
				army.name,
				" (" + army.infantry + "/" + army.cavalry + "/" + army.artillery + ")",
				//TODO: General, if any. Distinguish a 0/0/0/0 general from no general at all?
			])),
		]).value = "";
	});
	DOM("#battlesdlg").showModal();
}

function recalc_battles() {
	//...
}
on("change", "#battlesdlg select", recalc_battles);
on("click", "#battlesdlg input[type=checkbox]", recalc_battles);

section("badboy_hatred", "Badboy", "Aggressive Expansion (Badboy)", state => {
	let hater_count = 0, have_coalition = 0;
	const haters = state.badboy_hatred.map(hater => {
		const info = country_info[hater.tag];
		const attr = { };
		if (hater.in_coalition) {attr.className = "interesting2"; have_coalition = 1;}
		if (!info.overlord && !info.truce) ++hater_count;
		return TR([
			TD({class: info.opinion_theirs < 0 ? "interesting1" : ""}, info.opinion_theirs),
			TD({class: hater.badboy >= 50000 ? "interesting1" : ""}, Math.floor(hater.badboy / 1000) + ""),
			TD(Math.floor(hater.improved / 1000) + ""),
			TD(attr, COUNTRY(hater.tag)),
			TD(attr, [
				info.overlord && SPAN({title: "Is a " + info.subject_type + " of " + country_info[info.overlord].name}, "🙏"),
				info.truce && SPAN({title: "Truce until " + info.truce}, "🏳"),
				hater.in_coalition && SPAN({title: "In coalition against you!"}, "😠"),
			]),
		]);
	});
	max_interesting.badboy_hatred = have_coalition ? 2 : hater_count ? 1 : 0;
	return [
		SUMMARY("Badboy Haters (" + hater_count + ")"),
		!hater_count && "Nobody is in a position to join a coalition against you.",
		sortable({id: "badboyhaters", border: "1"},
			["#Opinion", ABBR({title: "Aggressive Expansion", "data-numeric": 1}, "Badboy"), "#Improv", "Country", "Notes"],
			haters,
		),
	];
});

section("unguarded_rebels", "Rebels", "Unguarded rebels", state => {
	let max = "";
	const factions = state.unguarded_rebels.map(faction => TR([
		TD(faction.name),
		TD({class: faction.progress >= 80 ? max = "interesting2" : "interesting1"}, faction.progress + "%"),
		TD(UL({style: "margin: 0"}, faction.provinces.map(p => {
			prov_unrest[p.id] = p;
			return LI({"data-provid": p.id}, [PROV(p.id), BUTTON({class: "show_unrest"}, threeplace(p.unrest))]);
		}))),
	]));
	max_interesting.unguarded_rebels = max ? 2 : state.unguarded_rebels.length ? 1 : 0;
	return [
		SUMMARY("Unguarded rebels (" + state.unguarded_rebels.length + ")"),
		sortable({id: "rebel_factions", border: "1"},
			["Faction", "Progress", "Provinces"],
			factions,
		),
	];
});

section("subjects", "Subjects", "Subject nations", state => [
	SUMMARY("Subject nations (" + state.subjects.length + ")"),
	sortable({id: "subject_nations", border: "1"},
		["Country", "Type", "#Liberty", "#Opinion", "#Improved", "Since", "Integrate?", "Est"],
		state.subjects.map(subj => TR([
			TD(COUNTRY(subj.tag)),
			TD(subj.type),
			TD(subj.liberty_desire),
			TD([
				SPAN({style: "display: inline-block; width: 1.75em"}, country_info[subj.tag].opinion_theirs),
				BUTTON({class: "show_relations", "data-tag": subj.tag}, "🔍"),
			]),
			TD(Math.floor(subj.improved / 1000) + ""),
			TD(subj.start_date),
			TD({class: subj.can_integrate ? "interesting1" : ""}, subj.integration_date),
			subj.integration_finished ? TD({
				title: subj.integration_cost + " at " + subj.integration_speed + "/mo",
			}, subj.integration_finished) : TD(),
		])),
	),
]);
section("colonization_targets", "Colonies", "Colonization targets", state => [
	SUMMARY("Colonization targets (" + state.colonization_targets.length + ")"), //TODO: Count interesting ones too?
	sortable({id: "colo_targets", border: "1"},
		["Province", "Dev", "Geography", "Settler penalty", "Features"],
		state.colonization_targets.map((prov,i) => TR([
			TD(PROV(prov.id, prov.name)),
			TD(""+prov.dev),
			TD(prov.climate + " " + prov.terrain + (prov.has_port ? " port" : "")),
			TD(""+prov.settler_penalty),
			TD({"data-sortkey": prov.modifiers.length * 10000 + prov.cot * 1000 - prov.settler_penalty * 10 - i}, UL([
				prov.cot && LI("L" + prov.cot + " center of trade"),
				prov.modifiers.map(mod => LI(ABBR({title: mod.effects.join("\n")}, mod.name))),
			])),
		])),
	),
]);

function describe_culture_impact(cul, which, fmt) {
	return TD(
		{title: "Base " + fmt(cul[which + "_auto"]) + " (" + fmt(cul[which + "_base"]) + ")"},
		[fmt(cul[which + "_impact_auto"]), I(" (" + fmt(cul[which + "_impact"]) + ")")],
	);
}

section("cultures", "Cultures", "Cultures", state => [
	SUMMARY("Cultures (" + state.cultures.accepted_cur + "/" + state.cultures.accepted_max + " accepted)"),
	DETAILS({style: "margin: 1em"}, [SUMMARY("Notes"),
		P({style: "margin: 0 1em"}, [
			"The impact of promoting or demoting a culture is affected by local autonomy. The first number shown ",
			"here is the amount of monthly tax, max sailors, and max manpower gained/lost if you promote/demote ",
			"this culture right now; the second is what you could reach if autonomy zeroes out. Hover over the cell ",
			"to see the base values, from which these are calculated. Blue highlight indicates currently-accepted; ",
			"green highlight is cultures with enough development to be accepted (assuming it is all in states).",
		]),
	]),
	sortable({id: "culture_impact", border: "1"},
		["Culture", "Dev", "Status", "Tax", "Sailors", "Manpower"],
		state.cultures.cultures.map(cul => TR(
			{style: "background-color: " + (cul.accepted ? "#eeeef7" : cul.total_dev < 20000 ? "#e0e0e0" : "#eef7ee")}, [
			TD(cul.label),
			TD(threeplace(cul.total_dev)),
			TD({
				style: "color: " + {
					"primary": "#D4AF37",
					"brother": cul.accepted ? "#C0C0C0" : "#CD7F32",
					"foreign": cul.accepted ? "#C0C0C0" : "#7F0000",
				}[cul.status],
				title: cul.status === "primary" ? "Primary culture" :
					(cul.accepted ? "Accepted " : "Non-accepted ") + cul.status,
			}, "★"),
			describe_culture_impact(cul, "tax", threeplace),
			describe_culture_impact(cul, "sailors", intify),
			describe_culture_impact(cul, "manpower", intify),
		])),
	),
]);

section("highlight", "Buildings", "Building expansions", state => state.highlight.id ? [
	SUMMARY("Building expansions: " + state.highlight.name),
	P([proventer("expansions"), "If developed, these places could support a new " + state.highlight.name + ". "
		+ "They do not currently contain one, there is no building that could be upgraded "
		+ "to one, and there are no building slots free. This list allows you to focus "
		+ "province development in a way that enables a specific building; once the slot "
		+ "is opened up, the province will disappear from here and appear in the in-game "
		+ "macro-builder list for that building."]),
	sortable({id: "building_highlight", border: true},
		"Province Buildings Devel MP-cost",
		state.highlight.provinces.map(prov => TR([
			TD(PROV(prov.id, prov.name)),
			TD(`${prov.buildings}/${prov.maxbuildings}`),
			TD(""+prov.dev),
			TD(""+prov.cost[3]),
		])),
	),
	provleave(),
] : [
	SUMMARY("Building expansions"),
	P("To search for provinces that could be developed to build something, choose a building in" +
	" the top right options."),
]);

section("upgradeables", "Upgrades", "Upgrades available", state => [ //Assumes that we get navy_upgrades with upgradeables
	SUMMARY("Upgrades available: " + state.upgradeables.length + " building type(s), " + state.navy_upgrades.length + " fleet(s)"),
	P([proventer("upgradeables"), state.upgradeables.length + " building type(s) available for upgrade."]),
	UL(state.upgradeables.map(upg => LI([
		proventer(upg[0]), upg[0] + ": ",
		upg[1].map(prov => PROV(prov.id, prov.name)),
		provleave(),
	]))),
	provleave(),
	P(state.navy_upgrades.length + " fleets(s) have outdated ships."),
	sortable({id: "navy_upgrades", border: true},
		["Fleet", "Heavy ships", "Light ships", "Galleys", "Transports"],
		state.navy_upgrades.map(f => TR([
			TD(f.name),
			upgrade(...f.heavy_ship),
			upgrade(...f.light_ship),
			upgrade(...f.galley),
			upgrade(...f.transport),
		])),
	),
]);

section("flagships", "Flagships", "Flagships of the World", state => [
	SUMMARY("Flagships of the World (" + state.flagships.length + ")"),
	sortable({id: "flagship_list", border: true},
		["Country", "Fleet", "Vessel", "Modifications", "Built by"],
		state.flagships.map(f => TR([TD(COUNTRY(f[0])), TD(f[1]), TD(f[2] + ' "' + f[3] + '"'), TD(f[4].join(", ")), TD(f[5])])),
	),
]);

section("golden_eras", "Golden Eras", "Golden Eras", state => [
	SUMMARY("Golden Eras (" + state.golden_eras.reduce((a,b) => a + b.active, 0) + ")"),
	sortable({id: "golden_era_list", border: true},
		["Country", "Start", "End"],
		state.golden_eras.map(c => TR({class: c.active ? "interesting1" : ""}, [
			TD(COUNTRY(c.tag, c.countryname)),
			TD(c.startdate),
			TD(c.enddate),
		])),
	),
]);

//Render an array of text segments as DOM elements
function render_text(txt) {
	if (typeof txt === "string") return txt;
	if (Array.isArray(txt)) return txt.map(render_text);
	if (txt.color) return SPAN({style: "color: rgb(" + txt.color + ")"}, render_text(txt.text));
	if (txt.abbr) return ABBR({title: txt.title}, txt.abbr);
	if (txt.icon) return IMG({src: txt.icon, alt: txt.title, title: txt.title});
	if (txt.prov) return PROV(txt.prov, txt.nameoverride, txt.namelast);
	if (txt.country) return PROV(txt.country, txt.nameoverride);
	return render_text({abbr: "<ERROR>", title: "Unknown text format: " + Object.keys(txt)});
}
//Note that this can and will be updated independently of the rest of the save file.
section("recent_peace_treaties", "Peaces", "Recent peace treaties", state => [
	SUMMARY(`Recent peace treaties: ${state.recent_peace_treaties.length}`),
	UL(state.recent_peace_treaties.map(t => LI(render_text(t)))),
]);

section("truces", "Truces", "Truces", state => [
	SUMMARY("Truces: " + state.truces.map(t => t.length - 1).reduce((a,b) => a+b, 0) + " countries, " + state.truces.length + " blocks"),
	state.truces.map(t => [
		H3(t[0]),
		UL(t.slice(1).map(c => LI([COUNTRY(c[0]), " ", c[1]]))),
	]),
]);

section("cbs", "CBs", "Casus belli", state => [
	SUMMARY(`Casus belli: ${state.cbs.from.tags.length} potential victims, ${state.cbs.against.tags.length} potential aggressors`),
	//NOTE: The order here (from, against) has to match the order in the badboy/prestige/peace_cost arrays (attacker, defender)
	[["from", "CBs you have on others"], ["against", "CBs others have against you"]].map(([grp, lbl], scoreidx) => [
		H3(lbl),
		BLOCKQUOTE(Object.entries(state.cbs[grp]).map(([type, cbs]) => type !== "tags" && [
			(t => H4([
				ABBR({title: t.desc}, t.name),
				" ",
				t.restricted && SPAN({className: "caution", title: t.restricted}, "⚠️"),
				" (", ABBR({title: "Aggressive Expansion"}, Math.floor(t.badboy[scoreidx] * 100) + "%"),
				", ", ABBR({title: "Prestige"}, Math.floor(t.prestige[scoreidx] * 100) + "%"),
				", ", ABBR({title: "Peace cost"}, Math.floor(t.peace_cost[scoreidx] * 100) + "%"),
				")",
			]))(state.cbs.types[type]),
			UL(cbs.map(cb => LI([
				COUNTRY(cb.tag),
				cb.end_date && " (until " + cb.end_date + ")",
			]))),
		])),
	]),
]);

section("miltech", "Mil tech", "Military technology", state => {
	const mine = state.miltech.levels[state.miltech.current];
	function value(tech, key, refkey) {
		if (typeof tech === "number") tech = state.miltech.levels[tech];
		const myval = mine[refkey ? state.miltech.units + refkey : key] || 0, curval = tech[key] || 0;
		let className = "tech";
		if (curval > myval) className += " above";
		if (curval < myval) className += " below";
		return SPAN({className}, ""+((curval-myval)/1000));
	}
	_saved_miltech = value; //hacky hacky
	const hover = country_info[hovertag || "SOM"] || {tech: [-1,-1,-1]};
	const headings = TR(["Level", "Infantry", "Cavalry", "Artillery", "Morale", "Tactics", state.miltech.groupname, hover.name || ""].map(h => TH(h)));
	//Hack: Put a CSS class on the last heading.
	headings.children[headings.children.length - 1].attributes.className = "hovercountry";
	return [
		SUMMARY(`Military technology (${state.miltech.current})`),
		TABLE({border: true, class: hover.name ? "" : "hoverinactive"}, [
			THEAD(headings),
			state.miltech.levels.map((tech, i) => TR({
				class: i === state.miltech.current ? "interesting1"
				: i === hover.tech[2] ? "interesting2" : "",
				"data-tech": i,
			}, [
				TD([""+i, i === state.miltech.current && " (you)"]),
				TD([value(tech, "infantry_fire"), " / ", value(tech, "infantry_shock")]),
				TD([value(tech, "cavalry_fire"), " / ", value(tech, "cavalry_shock")]),
				TD([value(tech, "artillery_fire"), " / ", value(tech, "artillery_shock")]),
				TD(value(tech, "land_morale")),
				TD(value(tech, "military_tactics")),
				TD([
					value(tech, state.miltech.group + "_infantry"), " / ",
					value(tech, state.miltech.group + "_cavalry"), " / ",
					value(tech, "0_artillery"), //Arty doesn't go by groups
				]),
				TD({class: "hovercountry", "data-tech": i}, hover.name && [
					value(tech, hover.unit_type + "_infantry", "_infantry"), " / ",
					value(tech, hover.unit_type + "_cavalry", "_cavalry"), " / ",
					value(tech, "0_artillery"),
				]),
			])),
		]),
	];
});

export function render(state) {
	curgroup = []; provgroups = { };
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
		IMG({className: "flag large", id: "playerflag", alt: "[flag of player's nation]"}),
		H1({id: "player"}),
		DETAILS({id: "selectprov"}, [
			SUMMARY("Find a province/country"),
			DIV({id: "search"}, H3("Search for a province or country")),
			DIV({id: "pin"}, H3("Pinned provinces")),
			DIV({id: "vital_interest"}, H3("Vital Interest")),
		]),
		sections.map(s => DETAILS({id: s.id}, SUMMARY(s.lbl))),
		DIV({id: "options"}, [ //Positioned fixed in the top corner
			BUTTON({id: "optexpand", title: "Show options and notifications"}, "🖈"),
			LABEL([
				"Building highlight: ",
				SELECT({id: "highlight_options"}, OPTGROUP({label: "Building highlight"})),
				SPAN({id: "spacer"}),
			]),
			DIV({id: "cyclegroup"}),
			UL({id: "interesting_details"}),
			UL({id: "notifications"}),
			DIV({id: "agenda"}),
			DIV({id: "now_parsing", className: "hidden"}),
			DIV({id: "hovercountry", className: "hidden"}),
		]),
		BUTTON({id: "customnations"}, "Custom nations"),
		//Always have DETAILS/SUMMARY nodes for every expandable, such that,
		//whenever content is updated, they remain in their open/closed state.
	]) && window.onresize();

	if (state.error) {
		replace_content("#error", [state.error, state.parsing > -1 ? state.parsing + "%" : ""]).classList.remove("hidden");
		return;
	}
	replace_content("#error", "").classList.add("hidden");
	if (state.province_info) province_info = state.province_info;
	if (state.countries) country_info = state.countries;
	selected_provgroup = state.cyclegroup || ""; //TODO: Allow the cycle group to be explicitly cleared, rather than assuming removal
	selected_prov_cycle = state.cycleprovinces || [];
	if (state.tag) {
		const c = country_info[countrytag = state.tag];
		DOM("#playerflag").src = "/flags/" + c.flag + ".png";
	}
	if (state.pinned_provinces) {
		pinned_provinces = { };
		replace_content("#pin", [H3([proventer("pin"), "Pinned provinces: " + state.pinned_provinces.length]),
			UL(state.pinned_provinces.map(([id, name]) => LI(PROV(pinned_provinces[id] = id, name, 1)))),
		]);
		provleave();
	}
	if (state.vital_interest) replace_content("#vital_interest", [
		H3([proventer("vital_interest"), "Vital Interest: " + state.vital_interest.length]),
		UL(state.vital_interest.map(([id, name]) => LI(PROV(id, name, 1)))),
		provleave(),
	]);
	if (state.search) {
		const input = DOM("#searchterm") || INPUT({id: "searchterm", size: 30});
		const focus = input === document.activeElement;
		replace_content("#search", [H3([proventer("search"), "Search results: " + state.search.results.length]),
			P({className: "indent"}, LABEL(["Search for:", input])),
			UL(state.search.results.map(info => LI(
				(typeof info[0] === "number" ? PROV : COUNTRY)(info[0], [info[1], STRONG(info[2]), info[3]])
			))),
			provleave(),
		]);
		if (state.search.term !== input.value) {
			//Update the input, but avoid fighting with the user
			let change_allowed = search_allow_change - +new Date;
			if (change_allowed <= 0) input.value = state.search.term;
			//else ... hold the change for the remaining milliseconds, and then do some sort of resynchronization
		}
		if (focus) input.focus();
	}
	if (typeof state.parsing === "number") {
		if (state.parsing > 0) replace_content("#now_parsing", "Parsing savefile... " + state.parsing + "%").classList.remove("hidden");
		else if (state.parsing > -1) replace_content("#now_parsing", "Parsing savefile...").classList.remove("hidden");
		else replace_content("#now_parsing", "").classList.add("hidden");
	}
	if (state.menu) {
		function lnk(dest) {return A({href: "/tag/" + encodeURIComponent(dest)}, dest);}
		replace_content("#menu", [
			"Save file parsed. Pick a player nation to monitor, or search for a country:",
			UL(state.menu.map(c => LI([lnk(c[0]), " - ", lnk(c[1])]))),
			FORM([
				LABEL(["Enter tag or name:", INPUT({name: "q", placeholder: "SPA"})]),
				INPUT({type: "submit", value: "Search"}),
			]),
		]).classList.remove("hidden");
		return;
	}
	if (state.name) replace_content("#player", state.name);
	sections.forEach(s => state[s.id] && replace_content("#" + s.id, s.render(state)));
	if (state.buildings_available) replace_content("#highlight_options", [
		OPTION({value: "none"}, "None"),
		OPTGROUP({label: "Need more of a building? Choose one to highlight places that could be expanded to build it."}), //hack
		Object.values(state.buildings_available).map(b => OPTION(
			{value: b.id},
			b.name, //TODO: Keep this brief, but give extra info, maybe in hover text??
		)),
	]).value = (state.highlight && state.highlight.id) || "none";
	update_hover_country(hovertag);
	const is_interesting = [];
	Object.entries(max_interesting).forEach(([id, lvl]) => {
		const el = DOM("#" + id + " > summary");
		if (lvl) is_interesting.push(LI({className: "interesting" + lvl, "data-id": id}, el.innerText));
		el.className = "interesting" + lvl;
	});
	replace_content("#interesting_details", is_interesting);
	if (state.cyclegroup) {
		if (!state.cycleprovinces) ws_sync.send({cmd: "cycleprovinces", cyclegroup: state.cyclegroup, provinces: provgroups[state.cyclegroup] || []});
		replace_content("#cyclegroup", [
			"Selected group: " + state.cyclegroup + " ",
			SPAN({className: "provnext"}, "⮞"), " ",
			SPAN({className: "provgroup clear"}, "❎"),
		]);
	}
	else replace_content("#cyclegroup", "");
	if (state.notifications) replace_content("#notifications", state.notifications.map(n => LI({className: "interesting2"}, ["🔔 ", render_text(n)])));
	if (state.agenda && state.agenda.expiry) {
		//Regardless of the agenda, you'll have a description and an expiry date.
		//The description might contain placeholders "[agenda_province.GetName]"
		//and/or "[agenda_country.GetUsableName]", which should be replaced with
		//PROV() and COUNTRY() markers respectively. It may also contain other
		//markers. Currently we have no way to handle these here on the client,
		//so hopefully the server can cope with them on our behalf.
		let prov = state.agenda.province && PROV(state.agenda.province, state.agenda.province_name);
		let country = state.agenda.country && COUNTRY(state.agenda.country);
		let rival_country = state.agenda.rival_country && COUNTRY(state.agenda.rival_country);
		let info = ["Agenda expires ", state.agenda.expiry, ": ", BR()];
		let desc = state.agenda.desc;
		let spl;
		while (spl = /^(.*)\[([^\]]*)\](.*)$/.exec(desc)) {
			info.push(spl[1]);
			switch (spl[2]) {
				case "agenda_province.GetName": info.push(prov || "(province)"); prov = null; break;
				case "agenda_country.GetUsableName": info.push(country || "(country)"); country = null; break;
				case "rival_country.GetUsableName": info.push(rival_country || "(rival)"); rival_country = null; break;
				default: info.push(B(spl[2])); //Unknown marker type, which the server didn't translate for us. A bit ugly.
			}
			desc = spl[3];
		}
		info.push(desc);
		if (prov) info.push(BR(), "See: ", prov); //If there's no placeholder, but there is a focus-on province/country, show it underneath.
		if (country) info.push(BR(), "See: ", country);
		replace_content("#agenda", info);
	}
	else if (state.agenda) replace_content("#agenda", "");
	if (curgroup.length) replace_content("#error", "INTERNAL ERROR: Residual groups " + curgroup.join("/")).classList.remove("hidden");
	if (state.war_rumours) replace_content("#war_rumours", war_rumours(state.war_rumours));

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

on("click", ".sorthead", e => {
	const tb = e.match.closest("table"), id = tb.id, idx = e.match.dataset.idx;
	if (sort_selections[id] === idx) sort_selections[id] = "-" + idx; //Note that "-0" is distinct from "0", as they're stored as strings
	else sort_selections[id] = idx;
	sortable(...tb._sortable_config);
});

//TODO: Generalize this Relations thing so you can get it for any country
on("click", ".show_relations", e => {
	const tag = e.match.closest("[data-tag]").dataset.tag;
	console.log(country_info[tag]);
	replace_content("#detailsmain", [
		P(["Relations with ", COUNTRY(tag), " ",
			B({title: "Their opinion of you"}, country_info[tag].opinion_theirs),
			" / ", B({title: "Your opinion of them"}, country_info[tag].opinion_yours)]),
		sortable({id: "relations_detail", border: "1"},
			["Reason", "Effect", "Per year", "Expiration"],
			country_info[tag].relations.map(rel => TR([
				TD(rel.name),
				TD(rel.current_opinion),
				TD(rel.yearly_decay),
				//I do not understand what "expiry_date" means. It seems to be boolean,
				//with false meaning "has an expiry date". Yes - False means that. ??????
				TD(rel.expiry_date ? "" : rel.date),
			])),
		),
	]);
	replace_content("#detailsdlg h3", "Detailed relations breakdown");
	DOM("#detailsdlg").showModal();
});

let prov_unrest = { };
on("click", ".show_unrest", e => {
	const provid = e.match.closest("[data-provid]").dataset.provid;
	const unrest = prov_unrest[provid];
	replace_content("#detailsmain", [
		P(["Unrest in ", PROV(provid), " ",
			B(threeplace(unrest.unrest))]),
		UL(unrest.sources.map(s => {
			const m = /(.*): (-?[0-9]+)$/.exec(s); //It's probably not worth reworking things to have a description and number
			return LI([m[1], ": ", SPAN({style: "font-weight: bold; color: " + (m[2] < 0 ? "green" : "red")}, threeplace(m[2]))]);
		})),
	]);
	replace_content("#detailsdlg h3", "Sources of unrest");
	DOM("#detailsdlg").showModal();
});

let custom_nations = { }, custom_ideas = [], map_colors = [];
let custom_filename = null, selected_idea = -1;
let effect_display_mode = { };

//Never have identify() return "*" - that's used for the "all" option.
const idea_filters = {
	cat: {
		lbl: "Category",
		identify(idea) {return idea.category;},
	},
	free: {
		lbl: "Free option?",
		identify(idea) {return +idea.level_cost_1 > 0 ? "No free option" : "Free option";},
	},
	maxcost: {
		lbl: "Max cost",
		identify(idea) {return +idea["level_cost_" + idea.max_level];},
		sortorder(a, b) {return a - b;}
	},
	type: {
		lbl: "Type",
		identify(idea) {return "Other (TODO)";}
		//Options: Ducats, Manpower, Mana, Time, Nation (prestige, legit, etc), Diplomacy?, Army, Navy, Other
		//May need to be a multiselect. For instance, autonomy change modifier will benefit
		//both ducats and manpower.
	}
};

function nation_flag(colors, cls="small") {
	return colors && IMG({class: "flag " + cls,
		src: `/flags/Custom-${colors.symbol_index}-${colors.flag}-`
			+ colors.flag_colors.join("-") + ".png",
		alt: "[flag of custom nation]",
	});
}

on("click", "#customnations", e => ws_sync.send({cmd: "listcustoms"}));
export function sockmsg_customnations(msg) {
	custom_nations = msg.nations; custom_ideas = msg.custom_ideas;
	map_colors = msg.map_colors; effect_display_mode = msg.effect_display_mode;
	custom_filename = null;
	//Skim over the custom ideas and identify them to each filter
	Object.values(idea_filters).forEach(fil => fil.opts = { });
	custom_ideas.forEach(idea => {
		idea.filters = { };
		Object.entries(idea_filters).forEach(([id, fil]) => {
			const opt = fil.identify(idea);
			fil.opts[opt] = 1;
			idea.filters[id] = opt;
		});
	});
	replace_content("#ideafilterstyles", Object.entries(idea_filters).map(([id, fil]) => {
		fil.opts = Object.keys(fil.opts).sort(fil.sortorder);
		//For every option, filter out every other option.
		return fil.opts.map(keep => fil.opts.map(check => check !== keep &&
			`[data-filter${id}="${keep}"] [data-filteropt${id}="${check}"] {display: none;}\n`));
	}));
	//Okay. So now, for every filter, we have a (sorted) list of the possible options it yields;
	//and for every idea, we have the options it fits into.
	replace_content("#customnationmain", [
		"Available custom nations:",
		UL(Object.entries(custom_nations).map(([fn, nat]) => LI([
			A({href: "#" + fn}, fn), " - ",
			nation_flag(nat.country_colors),
			" ", nat.name || "Unnamed",
			" (the ", nat.adjective || "Unnamed", "s) ",
		]))),
	]);
	DOM("#custompwd").hidden = true;
	DOM("#customnationsdlg").showModal();
}

function effectvalue(idea, value) {
	let mode = effect_display_mode[idea.effects[0]];
	if ((!mode || mode === "threeplace") && !(idea.effectvalue % 1000)) mode = "integer";
	switch (mode) {
		case "percent": return (value / 10) + "%";
		case "integer": return (value / 1000) + "";
		case "boolean": return "Yes"; //The idea always enables, never disables, so it'll never be set to "No"
		default: return threeplace(value);
	}
}

//Traditions and early ideas cost more. Traditions are late in the array.
const slotcosts = [100, 80, 60, 40, 20, 0, 0, 100, 100, 0];
let idea_imbalance_penalty = 0, total_idea_cost = 0;
function IDEA(idea, slot) { //no, not IKEA
	const info = custom_ideas[idea.index];
	const cost_base = info["level_cost_" + idea.level]|0;
	const cost_pos = cost_base * slotcosts[slot] / 100;
	const cost_imbal = Math.trunc(cost_base * idea_imbalance_penalty / 10) / 10; //Penalty is rounded towards zero, to one decimal place
	let title = "Cost: " + cost_base + " base";
	if (cost_pos) title += " + " + cost_pos + " early";
	if (cost_imbal) title += " + " + cost_imbal + " imbalanced";
	total_idea_cost += cost_base + cost_pos + cost_imbal;
	return LI([
		SPAN({class: "ideacost", title}, cost_base + cost_pos + cost_imbal + ""), " ",
		info.effectname, " ", effectvalue(info, info.effectvalue * idea.level), " ",
		BUTTON({class: "editidea", "data-slot": slot}, "✍"),
	]);
}

on("click", "#customnationmain a", e => {
	e.preventDefault();
	custom_filename = new URL(e.match.href).hash.slice(1);
	update_nation_details();
});

function update_nation_details() {
	const nat = custom_nations[custom_filename];
	//Note that we assume here that there'll be precisely ten ideas
	//(the seven regular ideas, two traditions, and one ambition).
	//The game crashes if you try to load a file with fewer, so I'm
	//not too concerned about the possibility!!

	//Ideas get a cost penalty if you have too many of the same type.
	//(Note that this is a percentage, and WILL magnify negative costs
	//as well as positive. So go ahead, abuse the system, and make a
	//nation with horrifically-bad admin ideas!)
	let levels = {ADM: 0, DIP: 0, MIL: 0};
	nat.idea.forEach(idea => {
		const info = custom_ideas[idea.index];
		levels[info.category] += Math.floor(10 * idea.level / info.max_level);
	});
	const tot = levels.ADM + levels.DIP + levels.MIL;
	const max = Math.max(levels.ADM, levels.DIP, levels.MIL);
	//Note that the penalty is quantized to half a percent. Not sure why that exact cutoff.
	idea_imbalance_penalty = Math.max(Math.floor(max / tot * 1000 - 500) / 2, 0);
	total_idea_cost = 0;
	replace_content("#customnationmain", [
		"Custom nation: " + custom_filename + " ",
		nation_flag(nat.country_colors), BR(),
		nat.country_colors && ["Flag: ",
			BUTTON({class: "editflag", "data-which": "symbol_index", "data-max": 120}, "Emblem " + (+nat.country_colors.symbol_index + 1)),
			BUTTON({class: "editflag", "data-which": "flag", "data-max": 54}, "BG " + (+nat.country_colors.flag + 1)),
			BUTTON({class: "editflag", "data-which": "0", "data-max": 17}, "Color " + (+nat.country_colors.flag_colors[0] + 1)),
			BUTTON({class: "editflag", "data-which": "1", "data-max": 17}, "Color " + (+nat.country_colors.flag_colors[1] + 1)),
			BUTTON({class: "editflag", "data-which": "2", "data-max": 17}, "Color " + (+nat.country_colors.flag_colors[2] + 1)),
			BR(), "Map color: ",
			BUTTON({class: "editflag", "data-which": "color", "data-max": 100}, "Color " + (+nat.country_colors.color + 1)),
		],
		//TODO: Text inputs to let you edit the name and adjective
		H4(["Ideas ", SPAN({id: "total_idea_cost"})]),
		"Traditions:", BR(),
		UL([IDEA(nat.idea[7], 7), IDEA(nat.idea[8], 8)]),
		"Ideas:", BR(),
		UL(nat.idea.slice(0, 7).map(IDEA)),
		"Ambition:", BR(),
		UL(IDEA(nat.idea[9], 9)),
		"Categories: ",
			SPAN({title: levels.ADM + " levels"}, Math.floor(levels.ADM * 100 / tot) + "% ADM"), " ",
			SPAN({title: levels.DIP + " levels"}, Math.floor(levels.DIP * 100 / tot) + "% DIP"), " ",
			SPAN({title: levels.MIL + " levels"}, Math.floor(levels.MIL * 100 / tot) + "% MIL"), " => ",
			B(idea_imbalance_penalty + "% penalty"),
	]);
	set_content("#total_idea_cost", " - " + total_idea_cost + " points");
	DOM("#custompwd").hidden = false;
}

function update_filter_classes() {
	const main = DOM("#customideamain");
	document.querySelectorAll(".filters select").forEach(sel =>
		main.dataset["filter" + sel.dataset.filter] = sel.value
	);
}

function build_idea_list(filters) {
	const nat = custom_nations[custom_filename];
	const inuse = { };
	nat.idea.forEach(idea => inuse[idea.index] = 1);
	inuse[nat.idea[selected_idea].index] = 2;
	replace_content("#customideamain", [
		UL({class: "filters"}, Object.entries(idea_filters).map(([id, fil]) => LI(
			SELECT({"data-filter": id}, [
				OPTION({value: "*"}, fil.lbl),
				fil.opts.map(opt => OPTION(opt)),
			]),
		))),
		sortable({id: "ideaoptions"}, "Cat Effect Power #Cost", custom_ideas.map((idea, idx) => {
			const filters = { };
			Object.entries(idea.filters).forEach(([id, val]) => filters["data-filteropt" + id] = val);
			let costs = "", powers = [];
			for (let i = 1; i <= +idea.max_level; ++i) {
				costs += "/" + idea["level_cost_" + i];
				//TODO: If inuse[idx], highlight the level that's in use
				powers.push(BUTTON({class: "selectidea", "data-ideaidx": idx, "data-level": i},
					effectvalue(idea, idea.effectvalue * i)));
			}
			if (inuse[idx]) filters["class"] = "interesting" + inuse[idx];
			return TR(filters, [
				TD(idea.category),
				TD(ABBR({title: idea.id}, idea.effectname)),
				TD({"data-sortkey": idea.effectvalue, class: "powers"}, [
					powers, " ",
					BUTTON({class: "seteffectmode", "data-effect": idea.effects[0]},
						{"percent": "Y", "boolean": "#"}[effect_display_mode[idea.effects[0]]] || "%"),
				]),
				TD({"data-sortkey": idea["level_cost_" + idea.max_level]}, costs.slice(1)), //Sorting by cost sorts by max cost
			]);
		})),
	]);
	if (filters) document.querySelectorAll(".filters select").forEach(sel => sel.value = filters[sel.dataset.filter] || "*");
	update_filter_classes();
}

on("click", ".editidea", e => {
	selected_idea = e.match.dataset.slot;
	const nat = custom_nations[custom_filename];
	build_idea_list({cat: custom_ideas[nat.idea[selected_idea].index].category});
	DOM("#customideadlg").showModal();
	DOM("#customideadlg tr.interesting2").scrollIntoView();
});

on("click", ".seteffectmode", e => {
	const effect = e.match.dataset.effect;
	const mode = {"percent": "boolean", "boolean": "threeplace"}[effect_display_mode[effect]] || "percent";
	ws_sync.send({cmd: "set_effect_mode", effect, mode});
	effect_display_mode[effect] = mode;
	build_idea_list();
});

on("click", ".selectidea", e => {
	const d = e.match.dataset;
	const nat = custom_nations[custom_filename];
	nat.idea[selected_idea] = {index: d.ideaidx, level: d.level, name: "", desc: ""};
	DOM("#customideadlg").close();
	update_nation_details();
});

on("click", ".editflag", e => {
	const nat = custom_nations[custom_filename];
	const which = e.match.dataset.which;
	const basis = which.length === 1 ? nat.country_colors.flag_colors : nat.country_colors;
	const orig = basis[which];
	const items = [];
	const max = +e.match.dataset.max;
	for (let i = 0; i < max; ++i) {
		basis[which] = ""+i;
		items.push(BUTTON({
				class: "pickflag " + which, "data-which": which, "data-idx": i,
				"style": which === "color" ? "background-color: rgb(" + map_colors[i].join(", ") + ")" : "", //Color swatch view
			},
			which !== "color" && nation_flag(nat.country_colors, "large") //Flag view
		));
	}
	basis[which] = orig;
	replace_content("#customflagmain", items);
	DOM("#customflagdlg").showModal();
});

on("click", ".pickflag", e => {
	const nat = custom_nations[custom_filename];
	const which = e.match.dataset.which;
	const basis = which.length === 1 ? nat.country_colors.flag_colors : nat.country_colors;
	basis[which] = e.match.dataset.idx;
	DOM("#customflagdlg").close();
	update_nation_details();
});

on("change", ".filters select", update_filter_classes);

on("click", "#savecustom", e => {
	ws_sync.send({
		cmd: "savecustom", "filename": custom_filename,
		password: DOM("#savecustom_password").value,
		data: custom_nations[custom_filename],
	});
});
export function sockmsg_savecustom(msg) {
	console.log("RESULT FROM SAVING:", msg); //TODO: Put this in the DOM somewhere
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
