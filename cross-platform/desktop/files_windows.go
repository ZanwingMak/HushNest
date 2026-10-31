package main

import (
	"syscall"
	"unsafe"
)

func replaceFile(source, target string) error {
	from, e := syscall.UTF16PtrFromString(source)
	if e != nil {
		return e
	}
	to, e := syscall.UTF16PtrFromString(target)
	if e != nil {
		return e
	}
	move := syscall.NewLazyDLL("kernel32.dll").NewProc("MoveFileExW")
	ok, _, err := move.Call(uintptr(unsafe.Pointer(from)), uintptr(unsafe.Pointer(to)), 0x1|0x8)
	if ok == 0 {
		return err
	}
	return nil
}
