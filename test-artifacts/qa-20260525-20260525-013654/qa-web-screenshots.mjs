import { createRequire } from 'node:module';
import fs from 'node:fs/promises';
import path from 'node:path';

const repoRoot = 'C:/Users/style/Documents/Codex/RocketFlow';
const artifactRoot = path.join(repoRoot, 'test-artifacts/qa-20260525-20260525-013654');
const screenshotsDir = path.join(artifactRoot, 'screenshots');
const playwrightRequire = createRequire(path.join(repoRoot, 'test-artifacts/2026-05-19/gate-closure/web-mobile/package.json'));
const { chromium } = playwrightRequire('playwright');

const baseUrl = process.env.QA_WEB_BASE_URL ?? 'http://127.0.0.1:5174';
const now = '2026-05-25T00:00:00.000Z';
const owner = {
  id: 'user-owner',
  email: 'owner@example.com',
  displayName: 'Owner Reviewer',
  timezone: 'Europe/Moscow',
  language: 'en',
  createdAt: '2026-01-01T00:00:00.000Z',
};

const folder = {
  id: 'folder-main',
  parentFolderId: null,
  ownerUserId: owner.id,
  name: 'QA Launch Folder',
  description: 'A long mocked folder for scrolling, forms, idea actions, and local reminders.',
  displayOrder: 1,
  archived: false,
  shared: false,
  fullAccess: true,
  canAccessFolderContent: true,
  version: 1,
  createdAt: now,
  updatedAt: now,
};

const goals = Array.from({ length: 10 }, (_, index) => {
  const number = String(index + 1).padStart(2, '0');
  return {
    id: `goal-${number}`,
    folderId: folder.id,
    ownerUserId: owner.id,
    name: `Launch Milestone ${number}`,
    description: `Milestone ${number} keeps enough tasks in the tree to force real scrolling on mobile and desktop.`,
    status: index % 3 === 0 ? 'in_progress' : 'todo',
    archived: false,
    shared: false,
    fullAccess: true,
    version: 1,
    createdAt: `2026-05-${String(index + 1).padStart(2, '0')}T08:00:00.000Z`,
    updatedAt: now,
  };
});

const tasksByGoal = Object.fromEntries(goals.map((goal, goalIndex) => {
  const tasks = Array.from({ length: 6 }, (_, taskIndex) => {
    const g = String(goalIndex + 1).padStart(2, '0');
    const t = String(taskIndex + 1).padStart(2, '0');
    return {
      id: `task-${g}-${t}`,
      goalId: goal.id,
      ownerUserId: owner.id,
      title: `${taskIndex === 0 ? 'Overdue' : 'Planned'} task ${g}-${t}`,
      description: `Task ${g}-${t} has a visible effort label and predictable status.`,
      type: taskIndex % 2 === 0 ? 'red' : 'green',
      priority: Math.max(1, 10 - taskIndex),
      effort: taskIndex + 1,
      status: taskIndex % 4 === 0 ? 'in_progress' : 'todo',
      plannedTime: taskIndex === 0 ? '2026-05-01T09:00:00.000Z' : `2026-06-${String(taskIndex + 1).padStart(2, '0')}T09:00:00.000Z`,
      dueTime: taskIndex === 0 ? '2026-05-02T18:00:00.000Z' : `2026-06-${String(taskIndex + 2).padStart(2, '0')}T18:00:00.000Z`,
      archived: false,
      shared: false,
      fullAccess: true,
      creatorUserId: owner.id,
      creatorEmail: owner.email,
      creatorName: owner.displayName,
      version: 1,
      tags: [],
      recurrence: taskIndex === 1 ? {
        mode: 'weekly',
        interval: 1,
        daysOfWeek: ['MONDAY'],
        dayOfMonth: null,
        startAt: '2026-06-02T09:00:00.000Z',
        endAt: null,
        active: true,
      } : null,
      createdAt: `2026-05-${String(taskIndex + 1).padStart(2, '0')}T09:00:00.000Z`,
      updatedAt: now,
    };
  });
  return [goal.id, tasks];
}));

