command -v swiftformat >/dev/null 2>&1 || {
  echo >&2 "swiftformat needs to be installed but is not available in the path."
  exit 1
}

printf "=> Checking format... "
FIRST_OUT="$(git status --porcelain)"
swiftformat . >/dev/null 2>&1
SECOND_OUT="$(git status --porcelain)"
if [[ "$FIRST_OUT" != "$SECOND_OUT" ]]; then
  printf "\033[0;31mformatting issues!\033[0m\n"
  git --no-pager diff
  exit 1
else
  printf "\033[0;32mokay.\033[0m\n"
fi
