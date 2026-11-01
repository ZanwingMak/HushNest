import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

/** 模拟 Capacitor 命令边界，原生设备可在用户点击确认后立即切换；不播放音频。 */
async function androidBridge(page: Page) {
  await page.addInitScript(() => {
    let confirmed = '', previewSound = '', previewAlarm = false;
    const snapshot = () => {
      const data = document.documentElement.dataset;
      const token = data.testDevice ?? 'headset-a';
      return { session: null, records: [], previewSound, route: { connected: confirmed === token, verified: false,
        name: token === 'headset-a' ? 'Test Bluetooth headphones' : 'Test Bluetooth speaker', token } };
    };
    Object.assign(window, { androidBridge: {}, Capacitor: {
      PluginHeaders: [{ name: 'HushNest', methods: ['snapshot', 'command', 'listMedia', 'requestNotifications'].map(name => ({ name, rtype: 'promise' })) }],
      nativePromise: async (_plugin: string, method: string, input: Record<string, unknown> = {}) => {
        const data = document.documentElement.dataset;
        if (method === 'listMedia') return { items: [] };
        if (method === 'requestNotifications') return { granted: true };
        if (method === 'command') {
          if (input.action === 'confirmRoute') {
            data.testConfirmedToken = String(input.routeToken);
            if (data.testSwitchOnConfirm) data.testDevice = 'speaker-b';
            if (input.routeToken !== snapshot().route.token) throw new Error('routeChanged');
            confirmed = String(input.routeToken);
          }
          if (input.action === 'preview') {
            previewSound = String(input.sound); previewAlarm = input.alarm === true;
            data.testNativeGain = String(input.volume); data.testPreviewAlarm = String(previewAlarm);
          }
          if (input.action === 'volume') {
            const p = input.preferences as { sleepVolume: number; alarmVolume: number };
            data.testNativeGain = String(previewAlarm ? p.alarmVolume : p.sleepVolume);
          }
        }
        return snapshot();
      },
    } });
  });
  await page.reload();
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    // Exercise timer/UI transitions without outputting audio on the developer's machine.
    window.HTMLMediaElement.prototype.play = async function () {
      const data = document.documentElement.dataset;
      data.testPlayCount = String(Number(data.testPlayCount ?? 0) + 1);
      Object.assign(document, { testAudio: this });
      this.dispatchEvent(new Event('play'));
    };
  });
  await page.goto('/');
  await expect(page.getByRole('heading', { name: '好好休息.' })).toBeVisible();
});

test('alarm and sleep preview volumes follow their own sliders without restarting playback', async ({ page }) => {
  await page.clock.install();
  await page.clock.pauseAt(new Date());
  await page.getByRole('button', { name: '试听唤醒铃声', exact: true }).click();
  const volume = () => page.evaluate(() => (document as Document & { testAudio: HTMLMediaElement }).testAudio.volume);
  await expect.poll(volume).toBe(.55);
  const alarm = page.getByRole('slider', { name: '唤醒铃声音量', exact: true });
  await alarm.focus(); await alarm.press('End');
  await expect.poll(volume).toBe(1);
  await alarm.press('Home');
  await expect.poll(volume).toBe(.05);
  const sleep = page.getByRole('slider', { name: '助眠音量', exact: true });
  await sleep.focus(); await sleep.press('End');
  await expect.poll(volume).toBe(.05);
  expect(await page.evaluate(() => Number(document.documentElement.dataset.testPlayCount))).toBe(1);
  await page.getByRole('button', { name: '试听', exact: true }).click();
  await expect.poll(volume).toBe(.6);
  await sleep.press('Home');
  await expect.poll(volume).toBe(.01);
  expect(await page.evaluate(() => Number(document.documentElement.dataset.testPlayCount))).toBe(2);
});

