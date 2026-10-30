import { useEffect, useRef, useState } from 'react';
import type { PropsWithChildren } from 'react';
import { ArrowUpRight, BellSimple, Check, Clock, CloudRain, Drop, Fire, Flower, Headphones, Heart, Leaf, MoonStars, MusicNote, Pause, Play, Plus, SlidersHorizontal, SpeakerSlash, Trash, Tree, UploadSimple, Waves, Waveform, X } from '@phosphor-icons/react';
import type { Icon } from '@phosphor-icons/react';
import { alarmSounds, formatDuration, nextOccurrence, remaining, sleepSounds } from './core/model';
import type { Language, MediaItem, Preferences } from './core/model';
import { deleteMedia, importFile, listMedia } from './core/storage';
import { translator } from './i18n';
import type { Translate } from './i18n';
import { useNest } from './useNest';
import { isAndroid, isWindows, isWeb, native, platformName } from './platform';

type Page = 'rest' | 'history' | 'library' | 'settings';
const soundIcons: Record<string, Icon> = { rain: CloudRain, ocean: Waves, stream: Drop, forest: Tree, fireplace: Fire, night: MoonStars, brown: Waveform, pink: Waveform, none: SpeakerSlash };
const languageNames: Record<Language, string> = { 'zh-Hans': '简体中文', 'zh-Hant': '繁體中文', en: 'English', ja: '日本語', ko: '한국어', es: 'Español' };
function Modal({ open, title, onClose, children }: PropsWithChildren<{ open: boolean; title: string; onClose: () => void }>) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => { if (open && !dialog.current?.open) dialog.current?.showModal(); else if (!open && dialog.current?.open) dialog.current.close(); }, [open]);
  return <dialog ref={dialog} onCancel={onClose} onClick={event => { if (event.target === dialog.current) onClose(); }} aria-label={title}>
    <div className="modal-header"><h2>{title}</h2><button className="icon-button" onClick={onClose} aria-label="Close"><X size={22} /></button></div>{children}
  </dialog>;
}
function Switch({ label, checked, onChange, disabled = false }: { label: string; checked: boolean; onChange: (value: boolean) => void; disabled?: boolean }) {
  return <label className="switch-row"><span>{label}</span><input type="checkbox" role="switch" checked={checked} disabled={disabled} onChange={e => onChange(e.target.checked)} /><span className="switch-track" aria-hidden="true" /></label>;
}
function VolumeControl({ preferences: p, update, t, alarm = false }: { preferences: Preferences; update: (patch: Partial<Preferences>) => void; t: Translate; alarm?: boolean }) {
  return <label className="volume"><span>{t(alarm ? '唤醒铃声' : '助眠音')}<strong>{Math.round((alarm ? p.alarmVolume : p.sleepVolume) * 100)}%</strong></span><input type="range" aria-label={t(alarm ? '唤醒铃声音量' : '助眠音量')} min={alarm ? 5 : 1} max={alarm ? 100 : 60} value={Math.round((alarm ? p.alarmVolume : p.sleepVolume) * 100)} onChange={e => update({ [alarm ? 'alarmVolume' : 'sleepVolume']: Number(e.target.value) / 100 })} /></label>;
}
export function App() {
  const nest = useNest(); const { preferences: p, session: s, route, now } = nest;
  const [dictionary, setDictionary] = useState<Record<string, string>>({});
  const [page, setPage] = useState<Page>('rest'); const [modal, setModal] = useState<null | 'route' | 'duration' | 'clear' | 'delete'>(null);
  const [minutes, setMinutes] = useState(30); const [seconds, setSeconds] = useState(0);
  const [mode, setMode] = useState<'countdown' | 'clock'>('countdown'); const [clockTime, setClockTime] = useState('13:30');
  const [media, setMedia] = useState<MediaItem[]>([]); const [mediaLoading, setMediaLoading] = useState(true);
  const [importing, setImporting] = useState(false); const [deleteId, setDeleteId] = useState('');
  const fileInput = useRef<HTMLInputElement>(null); const t = translator(p.language, dictionary);
  const update = nest.updatePreferences;
  useEffect(() => {
    let disposed = false;
    void fetch(new URL(`locales/${p.language}.json`, document.baseURI)).then(r => { if (!r.ok) throw new Error(); return r.json(); })
      .then(data => { if (!disposed) setDictionary(data); }).catch(() => { if (!disposed) nest.setError('storageError'); });
    document.documentElement.lang = p.language;
    return () => { disposed = true; };
  }, [p.language]);
  useEffect(() => {
    document.documentElement.dataset.theme = p.theme;
    document.documentElement.dataset.appearance = p.appearance;
    document.documentElement.dataset.large = String(p.largeText);
  }, [p.theme, p.appearance, p.largeText]);
  useEffect(() => {
    let disposed = false;
    const load = isAndroid ? native.listMedia().then(r => r.items) : listMedia();
    void load.then(items => { if (!disposed) setMedia(items); }).catch(() => nest.setError('storageError')).finally(() => { if (!disposed) setMediaLoading(false); });
    return () => { disposed = true; };
  }, []);
  const selectedSleep = sleepSounds.find(item => item[0] === p.sleepSound);
  const soundName = (id: string) => id.startsWith('custom:') ? media.find(item => item.id === id.slice(7))?.name ?? t('自定义声音') : t([...sleepSounds, ...alarmSounds].find(item => item[0] === id)?.[1] ?? id);
  const currentRemaining = s ? remaining(s, now) : p.duration;
  const fraction = s ? Math.min(1, currentRemaining / s.duration) : 1;
  const completed = nest.records.filter(r => r.completed).length;
  const totalMinutes = Math.floor(nest.records.reduce((sum, r) => sum + r.seconds, 0) / 60);
  const active = !!s; const disabled = !nest.ready || nest.busy || !nest.exclusive;
  function openDuration() { setMinutes(Math.floor(p.duration / 60)); setSeconds(p.duration % 60); setModal('duration'); }
  async function begin() {
    if (!isWeb && !route.connected) { setModal('route'); return; }
    let duration = p.duration;
    if (mode === 'clock') {
      duration = Math.ceil((nextOccurrence(clockTime, Date.now()) - Date.now()) / 1000);
      if (duration > 43200) { nest.setError('请选择有效的提醒时间。'); return; }
    }
    await nest.command('start', duration);
  }
  async function importAudio(file?: File) {
    setImporting(true); nest.setError('');
    try {
      const item = isAndroid ? await native.importMedia() : file ? await importFile(file) : null;
      if (item) setMedia(items => [...items, item]);
    } catch (error) {
      if (!(error instanceof Error && /cancel/i.test(error.message))) nest.setError('mediaError');
    } finally { setImporting(false); if (fileInput.current) fileInput.current.value = ''; }
  }
  async function confirmNativeRoute() {
    try { await native.command({ action: 'confirmRoute' }); await nest.checkRoute(); } catch { nest.setError('routeLost'); }
  }
  async function removeAudio() {
    try {
      if (isAndroid) await native.deleteMedia({ id: deleteId });
      else { await deleteMedia(deleteId); if (isWindows) await window.hushnestAudio!.deleteMedia(deleteId); }
      const patch: Partial<Preferences> = {};
      if (p.sleepSound === `custom:${deleteId}`) patch.sleepSound = 'rain';
      if (p.alarmSound === `custom:${deleteId}`) patch.alarmSound = 'dawn';
      update(patch); setMedia(items => items.filter(item => item.id !== deleteId)); setModal(null);
    } catch { nest.setError('storageError'); }
  }
  const navigation: [Page, Icon, string][] = [['rest', Leaf, '好好休息'], ['library', MusicNote, '我的声音'], ['history', Clock, '休息足迹'], ['settings', SlidersHorizontal, '我的耳憩']];
  return <div className="app-shell">
    <aside className="sidebar">
      <a className="brand" href="#rest" onClick={e => { e.preventDefault(); setPage('rest'); }}><img src="./icon.png" alt="" /><span>耳憩<small>HushNest</small></span></a>
      <nav aria-label={t('我的耳憩')}>{navigation.map(([id, IconComponent, label]) => <button key={id} className={page === id ? 'nav-item selected' : 'nav-item'} aria-current={page === id ? 'page' : undefined} onClick={() => setPage(id)}><IconComponent size={21} weight={page === id ? 'fill' : 'regular'} /><span>{t(label)}</span>{page === id && <span className="nav-dot" />}</button>)}</nav>
      <div className="sidebar-footer"><span className="free-badge"><span />{platformName} · OPEN SOURCE</span><p>{t('片刻安静，自在醒来。')}</p><a href="https://github.com/ZanwingMak/HushNest" target="_blank" rel="noreferrer">GitHub <ArrowUpRight size={14} /></a></div>
    </aside>
    <main className="main">
      <header className="topbar"><span className="eyebrow">A LITTLE SPACE FOR YOURSELF</span><span className="local-badge"><span />{t('local')}</span></header>
      <div className="page-heading"><div><div className="section-kicker">HUSHNEST / {platformName.toUpperCase()}</div><h1>{t(navigation.find(n => n[0] === page)![2])}<span className="heading-dot">.</span></h1><p>{t(page === 'rest' ? '片刻安静，自在醒来。' : page === 'history' ? '每次停下来，\n都在好好照顾自己。' : page === 'library' ? '导入喜欢的音乐、录音或视频声音。' : '按你的节奏')}</p></div><div className="heading-art" aria-hidden="true"><Leaf size={44} weight="thin" /><span /></div></div>
      {nest.error && <div className="alert" role="alert"><span>{t(nest.error)}</span><button className="icon-button" aria-label={t('完成')} onClick={() => nest.setError('')}><X size={18} /></button></div>}
      {!nest.ready && <div className="loading" role="status">{t('busy')}</div>}
      {page === 'rest' && <div className="rest-grid">
        <section className="timer-card card">
          <div className="card-top"><span className="section-kicker">{t(s?.phase === 'ringing' ? '时间到了' : s?.phase === 'paused' ? '休息已暂停' : s?.phase === 'blocked' ? '提醒已中断' : '把提醒留给自己')}</span><span className="quiet-pill"><Leaf size={13} />{t('片刻安静')}</span></div>
          {!active && <div className="segmented" aria-label={t('提醒方式')}><button className={mode === 'countdown' ? 'selected' : ''} onClick={() => setMode('countdown')}>{t('倒计时')}</button><button className={mode === 'clock' ? 'selected' : ''} onClick={() => setMode('clock')}>{t('指定时间')}</button></div>}
          <div className={`timer-orbit ${s?.phase === 'resting' ? 'breathing' : ''}`}>
            <svg className="orbit" viewBox="0 0 300 300" aria-hidden="true"><circle className="orbit-track" cx="150" cy="150" r="133" /><circle className="orbit-progress" cx="150" cy="150" r="133" strokeDasharray={835.66} strokeDashoffset={835.66 * (1 - fraction)} /></svg>
            <div className="timer-content"><div className="timer-symbol">{s?.phase === 'ringing' ? <BellSimple size={31} /> : <Leaf size={31} weight="light" />}</div>{!active && mode === 'clock' ? <input className="clock-input" aria-label={t('唤醒时间')} type="time" value={clockTime} onChange={e => setClockTime(e.target.value)} /> : <button className="timer-value" disabled={active} onClick={openDuration} aria-label={t('自定义时长和预设')}>{formatDuration(currentRemaining)}</button>}<span className="timer-caption">{t(s?.phase === 'ringing' ? '慢慢睁眼，带走这份轻松' : s?.phase === 'paused' ? '休息已暂停' : s?.phase === 'blocked' ? '提醒已中断' : '助眠声音 · 渐强唤醒')}</span></div>
          </div>
          {!active && <div className="presets">{p.presets.map(duration => <div key={duration} className={`preset-wrap ${p.duration === duration ? 'selected' : ''}`}><button disabled={mode !== 'countdown'} onClick={() => update({ duration })}>{duration % 60 ? formatDuration(duration) : `${duration / 60} ${t('分钟')}`}</button>{![900, 1800, 2700, 3600].includes(duration) && <button className="remove-preset" aria-label={t('删除 %@', formatDuration(duration))} onClick={() => update({ presets: p.presets.filter(v => v !== duration) })}><X size={12} /></button>}</div>)}<button className="add-preset icon-button" onClick={openDuration} aria-label={t('添加常用时长')}><Plus size={18} /></button></div>}
          {s?.reason && <p className="session-reason" role="status">{t(isWeb && s.reason === 'restored' ? 'webRestored' : s.reason)}</p>}
          <div className="timer-actions">{!s ? <button className="primary-button" disabled={disabled} onClick={() => void begin()}><Play size={19} weight="fill" />{t(nest.busy ? 'busy' : '开始我的片刻安静')}</button> : s.phase === 'ringing' ? <><button className="primary-button" disabled={disabled} onClick={() => void nest.command('stop')}><Check size={20} />{t('我醒了，结束休息')}</button><button className="secondary-button" disabled={disabled} onClick={() => void nest.command('snooze')}>{t('再休息 %@ 分钟', p.snoozeMinutes)}</button></> : <><button className="primary-button" disabled={disabled} onClick={() => void nest.command(s.phase === 'resting' ? 'pause' : 'resume')}>{s.phase === 'resting' ? <Pause size={20} /> : <Play size={20} />}{t(s.phase === 'resting' ? '暂停一下' : isWeb ? '继续休息' : '确认耳机，继续休息')}</button><button className="text-button" disabled={disabled} onClick={() => void nest.command('stop')}>{t('结束这次休息')}</button></>}</div>
          <p className="timer-footnote"><Headphones size={15} />{t(isAndroid || isWindows ? 'nativeLimit' : 'webLimit')}</p>
        </section>
        <div className="sound-column">
          <section className="route-card"><div className="route-icon">{isWeb ? <Waves size={24} /> : <Headphones size={24} />}</div><div><strong>{t(isWeb ? 'systemOutput' : 'output')}</strong><p>{isWeb ? t('webOutput') : route.connected ? route.name : t('尚未连接耳机')}</p></div>{!isWeb && <button className="icon-button" onClick={() => setModal('route')} aria-label={t('checkOutput')}><ArrowUpRight size={21} /></button>}</section>
          <section className="sound-card card"><div className="section-heading"><h2>{t('助眠音')}</h2><span className="subtle">SOUNDSCAPES</span></div><fieldset disabled={active || disabled} className="sound-grid">{sleepSounds.map(([id, label]) => { const SoundIcon = soundIcons[id]; return <button key={id} aria-pressed={p.sleepSound === id} className={`sound-tile sound-${id} ${p.sleepSound === id ? 'selected' : ''}`} onClick={() => update({ sleepSound: id })}><SoundIcon size={24} weight="light" /><span>{t(label)}</span>{p.sleepSound === id && <Check size={13} className="tile-check" />}</button>; })}</fieldset><div className="sound-detail"><p>{selectedSleep ? t(selectedSleep[2]) : soundName(p.sleepSound)}</p><button className="icon-button" disabled={active || disabled || p.sleepSound === 'none'} onClick={() => void nest.preview(p.sleepSound)} aria-label={t('试听')}><Play size={17} /></button></div><VolumeControl preferences={p} update={update} t={t} /></section>
          <section className="alarm-card card"><div className="section-heading"><h2><BellSimple size={19} />{t('轻轻唤醒')}</h2><button className="icon-button" disabled={active || disabled} onClick={() => void nest.preview(p.alarmSound, true)} aria-label={t('试听唤醒铃声')}><Play size={17} /></button></div><label className="select-field"><span>{t('唤醒铃声')}</span><select value={p.alarmSound} disabled={active} onChange={e => update({ alarmSound: e.target.value })}>{alarmSounds.map(([id, label]) => <option key={id} value={id}>{t(label)}</option>)}{media.map(item => <option key={item.id} value={`custom:${item.id}`}>{item.name}</option>)}</select></label><VolumeControl preferences={p} update={update} t={t} alarm /><Switch label={t('持续响铃')} checked={p.repeatAlarm} disabled={active} onChange={repeatAlarm => update({ repeatAlarm })} /><p className="small-note">{t(p.repeatAlarm ? '持续响铃，直到手动结束或稍后提醒。' : '关闭时最多提醒 3 分钟。')}</p></section>
        </div>
      </div>}
      {page === 'library' && <section className="library-page"><div className="import-banner"><div className="import-symbol"><MusicNote size={38} weight="light" /></div><div><h2>{t('我的声音')}</h2><p>{t('mediaHint')}</p></div><button className="primary-button compact" disabled={active || importing || media.length >= 20} onClick={() => isAndroid ? void importAudio() : fileInput.current?.click()}><UploadSimple size={18} />{t(importing ? '正在提取音轨…' : '从文件导入音频或视频')}</button><input ref={fileInput} hidden type="file" accept="audio/*,video/*,.m4a,.mp3,.wav,.ogg,.mp4,.webm,.flac" onChange={e => { const file = e.target.files?.[0]; if (file) void importAudio(file); }} /></div>{mediaLoading ? <div className="empty-state loading">{t('busy')}</div> : !media.length ? <div className="empty-state"><MusicNote size={44} weight="thin" /><h3>{t('导入喜欢的音乐、录音或视频声音。')}</h3><p>{t('仅保存在本机的音轨')}</p></div> : <div className="media-list card">{media.map(item => <article className="media-row" key={item.id}><div className="media-icon"><MusicNote size={24} /></div><div className="media-info"><h3>{item.name}</h3><p>{formatDuration(item.duration)} · {(item.size / 1024 / 1024).toFixed(1)} MB</p></div><button className="icon-button" aria-label={`${t('试听')} ${item.name}`} disabled={active || disabled} onClick={() => void nest.preview(`custom:${item.id}`)}><Play size={18} /></button><button disabled={active} className={`secondary-button small ${p.sleepSound === `custom:${item.id}` ? 'chosen' : ''}`} onClick={() => update({ sleepSound: `custom:${item.id}` })}>{t('助眠音')}{p.sleepSound === `custom:${item.id}` && <Check size={14} />}</button><button className="icon-button" aria-label={t('删除 %@', item.name)} disabled={active} onClick={() => { setDeleteId(item.id); setModal('delete'); }}><Trash size={18} /></button></article>)}</div>}</section>}
      {page === 'history' && <section className="history-page"><div className="stats"><div className="stat"><span>{t('完成休息')}</span><strong>{completed}<small>/ SESSIONS</small></strong></div><div className="stat"><span>{t('累计分钟')}</span><strong>{totalMinutes}<small>/ MINUTES</small></strong></div><div className="history-leaf"><Leaf size={52} weight="thin" /></div></div>{!nest.records.length ? <div className="empty-state"><Leaf size={44} weight="thin" /><h3>{t('从片刻安静开始')}</h3><p>{t('结束一次休息后，足迹会出现在这里。')}<br />{t('local')}</p></div> : <div className="card record-list">{nest.records.map(record => <article className="record-row" key={record.id}><div className={`record-symbol ${record.completed ? 'completed' : ''}`}>{record.completed ? <Check size={19} /> : <Leaf size={19} />}</div><div><strong>{t(record.completed ? '完成一段休息' : '提前结束')}</strong><p>{new Date(record.startedAt).toLocaleString(p.language)} · {soundName(record.sound)}</p></div><span className="record-duration">{formatDuration(record.seconds)}</span></article>)}</div>}{!!nest.records.length && <button className="text-button danger" disabled={active} onClick={() => setModal('clear')}><Trash size={16} />{t('清空本机记录')}</button>}</section>}
      {page === 'settings' && <section className="settings-grid">
        <div className="card settings-card"><h2><Flower size={21} />{t('心情与色彩')}</h2><fieldset className="theme-picker">{(['forest', 'ocean', 'dusk', 'rose'] as const).map((theme, index) => <button key={theme} data-theme={theme} className={p.theme === theme ? 'selected' : ''} aria-pressed={p.theme === theme} onClick={() => update({ theme })}><span>{p.theme === theme && <Check size={18} />}</span>{t(['松林', '海湾', '暮紫', '玫瑰'][index])}</button>)}</fieldset><label className="select-field"><span>{t('appearance')}</span><select value={p.appearance} onChange={e => update({ appearance: e.target.value as Preferences['appearance'] })}><option value="system">{t('跟随系统')}</option><option value="light">{t('light')}</option><option value="dark">{t('dark')}</option></select></label><Switch label={t('largeText')} checked={p.largeText} onChange={largeText => update({ largeText })} /><label className="select-field"><span>{t('语言')}</span><select value={p.language} onChange={e => update({ language: e.target.value as Language })}>{Object.entries(languageNames).map(([id, name]) => <option key={id} value={id}>{name}</option>)}</select></label></div>
        <div className="card settings-card"><h2><BellSimple size={21} />{t('提醒方式')}</h2><label className="select-field"><span>{t('稍后提醒')}</span><select value={p.snoozeMinutes} disabled={active} onChange={e => update({ snoozeMinutes: Number(e.target.value) })}>{[1, 3, 5, 10, 15, 30].map(v => <option value={v} key={v}>{v} {t('分钟')}</option>)}</select></label>{!isWindows && <Switch label={t('震动')} checked={p.vibration} disabled={active} onChange={vibration => update({ vibration })} />}<p className="small-note">{t(isAndroid ? 'notification' : isWindows ? 'nativeLimit' : 'webLimit')}</p>{!isWeb && <button className="secondary-button" onClick={() => setModal('route')}><Headphones size={18} />{t('checkOutput')}</button>}</div>
        <div className="card settings-card about-card"><h2><Heart size={21} />{t('自由，也透明')}</h2><p>{t('privacy')}</p><div className="about-links"><a href="https://github.com/ZanwingMak/HushNest" target="_blank" rel="noreferrer">{t('查看开源代码')}<ArrowUpRight size={16} /></a><a href="https://github.com/ZanwingMak/HushNest/issues" target="_blank" rel="noreferrer">{t('反馈问题与建议')}<ArrowUpRight size={16} /></a><a href="./audio/FieldRecordings.json" target="_blank" rel="noreferrer">CC0 / Public domain<ArrowUpRight size={16} /></a><a href="./LICENSE.txt" target="_blank" rel="noreferrer">MIT License<ArrowUpRight size={16} /></a></div><span className="version">HushNest {platformName} · 0.1.0</span></div>
      </section>}
      <footer className="page-footer"><span>HUSHNEST</span><p>{t('免费 · 无广告 · 无订阅 · 数据仅在本机')}</p><Leaf size={17} weight="light" /></footer>
    </main>
    <Modal open={modal === 'duration'} title={t('自定义时长和预设')} onClose={() => setModal(null)}><form onSubmit={e => { e.preventDefault(); const duration = minutes * 60 + seconds; if (duration >= 1 && duration <= 43200) { update({ duration, presets: [...p.presets, duration] }); setModal(null); } }}><div className="duration-fields"><label>{t('分钟')}<input type="number" min="0" max="720" required value={minutes} onChange={e => setMinutes(Number(e.target.value))} /></label><span>:</span><label>{t('seconds')}<input type="number" min="0" max="59" required value={seconds} onChange={e => setSeconds(Number(e.target.value))} /></label></div><button className="primary-button" disabled={minutes * 60 + seconds < 1 || minutes * 60 + seconds > 43200 || active}>{t('添加常用时长')}</button></form></Modal>
    {!isWeb && <Modal open={modal === 'route'} title={t('checkOutput')} onClose={() => setModal(null)}><div className="route-modal"><div className="route-illustration"><Headphones size={56} weight="thin" /></div><p>{t('nativeLimit')}</p><button className="primary-button" onClick={() => void nest.checkRoute().catch(() => nest.setError('routeLost'))}>{t('checkOutput')}</button><p className="route-result" role="status">{route.connected ? route.name : t('尚未连接耳机')}</p>{isAndroid && route.name && !route.verified && <label className="confirmation"><input type="checkbox" checked={route.connected} disabled={!!s && ['resting', 'ringing'].includes(s.phase)} onChange={() => void confirmNativeRoute()} /><span>{t('bluetoothConfirm')}</span></label>}<button className="primary-button" disabled={!route.connected} onClick={() => setModal(null)}>{t('完成')}</button></div></Modal>}
    <Modal open={modal === 'clear'} title={t('清空所有休息记录？')} onClose={() => setModal(null)}><p>{t('此操作只删除这台设备上的记录，无法恢复。')}</p><button className="primary-button danger-button" onClick={() => { void nest.clearRecords().then(() => setModal(null)).catch(() => nest.setError('storageError')); }}>{t('清空记录')}</button></Modal>
    <Modal open={modal === 'delete'} title={t('删除这个声音？')} onClose={() => setModal(null)}><p>{t('使用这个声音的配置将恢复为内置声音。')}</p><button className="primary-button danger-button" onClick={() => void removeAudio()}>{t('删除声音')}</button></Modal>
  </div>;
}
