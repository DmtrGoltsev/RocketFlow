const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('C:/Users/style/Documents/Codex/RocketFlow/test-artifacts/2026-05-19/gate-closure/web-mobile/node_modules/playwright-core');

const artifactRoot = __dirname;
const screenshotDir = path.join(artifactRoot, 'screenshots');
const logDir = path.join(artifactRoot, 'logs');
const reportPath = path.join(artifactRoot, 'report.json');
const markdownPath = path.join(artifactRoot, 'report.md');
const browserLogPath = path.join(logDir, 'browser.ndjson');
const webBase = 'http://127.0.0.1:5173/rocket';
const chromePath = 'C:/Program Files/Google/Chrome/Application/chrome.exe';

fs.mkdirSync(screenshotDir, { recursive: true });
fs.mkdirSync(logDir, { recursive: true });
fs.writeFileSync(browserLogPath, '');

const now = new Date('2026-05-24T00:08:14+03:00');
const iso = (value) => new Date(value).toISOString();
const user = {
  id: 'qa-user-1',
  email: 'visual.qa@example.com',
  displayName: 'Visual QA',
  timezone: 'Europe/Moscow',
  language: 'en',
  createdAt: iso(now),
};
const session = {
  user,
  tokens: {
    accessToken: 'qa-access-token',
    refreshToken: 'qa-refresh-token',
    expiresAt: '2026-06-24T00:00:00.000Z',
  },
};
const folders = [{
  id: 'folder-1',
  parentFolderId: null,
  ownerUserId: user.id,
  name: 'Authenticated visual QA folder',
  description: 'Folder used by route-mocked authenticated visual QA.',
  displayOrder: 1,
  archived: false,
  shared: false,
  fullAccess: true,
  canAccessFolderContent: true,
  version: 1,
  createdAt: iso(now),
  updatedAt: iso(now),
}];
const goals = [{
  id: 'goal-1',
  folderId: 'folder-1',
  ownerUserId: user.id,
  name: 'Authenticated visual QA goal',
  description: 'Goal detail should open as a full-screen surface on iPhone.',
  status: 'in_progress',
  archived: false,
  shared: false,
  fullAccess: true,
  version: 1,
  createdAt: iso(now),
  updatedAt: iso(now),
}];
const tasks = [
  {
    id: 'task-overdue',
    goalId: 'goal-1',
    ownerUserId: user.id,
    title: 'Overdue no estimate task',
    description: 'Shows the red overdue marker and no estimate copy.',
    type: 'red',
    priority: 9,
    effort: 0,
    status: 'todo',
    plannedTime: '2026-05-20T10:00:00.000Z',
    dueTime: null,
    archived: false,
    shared: false,
    fullAccess: true,
    creatorUserId: user.id,
    creatorEmail: user.email,
    creatorName: user.displayName,
    version: 1,
    tags: [],
    recurrence: null,
    createdAt: iso(now),
    updatedAt: iso(now),
  },
  {
    id: 'task-unscheduled',
    goalId: 'goal-1',
    ownerUserId: user.id,
    title: 'Unscheduled reminder task',
    description: 'Used for reminder editor and recurrence guard checks.',
    type: 'green',
    priority: 4,
    effort: 5,
    status: 'in_progress',
    plannedTime: null,
    dueTime: null,
    archived: false,
    shared: false,
    fullAccess: true,
    creatorUserId: user.id,
    creatorEmail: user.email,
    creatorName: user.displayName,
    version: 2,
    tags: [],
    recurrence: null,
    createdAt: iso(now),
    updatedAt: iso(now),
  },
  {
    id: 'task-done',
    goalId: 'goal-1',
    ownerUserId: user.id,
    title: 'Done effort task',
    description: 'Should be hidden in the main list but visible in goal detail.',
    type: 'green',
    priority: 2,
    effort: 3,
    status: 'done',
    plannedTime: '2026-05-21T11:00:00.000Z',
    dueTime: null,
    archived: false,
    shared: false,
    fullAccess: true,
    creatorUserId: user.id,
    creatorEmail: user.email,
    creatorName: user.displayName,
    version: 1,
    tags: [],
    recurrence: null,
    createdAt: iso(now),
    updatedAt: iso(now),
  },
  {
    id: 'task-cancelled',
    goalId: 'goal-1',
    ownerUserId: user.id,
    title: 'Cancelled effort task',
    description: 'Should be hidden in the main list but visible in goal detail.',
    type: 'red',
    priority: 1,
    effort: 2,
    status: 'cancelled',
    plannedTime: '2026-05-22T12:00:00.000Z',
    dueTime: null,
    archived: false,
    shared: false,
    fullAccess: true,
    creatorUserId: user.id,
    creatorEmail: user.email,
    creatorName: user.displayName,
    version: 1,
    tags: [],
    recurrence: null,
    createdAt: iso(now),
    updatedAt: iso(now),
  },
];
const settings = {
  language: 'en',
  greenPriorityDecayPolicy: { taskType: 'green', enabled: true, thresholdPreset: 'week', decayAmount: 1 },
  redPriorityDecayPolicy: { taskType: 'red', enabled: true, thresholdPreset: 'day', decayAmount: 2 },
  notificationsEnabled: true,
  version: 7,
};

