#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/import-assignment-issues.sh [--repo OWNER/REPO] [--update-existing]

Imports the versioned assignment issue definitions into a GitHub repository.
Existing finalized issues are preserved unless --update-existing is specified.
USAGE
}

target_repo="${GH_REPO:-}"
update_existing=false
issue_creation_delay_seconds="${ISSUE_CREATION_DELAY_SECONDS:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "--repo requires OWNER/REPO" >&2; exit 2; }
      target_repo="$2"
      shift 2
      ;;
    --update-existing)
      update_existing=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$issue_creation_delay_seconds" =~ ^[0-9]+$ ]] || {
  echo "ISSUE_CREATION_DELAY_SECONDS must be a non-negative integer" >&2
  exit 2
}

for command in gh git jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd "$script_dir/.." && pwd)
manifest="$repository_root/.assignment/manifest.json"

jq -e '
  def nonempty_string:
    if type == "string" then length > 0 else false end;
  def label_color:
    if type == "string" then test("^[0-9A-Fa-f]{6}$") else false end;
  def issue_body_path:
    if type == "string" then test("^issues/[A-Za-z0-9][A-Za-z0-9._-]*\\.md$") else false end;

  .schema_version == 1
  and (.assignment_version | nonempty_string)
  and (.labels | type == "array")
  and all(.labels[]?; (.name? | nonempty_string) and (.color? | label_color) and ((.description? | type) == "string"))
  and (.milestones | type == "array")
  and all(.milestones[]?; (.title? | nonempty_string) and ((.description? | type) == "string"))
  and (.issues | type == "array")
  and all(.issues[]?;
    (.id? | nonempty_string)
    and ((.order? | type) == "number")
    and (.title? | nonempty_string)
    and (.body? | issue_body_path)
    and (.labels? | type == "array")
    and all(.labels[]?; nonempty_string)
    and ((.milestone? == null) or (.milestone | nonempty_string))
  )
  and ([.issues[]? | .id?] | length == (unique | length))
  and ([.issues[]? | .order?] | length == (unique | length))
' "$manifest" >/dev/null || {
  echo "Invalid assignment manifest: $manifest" >&2
  exit 1
}

while IFS= read -r issue; do
  id=$(jq -r '.id' <<< "$issue")
  body_path="$repository_root/.assignment/$(jq -r '.body' <<< "$issue")"
  [[ -f "$body_path" ]] || {
    echo "Body file for '$id' does not exist: $body_path" >&2
    exit 1
  }

  while IFS= read -r reference; do
    referenced_id=${reference#\{\{issue:}
    referenced_id=${referenced_id%\}\}}
    jq -e --arg id "$referenced_id" '[.issues[].id] | index($id) != null' "$manifest" >/dev/null || {
      echo "Unknown issue link '$referenced_id' in $body_path" >&2
      exit 1
    }
  done < <(grep -o '{{issue:[a-z0-9-]*}}' "$body_path" || true)

  while IFS= read -r label; do
    jq -e --arg name "$label" '[.labels[].name] | index($name) != null' "$manifest" >/dev/null || {
      echo "Unknown label '$label' for issue '$id'" >&2
      exit 1
    }
  done < <(jq -r '.labels[]' <<< "$issue")

  milestone=$(jq -r '.milestone // empty' <<< "$issue")
  if [[ -n "$milestone" ]]; then
    jq -e --arg title "$milestone" '[.milestones[].title] | index($title) != null' "$manifest" >/dev/null || {
      echo "Unknown milestone '$milestone' for issue '$id'" >&2
      exit 1
    }
  fi
done < <(jq -c '.issues[]' "$manifest")

if [[ -z "$target_repo" ]]; then
  target_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

if [[ "$target_repo" == "yumemi-inc/ios-engineer-codecheck" ]]; then
  echo "Refusing to import into the assignment source repository." >&2
  exit 1
fi