const ideas = [
  {
    id: 'idea-creator',
    folderId: folder.id,
    ownerUserId: owner.id,
    title: 'Creator-owned launch idea',
    body: 'Idea detail should expose sharing, creator delete, and history-note actions.',
    status: 'active',
    displayOrder: 1,
    archived: false,
    allowAuthorNoteEdits: false,
    shared: false,
    fullAccess: true,
    creatorUserId: owner.id,
    creatorEmail: owner.email,
    creatorName: owner.displayName,
    version: 2,
    createdAt: '2026-05-05T09:00:00.000Z',
    updatedAt: now,
  },
  {
    id: 'idea-readonly-creator',
    folderId: folder.id,
    ownerUserId: 'user-other-owner',
    title: 'Creator read-only delete edge',
    body: 'Creator has view access but should still see delete.',
    status: 'active',
    displayOrder: 2,
    archived: false,
    allowAuthorNoteEdits: false,
    shared: true,
    fullAccess: false,
    creatorUserId: owner.id,
    creatorEmail: owner.email,
    creatorName: owner.displayName,
    version: 1,
    createdAt: '2026-05-06T09:00:00.000Z',
    updatedAt: now,
  },
];

const ideaNotesByIdea = {
  'idea-creator': [
    {
      id: 'idea-note-owner',
      ideaId: 'idea-creator',
      eventType: 'note',
      body: 'Owner note can be edited and deleted by the creator.',
      metadata: {},
      authorUserId: owner.id,
      authorEmail: owner.email,
      authorName: owner.displayName,
      version: 1,
      createdAt: '2026-05-05T10:00:00.000Z',
      updatedAt: '2026-05-05T10:00:00.000Z',
    },
    {
      id: 'idea-note-collab',
      ideaId: 'idea-creator',
      eventType: 'note',
      body: 'Collaborator note should be deletable by creator but not editable by creator.',
      metadata: {},
      authorUserId: 'user-collaborator',
      authorEmail: 'collaborator@example.com',
      authorName: 'Collaborator',
      version: 1,
      createdAt: '2026-05-05T11:00:00.000Z',
      updatedAt: '2026-05-05T11:00:00.000Z',
    },
  ],
  'idea-readonly-creator': [],
};

const invitations = [
  {
    id: 'invite-idea-pending',
    targetType: 'idea',
    targetId: 'idea-creator',
    targetEmail: 'reviewer@example.com',
    targetUserId: 'user-reviewer',
    fullAccess: false,
    status: 'pending',
    createdAt: '2026-05-05T12:00:00.000Z',
    expiresAt: '2026-06-05T12:00:00.000Z',
  },
];

const settings = {
  language: 'en',
  greenPriorityDecayPolicy: {
    taskType: 'green',
    enabled: true,
    thresholdPreset: 'week',
    decayAmount: 1,
  },
  redPriorityDecayPolicy: {
    taskType: 'red',
    enabled: true,
    thresholdPreset: 'day',
    decayAmount: 2,
  },
  notificationsEnabled: true,
  version: 7,
};

function jsonResponse(body, status = 200) {
  return {
    status,
    contentType: 'application/json',
    body: JSON.stringify(body),
  };
}

