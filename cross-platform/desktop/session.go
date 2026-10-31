package main

import (
	"crypto/rand"
	"encoding/hex"
	"math"
	"slices"
)

type Preferences struct {
	Duration      int     `json:"duration"`
	SleepSound    string  `json:"sleepSound"`
	AlarmSound    string  `json:"alarmSound"`
	SleepVolume   float64 `json:"sleepVolume"`
	AlarmVolume   float64 `json:"alarmVolume"`
	SnoozeMinutes int     `json:"snoozeMinutes"`
	RepeatAlarm   bool    `json:"repeatAlarm"`
	Language      string  `json:"language"`
}

type SessionPhase string

const (
	PhaseResting SessionPhase = "resting"
	PhasePaused  SessionPhase = "paused"
	PhaseRinging SessionPhase = "ringing"
	PhaseBlocked SessionPhase = "blocked"
)

type Session struct {
	ID              string       `json:"id"`
	StartedAt       int64        `json:"startedAt"`
	Deadline        int64        `json:"deadline"`
	Duration        int          `json:"duration"`
	Phase           SessionPhase `json:"phase"`
	PausedRemaining *float64     `json:"pausedRemaining"`
	SnoozeCount     int          `json:"snoozeCount"`
	AccumulatedRest float64      `json:"accumulatedRest"`
	RestingSince    *int64       `json:"restingSince"`
	Reason          *string      `json:"reason"`
}

type RestRecord struct {
	ID        string `json:"id"`
	StartedAt int64  `json:"startedAt"`
	EndedAt   int64  `json:"endedAt"`
	Seconds   int    `json:"seconds"`
	Completed bool   `json:"completed"`
	Sound     string `json:"sound"`
}

func newID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	h := hex.EncodeToString(b)
	return h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]
}

func newSession(now int64, duration int) *Session {
	duration = min(43200, max(1, duration))
	return &Session{ID: newID(), StartedAt: now, Deadline: now + int64(duration)*1000, Duration: duration, Phase: "resting", RestingSince: &now}
}

func (s *Session) remaining(now int64) float64 {
	if s.PausedRemaining != nil {
		return max(0, *s.PausedRemaining)
	}
	return max(0, float64(s.Deadline-now)/1000)
}

func (s *Session) rested(now int64) float64 {
	value := s.AccumulatedRest
	if s.RestingSince != nil {
		value += max(0, float64(min(now, s.Deadline)-*s.RestingSince)/1000)
	}
	return value
}

func (s *Session) settle(now int64) { s.AccumulatedRest = s.rested(now); s.RestingSince = nil }
func (s *Session) block(now int64, reason string) {
	if s.Phase == "paused" {
		return
	}
	s.settle(now)
	s.Phase = "blocked"
	s.Reason = &reason
}
func (s *Session) pause(now int64) {
	if s.Phase != "resting" {
		return
	}
	left := s.remaining(now)
	s.settle(now)
	s.PausedRemaining = &left
	s.Phase = "paused"
	s.Reason = nil
}
func (s *Session) resume(now int64) {
	if s.Phase != "paused" && s.Phase != "blocked" {
		return
	}
	if s.PausedRemaining != nil {
		s.Deadline = now + int64(math.Round(*s.PausedRemaining*1000))
	}
	s.PausedRemaining = nil
	s.Reason = nil
	if now >= s.Deadline {
		s.Phase = "ringing"
		s.RestingSince = nil
	} else {
		s.Phase = "resting"
		s.RestingSince = &now
	}
}
func (s *Session) snooze(now int64, minutes int) {
	if s.Phase != "ringing" {
		return
	}
	s.Duration = min(30, max(1, minutes)) * 60
	s.Deadline = now + int64(s.Duration)*1000
	s.Phase = "resting"
	s.RestingSince = &now
	s.PausedRemaining = nil
	s.Reason = nil
	s.SnoozeCount++
}
func (s *Session) tick(now int64, repeat bool) bool {
	if s.Phase == "resting" && now >= s.Deadline {
		s.settle(now)
		s.Phase = "ringing"
	}
	return slices.Contains([]SessionPhase{PhaseRinging, PhaseBlocked}, s.Phase) && s.PausedRemaining == nil && !repeat && now >= s.Deadline+180000
}
func (s *Session) valid() bool {
	return validID(s.ID) && slices.Contains([]SessionPhase{PhaseResting, PhasePaused, PhaseBlocked, PhaseRinging}, s.Phase) && s.StartedAt >= 0 && s.Deadline >= s.StartedAt &&
		s.Duration >= 1 && s.Duration <= 43200 && s.SnoozeCount >= 0 && s.AccumulatedRest >= 0 && !math.IsNaN(s.AccumulatedRest) && !math.IsInf(s.AccumulatedRest, 0) &&
		(s.PausedRemaining == nil || *s.PausedRemaining >= 0 && *s.PausedRemaining <= 43200) && (s.RestingSince == nil || *s.RestingSince >= s.StartedAt)
}
