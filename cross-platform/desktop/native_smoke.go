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
	previews := []map[string]any{}
	for _, sound := range builtinAlarms {
		var probe struct {
			Samples int     `json:"samples"`
			RMS     float64 `json:"rms"`
			Peak    float64 `json:"peak"`
		}
		if err := d.service.backend.request("inspect", map[string]any{"sound": sound, "startSeconds": alarmPreviewStart, "sampleSeconds": previewSeconds}, &probe); err != nil {
			result["error"] = "alarm preview " + sound + ": " + err.Error()
			return
		}
		if probe.Samples < 160000 || probe.RMS < .02 || probe.Peak < .05 || probe.Peak > 1 {
			result["error"] = fmt.Sprintf("inaudible alarm preview %s: %+v", sound, probe)
			return
		}
		previews = append(previews, map[string]any{"sound": sound, "rms": probe.RMS, "peak": probe.Peak})
	}
	result["alarmPreviews"] = previews
	// Decode both ends of every long sleep file with the actual system codec.
	// The PCM asset tests separately check the joined boundary for clicks,
	// level jumps and repeated short segments. No output device is opened.
	var catalog struct {
		Recordings []struct {
			ID      string
			Seconds float64
		} `json:"recordings"`
		Generated []struct {
			ID      string
			Seconds float64
		} `json:"generated"`
	}
	manifest, err := os.ReadFile(filepath.Join(resources, "audio", "FieldRecordings.json"))
	if err != nil || json.Unmarshal(manifest, &catalog) != nil {
		result["error"] = "missing sleep pack manifest"
		return
	}
	sleepAudio := []map[string]any{}
	for _, item := range append(catalog.Recordings, catalog.Generated...) {
		for _, start := range []float64{0, item.Seconds - 2} {
			var probe struct {
				Seconds   float64
				Samples   int
				RMS, Peak float64
			}
			if err := d.service.backend.request("inspect", map[string]any{"sound": item.ID, "startSeconds": start, "sampleSeconds": 2}, &probe); err != nil {
				result["error"] = "sleep decoder " + item.ID + ": " + err.Error()
				return
			}
			if probe.Seconds != item.Seconds || probe.Samples < 48000 || probe.RMS < .0001 || probe.Peak >= .75 {
				result["error"] = fmt.Sprintf("invalid long sleep audio %s at %v: %+v", item.ID, start, probe)
				return
			}
			sleepAudio = append(sleepAudio, map[string]any{"sound": item.ID, "start": start, "seconds": probe.Seconds, "rms": probe.RMS, "peak": probe.Peak})
		}
	}
	result["sleepAudio"] = sleepAudio
	result["ok"] = d.window.Page() == nil && noWebAssets && invalidPath != nil && invalidSound != nil && staleConfirmation != nil && manualConfirmation && result["nativeImport"] == true && result["deletedMedia"] == true && len(d.view.dictionaries) == 6 && len(previews) == 14 && len(sleepAudio) == 16
}
