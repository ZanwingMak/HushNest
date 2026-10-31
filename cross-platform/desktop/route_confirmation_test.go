package main

import (
	"testing"
	"time"

	"github.com/egoist/mygo/ui"
)

func manualRouteFixture(t *testing.T) (*nativeApp, *silentAudio) {
	t.Helper()
	a, audio := nativeFixture(t)
	audio.route = Route{Name: "USB audio reported as speakers", Token: "manual-output", RequiresConfirmation: true}
	a.snapshot.Route = audio.route
	return a, audio
}
func TestNativeUndetectedHeadphonesAskBeforeStarting(t *testing.T) {
	a, audio := manualRouteFixture(t)
	asks := 0
	a.confirmHeadphones = func(route Route) bool {
		asks++
		if route.Token != "manual-output" || len(audio.plays) != 0 || a.service.snapshot().Session != nil {
			t.Fatal("sound started before confirmation")
		}
		return true
	}
	tt := ui.NewTester(a.render, 1180, 840)
	clickNative(t, tt, "开始休息")
	if asks != 1 || audio.confirmations != 1 || len(audio.plays) != 1 || a.snapshot.Session == nil || !a.snapshot.Route.Connected || a.snapshot.Route.Verified {
		t.Fatalf("manual start failed: asks=%d route=%+v session=%+v", asks, a.snapshot.Route, a.snapshot.Session)
	}
	if !tt.HasText("耳机已手动确认") {
		t.Fatal("manual status is missing")
	}
}
func TestNativeCancelConfirmationDoesNotStartAudio(t *testing.T) {
	a, audio := manualRouteFixture(t)
	asks := 0
	a.confirmHeadphones = func(Route) bool { asks++; return false }
	a.begin()
	if asks != 1 || audio.confirmations != 0 || len(audio.plays) != 0 || a.snapshot.Session != nil || a.busy {
		t.Fatal("cancel did not leave the rest idle")
	}
}
func TestNativeConfirmationDoesNotApproveChangedOutput(t *testing.T) {
	a, audio := manualRouteFixture(t)
	a.confirmHeadphones = func(Route) bool { audio.route.Token = "another-output"; return true }
	a.begin()
	if audio.confirmations != 0 || len(audio.plays) != 0 || a.snapshot.Session != nil || a.errorText == "" {
		t.Fatal("confirmation approved another output")
	}
}
func TestNativeNoOutputCannotBeOverridden(t *testing.T) {
	a, audio := manualRouteFixture(t)
	audio.route = Route{}
	asks := 0
	a.confirmHeadphones = func(Route) bool { asks++; return true }
	a.begin()
	if asks != 0 || len(audio.plays) != 0 || a.snapshot.Session != nil || a.errorText == "" {
		t.Fatal("missing output was overridden")
	}
}
func TestNativePreviewAndResumeCanConfirmOutput(t *testing.T) {
	a, audio := manualRouteFixture(t)
	asks := 0
	a.confirmHeadphones = func(Route) bool { asks++; return true }
	a.command("preview", 0, "rain")
	if asks != 1 || len(audio.plays) != 1 || a.snapshot.Session != nil {
		t.Fatal("preview was not confirmed")
	}
	a.begin()
	if asks != 1 || a.snapshot.Session == nil {
		t.Fatal("confirmation did not remain valid for the current output")
	}
	audio.route.Token = "switched-output"
	s := a.service
	s.mu.Lock()
	s.lastRoute = 0
	err := s.tickLocked(time.Now().UnixMilli())
	s.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	a.snapshot = s.snapshot()
	if a.snapshot.Session.Phase != PhaseBlocked || a.snapshot.Route.Connected {
		t.Fatal("switch did not interrupt or revoke confirmation")
	}
	a.command("resume", 0, "")
	if asks != 2 || audio.confirmations != 2 || a.snapshot.Session.Phase != PhaseResting {
		t.Fatal("resume did not confirm the new output")
	}
}
func TestNativeDetectedHeadphonesDoNotPrompt(t *testing.T) {
	a, _ := nativeFixture(t)
	a.confirmHeadphones = func(Route) bool { t.Fatal("automatic route asked for confirmation"); return false }
	a.begin()
	if a.snapshot.Session == nil {
		t.Fatal("automatic route did not start")
	}
}
func TestNativeConfirmationIsNotPersisted(t *testing.T) {
	a, _ := manualRouteFixture(t)
	a.confirmHeadphones = func(Route) bool { return true }
	a.confirmCurrentRoute()
	backend := &silentAudio{route: Route{Token: "manual-output", RequiresConfirmation: true}}
	restored, err := newRestService(a.service.directory, backend)
	if err != nil {
		t.Fatal(err)
	}
	if err = restored.routeLocked(); err != nil {
		t.Fatal(err)
	}
	if restored.route.Connected {
		t.Fatal("manual confirmation survived a process restart")
	}
}
func TestServiceConfirmationRequiresMatchingToken(t *testing.T) {
	a, audio := manualRouteFixture(t)
	for _, token := range []string{"", "stale-output"} {
		if _, err := a.service.command(CommandInput{Action: "confirmRoute", RouteToken: token}); err == nil {
			t.Fatal("stale confirmation accepted")
		}
	}
	if audio.confirmations != 0 {
		t.Fatal("invalid token reached the helper")
	}
}
