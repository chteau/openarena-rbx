#!/usr/bin/env bash
# Checks ported bot modules (src/server/bot/**): each file is copied into the
# build/overlay tree (made by tools/bots-overlay.sh if missing), loaded under
# lune, its module members (BC./SB./C./S./Q./QS./BG.) checked, its B./G.
# calls checked against what botlib / the game define, and linted with
# luau-lsp for undeclared globals, and/or traps, bad format strings.
#   tools/check_bots.sh [--strict] src/server/bot/<file>.luau...
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LUNE=${LUNE:-$HOME/.local/bin/lune}
LSP=${LUAU_LSP:-/mnt/data/dev-cache/rbx-native/luau-lsp/bin/1.70.0/luau-lsp}
OV=$ROOT/build/overlay
[ -d "$OV/src/server" ] || "$ROOT/tools/bots-overlay.sh" >/dev/null
status=0
files=()
for a in "$@"; do
	[ "$a" = "--strict" ] && continue
	files+=("$a")
	mkdir -p "$OV/$(dirname "$a")"
	cp "$ROOT/$a" "$OV/$a"
done
cp "$ROOT/tools/check_bots.luau" "$OV/check_bots.luau"
(cd "$OV" && "$LUNE" run check_bots.luau "$@") || status=1
if [ -x "$LSP" ]; then
	out=$(cd "$OV" && "$LSP" analyze --platform standard "${files[@]}" 2>&1 |
		grep -E '\): (SyntaxError|UnknownGlobal|GlobalUsedAsLocal|BuiltinGlobalWrite|UninitializedLocal|MisleadingAndOr|FormatString|ForRange|ComparisonPrecedence|DuplicateFunction|DuplicateCondition|UnbalancedAssignment|IntegerParsing|LocalShadow|FunctionUnused|UnreachableCode):|: TypeError: Unknown global' |
		grep -vE 'LocalShadow|FunctionUnused|UnreachableCode' | sort -u)
	if [ -n "$out" ]; then
		echo "$out"
		echo "lint: $(echo "$out" | wc -l) problem(s)"
		status=1
	else
		echo "lint: clean"
	fi
else
	echo "lint: skipped ($LSP not found)"
fi
exit $status
