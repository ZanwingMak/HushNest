package main

import (
	"errors"
	"math"
	"os"
	"path/filepath"
	"testing"
)

type silentAudio struct {
	route Route
	plays []map[string]any
	stops int
	fail  bool
}

func (f *silentAudio) request(action string, data map[string]any, out any) error {
	if f.fail {
		return errors.New("test-device-unavailable")
	}
	switch action {
	case "route":
		*out.(*Route) = f.route
	case "inspect":
		out.(*struct{ Seconds float64 }).Seconds = 1
	case "play":
		f.plays = append(f.plays, data)
	case "stop":
		f.stops++
	case "confirmRoute":
		f.route.Connected = true
	}
	return nil
}
func (*silentAudio) close() {}
func fixture(t *testing.T) (*restService, *silentAudio) {
	t.Helper()
	a := &silentAudio{route: Route{Connected: true, Verified: true, Name: "silent test headphones", Token: "test-endpoint"}}
	s, e := newRestService(t.TempDir(), a)
	if e != nil {
		t.Fatal(e)
	}
	return s, a
}
func start(t *testing.T, s *restService, duration int) Snapshot {
	t.Helper()
	p := s.state.Preferences
	p.Duration = duration
	r, e := s.command(CommandInput{Action: "start", Preferences: &p})
	if e != nil {
		t.Fatal(e)
	}
	return r
}

