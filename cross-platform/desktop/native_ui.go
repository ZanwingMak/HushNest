package main

import (
	"fmt"
	"log"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
)

type soundChoice struct{ id, name string }

var sleepChoices = []soundChoice{{"none", "不播放助眠音"}, {"rain", "细雨"}, {"ocean", "潮汐"}, {"stream", "溪流"}, {"forest", "林间"}, {"fireplace", "炉火"}, {"night", "夏夜"}, {"brown", "棕噪音"}, {"pink", "粉红噪音"}}
var alarmChoices = []soundChoice{{"dawn", "晨光"}, {"bell", "风铃"}, {"orbit", "星轨"}, {"piano", "柔钢琴"}, {"marimba", "木琴"}, {"harp", "竖琴"}, {"bamboo", "竹语"}, {"aurora", "极光"}, {"classic", "经典滴滴"}, {"twinbell", "机械双铃"}, {"digital", "数字闹钟"}, {"pulse", "急促脉冲"}, {"beacon", "交替信号"}, {"reveille", "起床号角"}}

// All fields of nativeApp are owned by the UI thread. Workers publish results
// through Window.Update; only restService's own locked state crosses threads.
type nativeApp struct {
	service          *restService
	window           *mygo.Window
	preferences      Preferences
	settings         nativeSettings
	dictionaries     map[string]map[string]string
	snapshot         Snapshot
	page             string
	mode             string
	target           time.Time
	minutes, seconds float64
	busy             bool
	errorText        string
	dirty            bool
	dirtyAt          time.Time
	afterRender      func()
}

