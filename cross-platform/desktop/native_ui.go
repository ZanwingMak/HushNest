package main

import (
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/egoist/mygo"
)

type soundChoice struct{ id, name string }

var sleepChoices = []soundChoice{{"none", "不播放助眠音"}, {"rain", "细雨"}, {"ocean", "潮汐"}, {"stream", "溪流"}, {"forest", "林间"}, {"fireplace", "炉火"}, {"night", "夏夜"}, {"brown", "棕噪音"}, {"pink", "粉红噪音"}}
var alarmChoices = []soundChoice{{"dawn", "晨光"}, {"bell", "风铃"}, {"orbit", "星轨"}, {"piano", "柔钢琴"}, {"marimba", "木琴"}, {"harp", "竖琴"}, {"bamboo", "竹语"}, {"aurora", "极光"}, {"classic", "经典滴滴"}, {"twinbell", "机械双铃"}, {"digital", "数字闹钟"}, {"pulse", "急促脉冲"}, {"beacon", "交替信号"}, {"reveille", "起床号角"}}

// All fields of nativeApp are owned by the UI thread. Workers publish results
// through Window.Update; only restService's own locked state crosses threads.
type nativeApp struct {
	service                  *restService
	window                   *mygo.Window
	preferences              Preferences
	settings                 nativeSettings
	dictionaries             map[string]map[string]string
	snapshot                 Snapshot
	page                     string
	mode                     string
	target                   time.Time
	minutes, seconds         float64
	minuteDraft, secondDraft string
	busy                     bool
	errorText                string
	dirty                    bool
	dirtyAt                  time.Time
	afterRender              func()
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
	a.minuteDraft, a.secondDraft = strconv.Itoa(seconds/60), fmt.Sprintf("%02d", seconds%60)
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
	if a.mode == "countdown" {
		minutes, minuteError := strconv.Atoi(a.minuteDraft)
		seconds, secondError := strconv.Atoi(a.secondDraft)
		if minuteError != nil || secondError != nil || minutes < 0 || minutes > 720 || seconds < 0 || seconds > 59 || minutes*60+seconds < 1 || minutes*60+seconds > 43200 {
			a.showError("command", errors.New("invalid-time"))
			return
		}
		duration = minutes*60 + seconds
		a.setDuration(duration)
	}
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
