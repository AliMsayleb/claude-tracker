failures=0

check() {
  if [ "$2" = "$3" ]; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    echo "     expected: $2"
    echo "     actual:   $3"
    failures=$((failures + 1))
  fi
}

finish() {
  if [ "$failures" -eq 0 ]; then
    echo "all passed"
  else
    echo "$failures failed"
    exit 1
  fi
}

seconds_since() {
  echo $(( $(date +%s) - $1 ))
}
