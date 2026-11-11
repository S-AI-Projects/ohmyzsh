#!/usr/bin/env zsh
# Fixture test for the git-lfs plugin. Runs in a private sandbox and never calls real git or git-lfs.
# Usage: zsh -f plugins/git-lfs/tests/git-lfs.test.zsh [path/to/git-lfs.plugin.zsh]

emulate -LR zsh

plugin=${1:-${0:A:h:h}/git-lfs.plugin.zsh}
zsh_root=${ZSH:-${0:A:h:h:h:h}}
test_dir=$(mktemp -d "${${TMPDIR:-/tmp}%/}/git-lfs-test.XXXXXX") || exit 1
orig_path=($path)
orig_pwd=$PWD
trap 'cd "$orig_pwd" 2>/dev/null || true; path=($orig_path); command rm -rf -- "$test_dir"' EXIT

export HOME=$test_dir/home ZDOTDIR=$test_dir/zdot ZSH_CACHE_DIR=$test_dir/cache
export STUB_LOG=$test_dir/args.log STUB_STATUS_FILE=$test_dir/stub_status
work_dir=$test_dir/work
command mkdir -p -- "$HOME" "$ZDOTDIR" "$ZSH_CACHE_DIR" "$test_dir/bin" "$work_dir"
print -r -- 'decoy binary bytes' >| "$work_dir/a.psd"
decoy_snapshot=$(<"$work_dir/a.psd")

# Stub git: logs argc and arguments; simulates `symbolic-ref` branch output and `lfs track` .gitattributes updates.
command cat >| "$test_dir/bin/git" <<'STUB'
#!/bin/sh
{ echo "argc=$#"; for a in "$@"; do echo "arg=$a"; done; } >> "$STUB_LOG"
status=0
if [ -r "$STUB_STATUS_FILE" ]; then
  read -r status < "$STUB_STATUS_FILE"
fi
if [ "$status" -ne 0 ]; then
  exit "$status"
fi
if [ "$1" = "symbolic-ref" ]; then
  printf '%s\n' "refs/heads/feature/login"
  exit 0
fi
if [ "$1" = "lfs" ] && [ "$2" = "track" ]; then
  # Simulated file transition for stubbed `git lfs track` (real git-lfs updates .gitattributes).
  shift 2
  for pat in "$@"; do
    printf '%s filter=lfs diff=lfs merge=lfs -text\n' "$pat" >> .gitattributes
  done
fi
exit 0
STUB
command chmod 0755 "$test_dir/bin/git" || exit 1
path=($test_dir/bin)

