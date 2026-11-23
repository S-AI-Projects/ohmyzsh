plugin=$ZSH/plugins/bundler/bundler.plugin.zsh
T=$(mktemp -d "$TMPDIR/bundler.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p $T/bin $T/project $T/plain
log=$T/argv.log

eq() {
  if [[ "$2" == "$3" ]]; then print -r -- "PASS $1 :: [$2]"
  else print -r -- "FAIL $1 :: expected [$3] got [$2]"; fi
}

stub() {
  print -r -- '#!/bin/sh
printf "%s|" "$0" "$@" | sed "s#'$T'/bin/##g" >> '$log'
echo >> '$log'
[ -f '$T'/fail ] && { echo "'"$2"'"; exit 1; }
exit 0' > $T/bin/$1
  chmod +x $T/bin/$1
}

PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin
stub bundle "The following gems are missing"
stub rake
print 'source "https://rubygems.org"' > $T/project/Gemfile
rehash
source $plugin

cd $T/project
: > $log
eval 'ba rails'
eq "success: ba runs bundle add" "$(<$log)" "bundle|add|rails|"

: > $log
out=$(eval 'bck'); rc=$?
eq "success: bck runs bundle check" "$(<$log)" "bundle|check|"
eq "success: bck exit status" $rc 0
eq "success: bck output" "$out" ""

: > $log
eval 'bcn'
eq "success: bcn runs bundle clean" "$(<$log)" "bundle|clean|"

touch $T/fail
: > $log
out=$(eval 'bck'); rc=$?
eq "edge: missing dependency output" "$out" "The following gems are missing"
eq "edge: missing dependency exit status" $rc 1
eq "edge: missing dependency still calls bundle check once" "$(<$log)" "bundle|check|"
rm $T/fail

: > $log
eval 'rake -T spec'
eq "success: wrapped rake inside a project goes through bundle exec" "$(<$log)" "bundle|exec|rake|-T|spec|"

cd $T/plain
: > $log
eval 'rake -T spec'
eq "edge: wrapped rake outside a project runs directly" "$(<$log)" "rake|-T|spec|"

cd $T/project
rm $T/bin/bundle; rehash
: > $log
eval 'rake db:migrate'
eq "edge: wrapped rake without bundler runs directly" "$(<$log)" "rake|db:migrate|"

mkdir -p $T/project/bin
print -r -- '#!/bin/sh
echo "binstub|$@" >> '$log > $T/project/bin/rake
chmod +x $T/project/bin/rake
stub bundle
rehash
: > $log
eval 'rake test'
eq "success: binstub is preferred over bundle exec" "$(<$log)" "binstub|test"
