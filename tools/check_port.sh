#!/usr/bin/env bash
# Checks ported Luau game modules: load + member/G references
# (tools/check_port.luau) and the Luau linter for missing locals, misleading
# and/or ternaries, bad format strings and the like.
#   tools/check_port.sh [--strict] file.luau...
# The linter is luau-lsp's `analyze` (put the binary at build/tools/luau-lsp;
# rbx-native's build ships one in luau-lsp.zip). Type errors are ignored:
# the G-table pattern is untyped by design.
set -u
cd "$(dirname "$0")/.."
LUNE=${LUNE:-$HOME/.local/bin/lune}
LSP=${LUAU_LSP:-build/tools/luau-lsp}
status=0
"$LUNE" run tools/check_port.luau "$@" || status=1
files=()
for a in "$@"; do [ "$a" != "--strict" ] && files+=("$a"); done
if [ -x "$LSP" ]; then
	out=$("$LSP" analyze --platform standard "${files[@]}" 2>&1 |
		grep -E '\): (SyntaxError|UnknownGlobal|GlobalUsedAsLocal|BuiltinGlobalWrite|UninitializedLocal|MisleadingAndOr|FormatString|ForRange|ComparisonPrecedence|DuplicateFunction|DuplicateCondition|UnbalancedAssignment|IntegerParsing):|: TypeError: Unknown global' | sort -u)
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
