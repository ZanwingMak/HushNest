package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"time"

	"github.com/egoist/mygo"
)

var DesktopSuspend = mygo.NewEvent[bool]("desktop:suspend")

// Desktop exposes only the operations the HushNest frontend needs.
type Desktop struct {
	service  *restService
	window   *mygo.Window
	awake    atomic.Bool
	release  atomic.Pointer[func()]
	quitting atomic.Bool
}

func (d *Desktop) authorize(ctx context.Context) error {
	if d.service == nil || d.window == nil {
		return errors.New("desktop-not-ready")
	}
	if mygo.CallerWindow(ctx) != d.window {
		return errors.New("untrusted-sender")
	}
	return nil
}
func (d *Desktop) Snapshot(ctx context.Context) (Snapshot, error) {
	if e := d.authorize(ctx); e != nil {
		return Snapshot{}, e
	}
	return d.service.snapshot(), nil
}
func (d *Desktop) Route(ctx context.Context) (Route, error) {
	if e := d.authorize(ctx); e != nil {
		return Route{}, e
	}
	d.service.mu.Lock()
	defer d.service.mu.Unlock()
	e := d.service.routeLocked()
	return d.service.route, e
}
func (d *Desktop) Command(ctx context.Context, input CommandInput) (Snapshot, error) {
	if e := d.authorize(ctx); e != nil {
		return Snapshot{}, e
	}
	return d.service.command(input)
}
func (d *Desktop) CacheMedia(ctx context.Context, input CacheInput) error {
	if e := d.authorize(ctx); e != nil {
		return e
	}
	return d.service.cacheMedia(input)
}
func (d *Desktop) HasMedia(ctx context.Context, id string, size int64) (bool, error) {
	if e := d.authorize(ctx); e != nil {
		return false, e
	}
	return d.service.hasMedia(id, size), nil
}
func (d *Desktop) DeleteMedia(ctx context.Context, id string) error {
	if e := d.authorize(ctx); e != nil {
		return e
	}
	return d.service.deleteMedia(id)
}
func (d *Desktop) KeepAwake(ctx context.Context, active bool) error {
	if e := d.authorize(ctx); e != nil {
		return e
	}
	d.reconcilePower()
	return nil
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
	_ = DesktopSuspend.Emit(d.window, true)
}
func (d *Desktop) show() {
	if d.window != nil {
		d.window.Show()
		d.window.Focus()
	}
}

