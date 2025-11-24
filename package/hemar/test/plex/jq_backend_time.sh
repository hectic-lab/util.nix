#!/bin/dash

# shellcheck disable=SC1091
. "${WORKSPACE:?}/src/plex/plex.sh"
init_plex yq-go

math() {
  awk "BEGIN {print $1}"
}

elapsed() {
  local task time count decrease avg
  task=$1
  time=$2
  count=$3
  decrease=${4:-0}
  avg=$(math "$time/$count-$decrease")

  if [ "$time" -eq 0 ]; then
    log info "\n[$WHITE${task}$NC]\ninstant\n"
  else
    log info "\n[$WHITE${task}$NC]\nelapsed $WHITE${avg}$NC seconds\n$WHITE$(math "1/$avg")$NC per second\n"
  fi
  printf '%s' "$avg"
}

set_word_length() {
  local length
  length=${1:?}

  # shellcheck disable=SC2183
  __WORD_OFFSET_PATERN="$(printf '%*s' "$length" | tr ' ' '?')"
}

UNIQ_8_WORDS_COUNT=1000
DEFAULT_WORD_LENGTH=8
set_word_length "$DEFAULT_WORD_LENGTH"

randomword() {
  local length
  length=${1:-$DEFAULT_WORD_LENGTH}
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

WORDS=$(randomword $((8 * UNIQ_8_WORDS_COUNT)))
WORDS=0123456789abcdefg

new_word() {
  local prefix
  # shellcheck disable=SC2295
  prefix=${WORDS%"${WORDS#${__WORD_OFFSET_PATERN:?}}"}
  # shellcheck disable=SC2295
  WORDS=${WORDS#${__WORD_OFFSET_PATERN:?}}$prefix
  printf '%s' "$prefix"
}

bench_set() {
  local task depth count wordtime i start key d end
  task=$1
  depth=$2
  count=$3
  wordtime=$4
  i=0
  start=$(date +%s)
  while [ "$i" -lt "$count" ]; do
    key=$(new_word)
    if [ "$depth" -gt 1 ]; then
      d=1
      while [ "$d" -lt "$depth" ]; do
        key="$key.$(new_word)"
        d=$((d + 1))
      done
    fi
    set +e
    plex_set 'MY_STRUCT' "$key" "$i"
    error_code=$?
    log warning "error_code: $error_code"
    set -e
    if [ $error_code != 0 ]; then
	log error "key: $WHITE$key$NC, i: $WHITE$i$NC, struct: $WHITE$(jq . "$PLEX_TEMP/MY_STRUCT")$NC"
	exit 1
    fi

    i=$((i + 1))
  done
  end=$(date +%s)
  elapsed "$task" "$((end - start))" "$count" "$(math "$wordtime*$depth")" >/dev/null
}

DEFAULT_TRIES=1000
ACCURATE_TRIES=10000
SUPPER_ACCURATE_TRIES=100000

WORD_CREATE_ACCURACY="$SUPPER_ACCURATE_TRIES"
BENCH_ACCURACY="$DEFAULT_TRIES"

count="$WORD_CREATE_ACCURACY"
set_word_length 8
i=0
start=$(date +%s)
while [ "$i" -lt "${count:?}" ]; do
  new_word >/dev/null
  i=$((i + 1))
done
end=$(date +%s)
time=$((end - start))
log debug "word creation time: $time"
wordtime=$(elapsed 'Word creation' "$time" "$count")

bench_set 'Set element with depth 1 length 8' 1 "$BENCH_ACCURACY" "$wordtime"
bench_set 'Set element with depth 2 length 8' 2 "$BENCH_ACCURACY" "$wordtime"
bench_set 'Set element with depth 3 length 8' 3 "$BENCH_ACCURACY" "$wordtime"

log notice -

count="$WORD_CREATE_ACCURACY"
set_word_length 2
i=0
start=$(date +%s)
while [ "$i" -lt "${count:?}" ]; do
  new_word >/dev/null
  i=$((i + 1))
done
end=$(date +%s)
wordtime=$(elapsed 'Word creation' "$((end - start))" "$count")

bench_set 'Set element with depth 1 length 2' 1 "$BENCH_ACCURACY" "$wordtime"
bench_set 'Set element with depth 2 length 2' 2 "$BENCH_ACCURACY" "$wordtime"
bench_set 'Set element with depth 3 length 2' 3 "$BENCH_ACCURACY" "$wordtime"
