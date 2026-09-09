#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

mkdir -p "$temporary_dir/bin" "$temporary_dir/state"

reset_state() {
  echo '[{"number":50,"title":"Existing issue","body":"","pull_request":null}]' \
    > "$temporary_dir/state/issues.json"
  echo '[]' > "$temporary_dir/state/labels.json"
  echo '[]' > "$temporary_dir/state/milestones.json"
}

reset_state
: > "$temporary_dir/sleep.log"

cat > "$temporary_dir/bin/sleep" <<'MOCK_SLEEP'
#!/usr/bin/env bash

printf '%s\n' "$*" >> "${MOCK_SLEEP_LOG:?}"
MOCK_SLEEP

chmod +x "$temporary_dir/bin/sleep"

cat > "$temporary_dir/bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash

set -euo pipefail

state=${MOCK_GH_STATE:?}

if [[ "$1" == "label" && "$2" == "list" ]]; then
  cat "$state/labels.json"
  exit 0
fi

if [[ "$1" == "label" && ("$2" == "create" || "$2" == "edit") ]]; then
  action=$2
  name=$3
  shift 3
  color=
  description=
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        shift 2
        ;;
      --color)
        color=$2
        shift 2
        ;;
      --description)
        description=$2
        shift 2
        ;;
      *)
        echo "Unsupported mock gh label option: $1" >&2
        exit 1
        ;;
    esac
  done
  if [[ "$action" == "create" ]]; then
    jq --arg name "$name" --arg color "$color" --arg description "$description" \
      '. + [{name: $name, color: $color, description: $description}]' \
      "$state/labels.json" > "$state/labels.next"
  else
    jq --arg name "$name" --arg color "$color" --arg description "$description" \
      'map(if .name == $name then .color = $color | .description = $description else . end)' \
      "$state/labels.json" > "$state/labels.next"
  fi
  mv "$state/labels.next" "$state/labels.json"
  exit 0
fi

if [[ "$1" != "api" ]]; then
  echo "Unsupported mock gh invocation: $*" >&2
  exit 1
fi

shift
method=GET
input=
jq_filter=
endpoint=
title=
description=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --paginate)
      shift
      ;;
    --method)
      method=$2
      shift 2
      ;;
    --input)
      input=$2
      shift 2
      ;;
    --jq)
      jq_filter=$2
      shift 2
      ;;
    -f)
      case "$2" in
        title=*) title=${2#title=} ;;
        description=*) description=${2#description=} ;;
      esac
      shift 2
      ;;
    *)
      endpoint=$1
      shift
      ;;
  esac
done

case "$method:$endpoint" in
  GET:repos/*/issues\?*)
    cat "$state/issues.json"
    ;;
  GET:repos/*/milestones\?*)
    cat "$state/milestones.json"
    ;;
  POST:repos/*/milestones)
    number=$(($(jq 'length' "$state/milestones.json") + 1))
    created=$(jq -n \
      --argjson number "$number" \
      --arg title "$title" \
      --arg description "$description" \
      '{number: $number, title: $title, description: $description}')
    jq --argjson created "$created" '. + [$created]' "$state/milestones.json" \
      > "$state/milestones.next"
    mv "$state/milestones.next" "$state/milestones.json"
    echo "$created"
    ;;
  POST:repos/*/issues)
    number=$(jq '([.[].number] | max // 0) + 1' "$state/issues.json")
    created=$(jq --argjson number "$number" \
      '. + {number: $number, pull_request: null}' "$input")
    jq --argjson created "$created" '. + [$created]' "$state/issues.json" \
      > "$state/issues.next"
    mv "$state/issues.next" "$state/issues.json"
    if [[ "$jq_filter" == ".number" ]]; then
      echo "$number"
    else
      echo "$created"
    fi
    ;;
  PATCH:repos/*/issues/*)
    number=${endpoint##*/}
    jq --argjson number "$number" --slurpfile replacement "$input" '
      map(if .number == $number then . * $replacement[0] else . end)
    ' "$state/issues.json" > "$state/issues.next"
    mv "$state/issues.next" "$state/issues.json"
    jq --argjson number "$number" '.[] | select(.number == $number)' "$state/issues.json"
    ;;
  *)
    echo "Unsupported mock gh API invocation: $method $endpoint" >&2
    exit 1
    ;;
esac
MOCK_GH

chmod +x "$temporary_dir/bin/gh"

run_importer() {
  importer=$1
  shift
  PATH="$temporary_dir/bin:$PATH" \
    MOCK_GH_STATE="$temporary_dir/state" \
    MOCK_SLEEP_LOG="$temporary_dir/sleep.log" \
    GH_REPO="example/duplicate" \
    ASSIGNMENT_SOURCE_SHA="test-source-sha" \
    "$importer" "$@"
}

run_import() {
  run_importer "$script_dir/import-assignment-issues.sh" "$@"
}

run_import

[[ $(jq 'length' "$temporary_dir/state/issues.json") -eq 7 ]]
[[ $(jq 'length' "$temporary_dir/state/labels.json") -eq 3 ]]
[[ $(jq 'length' "$temporary_dir/state/milestones.json") -eq 1 ]]
jq -e --slurpfile manifest "$script_dir/../.assignment/manifest.json" \
  '. == $manifest[0].labels' "$temporary_dir/state/labels.json" >/dev/null
[[ $(wc -l < "$temporary_dir/sleep.log") -eq 6 ]]
! rg -v '^1$' "$temporary_dir/sleep.log" >/dev/null
jq -e '
  [ .[] | select(.number >= 51) | {number, title} ] == [
    {number: 51, title: "コードを整理し、変更・検証しやすくする"},
    {number: 52, title: "主要フローを調査し、安定させる"},
    {number: 53, title: "開発のフィードバックループを構築する"},
    {number: 54, title: "検索結果を複数ページ読み込めるようにする"},
    {number: 55, title: "利用体験を改善する"},
    {number: 56, title: "独自の価値を追加する"}
  ]
