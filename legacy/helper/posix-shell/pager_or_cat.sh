pager_or_cat_init() {
  # Pipe to pager only if stdout is a terminal, otherwise output directly
  if [ -t 1 ]; then
    PAGER_OR_CAT="${PAGER:-less}"
  else
    PAGER_OR_CAT=cat
  fi
}
