package main

import (
	"context"
	"os"
	"os/signal"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), platformSignals()...)
	defer stop()
	os.Exit(runInvocation(invocation{
		ctx: ctx, args: os.Args[1:], executable: os.Args[0], stdout: os.Stdout, stderr: os.Stderr,
	}))
}