test('Android confirmation sends the shown device token and rejects a device changed during confirmation', async ({ page }) => {
  await androidBridge(page);
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  const dialog = page.getByRole('dialog', { name: '检查耳机' });
  await expect(dialog.getByText('Test Bluetooth headphones', { exact: true })).toBeVisible();
  await page.evaluate(() => { document.documentElement.dataset.testSwitchOnConfirm = 'true'; });
  await dialog.getByRole('checkbox').click();
  await expect(page.getByRole('alert')).toBeVisible();
  await expect(dialog.getByRole('checkbox')).not.toBeChecked();
  expect(await page.evaluate(() => document.documentElement.dataset.testConfirmedToken)).toBe('headset-a');
  await expect(dialog.getByRole('button', { name: '完成', exact: true })).toBeDisabled();
  expect(await page.evaluate(() => Number(document.documentElement.dataset.testPlayCount ?? 0))).toBe(0);
});

test('Android preview uses alarm volume and forwards live adjustments without a session', async ({ page }) => {
  await androidBridge(page);
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  const dialog = page.getByRole('dialog', { name: '检查耳机' });
  await dialog.getByRole('checkbox').check();
  await dialog.getByRole('button', { name: '完成', exact: true }).click();
  await page.getByRole('button', { name: '试听唤醒铃声', exact: true }).click();
  const gain = () => page.evaluate(() => Number(document.documentElement.dataset.testNativeGain));
  await expect.poll(gain).toBe(.55);
  expect(await page.evaluate(() => document.documentElement.dataset.testPreviewAlarm)).toBe('true');
  const alarm = page.getByRole('slider', { name: '唤醒铃声音量', exact: true });
  await alarm.focus(); await alarm.press('End');
  await expect.poll(gain).toBe(1);
  await alarm.press('Home');
  await expect.poll(gain).toBe(.05);
  await expect(page.getByRole('button', { name: '开始我的片刻安静' })).toBeVisible();
});
async function duration(page: Page, seconds: number) {
  await page.getByRole('button', { name: '添加常用时长' }).click();
  await page.getByRole('spinbutton', { name: '分钟', exact: true }).fill('0');
  await page.getByRole('spinbutton', { name: '秒', exact: true }).fill(String(seconds));
  await page.getByRole('dialog').getByRole('button', { name: '添加常用时长' }).click();
}
test('Web starts without headphones, then alarms, snoozes, pauses, resumes and records', async ({ page }) => {
  await expect(page.getByRole('button', { name: '检查耳机' })).toHaveCount(0);
  await expect(page.getByText('系统默认音频输出', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: '不播放助眠音', exact: true }).click();
  await duration(page, 1);
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  await expect(page.getByRole('button', { name: '我醒了，结束休息' })).toBeVisible({ timeout: 4000 });
  await page.getByRole('button', { name: '再休息 5 分钟' }).click();
  await page.getByRole('button', { name: '暂停一下' }).click();
  const before = await page.locator('.timer-value').textContent();
  await page.waitForTimeout(1100);
  expect(await page.locator('.timer-value').textContent()).toBe(before);
  await page.getByRole('button', { name: '继续休息', exact: true }).click();
  await page.getByRole('button', { name: '结束这次休息' }).click();
  await page.getByRole('button', { name: '休息足迹', exact: true }).click();
  await expect(page.locator('.record-row')).toHaveCount(1);
});
test('Web restores an interrupted session without requiring headphone confirmation', async ({ page }) => {
  await duration(page, 30);
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  await page.reload();
  await expect(page.getByText('应用曾关闭，计时未在后台继续。可手动继续休息。')).toBeVisible();
  await page.getByRole('button', { name: '继续休息', exact: true }).click();
  await expect(page.getByRole('button', { name: '暂停一下' })).toBeVisible();
  await expect(page.getByRole('dialog', { name: '检查耳机' })).toHaveCount(0);
});
test('Web keeps its running session and deadline when output devices change', async ({ page }) => {
  await duration(page, 30);
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  const before = await page.evaluate(() => JSON.parse(localStorage.getItem('hushnest:session')!));
  await page.evaluate(() => navigator.mediaDevices.dispatchEvent(new Event('devicechange')));
  await expect(page.getByRole('button', { name: '暂停一下' })).toBeVisible();
  const after = await page.evaluate(() => JSON.parse(localStorage.getItem('hushnest:session')!));
  expect(after.phase).toBe('resting'); expect(after.deadline).toBe(before.deadline);
  await expect(page.getByText('耳机输出已变化，声音已停止。确认耳机后继续。')).toHaveCount(0);
});
test('Web previews sleep audio and alarms without a headphone check', async ({ page }) => {
  await page.getByRole('button', { name: '试听', exact: true }).click();
  await expect.poll(() => page.evaluate(() => Number(document.documentElement.dataset.testPlayCount))).toBe(1);
  await page.getByRole('button', { name: '试听唤醒铃声', exact: true }).click();
  await expect.poll(() => page.evaluate(() => Number(document.documentElement.dataset.testPlayCount))).toBe(2);
  await expect(page.getByRole('dialog', { name: '检查耳机' })).toHaveCount(0);
});
test('native desktop still requires headphones and blocks on an output change', async ({ page }) => {
  await page.addInitScript(() => {
    let session: import('../../src/core/model').Session | null = null;
    const route = () => {
      const connected = document.documentElement.dataset.testNativeConnected === 'true';
      return { connected, verified: connected, name: connected ? 'Test headphones' : '', token: connected ? 'test-headphones' : '' };
    };
    const snapshot = async () => {
      if (session && !route().connected) session = { ...session, phase: 'blocked', reason: 'routeLost' };
      return { session, route: route(), records: [] };
    };
    window.hushnestDesktop = {
      platform: 'windows', route: async () => route(), snapshot,
      command: async input => {
        if (input.action === 'start' && input.session) session = { ...input.session };
        if (input.action === 'stop') session = null;
        return snapshot();
      },
      keepAwake: async () => {}, onSuspend: () => () => {},
    };
    window.hushnestAudio = {
      cacheMedia: async () => {}, deleteMedia: async () => {},
    };
  });
  await page.reload();
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  const dialog = page.getByRole('dialog', { name: '检查耳机' });
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole('button', { name: '完成', exact: true })).toBeDisabled();
  expect(await page.evaluate(() => localStorage.getItem('hushnest:session'))).toBeNull();
  await page.evaluate(() => { document.documentElement.dataset.testNativeConnected = 'true'; });
  await dialog.getByRole('button', { name: '检查耳机', exact: true }).click();
  await dialog.getByRole('button', { name: '完成', exact: true }).click();
  await duration(page, 30);
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  await expect(page.getByRole('button', { name: '暂停一下' })).toBeVisible();
  await page.evaluate(() => { document.documentElement.dataset.testNativeConnected = 'false'; });
  await expect(page.getByRole('button', { name: '确认耳机，继续休息' })).toBeVisible();
  await expect(page.getByText('耳机输出已变化，声音已停止。确认耳机后继续。')).toBeVisible();
});
test('macOS requires confirming an ambiguous external headphone device', async ({ page }) => {
  await page.addInitScript(() => {
    const route = () => ({ connected: document.documentElement.dataset.testConfirmed === 'true', verified: false, name: 'USB headphones', token: 'usb-test', requiresConfirmation: true });
    const snapshot = async () => ({ session: null, route: route(), records: [] });
    window.hushnestDesktop = {
      platform: 'darwin', snapshot, route: async () => route(), keepAwake: async () => {}, onSuspend: () => () => {},
      command: async input => { if (input.action === 'confirmRoute') document.documentElement.dataset.testConfirmed = 'true'; return snapshot(); },
    };
    window.hushnestAudio = { cacheMedia: async () => {}, deleteMedia: async () => {} };
  });
  await page.reload();
  await expect(page.locator('.section-kicker').first()).toContainText('MACOS');
  await page.getByRole('button', { name: '开始我的片刻安静' }).click();
  const dialog = page.getByRole('dialog', { name: '检查耳机' });
  await expect(dialog.getByRole('button', { name: '完成', exact: true })).toBeDisabled();
  await dialog.getByRole('checkbox', { name: '我确认此设备是耳机，不是音箱或车载设备', exact: true }).check();
  await dialog.getByRole('button', { name: '完成', exact: true }).click();
  await expect(page.locator('.route-card')).toContainText('USB headphones');
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