func TestHeadphoneGuardRejectsStartAndPreview(t *testing.T) {
	s, a := fixture(t)
	a.route.Connected = false
	for _, action := range []string{"start", "resume", "snooze", "preview"} {
		_, e := s.command(CommandInput{Action: action, Sound: "dawn", Volume: .1})
		if e == nil {
			t.Fatalf("%s bypassed headphone protection", action)
		}
	}
	if s.state.Session != nil || len(a.plays) != 0 {
		t.Fatal("audio/session started without headphones")
	}
}
func TestNativeTimerAlarmsAndExpiresWithoutFrontend(t *testing.T) {
	s, a := fixture(t)
	r := start(t, s, 10)
	deadline := r.Session.Deadline
	if e := s.tickLocked(deadline); e != nil {
		t.Fatal(e)
	}
	if s.state.Session.Phase != PhaseRinging || a.plays[len(a.plays)-1]["sound"] != "dawn" {
		t.Fatal("native deadline did not start the alarm")
	}
	if e := s.tickLocked(deadline + 180000); e != nil {
		t.Fatal(e)
	}
	if s.state.Session != nil || len(s.state.Records) != 1 || s.state.Records[0].Seconds != 10 || !s.state.Records[0].Completed {
		t.Fatalf("invalid completed record: %+v", s.state.Records)
	}
}
func TestDisconnectStopsAudioAndPreservesDeadline(t *testing.T) {
	s, a := fixture(t)
	r := start(t, s, 30)
	deadline := r.Session.Deadline
	a.route.Connected = false
	if e := s.tickLocked(deadline - 1000); e != nil {
		t.Fatal(e)
	}
	v := s.state.Session
	if v.Phase != PhaseBlocked || v.Reason == nil || *v.Reason != "routeLost" || v.Deadline != deadline {
		t.Fatalf("invalid interrupted state: %+v", v)
	}
	if len(a.plays) != 1 || a.stops < 1 {
		t.Fatal("disconnect did not stop the existing output")
	}
	if _, e := s.command(CommandInput{Action: "resume"}); e == nil {
		t.Fatal("resumed without headphones")
	}
}
func TestSessionAccountingAndOriginalAlarmWindow(t *testing.T) {
	v := newSession(0, 60)
	v.pause(10000)
	if v.remaining(50000) != 50 {
		t.Fatal("pause drifted")
	}
	v.resume(100000)
	if v.Deadline != 150000 || v.rested(120000) != 30 {
		t.Fatal("paused time counted as rest")
	}
	v.block(120000, "routeLost")
	v.resume(400000)
	if v.Deadline != 150000 || !v.tick(400000, false) {
		t.Fatal("resumption reset the old alarm window")
	}
}
func TestContinuousAlarmAndSnooze(t *testing.T) {
	v := newSession(0, 1)
	if v.tick(900000, true) || v.Phase != PhaseRinging {
		t.Fatal("continuous alarm expired")
	}
	v.snooze(900000, 5)
	if v.Phase != PhaseResting || v.SnoozeCount != 1 || v.Deadline != 1200000 || v.rested(910000) != 11 {
		t.Fatalf("invalid snooze: %+v", v)
	}
}
func TestRestorationNeverCountsProcessDowntime(t *testing.T) {
	s, a := fixture(t)
	start(t, s, 60)
	s.state.Session.AccumulatedRest = 12
	if e := s.saveLocked(); e != nil {
		t.Fatal(e)
	}
	restored, e := newRestService(s.directory, a)
	if e != nil {
		t.Fatal(e)
	}
	v := restored.state.Session
	if v == nil || v.Phase != PhaseBlocked || v.RestingSince != nil || v.rested(v.Deadline+5000) != 12 {
		t.Fatalf("invalid restored state: %+v", v)
	}
}
func TestSnapshotIsIndependentOfFrontendMutation(t *testing.T) {
	s, _ := fixture(t)
	start(t, s, 60)
	r := s.snapshot()
	r.Session.Phase = PhaseRinging
	if s.snapshot().Session.Phase != PhaseResting {
		t.Fatal("snapshot mutated the native session")
	}
}
func TestChunkedMediaCacheBoundsAndDeletion(t *testing.T) {
	s, _ := fixture(t)
	id := newID()
	for _, in := range []CacheInput{{ID: "../escape", Data: []byte{1}, Final: true}, {ID: id, Offset: -1}, {ID: id, Offset: 200 * 1024 * 1024, Data: []byte{1}}, {ID: id, Offset: 5, Data: []byte{1}}} {
		if e := s.cacheMedia(in); e == nil {
			t.Fatalf("invalid chunk accepted: %+v", in)
		}
	}
	if e := s.cacheMedia(CacheInput{ID: id, Data: []byte{1, 2}}); e != nil {
		t.Fatal(e)
	}
	if e := s.cacheMedia(CacheInput{ID: id, Offset: 2, Data: []byte{3, 4}, Final: true}); e != nil {
		t.Fatal(e)
	}
	if !s.hasMedia(id, 4) {
		t.Fatal("cached media is incomplete")
	}
	file, _ := s.mediaPath(id, false)
	bytes, e := os.ReadFile(file)
	if e != nil || len(bytes) != 4 || bytes[3] != 4 {
		t.Fatal("chunk data changed")
	}
	if e := s.deleteMedia(id); e != nil {
		t.Fatal(e)
	}
	if s.hasMedia(id, 4) {
		t.Fatal("deleted media is present")
	}
	if _, e := os.Stat(filepath.Join(s.directory, "..", "escape.media")); !os.IsNotExist(e) {
		t.Fatal("file escaped private storage")
	}
}
func TestMediaDeletionCannotRemoveActiveSessionFiles(t *testing.T) {
	s, _ := fixture(t)
	id := newID()
	if e := s.cacheMedia(CacheInput{ID: id, Data: []byte{1}, Final: true}); e != nil {
		t.Fatal(e)
	}
	start(t, s, 60)
	if e := s.deleteMedia(id); e == nil || !s.hasMedia(id, 1) {
		t.Fatal("deleted media during a session")
	}
}
func TestPreferencesAndSoundValidation(t *testing.T) {
	s, _ := fixture(t)
	p := s.state.Preferences
	p.SleepVolume = math.NaN()
	if _, e := normalizePreferences(p); e == nil {
		t.Fatal("NaN accepted")
	}
	for _, sound := range []string{"../dawn", "custom:../../secret", "rain.wav", "https://example.com/a"} {
		if validSound(sound, true) {
			t.Fatalf("invalid sound accepted: %s", sound)
		}
	}
	if !validSound("none", true) || validSound("none", false) || !validSound("custom:"+newID(), false) {
		t.Fatal("sound validation rejected a supported choice")
	}
}
func TestHistoryIsBoundedAndStopIsIdempotent(t *testing.T) {
	s, _ := fixture(t)
	for i := range 366 {
		s.state.Session = newSession(int64(i)*10000, 1)
		if e := s.finishLocked(int64(i)*10000+1000, true); e != nil {
			t.Fatal(e)
		}
	}
	if len(s.state.Records) != 365 {
		t.Fatal("history limit exceeded")
	}
	if e := s.finishLocked(9999999, false); e != nil {
		t.Fatal(e)
	}
	if len(s.state.Records) != 365 {
		t.Fatal("duplicate stop appended a record")
	}
}