' "$temporary_dir/state/issues.json" >/dev/null
jq -e '.[] | select(.number == 52)
  | (.body | contains("### 問題: <問題の概要>"))
    and (.body | contains("- 関連するテストやコミット: <!-- 任意 -->"))
' "$temporary_dir/state/issues.json" >/dev/null
jq -e '.[] | select(.number == 52) | .body | contains("同じ問題が再発していないことを確認する自動テスト")' \
  "$temporary_dir/state/issues.json" >/dev/null
jq -e '.[] | select(.number == 54) | .body | startswith("#53 までの変更を土台として、GitHubの検索結果を複数ページ")' \
  "$temporary_dir/state/issues.json" >/dev/null
jq -e '.[] | select(.number == 53)
  | .labels == ["中級"]
    and .milestone == 1
    and (.body | contains("#51 で追加したテスト"))
    and (.body | contains("#52 で追加した回帰テスト"))
    and (.body | contains("<!-- assignment-issue-id: intermediate-development-harness -->"))
    and (.body | contains("<!-- assignment-version: swiftui-2026-09 -->"))
' \
  "$temporary_dir/state/issues.json" >/dev/null

jq 'map(if .number == 51 then .body = "Applicant edit\n\n<!-- assignment-issue-id: beginner-maintainability -->" else . end)' \
  "$temporary_dir/state/issues.json" > "$temporary_dir/state/issues.next"
mv "$temporary_dir/state/issues.next" "$temporary_dir/state/issues.json"
jq 'map(if .name == "ボーナス" then .color = "000000" | .description = "Stale description" else . end)' \
  "$temporary_dir/state/labels.json" > "$temporary_dir/state/labels.next"
mv "$temporary_dir/state/labels.next" "$temporary_dir/state/labels.json"

run_import
[[ $(jq 'length' "$temporary_dir/state/issues.json") -eq 7 ]]
jq -e '.[] | select(.number == 51) | .body | startswith("Applicant edit")' \
  "$temporary_dir/state/issues.json" >/dev/null
jq -e --slurpfile manifest "$script_dir/../.assignment/manifest.json" \
  '. == $manifest[0].labels' "$temporary_dir/state/labels.json" >/dev/null

run_import --update-existing
[[ $(jq 'length' "$temporary_dir/state/issues.json") -eq 7 ]]
jq -e '.[] | select(.number == 51) | .body | startswith("主要フローのコードを調査し")' \
  "$temporary_dir/state/issues.json" >/dev/null

jq 'map(
  if .number == 52
  then .body = "<!-- assignment-import-status: initializing -->\n<!-- assignment-issue-id: beginner-stability -->"
  else .
  end
)' "$temporary_dir/state/issues.json" > "$temporary_dir/state/issues.next"
mv "$temporary_dir/state/issues.next" "$temporary_dir/state/issues.json"

run_import
[[ $(jq 'length' "$temporary_dir/state/issues.json") -eq 7 ]]
jq -e '.[] | select(.number == 52) | .body | contains("assignment-import-status") | not' \
  "$temporary_dir/state/issues.json" >/dev/null

optional_fixture="$temporary_dir/optional-milestone"
mkdir -p "$optional_fixture/scripts"
cp "$script_dir/import-assignment-issues.sh" "$optional_fixture/scripts/"
cp -R "$script_dir/../.assignment" "$optional_fixture/.assignment"
jq '.issues = [.issues[] | select(.id == "bonus-value")] | del(.issues[0].milestone)' \
  "$optional_fixture/.assignment/manifest.json" > "$optional_fixture/manifest.next"
mv "$optional_fixture/manifest.next" "$optional_fixture/.assignment/manifest.json"

reset_state
run_importer "$optional_fixture/scripts/import-assignment-issues.sh"
jq -e '.[] | select(.number == 51) | .milestone == null' \
  "$temporary_dir/state/issues.json" >/dev/null

invalid_fixture="$temporary_dir/invalid-manifest"
mkdir -p "$invalid_fixture/scripts"
cp "$script_dir/import-assignment-issues.sh" "$invalid_fixture/scripts/"
cp -R "$script_dir/../.assignment" "$invalid_fixture/.assignment"
jq '.issues[0].id = "" | .issues[0].order = "first"' \
  "$invalid_fixture/.assignment/manifest.json" > "$invalid_fixture/manifest.next"
mv "$invalid_fixture/manifest.next" "$invalid_fixture/.assignment/manifest.json"

if run_importer "$invalid_fixture/scripts/import-assignment-issues.sh" >/dev/null 2>&1; then
  echo "Invalid manifest was accepted" >&2
  exit 1
fi

unsafe_body_fixture="$temporary_dir/unsafe-body-path"
mkdir -p "$unsafe_body_fixture/scripts"
cp "$script_dir/import-assignment-issues.sh" "$unsafe_body_fixture/scripts/"
cp -R "$script_dir/../.assignment" "$unsafe_body_fixture/.assignment"
jq '.issues[0].body = "../README.md"' \
  "$unsafe_body_fixture/.assignment/manifest.json" > "$unsafe_body_fixture/manifest.next"
mv "$unsafe_body_fixture/manifest.next" "$unsafe_body_fixture/.assignment/manifest.json"

if run_importer "$unsafe_body_fixture/scripts/import-assignment-issues.sh" >/dev/null 2>&1; then
  echo "Unsafe body path was accepted" >&2
  exit 1
fi

echo "Importer integration test passed."
