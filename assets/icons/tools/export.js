// Icon exporter: SVG (assets/icons/svg) -> 256 px transparent PNG (assets/icons/png),
// contact sheet (assets/icons/contact-sheet.png) and manifest (assets/icons/manifest.json).
//
// Usage (from the repository root):
//   node assets/icons/tools/export.js                 export everything
//   node assets/icons/tools/export.js --review out.png also write a large review sheet (128 px icons)
//
// Requires Playwright with Chromium (`npm i -g playwright && npx playwright install chromium`).
// Existing rbxassetid values in manifest.json are preserved on re-export.
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.resolve(__dirname, "..");
const SVG_DIR = path.join(ROOT, "svg");
const PNG_DIR = path.join(ROOT, "png");
const SHEET = path.join(ROOT, "contact-sheet.png");
const MANIFEST = path.join(ROOT, "manifest.json");
const SIZE = 256;

// Contract with the UI code (Theme.IconAssets is keyed by these names). Order = contact sheet order.
const ICONS = [
	"yen", "gems", "gold", "tokens", "power", "fighters", "summon",
	"settings", "auto", "sort", "lock", "check", "close", "plus",
	"quests", "shop", "upgrades", "worlds", "raids", "boss", "zone",
	"target", "team", "timer", "sell", "new", "star", "kills",
];

// Only these colours may appear in an icon (docs/ui/UI_RESEARCH.md §3.1).
const PALETTE = {
	"#05070D": "Ink",
	"#FFFFFF": "White",
	"#CFEFFF": "Ice",
	"#4FD2FF": "Cyan",
	"#4A95FF": "Blue400",
	"#1E6BFF": "Blue500",
	"#1546B8": "Blue700",
	"#0A2A6B": "Blue900",
};

