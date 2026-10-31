package main

import (
	"image/png"
	"os"
	"path/filepath"
	"testing"

	"github.com/egoist/mygo/ui"
)

func TestNativeDesktopPrimaryActionsStayVisible(t *testing.T) {
	for _, size := range [][2]int{{1180, 840}, {1040, 850}, {600, 560}} {
		a, _ := nativeFixture(t)
		tt := ui.NewTester(a.render, size[0], size[1])
		button, ok := tt.Find("开始休息")
		if !ok || button.W <= 0 || button.H <= 0 || button.X < 0 || button.Y < 0 || button.X+button.W > float32(size[0]) || button.Y+button.H > float32(size[1]) {
			t.Fatalf("start action clipped at %v: %+v", size, button)
		}
	}
}

func TestNativeDurationFieldCanBeClearedAndRetyped(t *testing.T) {
	a, _ := nativeFixture(t)
	tt := ui.NewTester(a.render, 1180, 840)
	clickNative(t, tt, "分钟")
	tt.Key(ui.Cmd, ui.KeyA)
	tt.Key(0, ui.KeyBackspace)
	if a.minuteDraft != "" {
		t.Fatalf("field cannot be cleared: %q", a.minuteDraft)
	}
	tt.Type("20")
	clickNative(t, tt, "开始休息")
	if a.snapshot.Session == nil || a.snapshot.Session.Duration != 1200 {
		t.Fatalf("typed duration not applied: %+v", a.snapshot.Session)
	}
}

func TestNativeCountdownRejectsInvalidDraft(t *testing.T) {
	a, audio := nativeFixture(t)
	a.minuteDraft = "1000"
	a.begin()
	if a.snapshot.Session != nil || len(audio.plays) != 0 || a.errorText == "" {
		t.Fatal("invalid duration started a rest")
	}
}

// Set HUSHNEST_VISUAL_QA to export deterministic headless layout previews.
func TestNativeVisualPreviews(t *testing.T) {
	if os.Getenv("HUSHNEST_VISUAL_QA") == "" {
		t.Skip("optional visual exports")
	}
	for _, name := range []string{"light", "dark", "compact", "large"} {
		a, _ := nativeFixture(t)
		w, h := 1180, 840
		a.settings.Appearance = "light"
		if name == "dark" {
			a.settings.Appearance = "dark"
		}
		if name == "compact" {
			w, h = 600, 560
		}
		if name == "large" {
			a.settings.LargeText = true
		}
		tt := ui.NewTester(a.render, w, h)
		folder := filepath.Join("..", "release", "mygo-native", "qa", "layouts")
		if err := os.MkdirAll(folder, 0700); err != nil {
			t.Fatal(err)
		}
		file, err := os.Create(filepath.Join(folder, name+".png"))
		if err != nil {
			t.Fatal(err)
		}
		if err = png.Encode(file, tt.Image()); err != nil {
			t.Fatal(err)
		}
		if err = file.Close(); err != nil {
			t.Fatal(err)
		}
	}
}