assignment_version=$(jq -r '.assignment_version' "$manifest")
source_sha="${ASSIGNMENT_SOURCE_SHA:-$(git -C "$repository_root" rev-parse HEAD)}"
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

issues_cache="$temporary_dir/issues.json"
milestones_cache="$temporary_dir/milestones.json"
mapping="$temporary_dir/mapping.json"
finalize_ids="$temporary_dir/finalize-ids"

echo '{}' > "$mapping"
: > "$finalize_ids"

echo "Importing assignment $assignment_version ($source_sha) into $target_repo"

gh api --paginate "repos/$target_repo/issues?state=all&per_page=100" \
  | jq -s 'add | map(select(.pull_request == null))' > "$issues_cache"
gh api --paginate "repos/$target_repo/milestones?state=all&per_page=100" \
  | jq -s 'add' > "$milestones_cache"

existing_labels=$(gh label list --repo "$target_repo" --limit 1000 --json name,color,description)
while IFS= read -r label; do
  name=$(jq -r '.name' <<< "$label")
  color=$(jq -r '.color' <<< "$label")
  description=$(jq -r '.description' <<< "$label")
  existing_label=$(jq -c --arg name "$name" '.[] | select(.name == $name)' <<< "$existing_labels")
  if [[ -z "$existing_label" ]]; then
    gh label create "$name" \
      --repo "$target_repo" \
      --color "$color" \
      --description "$description"
    existing_labels=$(jq --argjson label "$label" '. + [$label]' <<< "$existing_labels")
    echo "Created label: $name"
  elif ! jq -e \
    --arg color "$color" \
    --arg description "$description" \
    '(.color | ascii_downcase) == ($color | ascii_downcase) and (.description // "") == $description' \
    <<< "$existing_label" >/dev/null; then
    gh label edit "$name" \
      --repo "$target_repo" \
      --color "$color" \
      --description "$description"
    existing_labels=$(jq --argjson label "$label" \
      'map(if .name == $label.name then $label else . end)' <<< "$existing_labels")
    echo "Updated label: $name"
  fi
done < <(jq -c '.labels[]' "$manifest")

while IFS= read -r milestone; do
  title=$(jq -r '.title' <<< "$milestone")
  number=$(jq -r --arg title "$title" '.[] | select(.title == $title) | .number' "$milestones_cache" | head -n 1)
  if [[ -z "$number" ]]; then
    created=$(gh api --method POST "repos/$target_repo/milestones" \
      -f title="$title" \
      -f description="$(jq -r '.description' <<< "$milestone")")
    number=$(jq -r '.number' <<< "$created")
    jq --argjson milestone "$created" '. + [$milestone]' "$milestones_cache" \
      > "$milestones_cache.next"
    mv "$milestones_cache.next" "$milestones_cache"
    echo "Created milestone: $title"
  fi
done < <(jq -c '.milestones[]' "$manifest")