func newNativeApp(service *restService, resources string) (*nativeApp, error) {
	dictionaries, err := loadDictionaries(resources)
	if err != nil {
		return nil, err
	}
	settings, settingsErr := loadNativeSettings(service.directory)
	service.mu.Lock()
	preferences := service.state.Preferences
	service.mu.Unlock()
	a := &nativeApp{service: service, preferences: preferences, settings: settings, dictionaries: dictionaries,
		snapshot: service.snapshot(), page: "rest", mode: "countdown", target: time.Now().Add(30 * time.Minute)}
	a.setDuration(a.preferences.Duration)
	if settingsErr != nil {
		a.errorText = a.t("本机存储不可用或空间不足。")
	}
	// Keep audio cached by the earlier desktop client available without opening
	// its old WebView/IndexedDB. Original names are unavailable for orphan files.
	entries, _ := os.ReadDir(filepath.Join(service.directory, "media"))
	known := map[string]bool{}
	for _, item := range a.settings.Media {
		known[item.ID] = true
	}
	for _, entry := range entries {
		id := strings.TrimSuffix(entry.Name(), ".media")
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".media") || !validID(id) || known[id] || len(a.settings.Media) >= 20 {
			continue
		}
		info, e := entry.Info()
		if e != nil || info.Size() < 1 || info.Size() > 200*1024*1024 {
			continue
		}
		var metadata struct{ Seconds float64 }
		if service.backend.request("inspect", map[string]any{"sound": "custom:" + id}, &metadata) == nil && metadata.Seconds > 0 && metadata.Seconds <= 7200 {
			a.settings.Media = append(a.settings.Media, localMedia{ID: id, Name: a.t("自定义声音") + " " + id[:8], Seconds: metadata.Seconds, Size: info.Size()})
		}
	}
	return a, nil
}
func (a *nativeApp) t(key string, args ...any) string {
	return translateNative(a.preferences.Language, a.dictionaries, key, args...)
}
func (a *nativeApp) setDuration(seconds int) {
	seconds = min(43200, max(1, seconds))
	a.preferences.Duration = seconds
	a.minutes, a.seconds = float64(seconds/60), float64(seconds%60)
}
func (a *nativeApp) changed() { a.dirty = true; a.dirtyAt = time.Now().Add(650 * time.Millisecond) }
func (a *nativeApp) launch(kind string, work func() error, done func()) {
	if a.busy {
		return
	}
	a.busy, a.errorText = true, ""
	run := func() {
		err := work()
		snapshot := a.service.snapshot()
		apply := func() {
			a.busy = false
			a.snapshot = snapshot
			if err != nil {
				log.Printf("desktop %s: %v", kind, err)
				a.showError(kind, err)
			} else if done != nil {
				done()
			}
		}
		if a.window == nil {
			apply()
		} else {
			a.window.Update(apply)
		}
	}
	if a.window == nil {
		run()
	} else {
		go run()
	}
}
func (a *nativeApp) showError(kind string, err error) {
	key := "操作未完成，请重试。"
	switch {
	case strings.Contains(err.Error(), "routeLost"):
		key = "当前没有可用耳机，声音已停止。连接后请手动继续。"
	case strings.Contains(err.Error(), "invalid-time"):
		key = "请选择有效的提醒时间。"
	case kind == "media":
		key = "仅提取音轨并保存到本机，不上传。支持常见音频和视频；不支持受保护媒体。每个文件最多 200 MB、2 小时，最多 20 个。"
	case kind == "storage":
		key = "本机存储不可用或空间不足。"
	}
	a.errorText = a.t(key)
}
func (a *nativeApp) save() {
	p, settings := a.preferences, a.settings.clone()
	a.dirty = false
	a.launch("storage", func() error {
		if _, err := a.service.command(CommandInput{Action: "volume", Preferences: &p}); err != nil {
			return err
		}
		return saveNativeSettings(a.service.directory, settings)
	}, nil)
}
func (a *nativeApp) command(action string, duration int, sound string) {
	p := a.preferences
	input := CommandInput{Action: action, Preferences: &p, Sound: sound, Volume: 0.12}
	if action == "start" {
		input.Session = &Session{Duration: duration}
	}
	settings := a.settings.clone()
	a.dirty = false
	a.launch("command", func() error {
		if err := saveNativeSettings(a.service.directory, settings); err != nil {
			return err
		}
		_, err := a.service.command(input)
		return err
	}, nil)
}
func (a *nativeApp) begin() {
	duration := a.preferences.Duration
	if a.mode == "clock" {
		var err error
		duration, err = nextNativeDuration(time.Now(), a.target)
		if err != nil {
			a.showError("command", err)
			return
		}
	}
	a.command("start", duration, "")
}
func (a *nativeApp) checkRoute() {
	a.launch("command", func() error {
		a.service.mu.Lock()
		defer a.service.mu.Unlock()
		return a.service.routeLocked()
	}, nil)
}
func (a *nativeApp) watch() {
	go func() {
		ticker := time.NewTicker(400 * time.Millisecond)
		defer ticker.Stop()
		previous := a.service.snapshot()
		for {
			select {
			case <-a.service.stop:
				return
			case <-ticker.C:
				next := a.service.snapshot()
				if !reflect.DeepEqual(previous, next) {
					previous = next
					a.window.Update(func() { a.snapshot = next })
				}
			}
		}
	}()
}
func (a *nativeApp) ask(question, accept string) bool {
	if a.window == nil {
		return true
	}
	answer, err := mygo.Dialog.Message(mygo.MessageOptions{Parent: a.window, Message: a.t(question), Buttons: []string{a.t("取消"), a.t(accept)}, DefaultButton: 0, CancelButton: 0})
	return err == nil && answer.Button == 1
}
func (a *nativeApp) chooseMedia() {
	files, err := mygo.Dialog.Open(mygo.OpenDialogOptions{Parent: a.window, Title: a.t("从文件导入音频或视频")})
	if err != nil {
		a.showError("media", err)
		return
	}
	if len(files) == 0 {
		return
	}
	a.importMedia(files[0])
}
func (a *nativeApp) importMedia(file string) {
	settings := a.settings.clone()
	var item localMedia
	a.launch("media", func() error {
		var err error
		item, err = a.service.importNativeMedia(file, settings.Media)
		if err != nil {
			return err
		}
		settings.Media = append(settings.Media, item)
		if err = saveNativeSettings(a.service.directory, settings); err != nil {
			_ = a.service.deleteMedia(item.ID)
		}
		return err
	}, func() { a.settings = settings })
}
func (a *nativeApp) removeMedia(id string) {
	if !a.ask("删除这个声音？", "删除声音") {
		return
	}
	settings, p := a.settings.clone(), a.preferences
	settings.Media = slices.DeleteFunc(settings.Media, func(item localMedia) bool { return item.ID == id })
	if p.SleepSound == "custom:"+id {
		p.SleepSound = "rain"
	}
	if p.AlarmSound == "custom:"+id {
		p.AlarmSound = "dawn"
	}
	a.launch("storage", func() error {
		if _, err := a.service.command(CommandInput{Action: "volume", Preferences: &p}); err != nil {
			return err
		}
		if err := a.service.deleteMedia(id); err != nil {
			return err
		}
		return saveNativeSettings(a.service.directory, settings)
	}, func() { a.settings, a.preferences = settings, p })
}