function lint(name, svg) {
	const problems = [];
	if (!/viewBox="0 0 128 128"/.test(svg)) problems.push("viewBox must be 0 0 128 128");
	if (/<text[\s>]/.test(svg)) problems.push("no <text>: draw glyphs as paths");
	if (/<image[\s>]|href="(?!#)/.test(svg)) problems.push("no embedded/external images");
	for (const m of svg.matchAll(/#[0-9a-fA-F]{3,8}\b/g)) {
		const hex = m[0].toUpperCase();
		if (!PALETTE[hex]) problems.push(`off-palette colour ${m[0]}`);
	}
	for (const m of svg.matchAll(/(?:fill|stroke)="(?!none|#|url\()([^"]+)"/g)) problems.push(`named colour "${m[1]}"`);
	if (problems.length) throw new Error(`${name}.svg: ${[...new Set(problems)].join("; ")}`);
}

const dataUri = (mime, buf) => `data:${mime};base64,${Buffer.from(buf).toString("base64")}`;

function sheetHtml(icons, { size, small, title }) {
	const cell = (icon) => `
		<div class="cell">
			<div class="row">
				<div class="tile dark"><img src="${icon.png}" width="${size}" height="${size}"></div>
				<div class="tile blue"><img src="${icon.png}" width="${size}" height="${size}"></div>
			</div>
			${small ? `<div class="row small">
				<div class="mini dark"><img src="${icon.png}" width="32" height="32"></div>
				<div class="mini blue"><img src="${icon.png}" width="32" height="32"></div>
			</div>` : ""}
			<div class="name">${icon.name}</div>
		</div>`;
	const tile = size + 32;
	return `<!doctype html><html><head><meta charset="utf-8"><style>
		* { box-sizing: border-box; margin: 0; padding: 0; }
		body { background: #080C16; color: #FFFFFF; font: 700 14px/1.2 "Segoe UI", Roboto, Arial, sans-serif; padding: 20px 24px 24px; width: max-content; }
		h1 { font-size: 20px; letter-spacing: .5px; margin-bottom: 4px; }
		p { color: #A9B8D9; font-size: 13px; margin-bottom: 16px; }
		.grid { display: grid; grid-template-columns: repeat(7, auto); gap: 18px 22px; }
		.cell { display: flex; flex-direction: column; align-items: center; gap: 6px; }
		.row { display: flex; gap: 8px; }
		.tile { width: ${tile}px; height: ${tile}px; display: grid; place-items: center; border: 3px solid #05070D; }
		.tile.dark { background: #0E1424; border-radius: 12px; box-shadow: inset 0 0 0 1.5px #2A3A66; }
		.tile.blue { background: #1E6BFF; border-radius: 20px; box-shadow: 0 4px 0 #0A2A6B; }
		.mini { width: 44px; height: 44px; display: grid; place-items: center; border: 2px solid #05070D; border-radius: 10px; }
		.mini.dark { background: #0E1424; }
		.mini.blue { background: #1E6BFF; }
		.name { font-size: 15px; color: #FFFFFF; -webkit-text-stroke: 0; text-shadow: 0 2px 0 #05070D; margin-top: 2px; }
		img { display: block; }
	</style></head><body>
		<h1>${title}</h1>
		<p>${icons.length} icons · ${size} px on Panel #0E1424 and on a Blue500 #1E6BFF button${small ? " · 32 px row for phone legibility" : ""} · source: assets/icons/svg · export: assets/icons/tools/export.js</p>
		<div class="grid">${icons.map(cell).join("")}</div>
	</body></html>`;
}

async function shoot(page, html, out) {
	await page.setViewportSize({ width: 600, height: 400 });
	await page.setContent(html, { waitUntil: "load" });
	await page.evaluate(() => Promise.all([...document.images].map((i) => i.decode())));
	const box = await page.evaluate(() => ({ w: document.body.scrollWidth, h: document.body.scrollHeight }));
	await page.setViewportSize({ width: Math.ceil(box.w), height: Math.ceil(box.h) });
	await page.screenshot({ path: out, fullPage: true });
}

(async () => {
	const reviewIdx = process.argv.indexOf("--review");
	const reviewOut = reviewIdx > 0 ? path.resolve(process.argv[reviewIdx + 1]) : null;

	const present = fs.readdirSync(SVG_DIR).filter((f) => f.endsWith(".svg")).map((f) => f.slice(0, -4));
	const missing = ICONS.filter((n) => !present.includes(n));
	const extra = present.filter((n) => !ICONS.includes(n));
	if (missing.length) throw new Error(`missing SVGs: ${missing.join(", ")}`);
	if (extra.length) console.warn(`warning: SVGs not in the icon list (not exported): ${extra.join(", ")}`);

	fs.mkdirSync(PNG_DIR, { recursive: true });
	const browser = await chromium.launch();
	const context = await browser.newContext({ deviceScaleFactor: 1 });
	const page = await context.newPage();
	await page.setViewportSize({ width: SIZE, height: SIZE });

	const icons = [];
	for (const name of ICONS) {
		const svg = fs.readFileSync(path.join(SVG_DIR, `${name}.svg`), "utf8");
		lint(name, svg);
		const html = `<!doctype html><html><head><style>html,body{margin:0;background:transparent}img{display:block}</style></head>
			<body><img src="${dataUri("image/svg+xml", svg)}" width="${SIZE}" height="${SIZE}"></body></html>`;
		await page.setContent(html, { waitUntil: "load" });
		await page.evaluate(() => document.images[0].decode());
		const out = path.join(PNG_DIR, `${name}.png`);
		await page.screenshot({ path: out, omitBackground: true, clip: { x: 0, y: 0, width: SIZE, height: SIZE } });
		icons.push({ name, png: dataUri("image/png", fs.readFileSync(out)) });
		console.log(`png  ${path.relative(process.cwd(), out)}`);
	}

	await shoot(page, sheetHtml(icons, { size: 64, small: true, title: "Anime fighter simulator — icon set" }), SHEET);
	console.log(`sheet ${path.relative(process.cwd(), SHEET)}`);
	if (reviewOut) {
		await shoot(page, sheetHtml(icons, { size: 128, small: false, title: "Review sheet (128 px)" }), reviewOut);
		console.log(`review ${reviewOut}`);
	}
	await browser.close();

	// Manifest: keep ids already filled in after the Studio upload.
	let previous = {};
	if (fs.existsSync(MANIFEST)) previous = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
	const manifest = {};
	for (const name of ICONS) manifest[name] = { png: `png/${name}.png`, rbxassetid: (previous[name] && previous[name].rbxassetid) || "" };
	fs.writeFileSync(MANIFEST, JSON.stringify(manifest, null, "\t") + "\n");
	console.log(`manifest ${path.relative(process.cwd(), MANIFEST)} (${ICONS.length} icons)`);
})().catch((err) => {
	console.error(err.message || err);
	process.exit(1);
});
