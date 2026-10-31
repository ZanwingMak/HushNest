//go:build !windows

package main

import "os/exec"

func hideHelper(cmd *exec.Cmd) {}