const evidence = {
  startedAt: new Date().toISOString(),
  webBase,
  screenshots: [],
  checks: [],
  failures: [],
  warnings: [],
};

function logBrowser(entry) {
  fs.appendFileSync(browserLogPath, JSON.stringify({ at: new Date().toISOString(), ...entry }) + '\n');
}

function check(name, passed, details = {}) {
  const item = { name, status: passed ? 'PASS' : 'FAIL', ...details };
  evidence.checks.push(item);
  if (!passed) evidence.failures.push(item);
  return passed;
}

async function screenshot(page, name) {
  const file = path.join(screenshotDir, `${String(evidence.screenshots.length + 1).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  evidence.screenshots.push({ name, path: file, url: page.url(), viewport: page.viewportSize() });
  return file;
}

function jsonResponse(body, status = 200) {
  return {
    status,
    contentType: 'application/json',
    body: JSON.stringify(body),
  };
}

async function mockApi(route) {
  const request = route.request();
  const url = new URL(request.url());
  const pathname = url.pathname.replace('/rocket-api', '');
  const method = request.method();

  logBrowser({ type: 'api', method, pathname, search: url.search });

  if (method === 'GET' && pathname === '/me') return route.fulfill(jsonResponse(user));
  if (method === 'POST' && pathname === '/auth/refresh') return route.fulfill(jsonResponse({ tokens: session.tokens }));
  if (method === 'GET' && pathname === '/folders') return route.fulfill(jsonResponse({ items: folders }));
  if (method === 'GET' && pathname === '/shares/resources') {
    return route.fulfill(jsonResponse({ folders: [], goals: [], tasks: [], createTaskGoalIds: [] }));
  }
  if (method === 'GET' && pathname === '/shares/invitations') return route.fulfill(jsonResponse({ items: [] }));
  if (method === 'GET' && pathname === '/folders/folder-1/goals') return route.fulfill(jsonResponse({ items: goals }));
  if (method === 'GET' && pathname === '/goals/goal-1/tasks') return route.fulfill(jsonResponse({ items: tasks }));
  if (method === 'GET' && pathname === '/folders/folder-1/ideas') return route.fulfill(jsonResponse({ items: [] }));
  if (method === 'GET' && pathname === '/folders/folder-1/notes') return route.fulfill(jsonResponse({ items: [] }));
  if (method === 'GET' && pathname === '/me/settings') return route.fulfill(jsonResponse(settings));
  if (method === 'GET' && pathname === '/entity-links') return route.fulfill(jsonResponse({ items: [] }));
  if (method === 'PATCH' && pathname === '/tasks/task-unscheduled') {
    const payload = JSON.parse(request.postData() || '{}');
    return route.fulfill(jsonResponse({ ...tasks[1], ...payload, version: tasks[1].version + 1 }));
  }
  if (method === 'PUT' && pathname === '/tasks/task-unscheduled/recurrence') {
    const payload = JSON.parse(request.postData() || '{}');
    return route.fulfill(jsonResponse({ taskId: 'task-unscheduled', recurrence: payload }));
  }

  return route.fulfill(jsonResponse({ items: [] }));
}

async function createPage(browser, viewport, isMobile = false) {
  const context = await browser.newContext({
    viewport,
    isMobile,
    hasTouch: isMobile,
    deviceScaleFactor: isMobile ? 3 : 1,
    locale: 'en-US',
    timezoneId: 'Europe/Moscow',
    userAgent: isMobile
      ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'
      : undefined,
  });
  await context.route('**/rocket-api/**', mockApi);
  await context.addInitScript(({ sessionJson, userId }) => {
    window.localStorage.setItem('rocketflow.locale', 'en');
    window.localStorage.setItem('rocketflow.auth.session', sessionJson);
    window.localStorage.setItem(`rocketflow.local-reminders:${userId}:task-unscheduled`, JSON.stringify([
      { id: 'reminder-1', fireAt: '2026-05-24T09:00:00.000Z', repeat: 'none', note: 'Daily standup prep', completedAt: null },
      { id: 'reminder-2', fireAt: '2026-05-24T10:00:00.000Z', repeat: 'hourly', note: 'Hourly check-in', completedAt: null },
    ]));
  }, { sessionJson: JSON.stringify(session), userId: user.id });

  const page = await context.newPage();
  page.on('console', (message) => logBrowser({ type: 'console', level: message.type(), text: message.text() }));
  page.on('pageerror', (error) => logBrowser({ type: 'pageerror', message: error.message, stack: error.stack }));
  page.on('requestfailed', (request) => logBrowser({ type: 'requestfailed', url: request.url(), failure: request.failure() }));
  return { context, page };
}

async function waitForPlan(page) {
  await page.goto(`${webBase}/app/tasks`, { waitUntil: 'domcontentloaded' });
  await page.getByText('Authenticated visual QA goal', { exact: true }).waitFor({ state: 'visible', timeout: 15000 });
  await page.waitForTimeout(300);
}

async function overflowMetrics(page) {
  return page.evaluate(() => {
    const root = document.documentElement;
    const body = document.body;
    const width = window.innerWidth;
    const offenders = Array.from(document.querySelectorAll('body *'))
      .map((el) => {
        const rect = el.getBoundingClientRect();
        return { tag: el.tagName, className: String(el.className || ''), text: (el.textContent || '').trim().slice(0, 80), left: rect.left, right: rect.right, width: rect.width };
      })
      .filter((item) => item.right > width + 1 || item.left < -1)
      .slice(0, 12);
    return {
      innerWidth: width,
      documentScrollWidth: root.scrollWidth,
      bodyScrollWidth: body.scrollWidth,
      workspaceMainScrollWidth: document.querySelector('.workspace-main')?.scrollWidth ?? null,
      workspaceMainClientWidth: document.querySelector('.workspace-main')?.clientWidth ?? null,
      offenders,
    };
  });
}

async function desktopMain(browser) {
  const { context, page } = await createPage(browser, { width: 1280, height: 900 }, false);
  await waitForPlan(page);
  await screenshot(page, 'desktop-task-main');

  const planText = await page.locator('.plan-tree').innerText();
  const overdueCount = await page.locator('.plan-row__overdue').count();
  check('desktop web task main has overdue red !', overdueCount >= 1, { overdueCount });
  check('desktop web task main shows no estimate', planText.includes('no estimate'), { planText });
  check('desktop web task main hides done/cancelled rows', !planText.includes('Done effort task') && !planText.includes('Cancelled effort task'), { planText });
  await context.close();
}

async function iphoneMain(browser, viewport) {
  const { context, page } = await createPage(browser, viewport, true);
  await waitForPlan(page);
  const metrics = await overflowMetrics(page);
  await screenshot(page, `iphone-${viewport.width}x${viewport.height}-main-list`);
  check(`iPhone ${viewport.width}x${viewport.height} main list has no horizontal overflow`, metrics.documentScrollWidth <= viewport.width && metrics.bodyScrollWidth <= viewport.width, metrics);
  await context.close();
}

async function goalDetail(browser) {
  const { context, page } = await createPage(browser, { width: 390, height: 844 }, true);
  await waitForPlan(page);
  await page.getByText('Authenticated visual QA goal', { exact: true }).click();
  await page.locator('.detail-panel.is-open').waitFor({ state: 'visible', timeout: 5000 });
  await page.waitForTimeout(300);
  await screenshot(page, 'iphone-goal-detail');

  const detailText = await page.locator('.detail-panel').innerText();
  const panelBox = await page.locator('.detail-panel.is-open').boundingBox();
  const progressWidth = await page.locator('.goal-progress__bar span').evaluate((el) => getComputedStyle(el).width);
  check('goal detail opens as iPhone full-screen/detail surface', Boolean(panelBox && panelBox.width >= 388 && panelBox.x <= 1), { panelBox });
  check('goal detail shows progress percent', detailText.includes('30%'), { progressWidth, detailText });
  check('goal detail list includes done/cancelled statuses and effort', detailText.includes('Done effort task') && detailText.includes('Done') && detailText.includes('Cancelled effort task') && detailText.includes('Cancelled') && detailText.includes('3 h') && detailText.includes('2 h'), { detailText });
  const metrics = await overflowMetrics(page);
  check('goal detail has no obvious horizontal overflow', metrics.documentScrollWidth <= 390 && metrics.bodyScrollWidth <= 390, metrics);
  await context.close();
}

async function remindersAndRecurrence(browser) {
  const { context, page } = await createPage(browser, { width: 390, height: 844 }, true);
  await waitForPlan(page);
  await page.getByText('Unscheduled reminder task', { exact: true }).click();
  await page.locator('.detail-panel.is-open').waitFor({ state: 'visible', timeout: 5000 });
  await page.getByRole('button', { name: 'Edit' }).click();
  await page.waitForTimeout(300);
  await page.locator('.detail-panel').evaluate((el) => { el.scrollTop = el.scrollHeight; });
  await page.waitForTimeout(300);
  await screenshot(page, 'iphone-task-edit-reminders');

  const panelText = await page.locator('.detail-panel').innerText();
  const reminderCount = await page.locator('.local-reminder').count();
  const reminderInputValues = await page.locator('.local-reminder input').evaluateAll((inputs) => inputs.map((input) => input.value));
  const hourlySelected = await page.locator('.local-reminder select').evaluateAll((selects) => selects.some((select) => select.value === 'hourly'));
  check(
    'task edit shows multiple reminders list/editor',
    reminderCount >= 2 && reminderInputValues.includes('Daily standup prep') && reminderInputValues.includes('Hourly check-in'),
    { reminderCount, reminderInputValues, panelText },
  );
  check('task reminder editor exposes hourly option', hourlySelected && panelText.includes('Hourly'), { hourlySelected, reminderInputValues, panelText });

  await page.locator('.detail-panel').evaluate((el) => { el.scrollTop = 0; });
  await page.waitForTimeout(200);
  const recurrenceCheckbox = page.locator('.recurrence-editor input[type="checkbox"]').first();
  await recurrenceCheckbox.check();
  await page.waitForTimeout(300);
  await page.locator('.detail-panel').evaluate((el) => {
    const error = Array.from(el.querySelectorAll('.field__error')).find((item) => (item.textContent || '').includes('Recurrence needs'));
    if (error) error.scrollIntoView({ block: 'center' });
  });
  await page.waitForTimeout(300);
  await screenshot(page, 'iphone-task-edit-recurrence-guard');
  const guardText = await page.locator('.detail-panel').innerText();
  check('recurrence guard appears when repeat enabled without planned/due', guardText.includes('Recurrence needs planned or due time.'), { guardText });
  const metrics = await overflowMetrics(page);
  check('task edit reminder/recurrence surface has no obvious horizontal overflow', metrics.documentScrollWidth <= 390 && metrics.bodyScrollWidth <= 390, metrics);
  await context.close();
}

async function settingsBottom(browser) {
  const { context, page } = await createPage(browser, { width: 390, height: 844 }, true);
  await page.goto(`${webBase}/app/settings`, { waitUntil: 'domcontentloaded' });
  await page.getByText('Save settings', { exact: true }).waitFor({ state: 'visible', timeout: 15000 });
  await page.waitForTimeout(300);
  const before = await page.evaluate(() => document.querySelector('.workspace-main')?.scrollTop ?? document.documentElement.scrollTop);
  await page.locator('.workspace-main').evaluate((el) => { el.scrollTop = el.scrollHeight; });
  await page.waitForTimeout(600);
  const after = await page.evaluate(() => document.querySelector('.workspace-main')?.scrollTop ?? document.documentElement.scrollTop);
  await screenshot(page, 'iphone-settings-bottom');
  await page.waitForTimeout(500);
  const afterWait = await page.evaluate(() => document.querySelector('.workspace-main')?.scrollTop ?? document.documentElement.scrollTop);
  const metrics = await overflowMetrics(page);
  check('settings bottom at iPhone width has no obvious jump', after > before && Math.abs(afterWait - after) <= 2, { before, after, afterWait });
  check('settings bottom at iPhone width has no horizontal overflow', metrics.documentScrollWidth <= 390 && metrics.bodyScrollWidth <= 390, metrics);
  await context.close();
}

function writeReports() {
  evidence.finishedAt = new Date().toISOString();
  evidence.status = evidence.failures.length ? 'FAIL' : 'PASS';
  fs.writeFileSync(reportPath, JSON.stringify(evidence, null, 2));
  const lines = [
    '# Authenticated Web/iPhone Visual QA',
    '',
    `Verdict: **${evidence.status}**`,
    `Web: ${webBase}`,
    `Browser log: \`${browserLogPath}\``,
    '',
    '## Checks',
    '',
    '| Status | Check |',
    '|---|---|',
    ...evidence.checks.map((item) => `| ${item.status} | ${item.name} |`),
    '',
    '## Screenshots',
    '',
    ...evidence.screenshots.map((shot) => `- ${shot.name}: \`${shot.path}\``),
  ];
  fs.writeFileSync(markdownPath, lines.join('\n'));
}

async function main() {
  const browser = await chromium.launch({
    headless: true,
    executablePath: chromePath,
    args: ['--no-first-run', '--no-default-browser-check'],
  });

  try {
    await desktopMain(browser);
    await iphoneMain(browser, { width: 390, height: 844 });
    await iphoneMain(browser, { width: 430, height: 932 });
    await goalDetail(browser);
    await remindersAndRecurrence(browser);
    await settingsBottom(browser);
  } finally {
    await browser.close().catch(() => {});
    writeReports();
  }

  if (evidence.failures.length) {
    console.error(`${evidence.failures.length} QA check(s) failed. See ${reportPath}`);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  evidence.failures.push({ name: 'runner error', status: 'FAIL', message: error.message, stack: error.stack });
  writeReports();
  console.error(error);
  process.exitCode = 1;
});
