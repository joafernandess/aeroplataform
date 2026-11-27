// Scales every icon in a folder so its visible pixels span TARGET px (largest side), centred on the 512 canvas.
// Wraps the drawing (<g id="art">) in <g id="fit" transform="...">. Run after generate.py, before export.js.
// Usage (repo root): node assets/UI_Icons/tools/fit.js assets/UI_Icons/src 424
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const DIR = process.argv[2];
const TARGET = Number(process.argv[3] || 424);

(async () => {
	const browser = await chromium.launch();
	const page = await browser.newPage();
	for (const file of fs.readdirSync(DIR).filter((f) => f.endsWith(".svg"))) {
		const p = path.join(DIR, file);
		let svg = fs.readFileSync(p, "utf8");
		if (svg.includes('<g id="fit"')) {
			console.log(file, "already fitted (regenerate it first)");
			continue;
		}
		const box = await page.evaluate(async (src) => {
			const img = new Image();
			img.src = "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(src)));
			await img.decode();
			const canvas = document.createElement("canvas");
			canvas.width = canvas.height = 512;
			const g = canvas.getContext("2d");
			g.drawImage(img, 0, 0, 512, 512);
			const d = g.getImageData(0, 0, 512, 512).data;
			let x0 = 512, y0 = 512, x1 = -1, y1 = -1;
			for (let y = 0; y < 512; y++)
				for (let x = 0; x < 512; x++)
					if (d[(y * 512 + x) * 4 + 3] > 8) {
						x0 = Math.min(x0, x);
						x1 = Math.max(x1, x);
						y0 = Math.min(y0, y);
						y1 = Math.max(y1, y);
					}
			return { x0, y0, x1: x1 + 1, y1: y1 + 1 };
		}, svg);
		const s = TARGET / Math.max(box.x1 - box.x0, box.y1 - box.y0);
		const cx = (box.x0 + box.x1) / 2;
		const cy = (box.y0 + box.y1) / 2;
		const tf = `translate(256 256) scale(${s.toFixed(4)}) translate(${(-cx).toFixed(2)} ${(-cy).toFixed(2)})`;
		svg = svg.replace('<g id="art"', `<g id="fit" transform="${tf}"><g id="art"`).replace(/<\/svg>\s*$/, "</g></svg>\n");
		fs.writeFileSync(p, svg);
		console.log(file, `scale ${s.toFixed(3)}`);
	}
	await browser.close();
})();
