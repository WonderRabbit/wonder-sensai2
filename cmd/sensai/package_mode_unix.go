//go:build !windows

package main

import "io/fs"

func packageExecutableModeOK(info fs.FileInfo) bool {
	return info.Mode().IsRegular() && info.Mode().Perm() == 0755
}
