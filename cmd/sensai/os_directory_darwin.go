//go:build darwin

package main

import (
	"syscall"
	"unsafe"
)

const (
	darwinSysRenameatxNP = uintptr(488)
	darwinRenameExcl     = uintptr(0x4)
	darwinATFDCWD        = ^uintptr(1)
)

func publishDirectoryNoReplace(source, destination string) error {
	from, err := syscall.BytePtrFromString(source)
	if err != nil {
		return platformError("encode source", source, err)
	}
	to, err := syscall.BytePtrFromString(destination)
	if err != nil {
		return platformError("encode destination", destination, err)
	}
	_, _, errno := syscall.Syscall6(
		darwinSysRenameatxNP,
		darwinATFDCWD,
		uintptr(unsafe.Pointer(from)),
		darwinATFDCWD,
		uintptr(unsafe.Pointer(to)),
		darwinRenameExcl,
		0,
	)
	if errno != 0 {
		return platformError("renameatx_np", destination, errno)
	}
	return nil
}
