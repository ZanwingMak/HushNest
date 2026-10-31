package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
	"time"
)

type Route struct {
	// Connected means this active output is admitted, either detected or
	// explicitly confirmed. Verified distinguishes automatic detection.
	Connected            bool   `json:"connected"`
	Verified             bool   `json:"verified"`
	Name                 string `json:"name"`
	Token                string `json:"token"`
	RequiresConfirmation bool   `json:"requiresConfirmation"`
}
type helperReply struct {
	ID        int64           `json:"id"`
	Result    json.RawMessage `json:"result"`
	Error     string          `json:"error"`
	EventType string          `json:"eventType"`
}
type audioBackend interface {
	request(action string, data map[string]any, out any) error
	close()
}
type helperProcess struct {
	mu      sync.Mutex
	writeMu sync.Mutex
	next    int64
	stdin   io.WriteCloser
	cmd     *exec.Cmd
	pending map[int64]chan helperReply
	done    chan struct{}
	lost    chan struct{}
	once    sync.Once
}

func openHelper(resources, media string) (*helperProcess, error) {
	file := filepath.Join(resources, "audio-guard", "AudioGuard.exe")
	if runtime.GOOS == "darwin" {
		file = filepath.Join(resources, "AudioGuard")
	}
	cmd := exec.Command(file, filepath.Join(resources, "audio"), media)
	hideHelper(cmd)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		stdin.Close()
		return nil, err
	}
	h := &helperProcess{stdin: stdin, cmd: cmd, pending: map[int64]chan helperReply{}, done: make(chan struct{}), lost: make(chan struct{}, 1)}
	if err = cmd.Start(); err != nil {
		stdin.Close()
		return nil, fmt.Errorf("audio helper: %w", err)
	}
	go func() {
		scan := bufio.NewScanner(stdout)
		scan.Buffer(make([]byte, 4096), 1024*1024)
		for scan.Scan() {
			var reply helperReply
			if json.Unmarshal(scan.Bytes(), &reply) != nil {
				continue
			}
			if reply.EventType == "routeLost" {
				select {
				case h.lost <- struct{}{}:
				default:
				}
				continue
			}
			h.mu.Lock()
			ch := h.pending[reply.ID]
			h.mu.Unlock()
			if ch != nil {
				select {
				case ch <- reply:
				default:
				}
			}
		}
		_ = cmd.Wait()
		h.once.Do(func() { close(h.done) })
	}()
	return h, nil
}
func (h *helperProcess) request(action string, data map[string]any, out any) error {
	h.mu.Lock()
	h.next++
	id := h.next
	ch := make(chan helperReply, 1)
	h.pending[id] = ch
	h.mu.Unlock()
	defer func() { h.mu.Lock(); delete(h.pending, id); h.mu.Unlock() }()
	message := map[string]any{"id": id, "action": action}
	for k, v := range data {
		message[k] = v
	}
	bytes, err := json.Marshal(message)
	if err != nil {
		return err
	}
	bytes = append(bytes, '\n')
	h.writeMu.Lock()
	_, err = h.stdin.Write(bytes)
	h.writeMu.Unlock()
	if err != nil {
		return err
	}
	timer := time.NewTimer(10 * time.Second)
	defer timer.Stop()
	select {
	case reply := <-ch:
		if reply.Error != "" {
			return errors.New(reply.Error)
		}
		if out != nil && len(reply.Result) > 0 {
			return json.Unmarshal(reply.Result, out)
		}
		return nil
	case <-h.done:
		return errors.New("audio-service-stopped")
	case <-timer.C:
		return errors.New("audio-service-timeout")
	}
}
func (h *helperProcess) close() {
	_ = h.stdin.Close()
	select {
	case <-h.done:
	case <-time.After(2 * time.Second):
		_ = h.cmd.Process.Kill()
		<-h.done
	}
}