func main() {
	mygo.App.SetName("HushNest")
	if directory := os.Getenv("HUSHNEST_DATA_DIR"); directory != "" {
		_ = os.MkdirAll(directory, 0700)
		mygo.App.SetPath(mygo.PathUserData, directory)
	}
	d := &Desktop{}
	mygo.Bind(d)
	if os.Getenv("MYGO_GENERATE") == "" && !mygo.App.RequestSingleInstanceLock() {
		return
	}
	mygo.App.OnSecondInstance(func([]string, string) { d.show() })
	mygo.App.OnActivate(func(bool) { d.show() })
	mygo.App.WhenReady(func() {
		resources, e := mygo.App.Path(mygo.PathResources)
		if e != nil {
			log.Fatal(e)
		}
		directory, e := mygo.App.Path(mygo.PathUserData)
		if e != nil {
			log.Fatal(e)
		}
		helper, e := openHelper(resources, filepath.Join(directory, "media"))
		if e != nil {
			log.Fatal(e)
		}
		d.service, e = newRestService(directory, helper)
		if e != nil {
			helper.close()
			log.Fatal(e)
		}
		d.service.onChange = d.reconcilePower
		d.window = mygo.NewWindow(mygo.WindowOptions{Title: "耳憩 HushNest", URL: "/", Width: 1280, Height: 900, MinWidth: 420, MinHeight: 650, BackgroundColor: "#f5f5f0", Hidden: os.Getenv("HUSHNEST_SMOKE") != "", StateKey: "main", Page: mygo.PageOptions{PreloadScript: "window.__hushnestNativeSession = true;"}})
		d.window.OnClose(func(event *mygo.CloseEvent) {
			if d.service.active.Load() && !d.quitting.Load() {
				event.PreventDefault()
				d.window.Hide()
			}
		})
		d.window.Page().OnWillNavigate(func(event *mygo.NavigateEvent) {
			u, e := url.Parse(event.URL)
			if e != nil || u.Scheme != "mygo" && u.Scheme != "http" && u.Scheme != "https" {
				event.PreventDefault()
				return
			}
			if u.Scheme != "mygo" && u.Hostname() != "localhost" && u.Hostname() != "127.0.0.1" {
				event.PreventDefault()
			}
		})
		d.window.Page().SetPermissionHandler(func(request mygo.PermissionRequest) bool { return false })
		icon, _ := os.ReadFile(filepath.Join(resources, "tray.png"))
		tray, e := mygo.NewTray(mygo.TrayOptions{ID: "com.hushnest.desktop", Icon: icon, ToolTip: "HushNest", Menu: mygo.NewMenu([]*mygo.MenuItem{{Label: "打开 / Open HushNest", Click: func(*mygo.MenuItem, *mygo.Window) { d.show() }}, {Label: "退出 / Quit", Click: func(*mygo.MenuItem, *mygo.Window) { mygo.App.Quit() }}})})
		if e != nil {
			log.Printf("tray: %v", e)
		} else {
			tray.OnClick(d.show)
		}
		mygo.Power.OnSuspend(func() { go d.suspend() })
		d.service.run(helper.lost)
		if report := os.Getenv("HUSHNEST_SMOKE"); report != "" {
			d.window.Page().OnDidFinishLoad(func() { go desktopSmoke(d, report) })
		}
	})
	mygo.App.OnBeforeQuit(func(event *mygo.QuitEvent) {
		if d.service != nil && d.service.active.Load() && !d.quitting.Load() && os.Getenv("HUSHNEST_SMOKE") == "" {
			answer, e := mygo.Dialog.Message(mygo.MessageOptions{Parent: d.window, Message: "退出会停止当前提醒。Quit and stop the current rest?", Buttons: []string{"继续休息 / Keep resting", "退出 / Quit"}, DefaultButton: 0, CancelButton: 0})
			if e != nil || answer.Button != 1 {
				event.PreventDefault()
				return
			}
		}
		d.quitting.Store(true)
		d.reconcilePower()
	})
	if e := mygo.App.Run(); e != nil {
		log.Fatal(e)
	}
	if d.service != nil {
		d.service.close()
	}
}

func desktopSmoke(d *Desktop, report string) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	code := `(async()=>{
      while (!window.hushnestDesktop || !document.querySelector('.timer-actions')) await new Promise(r=>setTimeout(r,20));
      const desktop=window.hushnestDesktop;
      const snapshot=await desktop.snapshot();
      let invalidSound=false,invalidPath=false;
      try{await desktop.command({action:'preview',sound:'../../invalid',volume:0});}catch{invalidSound=true;}
      try{await window.hushnestAudio.cacheMedia({id:'../invalid',name:'x',bytes:new ArrayBuffer(1)});}catch{invalidPath=true;}
      const recordings=await fetch('./audio/FieldRecordings.json').then(r=>r.json());
      const result={ok:invalidSound&&invalidPath,platform:window.mygo.platform,framework:'MyGo',recordings:recordings.recordings.length,route:snapshot.route,nodeExposed:typeof window.require!=='undefined',invalidSound,invalidPath,title:document.title};
      if(result.nodeExposed||result.recordings!==6)result.ok=false;
      return result;
    })()`
	value, e := d.window.Page().EvalContext(ctx, code)
	data := map[string]any{"ok": false, "error": fmt.Sprint(e), "platform": runtime.GOOS, "framework": "MyGo"}
	if e == nil {
		if result, ok := value.(map[string]any); ok {
			data = result
		}
	}
	bytes, _ := json.Marshal(data)
	_ = os.WriteFile(report, bytes, 0600)
	if !strings.Contains(string(bytes), `"ok":true`) {
		log.Printf("desktop smoke: %s", bytes)
	}
	mygo.App.Quit()
}
