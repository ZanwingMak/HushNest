package main

import (
	"encoding/json"
	"fmt"
	"github.com/egoist/mygo"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// Smoke checks the packaged native window and the real decoder silently.
// CapturePage also captures native Content; Page() must remain nil.
func desktopSmoke(d *Desktop, resources, report string) {
	result := map[string]any{"ok": false, "framework": "MyGo", "nativeUI": true, "webview": d.window.Page() != nil, "platform": runtime.GOOS}
	defer func() {
		if recovered := recover(); recovered != nil {
			result["error"] = fmt.Sprint(recovered)
		}
		data, _ := json.Marshal(result)
		_ = os.WriteFile(report, data, 0600)
		mygo.App.Quit()
	}()
	pages := []string{"rest", "library", "history", "settings"}
	d.window.ShowInactive()
	for _, page := range pages {
		frame := make(chan struct{})
		d.window.Update(func() { d.view.page = page; d.view.afterRender = func() { close(frame) } })
		<-frame
		png, err := d.window.CapturePage()
		if err != nil || len(png) < 1000 {
			result["error"] = fmt.Sprintf("native capture %s: %v (%d bytes)", page, err, len(png))
			return
		}
		if err = os.WriteFile(filepath.Join(filepath.Dir(report), "native-"+page+".png"), png, 0600); err != nil {
			result["error"] = err.Error()
			return
		}
	}
	result["renderedPages"] = len(pages)
	noWebAssets := true
	_ = filepath.WalkDir(resources, func(file string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		switch strings.ToLower(filepath.Ext(file)) {
		case ".html", ".js", ".css", ".asar":
			noWebAssets = false
		}
		return nil
	})
	result["noWebAssets"] = noWebAssets
	_, invalidPath := d.service.mediaPath("../../invalid", false)
	var metadata struct{ Seconds float64 }
	invalidSound := d.service.backend.request("inspect", map[string]any{"sound": "custom:../../invalid"}, &metadata)
	result["invalidPath"] = invalidPath != nil
	result["invalidSound"] = invalidSound != nil
	_, staleConfirmation := d.service.command(CommandInput{Action: "confirmRoute", RouteToken: "__invalid-output"})
	result["staleConfirmationRejected"] = staleConfirmation != nil
	route := d.service.snapshot().Route
	result["outputAvailable"] = route.Token != ""
	manualConfirmation := true
	if route.Token != "" && route.RequiresConfirmation {
		// A silent helper contract check: approve an endpoint without playing
		// any sound or starting a rest, then inspect its admission status.
		next, confirmError := d.service.command(CommandInput{Action: "confirmRoute", RouteToken: route.Token})
		manualConfirmation = confirmError == nil && next.Route.Connected && !next.Route.Verified && next.Route.Token == route.Token
	}
	result["manualConfirmation"] = manualConfirmation
	item, err := d.service.importNativeMedia(filepath.Join(resources, "audio", "dawn.wav"), nil)
	if err != nil {
		result["error"] = "native import: " + err.Error()
		return
	}
	result["nativeImport"] = item.Seconds > 0 && d.service.hasMedia(item.ID, item.Size)
	if err = d.service.deleteMedia(item.ID); err != nil {
		result["error"] = err.Error()
		return
	}
	result["deletedMedia"] = !d.service.hasMedia(item.ID, item.Size)
	result["languages"] = len(d.view.dictionaries)
	result["ok"] = d.window.Page() == nil && noWebAssets && invalidPath != nil && invalidSound != nil && staleConfirmation != nil && manualConfirmation && result["nativeImport"] == true && result["deletedMedia"] == true && len(d.view.dictionaries) == 6
}
