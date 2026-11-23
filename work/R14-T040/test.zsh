plugin=${DASH_PLUGIN:-$ZSH/plugins/dash/dash.plugin.zsh}
T=$(mktemp -d "$TMPDIR/dash.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p $T/bin
PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [$2]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

source $ZSH/lib/functions.zsh
opened=""
open() { opened="$*" }
compdef() { :; }
source $plugin

dash python:tuple
eq "success: keyword query is url-encoded" "$opened" "-a Dash.app dash://python%3Atuple"
dash golang
eq "success: plain query" "$opened" "-a Dash.app dash://golang"
dash
eq "success: no query only opens the app" "$opened" "-a Dash.app dash://"
dash go lang
eq "edge: words are joined with a plus" "$opened" "-a Dash.app dash://go+lang"

added=""
compadd() { added="$*" }
plist=""
defaults() {
  print -r -- "defaults|$*" >> $T/defaults.log
  print -r -- "$plist"
}

plist='(
    {
        docsetName = "Python 3";
        isEnabled = 1;
        platform = python;
    }
)'
CURRENT=2; words=(dash py)
added=none; : > $T/defaults.log
_dash
eq "success: completes the keyword in position 2" "$added" "-qS: -- python3"
eq "success: reads the docset preferences once" "$(<$T/defaults.log)" "defaults|read com.kapeli.dashdoc docsets"

plist='(
    {
        docsetName = "Python 2";
        isEnabled = 1;
        keyword = py2;
        platform = python;
    }
)'
added=none; _dash
eq "success: explicit keyword wins over platform" "$added" "-qS: -- py2"

added=none; CURRENT=3; words=(dash py x)
_dash
eq "edge: nothing is completed in position 3" "$added" none

added=none; CURRENT=2; words=(dash python:t)
_dash
eq "edge: nothing is completed once a keyword is typed" "$added" none

added=none; CURRENT=1; words=(dash)
_dash
eq "edge: nothing is completed in position 1" "$added" none

plist='(
    {
        docsetName = "Python 3";
        isEnabled = 0;
        platform = python;
    }
)'
added=none; CURRENT=2; words=(dash py)
_dash
eq "edge: disabled docsets offer no keywords" "$added" "-qS: --"
