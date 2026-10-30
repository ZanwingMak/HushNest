import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    // Exercise timer/UI transitions without outputting audio on the developer's machine.
    window.HTMLMediaElement.prototype.play = async function () { this.dispatchEvent(new Event('play')); };
  });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: '好好休息.' })).toBeVisible();
});
async function confirmHeadphones(page: Page) {
  await page.getByRole('button', { name: '检查耳机' }).click();
  await page.getByRole('checkbox', { name: '我已确认声音仅从耳机播放' }).check();
  await page.getByRole('dialog').getByRole('button', { name: '完成', exact: true }).click();
}
async function duration(page: Page, seconds: number) {
  await page.getByRole('button', { name: '添加常用时长' }).click();
  await page.getByRole('spinbutton', { name: '分钟', exact: true }).fill('0');
  await page.getByRole('spinbutton', { name: '秒', exact: true }).fill(String(seconds));
  await page.getByRole('dialog').getByRole('button', { name: '添加常用时长' }).click();
}
test('headphone gate, short alarm, snooze, pause, resume, history', async ({ page }) => {
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  await expect(page.getByRole('dialog', { name: '检查耳机' })).toBeVisible();
  await page.getByRole('checkbox').check();
  await page.getByRole('dialog').getByRole('button', { name: '完成', exact: true }).click();
  await page.getByRole('button', { name: '不播放助眠音', exact: true }).click();
  await duration(page, 1);
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  await expect(page.getByRole('button', { name: '我醒了，结束休息' })).toBeVisible({ timeout: 4000 });
  await page.getByRole('button', { name: '再休息 5 分钟' }).click();
  await page.getByRole('button', { name: '暂停一下' }).click();
  const before = await page.locator('.timer-value').textContent();
  await page.waitForTimeout(1100);
  expect(await page.locator('.timer-value').textContent()).toBe(before);
  await page.getByRole('button', { name: '确认耳机，继续休息' }).click();
  await page.getByRole('button', { name: '结束这次休息' }).click();
  await page.getByRole('button', { name: '休息足迹', exact: true }).click();
  await expect(page.locator('.record-row')).toHaveCount(1);
});
test('reload restores interrupted state and requires a new headphone confirmation', async ({ page }) => {
  await confirmHeadphones(page); await duration(page, 30);
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  await page.reload();
  await expect(page.getByText('应用曾关闭，计时未在后台继续。确认耳机后可手动恢复。')).toBeVisible();
  await page.getByRole('button', { name: '确认耳机，继续休息' }).click();
  await expect(page.getByRole('alert')).toContainText('耳机输出已变化');
  await confirmHeadphones(page);
  await page.getByRole('button', { name: '确认耳机，继续休息' }).click();
  await expect(page.getByRole('button', { name: '暂停一下' })).toBeVisible();
});
test('an output change immediately blocks a running session', async ({ page }) => {
  await confirmHeadphones(page); await duration(page, 30);
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  await page.evaluate(() => navigator.mediaDevices.dispatchEvent(new Event('devicechange')));
  await expect(page.getByText('耳机输出已变化，声音已停止。确认耳机后继续。')).toBeVisible();
  await expect(page.getByRole('button', { name: '确认耳机，继续休息' })).toBeVisible();
});
test('imported audio survives reload and deletion resets its selected sound', async ({ page }) => {
  await page.getByRole('button', { name: '我的声音', exact: true }).click();
  const bytes = Buffer.alloc(44 + 16000);
  bytes.write('RIFF', 0); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVEfmt ', 8);
  bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22); bytes.writeUInt32LE(8000, 24);
  bytes.writeUInt32LE(16000, 28); bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34); bytes.write('data', 36); bytes.writeUInt32LE(16000, 40);
  await page.locator('input[type=file]').setInputFiles({ name: 'quiet-test.wav', mimeType: 'audio/wav', buffer: bytes });
  await expect(page.getByRole('heading', { name: 'quiet-test.wav' })).toBeVisible();
  await page.locator('.media-row').getByRole('button', { name: '助眠音', exact: true }).click();
  await page.reload();
  await page.getByRole('button', { name: '我的声音', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'quiet-test.wav' })).toBeVisible();
  await page.getByRole('button', { name: '删除 quiet-test.wav' }).click();
  await page.getByRole('button', { name: '删除声音', exact: true }).click();
  await expect(page.locator('.media-row')).toHaveCount(0);
  const selected = await page.evaluate(() => JSON.parse(localStorage.getItem('hushnest:preferences')!).sleepSound);
  expect(selected).toBe('rain');
});
test('mobile layout, language and theme preferences persist without horizontal overflow', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('button', { name: '我的耳憩', exact: true }).click();
  await page.getByRole('button', { name: '海湾', exact: true }).click();
  await page.getByRole('combobox', { name: '语言', exact: true }).selectOption('en');
  await expect(page.getByRole('heading', { name: 'My HushNest.' })).toBeVisible();
  await page.reload();
  await page.getByRole('button', { name: 'My HushNest', exact: true }).click();
  await expect(page.getByRole('combobox', { name: 'Language', exact: true })).toHaveValue('en');
  expect(await page.evaluate(() => document.documentElement.dataset.theme)).toBe('ocean');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
test('a second tab cannot run an independent alarm', async ({ page }) => {
  const second = await page.context().newPage(); await second.goto('/');
  await expect(second.getByRole('alert')).toContainText('已有另一个耳憩页面正在运行');
  await expect(second.getByRole('button', { name: '开始我的片刻安静' })).toBeDisabled();
  await second.close();
});
