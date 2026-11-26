// HUD icon exporter: assets/UI_Icons/src/*.svg -> assets/UI_Icons/*.png (512x512, transparent background),
// plus a review sheet (assets/UI_Icons/preview.png) showing every icon at 512/128/48/32 px on the HUD button.
//
// Usage (repository root):  node assets/UI_Icons/tools/export.js
// Requires Playwright + Chromium (preinstalled in the cloud dev container).
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "src");
const SIZE = 512;

// File name -> Roblox icon key (Theme.IconAssets) and the HUD button it belongs to. Order = sheet order.
const ICONS = [
	["Icon_Shop", "shop", "Left menu · Shop"],
	["Icon_Fighters", "fighters", "Left menu · Fighters"],
	["Icon_Settings", "settings", "Left menu · Settings"],
	["Icon_Codes", "codes", "Left menu · Codes"],
	["Icon_Quests", "quests", "Left menu · Quests"],
	["Icon_Teleport", "teleport", "Left menu · TP"],
	["Icon_Inventory", "inventory", "Right menu · Inventory"],
	["Icon_Mounts", "mounts", "Right menu · Mounts"],
	["Icon_Achievements", "achievements", "Right menu · Achievements"],
	["Icon_Stats", "stats", "Right menu · Stats"],
	["Icon_Index", "index", "Right menu · Index"],
	["Icon_UpdateLog", "update", "Top-right · Update Log card"],
	["Icon_Yen", "yen", "Top-left · Yen counter (and the coins)"],
];

function lint(name, svg) {
	const problems = [];
	if (!/viewBox="0 0 512 512"/.test(svg)) problems.push("viewBox must be 0 0 512 512");
	if (/<text[\s>]/.test(svg)) problems.push("no <text>: icons contain no letters");
	if (/<image[\s>]/.test(svg)) problems.push("no embedded images");
	if (/<rect[^>]*width="512"[^>]*height="512"/.test(svg)) problems.push("no background square");
	if (problems.length) throw new Error(`${name}.svg: ${problems.join("; ")}`);
}

const dataUri = (buf, mime) => `data:${mime};base64,${Buffer.from(buf).toString("base64")}`;

function sheet(icons) {
	const tile = (png, px, cls) => `<div class="btn ${cls}" style="width:${px * 1.45}px;height:${px * 1.45}px;border-radius:${Math.max(6, px * 0.3)}px"><img src="${png}" width="${px}" height="${px}"></div>`;
	const cells = icons
		.map(
			(i) => `<div class="cell">
				<div class="big"><img src="${i.uri}" width="160" height="160"></div>
				<div class="row">${tile(i.uri, 48, "")}${tile(i.uri, 32, "")}${tile(i.uri, 48, "light")}</div>
				<div class="name">${i.file}.png</div><div class="where">${i.where}</div>
			</div>`
		)
		.join("");
	return `<!doctype html><html><head><meta charset="utf-8"><style>
		* { box-sizing: border-box; margin: 0; padding: 0; }
		body { background: #1b1c21; color: #fff; font: 700 13px/1.25 "Segoe UI", Roboto, Arial, sans-serif; padding: 22px; width: max-content; }
		h1 { font-size: 20px; margin-bottom: 4px; } p { color: #a7abb6; margin-bottom: 18px; }
		.grid { display: grid; grid-template-columns: repeat(6, 200px); gap: 18px; }
		.cell { display: flex; flex-direction: column; align-items: center; gap: 8px; background: #24262d; border-radius: 14px; padding: 12px 8px; }
		.big { width: 176px; height: 176px; display: grid; place-items: center;
			background: repeating-conic-gradient(#3a3c44 0% 25%, #2e3037 0% 50%) 0 0 / 22px 22px; border-radius: 10px; }
		.row { display: flex; gap: 10px; align-items: center; }
		.btn { display: grid; place-items: center; background: linear-gradient(#26272c, #0d0d10); border: 2.5px solid #e9eaee; box-shadow: 0 3px 0 rgba(0,0,0,.55); }
		.btn.light { background: #e9eaee; border-color: #12131a; }
		.name { font-size: 13px; } .where { color: #a7abb6; font-size: 11px; font-weight: 600; }
	</style></head><body><h1>UI_Icons — ${icons.length} PNGs, 512×512, transparent</h1>
	<p>Checkerboard = transparency · then 48 px and 32 px on the dark HUD button, and 48 px on a light tile</p>
	<div class="grid">${cells}</div></body></html>`;
}

(async () => {
	const browser = await chromium.launch();
	const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE }, deviceScaleFactor: 1 });
	const done = [];
	for (const [file, key, where] of ICONS) {
		const svg = fs.readFileSync(path.join(SRC, file + ".svg"), "utf8");
		lint(file, svg);
		await page.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
		const png = await page.locator("svg").screenshot({ omitBackground: true });
		fs.writeFileSync(path.join(ROOT, file + ".png"), png);
		done.push({ file, key, where, uri: dataUri(png, "image/png") });
		console.log("exported", file + ".png");
	}
	const review = await browser.newPage({ viewport: { width: 1400, height: 900 }, deviceScaleFactor: 1 });
	await review.setContent(sheet(done));
	await review.screenshot({ path: path.join(ROOT, "preview.png"), fullPage: true });
	fs.writeFileSync(
		path.join(ROOT, "manifest.json"),
		JSON.stringify(Object.fromEntries(done.map((i) => [i.key, { png: i.file + ".png", button: i.where, rbxassetid: "" }])), null, "\t") + "\n"
	);
	await browser.close();
})().catch((e) => {
	console.error(e.message);
	process.exit(1);
});
