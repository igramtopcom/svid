package service

import (
	"strings"
	"testing"
)

func TestNormalizeCrashTitle_StripsLocalPaths(t *testing.T) {
	title := "Invalid argument(s): No host specified in URI C:/Users/Alice/AppData/Local/Temp/legacy_thumbnails/14.jpg"

	got := NormalizeCrashTitle(title)

	if got == "" {
		t.Fatal("expected normalized title to remain non-empty")
	}
	if got == title {
		t.Fatal("expected normalized title to differ from raw title")
	}
	if containsLocalPath(got) {
		t.Fatalf("expected normalized title to strip local path, got %q", got)
	}
}

func TestComputeFingerprint_IgnoresPathAndLineNoise(t *testing.T) {
	msgA := "Invalid argument(s): No host specified in URI C:/Users/Alice/AppData/Local/Temp/legacy_thumbnails/14.jpg"
	msgB := "Invalid argument(s): No host specified in URI C:/Users/Bob/AppData/Local/Temp/legacy_thumbnails/99.jpg"

	stackA := `
#0      _FileImage._loadAsync (package:flutter/src/painting/_network_image_io.dart:111:9)
#1      MultiFrameImageStreamCompleter._handleCodecReady (package:flutter/src/painting/image_stream.dart:1015:3)
#2      NewTabPage._buildThumbnail (package:snakeloader/features/browser/presentation/widgets/new_tab_page.dart:557:12)
`
	stackB := `
#0      _FileImage._loadAsync (package:flutter/src/painting/_network_image_io.dart:118:15)
#1      MultiFrameImageStreamCompleter._handleCodecReady (package:flutter/src/painting/image_stream.dart:1048:7)
#2      NewTabPage._buildThumbnail (package:snakeloader/features/browser/presentation/widgets/new_tab_page.dart:562:18)
`

	gotA := ComputeFingerprint(msgA, stackA)
	gotB := ComputeFingerprint(msgB, stackB)

	if gotA != gotB {
		t.Fatalf("expected fingerprints to match for same incident, got %q vs %q", gotA, gotB)
	}
}

func TestComputeFingerprint_DistinguishesDifferentIncidents(t *testing.T) {
	stack := `
#0      SomePlayer.play (package:snakeloader/features/player/player.dart:77:9)
#1      PlayerScreen.build (package:snakeloader/features/player/player_screen.dart:44:3)
`

	timeout := ComputeFingerprint("SocketException: connection timed out", stack)
	disposed := ComputeFingerprint("Assertion failed: [Player] has been disposed", stack)

	if timeout == disposed {
		t.Fatal("expected distinct incidents to keep distinct fingerprints")
	}
}

func TestComputeLegacyFingerprint_PreservesLegacyNoise(t *testing.T) {
	stackA := `
goroutine 31 [running]:
main.main.func1(0x7ff6aabb)
	/Users/alice/project/main.go:123 +0x42
`
	stackB := `
goroutine 98 [running]:
main.main.func1(0x7ff6ccdd)
	/Users/bob/project/main.go:999 +0x42
`

	gotA, gotB := ComputeLegacyFingerprint(stackA), ComputeLegacyFingerprint(stackB)
	if gotA == "" || gotB == "" {
		t.Fatal("expected legacy fingerprints to remain non-empty")
	}
	if gotA == gotB {
		t.Fatalf("expected legacy fingerprinting to keep old noisy behavior, got identical hashes %q", gotA)
	}
}

func containsLocalPath(value string) bool {
	lower := strings.ToLower(value)
	return strings.Contains(lower, "c:/") ||
		strings.Contains(lower, "c:\\") ||
		strings.Contains(lower, "/users/") ||
		strings.Contains(lower, "/home/") ||
		strings.Contains(lower, "/var/")
}
