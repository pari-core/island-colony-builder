#!/bin/bash
# Runs every test in this folder and prints a summary.
# Usage, from the project folder (the one with project.godot):
#   bash tests/run_all_tests.sh
# Set GODOT to the Godot program if it is not in a standard place, for example:
#   GODOT=/Applications/Godot.app/Contents/MacOS/Godot bash tests/run_all_tests.sh
# A game window opens for each test. Do not move the mouse while they run.

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
	for candidate in /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"; do
		if [ -x "$candidate" ]; then GODOT="$candidate"; break; fi
	done
fi
if [ -z "$GODOT" ]; then
	echo "Godot not found. Set GODOT to its path." >&2
	exit 2
fi

failed=0
for test in tests/test_*.gd; do
	# perl's alarm stops a test that hangs; macOS has no "timeout" command.
	# caffeinate -d -u wakes the display and keeps it awake during the test.
	# While the display sleeps, macOS stops drawing the game window and tests that
	# wait for frames stall. It changes no settings and stops when the test ends.
	output=$(caffeinate -d -u perl -e 'alarm 300; exec @ARGV' "$GODOT" --path . --script "res://$test" 2>&1)
	result=$(echo "$output" | grep 'RESULT fails=' | tail -1)
	if [ "$result" = "RESULT fails=0" ]; then
		echo "PASS  $test"
	else
		echo "FAIL  $test  ${result:-did not finish}"
		echo "$output" | grep -E '^FAIL|SCRIPT ERROR' | sed 's/^/      /'
		failed=$((failed + 1))
	fi
done
echo
if [ "$failed" -eq 0 ]; then echo "All tests passed."; else echo "$failed test file(s) failed."; fi
exit "$failed"
