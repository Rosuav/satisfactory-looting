import {choc, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {H1} = choc; //autoimport

set_content("main", H1("Hello, world!"));

export function render(state) {
	console.log("Rendering!");
}