async function routeApi(route) {
  const request = route.request();
  const url = new URL(request.url());
  const apiPath = url.pathname.replace('/rocket-api', '');
  const method = request.method();

  if (method === 'GET' && apiPath === '/me') {
    return route.fulfill(jsonResponse(owner));
  }
  if (method === 'GET' && apiPath === '/folders') {
    return route.fulfill(jsonResponse({ items: [folder] }));
  }
  if (method === 'GET' && apiPath === '/shares/resources') {
    return route.fulfill(jsonResponse({
      folders: [],
      goals: [],
      tasks: [],
      ideas: [],
      createTaskGoalIds: [],
    }));
  }
  if (method === 'GET' && apiPath === '/shares/invitations') {
    return route.fulfill(jsonResponse({ items: invitations }));
  }
  if (method === 'GET' && apiPath === `/folders/${folder.id}/goals`) {
    return route.fulfill(jsonResponse({ items: goals }));
  }
  if (method === 'GET' && apiPath.startsWith('/goals/') && apiPath.endsWith('/tasks')) {
    const goalId = apiPath.split('/')[2];
    return route.fulfill(jsonResponse({ items: tasksByGoal[goalId] ?? [] }));
  }
  if (method === 'GET' && apiPath === `/folders/${folder.id}/ideas`) {
    return route.fulfill(jsonResponse({ items: ideas }));
  }
  if (method === 'GET' && apiPath === `/folders/${folder.id}/notes`) {
    return route.fulfill(jsonResponse({ items: [] }));
  }
  if (method === 'POST' && apiPath === `/folders/${folder.id}/goals`) {
    return route.fulfill(jsonResponse({
      id: 'goal-created',
      folderId: folder.id,
      ownerUserId: owner.id,
      name: 'New goal',
      description: '',
      status: 'todo',
      archived: false,
      shared: false,
      fullAccess: true,
      version: 1,
      createdAt: now,
      updatedAt: now,
    }, 201));
  }
  if (method === 'GET' && apiPath.startsWith('/ideas/') && apiPath.endsWith('/notes')) {
    const ideaId = apiPath.split('/')[2];
    return route.fulfill(jsonResponse({ items: ideaNotesByIdea[ideaId] ?? [] }));
  }
  if (method === 'GET' && apiPath === '/entity-links') {
    return route.fulfill(jsonResponse({ items: [] }));
  }
  if (method === 'GET' && apiPath === '/me/settings') {
    return route.fulfill(jsonResponse(settings));
  }
  if (method === 'POST' && apiPath.endsWith('/share')) {
    return route.fulfill(jsonResponse({
      ...invitations[0],
      id: `invite-${Date.now()}`,
      targetType: apiPath.includes('/ideas/') ? 'idea' : 'task',
      targetId: apiPath.split('/')[2],
      targetEmail: 'new-reviewer@example.com',
    }, 201));
  }
  if (method === 'DELETE') {
    return route.fulfill({ status: 204, body: '' });
  }

  console.log(`Unhandled mocked API ${method} ${apiPath}`);
  return route.fulfill(jsonResponse({ error: { code: 'not_found', message: `Unhandled ${method} ${apiPath}`, details: [] } }, 404));
}

async function installSession(context) {
  const session = {
    user: owner,
    tokens: {
      accessToken: 'qa-access-token',
      refreshToken: 'qa-refresh-token',
      expiresAt: '2027-01-01T00:00:00.000Z',
    },
  };
  const reminders = [
    {
      id: 'local-reminder-1',
      fireAt: '2026-06-01T09:00:00.000Z',
      repeat: 'hourly',
      note: 'QA local reminder status copy',
      completedAt: null,
    },
  ];
  await context.addInitScript(({ session, reminders }) => {
    window.localStorage.setItem('rocketflow.locale', 'en');
    window.localStorage.setItem('rocketflow.auth.session', JSON.stringify(session));
    window.localStorage.setItem('rocketflow.local-reminders:user-owner:task-01-01', JSON.stringify(reminders));
  }, { session, reminders });
}

async function screenshot(page, viewportName, name) {
  const file = path.join(screenshotsDir, `${viewportName}-${name}.png`);
  await page.screenshot({ path: file, fullPage: false });
  return file;
}