# Case 1: Sourcing git-lfs defines exactly 4 new aliases and leaves unrelated shell aliases untouched.
alias ll='ls -l'
typeset -i tests=0 failures=0
before_alias_count=${#aliases}
before_glfsi=${+aliases[glfsi]}
before_glfst=${+aliases[glfst]}
before_glfsls=${+aliases[glfsls]}
before_glfsmi=${+aliases[glfsmi]}
before_ll=${aliases[ll]}

source "$zsh_root/lib/git.zsh" || exit 1
source "$plugin" || exit 1

after_alias_count=${#aliases}
after_ll=${aliases[ll]:-__UNSET__}

(( tests++ ))
if [[ $before_glfsi == 0 && $before_glfst == 0 && $before_glfsls == 0 && $before_glfsmi == 0 \
   && $aliases[glfsi] == 'git lfs install' \
   && $aliases[glfst] == 'git lfs track' \
   && $aliases[glfsls] == 'git lfs ls-files' \
   && $aliases[glfsmi] == 'git lfs migrate import --include=' \
   && $(( after_alias_count - before_alias_count )) -eq 4 \
   && $after_ll == "$before_ll" ]]; then
  print -r -- 'PASS: [success] sourcing plugin adds 4 git-lfs aliases and preserves unrelated alias ll'
else
  print -r -- 'FAIL: [success] sourcing plugin adds 4 git-lfs aliases and preserves unrelated alias ll'
  (( failures++ ))
fi
print -r -- "  status: 0"
print -r -- "  state:  alias_count_before=$before_alias_count alias_count_after=$after_alias_count ll_after=${(qqq)after_ll}"

snapshot_files() {
  local -a entries
  entries=(*(DN.))
  # Sort in array context, or check exact elements deterministically across macOS/Linux locales.
  print -r -- "${(oj:,:)entries}"
}

cd "$work_dir" || exit 1

# Case 2: glfst forwards unexpanded wildcard/spaced patterns and simulated .gitattributes changes without modifying a.psd.
: >| "$STUB_LOG"
print -r -- 0 >| "$STUB_STATUS_FILE"
files_before=(*(DN.))
eval 'glfst "*.psd" "design files/*.ai"' >| "$test_dir/stdout" 2>| "$test_dir/stderr"
actual_status=$?
actual_args=$(<"$STUB_LOG")
files_after=(*(DN.))
if [[ -f "$work_dir/.gitattributes" ]]; then
  attr_after=$(<"$work_dir/.gitattributes")
else
  attr_after=''
fi
decoy_after=$(<"$work_dir/a.psd")
expected_args=$'argc=4\narg=lfs\narg=track\narg=*.psd\narg=design files/*.ai'
expected_attr=$'*.psd filter=lfs diff=lfs merge=lfs -text\ndesign files/*.ai filter=lfs diff=lfs merge=lfs -text'

(( tests++ ))
if [[ $actual_status == 0 \
   && -z $(<"$test_dir/stderr") \
   && $actual_args == "$expected_args" \
   && ${#files_before} -eq 1 && ${files_before[1]} == 'a.psd' \
   && ${#files_after} -eq 2 && -f "$work_dir/.gitattributes" && -f "$work_dir/a.psd" \
   && $attr_after == "$expected_attr" \
   && $decoy_after == "$decoy_snapshot" ]]; then
  print -r -- 'PASS: [success] glfst preserves quoted wildcards/spaces, updates .gitattributes (simulated), and leaves a.psd untouched'
else
  print -r -- 'FAIL: [success] glfst preserves quoted wildcards/spaces, updates .gitattributes (simulated), and leaves a.psd untouched'
  (( failures++ ))
fi
print -r -- "  status: $actual_status (expected 0)"
print -r -- "  stderr: ${(qqq)$(<"$test_dir/stderr")}"
print -r -- "  args:   ${(j: | :)${(f)actual_args}} (expected ${(j: | :)${(f)expected_args}})"
print -r -- "  state:  before_count=${#files_before} after_count=${#files_after} attr_created=$([[ -f "$work_dir/.gitattributes" ]] && echo yes || echo no) attr_after=${(qqq)attr_after} decoy_unchanged=$([[ $decoy_after == "$decoy_snapshot" ]] && echo yes || echo no)"

# Case 3: glfsls leaves PWD, files, and alias definitions unchanged.
: >| "$STUB_LOG"
print -r -- 0 >| "$STUB_STATUS_FILE"
pwd_before=$PWD
files_before=$(snapshot_files)
eval 'glfsls' >| "$test_dir/stdout" 2>| "$test_dir/stderr"
actual_status=$?
actual_args=$(<"$STUB_LOG")
pwd_after=$PWD
files_after=$(snapshot_files)
expected_args=$'argc=2\narg=lfs\narg=ls-files'

(( tests++ ))
if [[ $actual_status == 0 \
   && -z $(<"$test_dir/stderr") \
   && $actual_args == "$expected_args" \
   && $pwd_after == "$pwd_before" \
   && $files_after == "$files_before" ]]; then
  print -r -- 'PASS: [success] glfsls forwards lfs ls-files and leaves PWD and files unchanged'
else
  print -r -- 'FAIL: [success] glfsls forwards lfs ls-files and leaves PWD and files unchanged'
  (( failures++ ))
fi
print -r -- "  status: $actual_status (expected 0)"
print -r -- "  args:   ${(j: | :)${(f)actual_args}} (expected ${(j: | :)${(f)expected_args}})"
print -r -- "  state:  pwd_unchanged=$([[ $pwd_after == "$pwd_before" ]] && echo yes || echo no) files_before=$files_before files_after=$files_after"

# Case 4: gplfs resolves current branch via git_current_branch and pushes all refs to origin.
: >| "$STUB_LOG"
print -r -- 0 >| "$STUB_STATUS_FILE"
files_before=$(snapshot_files)
gplfs >| "$test_dir/stdout" 2>| "$test_dir/stderr"
actual_status=$?
actual_args=$(<"$STUB_LOG")
files_after=$(snapshot_files)
expected_args=$'argc=3\narg=symbolic-ref\narg=--quiet\narg=HEAD\nargc=5\narg=lfs\narg=push\narg=origin\narg=feature/login\narg=--all'

(( tests++ ))
if [[ $actual_status == 0 \
   && -z $(<"$test_dir/stderr") \
   && $actual_args == "$expected_args" \
   && $files_after == "$files_before" ]]; then
  print -r -- 'PASS: [success] gplfs resolves branch via git_current_branch and calls git lfs push origin feature/login --all'
else
  print -r -- 'FAIL: [success] gplfs resolves branch via git_current_branch and calls git lfs push origin feature/login --all'
  (( failures++ ))
fi
print -r -- "  status: $actual_status (expected 0)"
print -r -- "  args:   ${(j: | :)${(f)actual_args}}"
print -r -- "  state:  files_unchanged=$([[ $files_after == "$files_before" ]] && echo yes || echo no)"

# Case 5: glfsi returns git exit 1 when git-lfs is unavailable and preserves shell definitions and files.
: >| "$STUB_LOG"
print -r -- 1 >| "$STUB_STATUS_FILE"
typeset -A aliases_before_map aliases_after_map
aliases_before_map=("${(@kv)aliases}")
files_before=$(snapshot_files)
eval 'glfsi' >| "$test_dir/stdout" 2>| "$test_dir/stderr"
actual_status=$?
actual_args=$(<"$STUB_LOG")
aliases_after_map=("${(@kv)aliases}")
files_after=$(snapshot_files)
expected_args=$'argc=2\narg=lfs\narg=install'

(( tests++ ))
if [[ $actual_status == 1 \
   && -z $(<"$test_dir/stderr") \
   && $actual_args == "$expected_args" \
   && ${(okj:,:)aliases_after_map} == "${(okj:,:)aliases_before_map}" \
   && ${aliases_after_map[glfsi]} == "${aliases_before_map[glfsi]}" \
   && $files_after == "$files_before" ]]; then
  print -r -- 'PASS: [edge] glfsi propagates status 1 on failure and leaves aliases and files unchanged'
else
  print -r -- 'FAIL: [edge] glfsi propagates status 1 on failure and leaves aliases and files unchanged'
  (( failures++ ))
fi
print -r -- "  status: $actual_status (expected 1)"
print -r -- "  args:   ${(j: | :)${(f)actual_args}} (expected ${(j: | :)${(f)expected_args}})"
print -r -- "  state:  aliases_unchanged=$([[ ${(okj:,:)aliases_after_map} == "${(okj:,:)aliases_before_map}" ]] && echo yes || echo no) files_unchanged=$([[ $files_after == "$files_before" ]] && echo yes || echo no)"

cd "$orig_pwd" || exit 1
print -r -- "$tests tests, $failures failures"
(( tests > 0 && failures == 0 ))