func (a *nativeApp) render(c *ui.Context) {
	theme := *c.Theme()
	if a.settings.Appearance == "light" {
		theme = *ui.LightTheme()
	}
	if a.settings.Appearance == "dark" {
		theme = *ui.DarkTheme()
	}
	accent := map[string]string{"pine": "#246b60", "ocean": "#27668b", "dusk": "#765b91", "rose": "#9b556a"}[a.settings.Theme]
	if theme.Dark {
		accent = map[string]string{"pine": "#70c5ad", "ocean": "#7cbee6", "dusk": "#bea4df", "rose": "#e9a1b5"}[a.settings.Theme]
		theme.AccentText = ui.Hex("#10241e")
	}
	theme.Accent, theme.Focus = ui.Hex(accent), ui.Hex(accent)
	theme.AccentHover, theme.AccentPressed = theme.Accent.Alpha(0.85), theme.Accent.Alpha(0.7)
	theme.Radius, theme.Spacing = 10, 5
	if runtime.GOOS == "windows" {
		switch a.preferences.Language {
		case "zh-Hans":
			theme.Font = "Microsoft YaHei UI"
		case "zh-Hant":
			theme.Font = "Microsoft JhengHei UI"
		case "ja":
			theme.Font = "Yu Gothic UI"
		case "ko":
			theme.Font = "Malgun Gothic"
		}
	}
	if !theme.Dark {
		theme.Background = ui.Hex("#f5f5f0")
		theme.Surface = ui.Hex("#ffffff")
	}
	if a.settings.LargeText {
		theme.FontSize = 18
	}
	c.SetTheme(&theme)
	if a.dirty {
		if !a.busy && !time.Now().Before(a.dirtyAt) {
			a.save()
		} else {
			c.After(650 * time.Millisecond)
		}
	}
	if a.snapshot.Session != nil {
		c.After(time.Second)
	}
	ui.Column(c).Fill().Padding(24).Gap(18).Children(func() {
		ui.Row(c).Gap(12).Children(func() {
			ui.Text(c, a.t("耳憩 HushNest")).FontSize(25).Bold().Grow(1)
			ui.Text(c, a.t("片刻安静，自在醒来。")).TextColor(theme.TextMuted).FontSize(13)
		})
		ui.Row(c).Gap(8).Children(func() {
			for _, page := range []soundChoice{{"rest", "休息"}, {"library", "我的声音"}, {"history", "足迹"}, {"settings", "设置"}} {
				button := ui.Button(c.Key(page.id), a.t(page.name)).Grow(1).Height(42)
				if a.page == page.id {
					button.Background(theme.Accent.Alpha(0.13)).TextColor(theme.Accent)
				}
				button.OnClick(func() { a.page = page.id; a.errorText = "" })
			}
		})
		if a.errorText != "" {
			ui.Row(c).Gap(12).Padding(12).Radius(10).Background(theme.Danger.Alpha(0.09)).Children(func() {
				ui.Text(c, a.errorText).Grow(1).TextColor(theme.Danger)
				ui.Button(c, "×").Label(a.t("知道了")).OnClick(func() { a.errorText = "" })
			})
		}
		ui.Scroll(c.Key(a.page)).Grow(1).Gap(18).Padding(0, 2, 24, 2).Children(func() {
			ui.Column(c).FillWidth().MaxWidth(940).Margin(0, ui.Auto).Gap(18).Children(func() {
				switch a.page {
				case "rest":
					a.restPage(c)
				case "library":
					a.libraryPage(c)
				case "history":
					a.historyPage(c)
				case "settings":
					a.settingsPage(c)
				}
			})
		})
	})
	if done := a.afterRender; done != nil {
		a.afterRender = nil
		done()
	}
}
func (a *nativeApp) card(c *ui.Context, title string, content func()) {
	t := c.Theme()
	ui.Column(c).Padding(22).Gap(15).Radius(18).Background(t.Surface).Border(1, t.Border).Children(func() {
		if title != "" {
			ui.Text(c, a.t(title)).FontSize(18).Bold()
		}
		content()
	})
}
func (a *nativeApp) restPage(c *ui.Context) {
	t, session := c.Theme(), a.snapshot.Session
	active := session != nil
	remaining := float64(a.preferences.Duration)
	heading := "给自己，片刻安静。"
	if session != nil {
		remaining = session.remaining(time.Now().UnixMilli())
		heading = map[SessionPhase]string{PhaseResting: "安心休息，慢慢来。", PhasePaused: "休息已暂停", PhaseBlocked: "提醒已中断", PhaseRinging: "休息好啦，慢慢醒来"}[session.Phase]
	}
	a.card(c, "", func() {
		ui.Column(c).AlignItems(ui.Center).Gap(12).Padding(16, 0).Children(func() {
			ui.Text(c, a.t(heading)).FontSize(22).TextColor(t.Accent)
			text := clockText(remaining)
			if session != nil && session.Phase == PhaseRinging {
				text = a.t("时间到了")
			}
			ui.Text(c, text).FontSize(68).Bold()
			if session != nil {
				ui.Progress(c, min(1, remaining/float64(session.Duration))).Width(300).Height(5)
				ui.Text(c, a.t("唤醒时间")+"  "+time.UnixMilli(session.Deadline).Local().Format("15:04:05")).TextColor(t.TextMuted)
				if session.Phase == PhaseBlocked {
					key := "当前没有可用耳机，声音已停止。连接后请手动继续。"
					if session.Reason != nil && *session.Reason == "restored" {
						key = "应用曾被关闭或系统结束，提醒未在后台继续。请确认耳机后手动恢复。"
					}
					if session.Reason != nil && *session.Reason == "audioError" {
						key = "声音已停止，请检查耳机或重新选择声音。"
					}
					ui.Text(c, a.t(key)).TextColor(t.Warning)
				}
			}
			ui.Row(c).Gap(10).Wrap().Justify(ui.Center).Children(func() {
				if !active {
					ui.PrimaryButton(c, a.t("开始休息")).Height(48).Width(210).Disabled(a.busy).OnClick(a.begin)
				} else {
					switch session.Phase {
					case PhaseResting:
						ui.Button(c, a.t("暂停一下")).Disabled(a.busy).OnClick(func() { a.command("pause", 0, "") })
					case PhasePaused, PhaseBlocked:
						ui.PrimaryButton(c, a.t("确认耳机，继续休息")).Disabled(a.busy).OnClick(func() { a.command("resume", 0, "") })
					case PhaseRinging:
						ui.Button(c, a.t("再休息 %@ 分钟", a.preferences.SnoozeMinutes)).Disabled(a.busy).OnClick(func() { a.command("snooze", 0, "") })
					}
					ui.Button(c, a.t("结束休息")).Disabled(a.busy).OnClick(func() {
						if a.ask("结束这次休息？", "结束休息") {
							a.command("stop", 0, "")
						}
					})
				}
			})
			if a.busy {
				ui.Text(c, a.t("正在准备…")).TextColor(t.TextMuted)
			}
		})
	})
	a.card(c, "选择耳机输出", func() { a.routeControls(c) })
	if !active {
		a.durationControls(c)
	}
	a.card(c, "声音与唤醒", func() {
		a.soundSelector(c, "助眠音", &a.preferences.SleepSound, sleepChoices, active)
		a.soundSelector(c, "唤醒铃声", &a.preferences.AlarmSound, alarmChoices, active)
		a.volume(c, "助眠音量", &a.preferences.SleepVolume, 0.01, 0.6)
		a.volume(c, "唤醒铃声音量", &a.preferences.AlarmVolume, 0.05, 1)
	})
	ui.Text(c, a.t("休息期间关闭窗口会收至托盘，退出应用会停止提醒。")).TextColor(t.TextMuted).FontSize(13)
}
func (a *nativeApp) routeControls(c *ui.Context) {
	route := a.snapshot.Route
	label := a.t("尚未连接耳机")
	if route.Connected {
		label = a.t("耳机已就绪")
	}
	ui.Row(c).Gap(12).Wrap().Children(func() {
		ui.Column(c).Gap(5).Grow(1).Children(func() {
			ui.Text(c, label).Bold()
			if route.Name != "" {
				ui.Text(c, route.Name).TextColor(c.Theme().TextMuted)
			}
		})
		ui.Button(c, a.t("检查耳机")).Disabled(a.busy).OnClick(a.checkRoute)
	})
	if route.RequiresConfirmation && !route.Connected {
		ui.Text(c, a.t("请确认当前输出是耳机，而不是音箱或车载设备。"))
		ui.Button(c, a.t("确认这是耳机")).Disabled(a.busy).OnClick(func() {
			if a.ask("请确认当前输出是耳机，而不是音箱或车载设备。", "确认这是耳机") {
				a.command("confirmRoute", 0, "")
			}
		})
	}
}
func (a *nativeApp) durationControls(c *ui.Context) {
	a.card(c, "按你的节奏", func() {
		ui.Row(c).Gap(8).Children(func() {
			for _, mode := range []soundChoice{{"countdown", "倒计时"}, {"clock", "指定时间"}} {
				button := ui.Button(c.Key(mode.id), a.t(mode.name)).Disabled(a.busy)
				if a.mode == mode.id {
					button.Background(c.Theme().Accent.Alpha(.13)).TextColor(c.Theme().Accent)
				}
				button.OnClick(func() { a.mode = mode.id })
			}
		})
		if a.mode == "clock" {
			ui.TimeInput(c, &a.target).Label(a.t("唤醒时间")).Width(220).Disabled(a.busy)
		} else {
			ui.Row(c).Gap(10).Wrap().Children(func() {
				if ui.NumberInput(c, &a.minutes, 0, 720, 1).Label(a.t("分钟")).Disabled(a.busy).Changed() {
					a.setDuration(int(a.minutes)*60 + int(a.seconds))
					a.changed()
				}
				ui.Text(c, a.t("分钟"))
				if ui.NumberInput(c, &a.seconds, 0, 59, 1).Label(a.t("秒")).Disabled(a.busy).Changed() {
					a.setDuration(int(a.minutes)*60 + int(a.seconds))
					a.changed()
				}
				ui.Text(c, a.t("秒"))
			})
			ui.Row(c).Gap(8).Wrap().Children(func() {
				for _, duration := range a.settings.Presets {
					ui.Button(c.Key(duration), clockText(float64(duration))).Disabled(a.busy).OnClick(func() { a.setDuration(duration); a.changed() })
				}
				ui.Button(c, a.t("添加常用时长")).Disabled(a.busy || slices.Contains(a.settings.Presets, a.preferences.Duration)).OnClick(func() { a.settings.Presets = append(a.settings.Presets, a.preferences.Duration); a.changed() })
			})
		}
	})
}
func (a *nativeApp) soundSelector(c *ui.Context, label string, value *string, choices []soundChoice, active bool) {
	choices = slices.Clone(choices)
	for _, item := range a.settings.Media {
		choices = append(choices, soundChoice{"custom:" + item.ID, item.Name})
	}
	ui.Row(c).Gap(12).Children(func() {
		ui.Text(c, a.t(label)).Width(110)
		if a.selectChoice(c, label, value, choices, active || a.busy).Changed() {
			a.changed()
		}
		ui.Button(c.Key(label+"-preview"), a.t("试听")).Label(a.t("试听") + " " + a.t(label)).Disabled(active || a.busy || *value == "none").OnClick(func() { a.command("preview", 0, *value) })
	})
}
func (a *nativeApp) selectChoice(c *ui.Context, label string, value *string, choices []soundChoice, disabled bool) ui.Element {
	names := make([]string, len(choices))
	selected := ""
	seen := map[string]bool{}
	for i, choice := range choices {
		names[i] = a.t(choice.name)
		if seen[names[i]] {
			names[i] += " · " + choice.id[max(0, len(choice.id)-8):]
		}
		seen[names[i]] = true
		if choice.id == *value {
			selected = names[i]
		}
	}
	if selected == "" {
		selected = a.t("自定义声音")
	}
	element := ui.Select(c.Key(label), &selected, names).Label(a.t(label)).Grow(1).Disabled(disabled)
	if element.Changed() {
		for i, name := range names {
			if name == selected {
				*value = choices[i].id
				break
			}
		}
	}
	return element
}
func (a *nativeApp) volume(c *ui.Context, label string, value *float64, low, high float64) {
	ui.Row(c).Gap(12).Children(func() {
		ui.Text(c, a.t(label)).Width(110)
		if ui.Slider(c, value, low, high).Label(a.t(label)).Grow(1).Disabled(a.busy).Changed() {
			a.changed()
		}
		ui.Text(c, fmt.Sprintf("%d%%", int(math.Round(*value*100)))).Width(50)
	})
}
func (a *nativeApp) libraryPage(c *ui.Context) {
	a.card(c, "我的声音", func() {
		ui.Text(c, a.t("导入喜欢的音乐、录音或视频声音。"))
		ui.Text(c, a.t("仅提取音轨并保存到本机，不上传。支持常见音频和视频；不支持受保护媒体。每个文件最多 200 MB、2 小时，最多 20 个。")).TextColor(c.Theme().TextMuted)
		ui.PrimaryButton(c, a.t("从文件导入音频或视频")).Disabled(a.busy || a.snapshot.Session != nil || len(a.settings.Media) >= 20).OnClick(a.chooseMedia)
		for _, item := range a.settings.Media {
			ui.Column(c.Key(item.ID)).Gap(10).Padding(14).Radius(10).Border(1, c.Theme().Border).Children(func() {
				ui.Text(c, item.Name).Bold()
				ui.Text(c, clockText(item.Seconds)+" · "+strconv.FormatFloat(float64(item.Size)/1024/1024, 'f', 1, 64)+" MB").TextColor(c.Theme().TextMuted)
				ui.Row(c).Gap(8).Wrap().Children(func() {
					disabled := a.busy || a.snapshot.Session != nil
					ui.Button(c, a.t("助眠音")).Disabled(disabled).OnClick(func() { a.preferences.SleepSound = "custom:" + item.ID; a.changed() })
					ui.Button(c, a.t("唤醒铃声")).Disabled(disabled).OnClick(func() { a.preferences.AlarmSound = "custom:" + item.ID; a.changed() })
					ui.Button(c, a.t("试听")).Disabled(disabled).OnClick(func() { a.command("preview", 0, "custom:"+item.ID) })
					ui.Button(c, a.t("删除声音")).Disabled(disabled).OnClick(func() { a.removeMedia(item.ID) })
				})
			})
		}
	})
}
func (a *nativeApp) historyPage(c *ui.Context) {
	completed, total := 0, 0
	for _, record := range a.snapshot.Records {
		if record.Completed {
			completed++
		}
		total += record.Seconds
	}
	a.card(c, "休息足迹", func() {
		ui.Row(c).Gap(30).Wrap().Children(func() {
			ui.Text(c, fmt.Sprint(completed)+"  "+a.t("完成休息")).FontSize(22).Bold()
			ui.Text(c, fmt.Sprint(total/60)+"  "+a.t("累计分钟")).FontSize(22).Bold()
		})
		ui.Text(c, a.t("文件和记录仅保存在这台设备上。")).TextColor(c.Theme().TextMuted)
		if len(a.snapshot.Records) == 0 {
			ui.Text(c, a.t("结束一次休息后，足迹会出现在这里。"))
		}
		for _, record := range a.snapshot.Records {
			ui.Row(c.Key(record.ID)).Gap(15).Padding(12, 0).Children(func() {
				label := "提前结束"
				if record.Completed {
					label = "完成一段休息"
				}
				ui.Text(c, time.UnixMilli(record.StartedAt).Local().Format("2006-01-02 15:04")).Grow(1)
				ui.Text(c, a.t(label)).TextColor(c.Theme().TextMuted)
				ui.Text(c, clockText(float64(record.Seconds)))
			})
		}
		ui.Button(c, a.t("清空本机记录")).Disabled(a.busy || len(a.snapshot.Records) == 0 || a.snapshot.Session != nil).OnClick(func() {
			if a.ask("清空所有休息记录？", "清空记录") {
				a.command("clearRecords", 0, "")
			}
		})
	})
}
func (a *nativeApp) settingsPage(c *ui.Context) {
	a.card(c, "心情与色彩", func() {
		if a.selectChoice(c, "主题", &a.settings.Theme, []soundChoice{{"pine", "松林"}, {"ocean", "海湾"}, {"dusk", "暮紫"}, {"rose", "玫瑰"}}, a.busy).Changed() {
			a.changed()
		}
		if a.selectChoice(c, "外观", &a.settings.Appearance, []soundChoice{{"system", "跟随系统"}, {"light", "浅色"}, {"dark", "深色"}}, a.busy).Changed() {
			a.changed()
		}
		if ui.Checkbox(c, &a.settings.LargeText, a.t("大字体")).Disabled(a.busy).Changed() {
			a.changed()
		}
	})
	a.card(c, "语言", func() {
		language := a.preferences.Language
		choices := make([]soundChoice, len(languageIDs))
		for i, id := range languageIDs {
			choices[i] = soundChoice{id, languageNames[i]}
		}
		if a.selectChoice(c, "语言", &language, choices, a.busy).Changed() {
			a.preferences.Language = language
			if a.window != nil {
				mygo.App.SetLocale(language)
			}
			a.changed()
		}
	})
	a.card(c, "唤醒铃声", func() {
		if ui.Checkbox(c, &a.preferences.RepeatAlarm, a.t("持续响铃直到手动结束")).Disabled(a.busy || a.snapshot.Session != nil).Changed() {
			a.changed()
		}
		ui.Text(c, a.t("关闭时最多响铃 3 分钟。")).TextColor(c.Theme().TextMuted)
		snooze := float64(a.preferences.SnoozeMinutes)
		ui.Row(c).Gap(12).Children(func() {
			ui.Text(c, a.t("稍后提醒"))
			if ui.NumberInput(c, &snooze, 1, 30, 1).Label(a.t("稍后提醒")).Disabled(a.busy || a.snapshot.Session != nil).Changed() {
				a.preferences.SnoozeMinutes = int(snooze)
				a.changed()
			}
			ui.Text(c, a.t("分钟"))
		})
	})
	a.card(c, "自定义时长和预设", func() {
		for _, seconds := range a.settings.Presets {
			ui.Row(c.Key(seconds)).Gap(12).Children(func() {
				ui.Text(c, clockText(float64(seconds))).Grow(1)
				ui.Button(c, a.t("移除预设")).Disabled(a.busy).OnClick(func() {
					a.settings.Presets = slices.DeleteFunc(a.settings.Presets, func(n int) bool { return n == seconds })
					a.changed()
				})
			})
		}
	})
	ui.PrimaryButton(c, a.t("保存配置")).Disabled(a.busy).OnClick(a.save)
	a.card(c, "自由，也透明", func() {
		ui.Text(c, a.t("文件和记录仅保存在这台设备上。"))
		ui.Text(c, a.t("免费 · 无广告 · 无订阅 · 数据仅在本机"))
		ui.Text(c, a.t("休息期间关闭窗口会收至托盘，退出应用会停止提醒。"))
		ui.Text(c, a.t("版本")+" 0.2.0").TextColor(c.Theme().TextMuted)
		ui.Button(c, a.t("查看开源代码")).OnClick(func() { go func() { _ = mygo.Shell.OpenExternal("https://github.com/ZanwingMak/HushNest") }() })
	})
}
