package main

import (
	"testing"
)

func TestAllNativeAlarmPreviewsSkipQuietIntro(t *testing.T) {
	for _, sound := range builtinAlarms {
		t.Run(sound, func(t *testing.T) {
			a, audio := nativeFixture(t)
			a.preferences.AlarmVolume = .63
			a.command("preview", 0, sound, true)
			if len(audio.plays) != 1 {
				t.Fatalf("preview failed: %s", a.errorText)
			}
			play := audio.plays[0]
			if play["volume"] != .63 || play["alarm"] != true || play["preview"] != true || play["startSeconds"] != alarmPreviewStart || play["previewSeconds"] != previewSeconds {
				t.Fatalf("incorrect preview: %+v", play)
			}
			deadline := a.service.previewUntil
			if deadline == 0 {
				t.Fatal("preview has no deadline")
			}
			a.service.mu.Lock()
			_ = a.service.tickLocked(deadline - 1)
			a.service.mu.Unlock()
			if a.service.previewUntil != deadline {
				t.Fatal("preview stopped before its deadline")
			}
			if a.snapshot.Session != nil {
				t.Fatal("preview started a rest")
			}
		})
	}
}
func TestNativeSleepAndCustomPreviewsUseTheirSelectedVolume(t *testing.T) {
	a, audio := nativeFixture(t)
	a.preferences.SleepVolume = .27
	a.preferences.AlarmVolume = .72
	a.command("preview", 0, "rain")
	if play := audio.plays[len(audio.plays)-1]; play["volume"] != .27 || play["startSeconds"] != 0 || play["alarm"] != false {
		t.Fatal(play)
	}
	a.command("preview", 0, "custom:"+newID(), true)
	if play := audio.plays[len(audio.plays)-1]; play["volume"] != .72 || play["startSeconds"] != 0 || play["alarm"] != true {
		t.Fatal(play)
	}
	a.service.mu.Lock()
	_ = a.service.tickLocked(a.service.previewUntil)
	a.service.mu.Unlock()
	if a.service.previewUntil != 0 {
		t.Fatal("preview did not stop")
	}
}
func TestActualAlarmStillStartsFromBeginningWithRamp(t *testing.T) {
	s, audio := fixture(t)
	start(t, s, 30)
	deadline := s.state.Session.Deadline
	s.mu.Lock()
	err := s.tickLocked(deadline)
	s.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	play := audio.plays[len(audio.plays)-1]
	if play["preview"] != false || play["alarm"] != true || play["startSeconds"] != nil || play["volume"].(float64) >= .02 {
		t.Fatal(play)
	}
}
