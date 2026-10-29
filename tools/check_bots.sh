#!/usr/bin/env bash
# Checks ported bot modules (src/server/bot/**): each file is loaded under
# lune, its module members (BC./SB./C./S./Q./QS./BG.) checked, its B./G.
# calls checked against what botlib / the game define, and linted with
# luau-lsp for undeclared globals, and/or traps, bad format strings.
#   tools/check_bots.sh [--strict] src/server/bot/<file>.luau...
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LUNE=${LUNE:-$HOME/.local/bin/lune}
LSP=${LUAU_LSP:-/mnt/data/dev-cache/rbx-native/luau-lsp/bin/1.70.0/luau-lsp}
cd "$ROOT"
status=0
files=()
for a in "$@"; do [ "$a" != "--strict" ] && files+=("$a"); done
"$LUNE" run tools/check_bots.luau "$@" || status=1
if [ -x "$LSP" ]; then
	out=$("$LSP" analyze --platform standard "${files[@]}" 2>&1 |
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