while IFS= read -r issue; do
  id=$(jq -r '.id' <<< "$issue")
  title=$(jq -r '.title' <<< "$issue")
  marker="<!-- assignment-issue-id: $id -->"
  matches=$(jq --arg marker "$marker" '[.[] | select((.body // "") | contains($marker))]' "$issues_cache")
  match_count=$(jq 'length' <<< "$matches")

  if [[ "$match_count" -gt 1 ]]; then
    echo "Multiple issues use assignment id '$id'; resolve the duplicate before retrying." >&2
    exit 1
  fi

  if [[ "$match_count" -eq 1 ]]; then
    number=$(jq -r '.[0].number' <<< "$matches")
    body=$(jq -r '.[0].body // ""' <<< "$matches")
    if [[ "$update_existing" == true ]] || [[ "$body" == *"<!-- assignment-import-status: initializing -->"* ]]; then
      echo "$id" >> "$finalize_ids"
    else
      echo "Preserving existing issue #$number: $title"
    fi
  else
    milestone_title=$(jq -r '.milestone // empty' <<< "$issue")
    milestone_json=null
    if [[ -n "$milestone_title" ]]; then
      milestone_number=$(jq -r --arg title "$milestone_title" \
        '.[] | select(.title == $title) | .number' "$milestones_cache" | head -n 1)
      [[ -n "$milestone_number" ]] || {
        echo "Milestone '$milestone_title' was not found for issue '$id'" >&2
        exit 1
      }
      milestone_json="$milestone_number"
    fi
    labels=$(jq '.labels' <<< "$issue")
    initializer="$temporary_dir/$id.initial.md"
    payload="$temporary_dir/$id.create.json"

    {
      echo '<!-- assignment-import-status: initializing -->'
      echo "$marker"
      echo "<!-- assignment-version: $assignment_version -->"
      echo "<!-- assignment-source-sha: $source_sha -->"
    } > "$initializer"

    jq -n \
      --arg title "$title" \
      --rawfile body "$initializer" \
      --argjson labels "$labels" \
      --argjson milestone "$milestone_json" \
      '{title: $title, body: $body, labels: $labels, milestone: $milestone}' \
      > "$payload"

    number=$(gh api --method POST "repos/$target_repo/issues" --input "$payload" --jq '.number')
    echo "$id" >> "$finalize_ids"
    echo "Created issue #$number: $title"
    if (( issue_creation_delay_seconds > 0 )); then
      sleep "$issue_creation_delay_seconds"
    fi
  fi

  jq --arg id "$id" --argjson number "$number" '. + {($id): $number}' "$mapping" \
    > "$mapping.next"
  mv "$mapping.next" "$mapping"
done < <(jq -c '.issues | sort_by(.order)[]' "$manifest")

while IFS= read -r id; do
  issue=$(jq -c --arg id "$id" '.issues[] | select(.id == $id)' "$manifest")
  number=$(jq -r --arg id "$id" '.[$id]' "$mapping")
  title=$(jq -r '.title' <<< "$issue")
  body_path="$repository_root/.assignment/$(jq -r '.body' <<< "$issue")"
  milestone_title=$(jq -r '.milestone // empty' <<< "$issue")
  milestone_json=null
  if [[ -n "$milestone_title" ]]; then
    milestone_number=$(jq -r --arg title "$milestone_title" \
      '.[] | select(.title == $title) | .number' "$milestones_cache" | head -n 1)
    [[ -n "$milestone_number" ]] || {
      echo "Milestone '$milestone_title' was not found for issue '$id'" >&2
      exit 1
    }
    milestone_json="$milestone_number"
  fi
  labels=$(jq '.labels' <<< "$issue")
  resolved_body="$temporary_dir/$id.body.md"
  payload="$temporary_dir/$id.update.json"

  jq -Rs --slurpfile mapping "$mapping" '
    reduce ($mapping[0] | to_entries[]) as $entry
      (. ; split("{{issue:" + $entry.key + "}}") | join("#" + ($entry.value | tostring)))
  ' "$body_path" > "$resolved_body.json"
  jq -r '.' "$resolved_body.json" > "$resolved_body"

  if grep -q '{{issue:' "$resolved_body"; then
    echo "Unresolved issue link in $body_path" >&2
    exit 1
  fi

  {
    echo
    echo "<!-- assignment-issue-id: $id -->"
    echo "<!-- assignment-version: $assignment_version -->"
    echo "<!-- assignment-source-sha: $source_sha -->"
  } >> "$resolved_body"

  jq -n \
    --arg title "$title" \
    --rawfile body "$resolved_body" \
    --argjson labels "$labels" \
    --argjson milestone "$milestone_json" \
    '{title: $title, body: $body, labels: $labels, milestone: $milestone}' \
    > "$payload"

  gh api --method PATCH "repos/$target_repo/issues/$number" --input "$payload" >/dev/null
  echo "Finalized issue #$number: $title"
done < "$finalize_ids"

echo "Assignment issue import completed."
