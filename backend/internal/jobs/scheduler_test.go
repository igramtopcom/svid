package jobs

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/snakeloader/backend/internal/pkg/logger"
)

func init() {
	// Initialize logger to prevent nil dereference in safeRun's recover handler.
	logger.Init("debug")
}

func TestSafeRun_RecoverFromPanic(t *testing.T) {
	s := &Scheduler{}

	// safeRun should recover from a panic and not crash the test process.
	didPanic := false
	func() {
		defer func() {
			if r := recover(); r != nil {
				didPanic = true
			}
		}()
		s.safeRun("panic-job", func() {
			panic("test panic: something went wrong")
		})
	}()

	if didPanic {
		t.Fatal("safeRun did not recover from panic — it propagated to the caller")
	}
}

func TestSafeRun_RunsNormalFunction(t *testing.T) {
	s := &Scheduler{}
	var executed atomic.Bool

	s.safeRun("normal-job", func() {
		executed.Store(true)
	})

	if !executed.Load() {
		t.Fatal("expected normal job function to be executed")
	}
}

func TestSafeRun_RunsAfterPanic(t *testing.T) {
	s := &Scheduler{}

	// First call panics.
	s.safeRun("panic-job", func() {
		panic("first panic")
	})

	// Second call should still run normally.
	var executed atomic.Bool
	s.safeRun("normal-job", func() {
		executed.Store(true)
	})

	if !executed.Load() {
		t.Fatal("expected normal job to run after a previous panic was recovered")
	}
}

func TestSafeRun_PanicWithNilValue(t *testing.T) {
	s := &Scheduler{}

	// Panicking with nil should still be recovered.
	func() {
		defer func() {
			if r := recover(); r != nil {
				t.Fatal("safeRun did not recover from nil panic")
			}
		}()
		s.safeRun("nil-panic-job", func() {
			panic(nil)
		})
	}()
}

func TestRunEvery_NoImmediateSkipsStartupExecution(t *testing.T) {
	s := &Scheduler{}
	s.ctx, s.cancel = context.WithCancel(context.Background())
	defer s.cancel()

	var executed atomic.Int32
	go s.runEvery("delayed-job", 25*time.Millisecond, false, func() {
		executed.Add(1)
	})

	time.Sleep(10 * time.Millisecond)
	if executed.Load() != 0 {
		t.Fatalf("expected no immediate execution, got %d", executed.Load())
	}

	time.Sleep(35 * time.Millisecond)
	if executed.Load() == 0 {
		t.Fatal("expected delayed job to execute after interval")
	}
}

func TestRunEvery_ImmediateRunsOnStartup(t *testing.T) {
	s := &Scheduler{}
	s.ctx, s.cancel = context.WithCancel(context.Background())
	defer s.cancel()

	var executed atomic.Int32
	go s.runEvery("immediate-job", time.Hour, true, func() {
		executed.Add(1)
	})

	time.Sleep(10 * time.Millisecond)
	if executed.Load() == 0 {
		t.Fatal("expected immediate job execution on startup")
	}
}
