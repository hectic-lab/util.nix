# FIXME: very unstable (on every request opens pager) but works somehow
{pkgs, ...}:
pkgs.writeShellScriptBin "gh-tl" ''
  set -euo pipefail

  export GH_PAGER=cat

  alias gh="${pkgs.gh}/bin/gh"
  alias jq="${pkgs.jq}/bin/gh"

  usage() {
    echo "Usage: $0 [--force] <source_repo> <target_repo>"
    echo "Options:"
    echo "  --force    Replace existing labels in the target repository."
    echo "Example:"
    echo "  $0 owner/source-repo owner/target-repo"
    echo "  $0 --force owner/source-repo owner/target-repo"
    exit 1
  }

  FORCE=0

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --force)
        FORCE=1
        shift
        ;;
      -h|--help)
        usage
        ;;
      *)
        break
        ;;
    esac
  done

  if [ "$#" -ne 2 ]; then
    usage
  fi

  SOURCE_REPO="$1"
  TARGET_REPO="$2"
  TEMP_FILE="$(mktemp)"
  trap 'rm -f "$TEMP_FILE"' EXIT

  # Check if required commands are available
  for cmd in gh jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: '$cmd' is not installed or not in PATH."
      exit 1
    fi
  done

  # Fetch all labels from the source repository with pagination
  echo "Fetching labels from $SOURCE_REPO..."

  LABELS_JSON=$(gh api -H "Accept: application/vnd.github.v3+json" \
    /repos/"$SOURCE_REPO"/labels --paginate | jq -s 'add')

  if [ -z "$LABELS_JSON" ] || [ "$LABELS_JSON" == "[]" ]; then
    echo "No labels found or an error occurred." >&2
    exit 1
  fi

  echo "$LABELS_JSON" > "$TEMP_FILE"

  # Create or update labels in the target repository
  echo "Processing labels for $TARGET_REPO..."
  jq -c '.[]' "$TEMP_FILE" | while IFS= read -r label; do
    name=$(echo "$label" | jq -r '.name')
    encoded_name=$(printf "%s" "$name" | jq -s -R -r @uri)
    color=$(echo "$label" | jq -r '.color')
    description=$(echo "$label" | jq -r '.description // ""')

    if [ "$FORCE" -eq 1 ]; then
      if update_output=$(gh api -X PATCH -H "Accept: application/vnd.github.v3+json" \
          /repos/"$TARGET_REPO"/labels/"$encoded_name" \
          -f name="$name" -f color="$color" -f description="$description" 2>&1); then
        echo "Label '$name' updated in $TARGET_REPO."
      else
        if echo "$update_output" | grep -q '"status": *"404"'; then
          echo "Label '$name' not found, creating..."
          if gh api -X POST -H "Accept: application/vnd.github.v3+json" \
              /repos/"$TARGET_REPO"/labels \
              -f name="$name" -f color="$color" -f description="$description"; then
            echo "Label '$name' created in $TARGET_REPO."
          else
            echo "Error: Failed to create label '$name'."
          fi
        else
          echo "Error: Failed to update label '$name'."
        fi
      fi
    else
      echo "Creating label '$name' in $TARGET_REPO..."
      if gh api -X POST -H "Accept: application/vnd.github.v3+json" \
          /repos/"$TARGET_REPO"/labels \
          -f name="$name" -f color="$color" -f description="$description" 1>/dev/null 2>&1; then
        echo "Label '$name' created in $TARGET_REPO."
      else
        echo "Warning: Label '$name' already exists or creation failed. Skipping."
      fi
    fi
  done

  echo "Label transfer completed successfully."
''
