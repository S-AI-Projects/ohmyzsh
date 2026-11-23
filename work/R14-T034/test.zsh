plugin=$ZSH/plugins/node/node.plugin.zsh
T=$(mktemp -d "$TMPDIR/node.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/dir with space"

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [$2]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

print -r -- '#!/bin/sh
echo v22.1.0' > "$T/bin/node"
chmod +x "$T/bin/node"
PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin

opened=()
open_command() { opened=("$@") }

source $plugin

cd "$T/dir with space"
touch fs-a.html fs-b.html other.txt
before="$(print -r -- *)"

node-docs
eq "success: default section argument count" ${#opened} 1
eq "success: default section url" "$opened[1]" "https://nodejs.org/docs/v22.1.0/api/all.html"

node-docs fs
eq "success: named section url" "$opened[1]" "https://nodejs.org/docs/v22.1.0/api/fs.html"

node-docs 'fs*'
eq "edge: wildcard stays one argument" ${#opened} 1
eq "edge: wildcard is not expanded" "$opened[1]" 'https://nodejs.org/docs/v22.1.0/api/fs*.html'

node-docs 'path with space'
eq "edge: spaced section stays one argument" ${#opened} 1
eq "edge: spaced section is passed verbatim" "$opened[1]" 'https://nodejs.org/docs/v22.1.0/api/path with space.html'

eq "edge: files in the spaced directory are untouched" "$(print -r -- *)" "$before"
eq "edge: directory listing is unchanged" "$(print -r -- *)" "fs-a.html fs-b.html other.txt"