async function gotoPlan(page) {
  await page.goto(`${baseUrl}/rocket/app`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('.plan-tree', { timeout: 15000 });
  await page.waitForTimeout(250);
}

async function gotoSettings(page) {
  await page.goto(`${baseUrl}/rocket/app/settings`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('.planner--settings', { timeout: 15000 });
  await page.waitForTimeout(250);
}

async function clickPlanText(page, text) {
  await page.locator('.plan-tree').getByText(text, { exact: false }).first().click();
  await page.waitForSelector('.detail-panel.is-open', { timeout: 10000 });
  await page.waitForTimeout(200);
}

async function openCreateMenuItem(page, itemName) {
  await page.locator('.planner-toolbar [aria-label="Create"]').click();
  await page.getByRole('menuitem', { name: itemName, exact: true }).click();
  await page.waitForSelector('.detail-panel.is-open', { timeout: 10000 });
  await page.waitForTimeout(250);
}

async function openDetailEdit(page) {
  const editButton = page.locator('.detail-panel__header button').filter({ hasText: 'Edit' }).first();
  if (await editButton.count()) {
    await editButton.click();
    await page.waitForTimeout(200);
  }
}

async function openDetailAddMenuItem(page, itemName) {
  await page.locator('.detail-panel__header button').filter({ hasText: 'Add' }).first().click();
  await page.getByRole('menuitem', { name: itemName, exact: true }).click();
  await page.waitForSelector('.detail-panel.is-open', { timeout: 10000 });
  await page.waitForTimeout(250);
}

async function expandAccess(page) {
  const accessButton = page.locator('.detail-panel .detail-disclosure__trigger').filter({ hasText: 'Access' }).first();
  if (await accessButton.count()) {
    await accessButton.click();
    await page.waitForTimeout(200);
  }
}

async function scrollMainBottom(page) {
  await page.locator('.workspace-main').evaluate((element) => {
    element.scrollTop = element.scrollHeight;
  }).catch(async () => {
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  });
  await page.waitForTimeout(250);
}

async function runViewport(browser, viewportName, viewport, mobile) {
  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: 1,
    isMobile: mobile,
    hasTouch: mobile,
  });
  await installSession(context);
  const page = await context.newPage();
  page.setDefaultTimeout(10000);
  await page.route('**/rocket-api/**', routeApi);

  const captured = [];
  await gotoPlan(page);
  captured.push(await screenshot(page, viewportName, 'main-long-list-top'));
  await scrollMainBottom(page);
  captured.push(await screenshot(page, viewportName, 'main-long-list-bottom'));

  await gotoPlan(page);
  await clickPlanText(page, 'Launch Milestone 01');
  captured.push(await screenshot(page, viewportName, 'goal-detail-plan'));

  await gotoPlan(page);
  await openCreateMenuItem(page, 'Goal');
  await openDetailEdit(page);
  captured.push(await screenshot(page, viewportName, 'create-goal-fullscreen'));

  await gotoPlan(page);
  await clickPlanText(page, 'Launch Milestone 01');
  await openDetailAddMenuItem(page, 'Task');
  captured.push(await screenshot(page, viewportName, 'create-task-fullscreen'));

  await gotoPlan(page);
  await clickPlanText(page, 'Creator-owned launch idea');
  captured.push(await screenshot(page, viewportName, 'idea-detail-delete-top'));
  await expandAccess(page);
  captured.push(await screenshot(page, viewportName, 'idea-detail-share-delete-history'));

  await gotoPlan(page);
  await clickPlanText(page, 'Overdue task 01-01');
  captured.push(await screenshot(page, viewportName, 'reminders-status'));

  await gotoSettings(page);
  captured.push(await screenshot(page, viewportName, 'settings'));

  const consoleErrors = (await page.context().pages()[0].evaluate(() => [])).length;
  await context.close();
  return { viewportName, captured, consoleErrors };
}

await fs.mkdir(screenshotsDir, { recursive: true });
const browser = await chromium.launch({ headless: true });
const results = [];
try {
  results.push(await runViewport(browser, 'desktop-1440x1000', { width: 1440, height: 1000 }, false));
  results.push(await runViewport(browser, 'iphone-390x844', { width: 390, height: 844 }, true));
  results.push(await runViewport(browser, 'iphone-430x932', { width: 430, height: 932 }, true));
} finally {
  await browser.close();
}

await fs.writeFile(path.join(artifactRoot, 'web-screenshots-index.json'), JSON.stringify({
  baseUrl,
  generatedAt: new Date().toISOString(),
  results,
}, null, 2));

console.log(JSON.stringify(results, null, 2));
