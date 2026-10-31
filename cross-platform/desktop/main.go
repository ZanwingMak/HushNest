package main

import (
	"log"
	"os"
	"path/filepath"
	"slices"
	"sync/atomic"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
)

// Desktop owns the native window and the background service. It has no page,
// JavaScript bridge, embedded frontend or IPC surface.
type Desktop struct {
	service  *restService
	window   *mygo.Window
	view     *nativeApp
	awake    atomic.Bool
	release  atomic.Pointer[func()]
	quitting atomic.Bool
}

func (d *Desktop) reconcilePower() {
	want := d.service != nil && d.service.active.Load() && !d.quitting.Load()
	if want && d.awake.CompareAndSwap(false, true) {
		release := mygo.Power.KeepAwake("HushNest rest timer", false)
		d.release.Store(&release)
		if !d.awake.Load() || d.quitting.Load() {
			if old := d.release.Swap(nil); old != nil {
				(*old)()
			}
		}
	} else if !want && d.awake.CompareAndSwap(true, false) {
		if release := d.release.Swap(nil); release != nil {
			(*release)()
		}
	}
}
func (d *Desktop) suspend() {
	d.service.mu.Lock()
	d.service.blockLocked(time.Now().UnixMilli(), "restored")
	d.service.mu.Unlock()
	d.service.notify()
}
func (d *Desktop) show() {
	if d.window != nil {
		d.window.Show()
		d.window.Focus()
	}
}
func main() {
	mygo.App.SetName("HushNest")
	mygo.App.SetLanguages("zh-Hans", "zh-Hant", "en", "ja", "ko", "es")
	if directory := os.Getenv("HUSHNEST_DATA_DIR"); directory != "" {
		_ = os.MkdirAll(directory, 0700)
		mygo.App.SetPath(mygo.PathUserData, directory)
	}
	d := &Desktop{}
	if !mygo.App.RequestSingleInstanceLock() {
		return
	}
	mygo.App.OnSecondInstance(func([]string, string) { d.show() })
	mygo.App.OnActivate(func(bool) { d.show() })
	mygo.App.WhenReady(func() {
		resources, err := mygo.App.Path(mygo.PathResources)
		if err != nil {
			log.Fatal(err)
		}
		directory, err := mygo.App.Path(mygo.PathUserData)
		if err != nil {
			log.Fatal(err)
		}
		helper, err := openHelper(resources, filepath.Join(directory, "media"))
		if err != nil {
			log.Fatal(err)
		}
		d.service, err = newRestService(directory, helper)
		if err != nil {
			helper.close()
			log.Fatal(err)
		}
		d.view, err = newNativeApp(d.service, resources)
		if err != nil {
			helper.close()
			log.Fatal(err)
		}
		if _, err := os.Stat(filepath.Join(directory, "rest-state.json")); os.IsNotExist(err) {
			if language := mygo.App.Locale(); slices.Contains(languageIDs, language) {
				d.view.preferences.Language = language
				d.service.state.Preferences.Language = language
			}
		}
		mygo.App.SetLocale(d.view.preferences.Language)
		d.window = mygo.NewWindow(mygo.WindowOptions{
			Title: "耳憩 HushNest", Content: ui.View(d.view.render),
			Width: 1040, Height: 850, MinWidth: 600, MinHeight: 560,
			BackgroundColor: "#f5f5f0", StateKey: "main",
			Hidden: os.Getenv("HUSHNEST_SMOKE") != "",
		})
		d.view.window = d.window
		d.service.onChange = d.reconcilePower
		d.window.OnClose(func(event *mygo.CloseEvent) {
			if d.service.active.Load() && !d.quitting.Load() {
				event.PreventDefault()
				d.window.Hide()
			}
		})
		icon, _ := os.ReadFile(filepath.Join(resources, "tray.png"))
		tray, err := mygo.NewTray(mygo.TrayOptions{ID: "com.hushnest.desktop", Icon: icon, ToolTip: "HushNest", Menu: mygo.NewMenu([]*mygo.MenuItem{
			{Label: "打开 / Open HushNest", Click: func(*mygo.MenuItem, *mygo.Window) { d.show() }},
			{Label: "退出 / Quit", Click: func(*mygo.MenuItem, *mygo.Window) { mygo.App.Quit() }},
		})})
		if err != nil {
			log.Printf("tray: %v", err)
		} else {
			tray.OnClick(d.show)
		}
		mygo.Power.OnSuspend(func() { go d.suspend() })
		d.service.run(helper.lost)
		d.view.watch()
		if report := os.Getenv("HUSHNEST_SMOKE"); report != "" {
			go desktopSmoke(d, resources, report)
		}
	})
	mygo.App.OnBeforeQuit(func(event *mygo.QuitEvent) {
		if d.service != nil && d.service.active.Load() && !d.quitting.Load() && os.Getenv("HUSHNEST_SMOKE") == "" {
			answer, err := mygo.Dialog.Message(mygo.MessageOptions{Parent: d.window, Message: "退出会停止当前提醒。Quit and stop the current rest?", Buttons: []string{"继续休息 / Keep resting", "退出 / Quit"}, DefaultButton: 0, CancelButton: 0})
			if err != nil || answer.Button != 1 {
				event.PreventDefault()
				return
			}
		}
		d.quitting.Store(true)
		d.reconcilePower()
	})
	if err := mygo.App.Run(); err != nil {
		log.Fatal(err)
	}
	if d.service != nil {
		d.service.close()
	}
}
