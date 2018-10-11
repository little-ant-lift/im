BASE=`git describe --tags --match="[0-9]*.[0-9]*" --abbrev=0 2>/dev/null || echo 0.0]`
COMMIT=`git rev-list  ${BASE}..HEAD | wc -l`
COMMIT_NO_WHITESPACE="$(echo -e "${COMMIT}" | tr -d '[[:space:]]')"
echo $BASE.$COMMIT_NO_WHITESPACE
