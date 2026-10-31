package main

import (
	"encoding/json"
	"errors"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

var idPattern = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

func validID(s string) bool { return idPattern.MatchString(s) }

var builtinSounds = strings.Fields("rain ocean stream forest fireplace night brown pink dawn bell orbit piano marimba harp bamboo aurora classic twinbell digital pulse beacon reveille")
var builtinAlarms = strings.Fields("dawn bell orbit piano marimba harp bamboo aurora classic twinbell digital pulse beacon reveille")

const previewSeconds = 4
const alarmPreviewStart = 12

func validSound(sound string, allowNone bool) bool {
	return allowNone && sound == "none" || slices.Contains(builtinSounds, sound) || strings.HasPrefix(sound, "custom:") && validID(strings.TrimPrefix(sound, "custom:"))
}
func normalizePreferences(p Preferences) (Preferences, error) {
	if !validSound(p.SleepSound, true) || !validSound(p.AlarmSound, false) {
		return p, errors.New("invalid-sound")
	}
	if math.IsNaN(p.SleepVolume) || math.IsInf(p.SleepVolume, 0) || math.IsNaN(p.AlarmVolume) || math.IsInf(p.AlarmVolume, 0) {
		return p, errors.New("invalid-volume")
	}
	p.Duration = min(43200, max(1, p.Duration))
	p.SnoozeMinutes = min(30, max(1, p.SnoozeMinutes))
	p.SleepVolume = min(0.6, max(0.01, p.SleepVolume))
	p.AlarmVolume = min(1, max(0.05, p.AlarmVolume))
	if !slices.Contains([]string{"zh-Hans", "zh-Hant", "en", "ja", "ko", "es"}, p.Language) {
		p.Language = "en"
	}
	return p, nil
}

type Snapshot struct {
	Session *Session     `json:"session"`
	Route   Route        `json:"route"`
	Records []RestRecord `json:"records"`
}
type CommandInput struct {
	Action      string       `json:"action"`
	Session     *Session     `json:"session,omitempty"`
	Preferences *Preferences `json:"preferences,omitempty"`
	Sound       string       `json:"sound,omitempty"`
	Volume      float64      `json:"volume,omitempty"`
	RouteToken  string       `json:"routeToken,omitempty"`
	Alarm       bool         `json:"alarm,omitempty"`
}
type CacheInput struct {
	ID     string `json:"id"`
	Offset int64  `json:"offset"`
	Data   []byte `json:"data"`
	Final  bool   `json:"final"`
}
type persistedState struct {
	Session     *Session     `json:"session"`
	Preferences Preferences  `json:"preferences"`
	Records     []RestRecord `json:"records"`
}
type restService struct {
	mu           sync.Mutex
	backend      audioBackend
	state        persistedState
	route        Route
	directory    string
	audioKey     string
	outputToken  string
	previewUntil int64
	lastRoute    int64
	lastSave     int64
	active       atomic.Bool
	onChange     func()
	stop         chan struct{}
	done         chan struct{}
}

func newRestService(directory string, backend audioBackend) (*restService, error) {
	if err := os.MkdirAll(filepath.Join(directory, "media"), 0700); err != nil {
		return nil, err
	}
	s := &restService{directory: directory, backend: backend, stop: make(chan struct{}), done: make(chan struct{})}
	s.state.Preferences = Preferences{Duration: 1800, SleepSound: "rain", AlarmSound: "dawn", SleepVolume: 0.18, AlarmVolume: 0.55, SnoozeMinutes: 5, Language: "en"}
	if bytes, err := os.ReadFile(filepath.Join(directory, "rest-state.json")); err == nil {
		var saved persistedState
		if json.Unmarshal(bytes, &saved) == nil {
			if p, err := normalizePreferences(saved.Preferences); err == nil {
				s.state.Preferences = p
			}
			for _, r := range saved.Records {
				if validID(r.ID) && r.Seconds >= 0 && r.StartedAt >= 0 && r.EndedAt >= r.StartedAt && validSound(r.Sound, true) {
					s.state.Records = append(s.state.Records, r)
					if len(s.state.Records) == 365 {
						break
					}
				}
			}
			if saved.Session != nil && saved.Session.valid() {
				s.state.Session = saved.Session
				s.state.Session.RestingSince = nil
				if s.state.Session.Phase != "paused" {
					reason := "restored"
					s.state.Session.Phase = "blocked"
					s.state.Session.Reason = &reason
				}
			}
		}
	}
	if s.state.Records == nil {
		s.state.Records = []RestRecord{}
	}
	return s, nil
}
func (s *restService) saveLocked() error {
	bytes, err := json.Marshal(s.state)
	if err != nil {
		return err
	}
	file := filepath.Join(s.directory, "rest-state.json")
	tmp := file + ".tmp"
	if err = os.WriteFile(tmp, bytes, 0600); err != nil {
		return err
	}
	return replaceFile(tmp, file)
}
func (s *restService) snapshotLocked() Snapshot {
	var session *Session
	if s.state.Session != nil {
		copy := *s.state.Session
		session = &copy
	}
	return Snapshot{Session: session, Route: s.route, Records: slices.Clone(s.state.Records)}
}
func (s *restService) snapshot() Snapshot {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.snapshotLocked()
}
func (s *restService) notify() {
	s.mu.Lock()
	s.active.Store(s.state.Session != nil && s.state.Session.Phase != "paused")
	s.mu.Unlock()
	if s.onChange != nil {
		s.onChange()
	}
}
func (s *restService) routeLocked() error {
	var route Route
	if err := s.backend.request("route", nil, &route); err != nil {
		s.route = Route{}
		return err
	}
	s.route = route
	s.lastRoute = time.Now().UnixMilli()
	return nil
}
func (s *restService) stopAudioLocked() {
	s.audioKey = ""
	s.previewUntil = 0
	_ = s.backend.request("stop", nil, nil)
}
func (s *restService) blockLocked(now int64, reason string) {
	s.stopAudioLocked()
	if v := s.state.Session; v != nil {
		v.block(now, reason)
		_ = s.saveLocked()
	}
}
func (s *restService) finishLocked(now int64, completed bool) error {
	if v := s.state.Session; v != nil {
		r := RestRecord{ID: v.ID, StartedAt: v.StartedAt, EndedAt: now, Seconds: int(v.rested(now)), Completed: completed, Sound: s.state.Preferences.SleepSound}
		s.state.Records = append([]RestRecord{r}, slices.DeleteFunc(s.state.Records, func(old RestRecord) bool { return old.ID == r.ID })...)
		if len(s.state.Records) > 365 {
			s.state.Records = s.state.Records[:365]
		}
	}
	s.stopAudioLocked()
	s.state.Session = nil
	s.outputToken = ""
	return s.saveLocked()
}
func (s *restService) command(input CommandInput) (result Snapshot, err error) {
	s.mu.Lock()
	defer func() { result = s.snapshotLocked(); s.mu.Unlock(); s.notify() }()
	now := time.Now().UnixMilli()
	if input.Preferences != nil {
		p, e := normalizePreferences(*input.Preferences)
		if e != nil {
			return result, e
		}
		s.state.Preferences = p
	}
	p := s.state.Preferences
	v := s.state.Session
	switch input.Action {
	case "start", "resume", "snooze", "preview":
		if e := s.routeLocked(); e != nil || !s.route.Connected {
			return result, errors.New("routeLost")
		}
	}
	switch input.Action {
	case "confirmRoute":
		if v != nil && v.Phase != "paused" && v.Phase != "blocked" {
			return result, errors.New("session-active")
		}
		if e := s.routeLocked(); e != nil {
			return result, e
		}
		if input.RouteToken == "" || s.route.Token == "" || input.RouteToken != s.route.Token {
			return result, errors.New("routeChanged")
		}
		if e := s.backend.request("confirmRoute", map[string]any{"token": input.RouteToken}, nil); e != nil {
			return result, e
		}
		err = s.routeLocked()
		if err == nil && (!s.route.Connected || s.route.Token != input.RouteToken) {
			err = errors.New("routeChanged")
		}
		return
	case "start":
		if v != nil {
			return result, errors.New("session-active")
		}
		s.stopAudioLocked()
		duration := p.Duration
		if input.Session != nil {
			duration = input.Session.Duration
		}
		s.state.Session = newSession(now, duration)
		s.outputToken = s.route.Token
	case "pause":
		if v != nil {
			v.pause(now)
			s.stopAudioLocked()
		}
	case "resume":
		if v != nil {
			v.resume(now)
			s.outputToken = s.route.Token
		}
	case "snooze":
		if v != nil {
			v.snooze(now, p.SnoozeMinutes)
			s.stopAudioLocked()
		}
	case "stop":
		return result, s.finishLocked(now, v != nil && (v.Phase == "ringing" || v.PausedRemaining == nil && now >= v.Deadline))
	case "clearRecords":
		s.state.Records = []RestRecord{}
	case "volume":
	case "preview":
		if v != nil {
			return result, errors.New("session-active")
		}
		if !validSound(input.Sound, false) || math.IsNaN(input.Volume) || math.IsInf(input.Volume, 0) {
			return result, errors.New("invalid-audio")
		}
		s.stopAudioLocked()
		alarm := input.Alarm || slices.Contains(builtinAlarms, input.Sound)
		start := 0
		if slices.Contains(builtinAlarms, input.Sound) {
			start = alarmPreviewStart
		}
		err = s.backend.request("play", map[string]any{"sound": input.Sound, "volume": min(1, max(0.01, input.Volume)), "alarm": alarm, "preview": true, "startSeconds": start, "previewSeconds": previewSeconds}, nil)
		if err == nil {
			s.previewUntil = time.Now().UnixMilli() + previewSeconds*1000
			s.outputToken = s.route.Token
		}
		return
	default:
		return result, errors.New("invalid-action")
	}
	if err = s.saveLocked(); err != nil {
		return result, err
	}
	return result, s.tickLocked(now)
}
func (s *restService) tickLocked(now int64) error {
	if now-s.lastRoute >= 500 {
		if err := s.routeLocked(); err != nil {
			s.blockLocked(now, "routeLost")
			return err
		}
	}
	if s.previewUntil > 0 {
		if now >= s.previewUntil || !s.route.Connected || s.route.Token != s.outputToken {
			s.stopAudioLocked()
		}
		return nil
	}
	v := s.state.Session
	if v == nil {
		return nil
	}
	p := s.state.Preferences
	oldPhase := v.Phase
	if v.tick(now, p.RepeatAlarm) {
		return s.finishLocked(now, v.AccumulatedRest >= float64(v.Duration))
	}
	if v.Phase == "resting" || v.Phase == "ringing" {
		if !s.route.Connected || s.outputToken != "" && s.outputToken != s.route.Token {
			s.blockLocked(now, "routeLost")
			return nil
		}
		alarm := v.Phase == "ringing"
		sound := p.SleepSound
		volume := p.SleepVolume
		if alarm {
			sound = p.AlarmSound
			volume = p.AlarmVolume * min(1, max(0.01, float64(now-v.Deadline)/15000))
		}
		key := v.ID + ":" + string(v.Phase) + ":" + sound
		if key != s.audioKey {
			s.stopAudioLocked()
			if sound != "none" {
				if err := s.backend.request("play", map[string]any{"sound": sound, "volume": volume, "alarm": alarm, "preview": false}, nil); err != nil {
					s.blockLocked(now, "audioError")
					return err
				}
			}
			s.audioKey = key
		}
		if sound != "none" {
			if err := s.backend.request("volume", map[string]any{"value": volume}, nil); err != nil {
				s.blockLocked(now, "audioError")
				return err
			}
		}
	}
	if oldPhase != v.Phase || now-s.lastSave >= 5000 {
		if v.Phase == "resting" {
			v.settle(now)
			v.RestingSince = &now
		}
		s.lastSave = now
		return s.saveLocked()
	}
	return nil
}
func (s *restService) run(lost <-chan struct{}) {
	go func() {
		defer close(s.done)
		ticker := time.NewTicker(200 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-s.stop:
				return
			case <-lost:
				s.mu.Lock()
				s.blockLocked(time.Now().UnixMilli(), "routeLost")
				s.mu.Unlock()
				s.notify()
			case t := <-ticker.C:
				s.mu.Lock()
				_ = s.tickLocked(t.UnixMilli())
				s.mu.Unlock()
				s.notify()
			}
		}
	}()
}
func (s *restService) close() {
	close(s.stop)
	<-s.done
	s.mu.Lock()
	s.stopAudioLocked()
	if v := s.state.Session; v != nil {
		v.settle(time.Now().UnixMilli())
		if v.Phase != "paused" {
			v.block(time.Now().UnixMilli(), "restored")
		}
	}
	_ = s.saveLocked()
	s.mu.Unlock()
	s.backend.close()
}
func (s *restService) mediaPath(id string, temporary bool) (string, error) {
	if !validID(id) {
		return "", errors.New("invalid-id")
	}
	suffix := ".media"
	if temporary {
		suffix = ".import"
	}
	return filepath.Join(s.directory, "media", id+suffix), nil
}
func (s *restService) cacheMedia(input CacheInput) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	file, err := s.mediaPath(input.ID, true)
	if err != nil {
		return err
	}
	if input.Offset < 0 || input.Offset > 200*1024*1024 || len(input.Data) > 1024*1024 || input.Offset+int64(len(input.Data)) > 200*1024*1024 {
		return errors.New("media-size")
	}
	flags := os.O_CREATE | os.O_WRONLY
	if input.Offset == 0 {
		flags |= os.O_TRUNC
	} else {
		info, e := os.Stat(file)
		if e != nil || info.Size() != input.Offset {
			return errors.New("media-offset")
		}
	}
	f, err := os.OpenFile(file, flags, 0600)
	if err != nil {
		return err
	}
	_, err = f.WriteAt(input.Data, input.Offset)
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if input.Final {
		info, e := os.Stat(file)
		if e != nil || info.Size() == 0 {
			return errors.New("media-size")
		}
		target, _ := s.mediaPath(input.ID, false)
		return replaceFile(file, target)
	}
	return nil
}
func (s *restService) hasMedia(id string, size int64) bool {
	file, err := s.mediaPath(id, false)
	if err != nil || size < 1 {
		return false
	}
	info, err := os.Stat(file)
	return err == nil && info.Size() == size
}
func (s *restService) deleteMedia(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state.Session != nil {
		return errors.New("session-active")
	}
	file, err := s.mediaPath(id, false)
	if err != nil {
		return err
	}
	err = os.Remove(file)
	if os.IsNotExist(err) {
		return nil
	}
	return err
}
