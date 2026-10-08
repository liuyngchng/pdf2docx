//go:build !linux

package main

// acquireSingleInstanceLock returns a no-op cleanup on non-Linux platforms.
func acquireSingleInstanceLock() (func(), error) {
	return func() {}, nil
}
