const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const { chromium } = require(process.env.PLAYWRIGHT_CORE_PATH || "playwright-core");

const outputDir = process.argv[2] || path.join(process.cwd(), "playwright-report");
const harnessHtmlPath = path.join(__dirname, "harness.html");
const actionTimeoutMs = Number(process.env.VIDEO_RECORDER_ACTION_TIMEOUT_MS || 5000);
const launchTimeoutMs = Number(process.env.VIDEO_RECORDER_LAUNCH_TIMEOUT_MS || 15000);
const totalTimeoutMs = Number(process.env.VIDEO_RECORDER_TOTAL_TIMEOUT_MS || 60000);

function withTimeout(promise, label, timeoutMs) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${timeoutMs}ms`)), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function openPage(browser, scenario, enabled = true) {
  const page = await browser.newPage();
  page.setDefaultTimeout(actionTimeoutMs);
  page.setDefaultNavigationTimeout(actionTimeoutMs);
  const configScript = `<script>window.__videoHarnessConfig = ${JSON.stringify({ scenario, enabled })};</script>`;
  const html = (await fs.readFile(harnessHtmlPath, "utf8")).replace("<head>", `<head>${configScript}`);
  await page.setContent(html, { timeout: actionTimeoutMs });
  return page;
}

async function writeArtifact(name, artifact) {
  await fs.mkdir(outputDir, { recursive: true });
  await fs.writeFile(path.join(outputDir, name), `${JSON.stringify(artifact, null, 2)}\n`);
}

async function findChromiumExecutable() {
  if (process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE) return process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  if (!process.env.PLAYWRIGHT_BROWSERS_PATH) return undefined;

  const entries = await fs.readdir(process.env.PLAYWRIGHT_BROWSERS_PATH);
  const chromiumDir = entries.find((entry) => /^chromium-\d+$/.test(entry));
  if (!chromiumDir) return undefined;

  return path.join(process.env.PLAYWRIGHT_BROWSERS_PATH, chromiumDir, "chrome-linux", "chrome");
}

async function snapshot(page) {
  return page.evaluate(() => window.__videoHarness);
}

async function runScenario(name, test) {
  const startedAt = new Date().toISOString();
  try {
    const artifact = await test();
    return { name, startedAt, status: "passed", artifact };
  } catch (error) {
    return {
      name,
      startedAt,
      status: "failed",
      error: error instanceof Error ? { message: error.message, stack: error.stack } : String(error),
    };
  }
}

async function main() {
  const executablePath = await findChromiumExecutable();
  const browser = await chromium.launch({
    args: [
      "--disable-dev-shm-usage",
      "--no-sandbox",
      "--use-fake-device-for-media-stream",
      "--use-fake-ui-for-media-stream",
    ],
    executablePath,
    headless: true,
    timeout: launchTimeoutMs,
  });

  const results = [];

  results.push(await runScenario("disabled config hides recorder button", async () => {
    const page = await openPage(browser, "disabled", false);
    const count = await page.locator('[data-testid="video-message-button"]').count();
    assert.equal(count, 0);
    const artifact = { buttonCount: count, selector: '[data-testid="video-message-button"]' };
    await page.close();
    return artifact;
  }));

  results.push(await runScenario("enabled config shows recorder button", async () => {
    const page = await openPage(browser, "enabled", true);
    const button = page.getByRole("button", { name: "Record video message" });
    await assert.doesNotReject(() => button.waitFor({ state: "visible", timeout: actionTimeoutMs }));
    const count = await page.locator('[data-testid="video-message-button"]').count();
    assert.equal(count, 1);
    const artifact = { accessibleLabel: "Record video message", buttonCount: count };
    await page.close();
    return artifact;
  }));

  results.push(await runScenario("happy path records previews and sends m.video", async () => {
    const page = await openPage(browser, "happy-path", true);
    await page.getByRole("button", { name: "Record video message" }).click();
    await page.locator('[data-testid="video-message-stop-button"]').waitFor({ state: "visible", timeout: actionTimeoutMs });
    await page.waitForTimeout(600);
    await page.locator('[data-testid="video-message-stop-button"]').click();
    await page.locator('[data-testid="video-message-preview"]').waitFor({ state: "visible", timeout: actionTimeoutMs });
    await page.locator('[data-testid="video-message-send-button"]').click();
    await page.waitForFunction(() => window.__videoHarness.sendCalls.length === 1, null, { timeout: actionTimeoutMs });

    const harness = await snapshot(page);
    const call = harness.sendCalls[0];
    assert.equal(call.content.msgtype, "m.video");
    assert.match(call.content.info.mimetype, /^video\//);
    assert.match(call.content.body, /\.webm$/);
    assert.deepEqual(harness.getUserMediaConstraints[0], { video: true, audio: true });
    assert.ok(harness.stoppedTrackCount >= 1);

    const artifact = {
      boundary: harness.contentMessagesBoundary,
      content: call.content,
      fakeMediaFlags: ["--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream"],
      fallbackChunkUsed: harness.fallbackChunkUsed,
      getUserMediaConstraints: harness.getUserMediaConstraints,
      mediaSource: harness.mediaSource,
      sendCallCount: harness.sendCalls.length,
      stoppedTrackCount: harness.stoppedTrackCount,
    };
    await writeArtifact("happy-path.json", artifact);
    await page.close();
    return artifact;
  }));

  results.push(await runScenario("cancel stops tracks without sending", async () => {
    const page = await openPage(browser, "cancel", true);
    await page.getByRole("button", { name: "Record video message" }).click();
    await page.locator('[data-testid="video-message-cancel-button"]').waitFor({ state: "visible", timeout: actionTimeoutMs });
    await page.locator('[data-testid="video-message-cancel-button"]').click();
    await page.waitForFunction(() => window.__videoHarness.acquiredTrackCount > 0 && window.__videoHarness.stoppedTrackCount >= window.__videoHarness.acquiredTrackCount, null, { timeout: actionTimeoutMs });
    const harness = await snapshot(page);
    assert.equal(harness.sendCalls.length, 0);
    assert.ok(harness.stoppedTrackCount >= harness.acquiredTrackCount);
    const artifact = {
      acquiredTrackCount: harness.acquiredTrackCount,
      sendCallCount: harness.sendCalls.length,
      stoppedTrackCount: harness.stoppedTrackCount,
    };
    await page.close();
    return artifact;
  }));

  results.push(await runScenario("permission denied shows copy without sending", async () => {
    const page = await openPage(browser, "permission-denied", true);
    await page.getByRole("button", { name: "Record video message" }).click();
    await page.getByText("Camera permission denied").waitFor({ state: "visible", timeout: actionTimeoutMs });
    const harness = await snapshot(page);
    assert.equal(harness.sendCalls.length, 0);
    const artifact = {
      errorText: "Camera permission denied",
      getUserMediaConstraints: harness.getUserMediaConstraints,
      sendCallCount: harness.sendCalls.length,
    };
    await writeArtifact("permission-denied.json", artifact);
    await page.close();
    return artifact;
  }));

  results.push(await runScenario("unsupported browser keeps composer usable", async () => {
    const page = await openPage(browser, "unsupported", true);
    const count = await page.locator('[data-testid="video-message-button"]').count();
    assert.equal(count, 0);
    await page.getByLabel("Message composer").fill("composer still works");
    const composerValue = await page.getByLabel("Message composer").inputValue();
    assert.equal(composerValue, "composer still works");
    const artifact = {
      buttonCount: count,
      composerValue,
      outcome: "recorder absent and text composer remains usable",
    };
    await writeArtifact("unsupported.json", artifact);
    await page.close();
    return artifact;
  }));

  await browser.close();

  await writeArtifact("report.json", { generatedAt: new Date().toISOString(), results });
  const failures = results.filter((result) => result.status !== "passed");
  if (failures.length > 0) {
    console.error(JSON.stringify(failures, null, 2));
    process.exit(1);
  }

  console.log(JSON.stringify({ status: "passed", scenarios: results.map((result) => result.name) }, null, 2));
}

withTimeout(main(), "video recorder harness", totalTimeoutMs).catch((error) => {
  console.error(error);
  process.exit(1);
});
