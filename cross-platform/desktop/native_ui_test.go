package main

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

func nativeFixture(t *testing.T) (*nativeApp, *silentAudio) {
	t.Helper()
	s, audio := fixture(t)
	s.state.Preferences.Language = "zh-Hans"
	s.route = audio.route
	a := &nativeApp{service: s, preferences: s.state.Preferences, settings: defaultNativeSettings(), snapshot: s.snapshot(),
		dictionaries: map[string]map[string]string{}, page: "rest", mode: "countdown", target: time.Now().Add(30 * time.Minute)}
	a.setDuration(a.preferences.Duration)
	return a, audio
}
func clickNative(t *testing.T, tt *ui.Tester, label string) {
	t.Helper()
	if err := tt.Click(label); err != nil {
		t.Fatal(err)
	}
}

func TestNativeTimerControlsUseBackgroundSession(t *testing.T) {
	a, audio := nativeFixture(t)
	tt := ui.NewTester(a.render, 1040, 850)
	clickNative(t, tt, "开始休息")
	if a.snapshot.Session == nil || a.snapshot.Session.Phase != PhaseResting || len(audio.plays) != 1 {
		t.Fatal("start did not reach the native service")
	}
	clickNative(t, tt, "暂停一下")
	if a.snapshot.Session.Phase != PhasePaused {
		t.Fatal("not paused")
	}
	clickNative(t, tt, "确认耳机，继续休息")
	if a.snapshot.Session.Phase != PhaseResting {
		t.Fatal("not resumed")
	}
	clickNative(t, tt, "结束休息")
	if a.snapshot.Session != nil || len(a.snapshot.Records) != 1 {
		t.Fatal("not stopped/recorded")
	}
}
func TestNativeStartPreservesHeadphoneGate(t *testing.T) {
	a, audio := nativeFixture(t)
	audio.route.Connected = false
	tt := ui.NewTester(a.render, 1040, 850)
	clickNative(t, tt, "开始休息")
	if a.snapshot.Session != nil || len(audio.plays) != 0 || a.errorText == "" {
		t.Fatal("disconnected start was not rejected")
	}
}
func TestNativeAmbiguousRouteRequiresConfirmation(t *testing.T) {
	a, audio := nativeFixture(t)
	audio.route.Connected = false
	audio.route.RequiresConfirmation = true
	a.snapshot.Route = audio.route
	tt := ui.NewTester(a.render, 1040, 850)
	clickNative(t, tt, "确认这是耳机")
	if !a.snapshot.Route.Connected {
		t.Fatal("route was not confirmed")
	}
}
func TestNativeSnoozeAfterBackgroundAlarm(t *testing.T) {
	a, _ := nativeFixture(t)
	a.setDuration(1)
	tt := ui.NewTester(a.render, 1040, 850)
	clickNative(t, tt, "开始休息")
	s := a.service
	deadline := s.state.Session.Deadline
	if err := s.tickLocked(deadline); err != nil {
		t.Fatal(err)
	}
	a.snapshot = s.snapshot()
	tt.Frame()
	if !tt.HasText("时间到了") {
		t.Fatal("alarm state is not visible")
	}
	clickNative(t, tt, "再休息 5 分钟")
	if a.snapshot.Session.SnoozeCount != 1 || a.snapshot.Session.Phase != PhaseResting {
		t.Fatal("not snoozed")
	}
}
func TestNativePresetsAndSettingsPersist(t *testing.T) {
	a, _ := nativeFixture(t)
	tt := ui.NewTester(a.render, 1040, 850)
	clickNative(t, tt, "15:00")
	if a.preferences.Duration != 900 {
		t.Fatal("preset not applied")
	}
	clickNative(t, tt, "设置")
	clickNative(t, tt, "大字体")
	tt.Scroll(800, 700, 0, 700)
	clickNative(t, tt, "保存配置")
	saved, err := loadNativeSettings(a.service.directory)
	if err != nil || !saved.LargeText {
		t.Fatalf("not persisted: %+v %v", saved, err)
	}
	s, err := newRestService(a.service.directory, &silentAudio{})
	if err != nil || s.state.Preferences.Duration != 900 {
		t.Fatalf("duration not persisted: %v", err)
	}
}
func TestNativeViewsAtDesktopAndMinimumSize(t *testing.T) {
	for _, size := range [][2]int{{1040, 850}, {600, 560}} {
		for _, page := range []string{"rest", "library", "history", "settings"} {
			t.Run(page+clockText(float64(size[0])), func(t *testing.T) {
				a, _ := nativeFixture(t)
				a.page = page
				tt := ui.NewTester(a.render, size[0], size[1])
				if len(tt.Texts()) < 8 {
					t.Fatalf("empty native page: %v", tt.Texts())
				}
				tt.SetDark(true)
				tt.Frame()
			})
		}
	}
}
func TestNativeClockLimitAndNextDay(t *testing.T) {
	zone := time.FixedZone("CST", 8*60*60)
	now := time.Date(2026, 10, 31, 23, 50, 0, 0, zone)
	next := time.Date(2026, 10, 31, 0, 10, 0, 0, zone)
	if n, err := nextNativeDuration(now, next); err != nil || n != 1200 {
		t.Fatalf("next day: %d %v", n, err)
	}
	if _, err := nextNativeDuration(now, now.Add(13*time.Hour)); err == nil {
		t.Fatal("accepted over 12 hours")
	}
}
func TestNativeImportDeletionAndPreferenceFallback(t *testing.T) {
	a, _ := nativeFixture(t)
	file := filepath.Join(t.TempDir(), "recording.wav")
	if err := os.WriteFile(file, []byte("silent decoder fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	a.importMedia(file)
	if a.errorText != "" || len(a.settings.Media) != 1 {
		t.Fatalf("import: %s", a.errorText)
	}
	item := a.settings.Media[0]
	if !a.service.hasMedia(item.ID, item.Size) {
		t.Fatal("private media file missing")
	}
	a.preferences.SleepSound = "custom:" + item.ID
	a.preferences.AlarmSound = "custom:" + item.ID
	a.removeMedia(item.ID)
	if len(a.settings.Media) != 0 || a.service.hasMedia(item.ID, item.Size) || a.preferences.SleepSound != "rain" || a.preferences.AlarmSound != "dawn" {
		t.Fatal("delete/fallback failed")
	}
	saved, err := loadNativeSettings(a.service.directory)
	if err != nil || len(saved.Media) != 0 {
		t.Fatal("deleted metadata was not persisted")
	}
}
func TestNativeImportLimitsAndRollback(t *testing.T) {
	a, audio := nativeFixture(t)
	file := filepath.Join(t.TempDir(), "empty.wav")
	_ = os.WriteFile(file, nil, 0600)
	if _, err := a.service.importNativeMedia(file, nil); err == nil {
		t.Fatal("empty input accepted")
	}
	_ = os.WriteFile(file, []byte("unsupported"), 0600)
	audio.fail = true
	if _, err := a.service.importNativeMedia(file, nil); err == nil {
		t.Fatal("decoder failure ignored")
	}
	entries, _ := os.ReadDir(filepath.Join(a.service.directory, "media"))
	if len(entries) != 0 {
		t.Fatalf("failed import leaked files: %v", entries)
	}
	audio.fail = false
	if _, err := a.service.importNativeMedia(file, make([]localMedia, 20)); err == nil {
		t.Fatal("quota ignored")
	}
}
func TestNativeClearHistoryButton(t *testing.T) {
	a, _ := nativeFixture(t)
	a.service.state.Records = []RestRecord{{ID: newID(), Seconds: 900, StartedAt: 1, EndedAt: 900001, Completed: true, Sound: "rain"}}
	a.snapshot = a.service.snapshot()
	a.page = "history"
	tt := ui.NewTester(a.render, 1040, 850)
	clickNative(t, tt, "清空本机记录")
	if len(a.snapshot.Records) != 0 {
		t.Fatal("records not cleared")
	}
}
func TestNativeTranslationSupplementsCoverAllLanguages(t *testing.T) {
	for _, language := range languageIDs {
		for key, values := range desktopCopy {
			if text := translateNative(language, nil, key); text == "" || text != values[slices.Index(languageIDs, language)] {
				t.Fatalf("missing %s: %s", language, key)
			}
		}
	}
	if text := translateNative("en", map[string]map[string]string{"en": {"再休息 %@ 分钟": "Rest %@ more minutes"}}, "再休息 %@ 分钟", 5); text != "Rest 5 more minutes" {
		t.Fatal(text)
	}
}
