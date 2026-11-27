// Screenshots every HTML page produced by preview.luau.
// Usage: node tools/ui-preview/screenshot.js [outputDir] [deviceScaleFactor]
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

(async () => {
	const dir = path.resolve(process.argv[2] || "ui-preview-out");
	const scale = Number(process.argv[3] || 2);
	const browser = await chromium.launch({ args: ["--allow-file-access-from-files", "--use-gl=swiftshader", "--enable-unsafe-swiftshader"] });
	const files = fs.readdirSync(dir).filter((f) => f.endsWith(".html") && !f.startsWith("_")).sort();
	for (const file of files) {
		const html = fs.readFileSync(path.join(dir, file), "utf8");
		const match = html.match(/body\{width:(\d+)px;height:(\d+)px/);
		const width = match ? Number(match[1]) : 1280;
		const height = match ? Number(match[2]) : 720;
		const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: scale });
		await page.goto("file://" + path.join(dir, file), { waitUntil: "networkidle" });
		await page.evaluate(() => document.fonts.ready);
		// 3D scene pages flag themselves when the WebGL frame and labels are ready.
		if (html.includes("THREE.WebGLRenderer")) await page.waitForFunction(() => document.body.dataset.ready === "1", null, { timeout: 30000 });
		await page.waitForTimeout(150);
		await page.screenshot({ path: path.join(dir, file.replace(/\.html$/, ".png")) });
		await page.close();
		console.log("shot", file);
	}
	await browser.close();
})();
