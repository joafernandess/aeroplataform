// Screenshots every HTML page produced by preview.luau.
// Usage: node tools/ui-preview/screenshot.js [outputDir] [deviceScaleFactor]
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

(async () => {
	const dir = path.resolve(process.argv[2] || "ui-preview-out");
	const scale = Number(process.argv[3] || 2);
	const browser = await chromium.launch();
	const files = fs.readdirSync(dir).filter((f) => f.endsWith(".html")).sort();
	for (const file of files) {
		const html = fs.readFileSync(path.join(dir, file), "utf8");
		const match = html.match(/body\{width:(\d+)px;height:(\d+)px/);
		const width = match ? Number(match[1]) : 1280;
		const height = match ? Number(match[2]) : 720;
		const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: scale });
		await page.goto("file://" + path.join(dir, file));
		await page.waitForTimeout(100);
		await page.screenshot({ path: path.join(dir, file.replace(/\.html$/, ".png")) });
		await page.close();
		console.log("shot", file);
	}
	await browser.close();
})();
