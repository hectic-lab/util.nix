# FIXME: very unstable (on every request opens pager) but works somehow
{ pkgs, ... }:
pkgs.writeShellScriptBin "gh_translabeles" ''
  set -euo pipefail

  # Function to display usage information
  usage() {
    echo "Usage: $0 [--force] <source_repo> <target_repo>"
    echo "Options:"
    echo "  --force    Replace existing labels in the target repository."
    echo "Example:"
    echo "  $0 owner/source-repo owner/target-repo"
    echo "  $0 --force owner/source-repo owner/target-repo"
    exit 1
  }

  # Initialize variables
  FORCE=0

  # Parse options
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

  # Check for required arguments
  if [ "$#" -ne 2 ]; then
    usage
  fi

  SOURCE_REPO="$1"
  TARGET_REPO="$2"
  TEMP_FILE="$(mktemp)"
  trap 'rm -f "$TEMP_FILE"' EXIT

  # Check if required commands are available
  for cmd in ${pkgs.gh}/bin/gh ${pkgs.jq}/bin/jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "Error: '$cmd' is not installed or not in PATH."
      exit 1
    fi
  done

  # Fetch all labels from the source repository with pagination
  echo "Fetching labels from $SOURCE_REPO..."
  
  LABELS_JSON=$(${pkgs.gh}/bin/gh api -H "Accept: application/vnd.github.v3+json" \
    /repos/"$SOURCE_REPO"/labels --paginate | ${pkgs.jq}/bin/jq -s 'add')

  if [ -z "$LABELS_JSON" ] || [ "$LABELS_JSON" == "[]" ]; then
    echo "No labels found or an error occurred." >&2
    exit 1
  fi

  echo "$LABELS_JSON" > "$TEMP_FILE"

  # Create or update labels in the target repository
  echo "Processing labels for $TARGET_REPO..."
  ${pkgs.jq}/bin/jq -c '.[]' "$TEMP_FILE" | while IFS= read -r label; do
    name=$(echo "$label" | ${pkgs.jq}/bin/jq -r '.name')
    encoded_name=$(echo "$name" | ${pkgs.jq}/bin/jq -s -R -r @uri)
    color=$(echo "$label" | ${pkgs.jq}/bin/jq -r '.color')
    description=$(echo "$label" | ${pkgs.jq}/bin/jq -r '.description // ""')

    if [ "$FORCE" -eq 1 ]; then
      echo "Creating or updating label '$name' in $TARGET_REPO..."
      if ! ${pkgs.gh}/bin/gh api -X PATCH -H "Accept: application/vnd.github.v3+json" \
          /repos/"$TARGET_REPO"/labels/"$encoded_name" \
          -f name="$name" -f color="$color" -f description="$description"; then
        echo "Error: Failed to create/update label '$name'. Skipping."
      else
        echo "Label '$name' has been created/updated in $TARGET_REPO."
      fi
    else
      if ${pkgs.gh}/bin/gh api -H "Accept: application/vnd.github.v3+json" \
        /repos/"$TARGET_REPO"/labels/"$encoded_name" &>/dev/null; then
        echo "Label '$name' already exists in $TARGET_REPO. Skipping."
      else
        echo "Creating label '$name' in $TARGET_REPO..."
        if ! ${pkgs.gh}/bin/gh api -X POST -H "Accept: application/vnd.github.v3+json" \
            /repos/"$TARGET_REPO"/labels \
            -f name="$name" -f color="$color" -f description="$description"; then
          echo "Warning: Label '$name' already exists or failed to create. Skipping."
        else
          echo "Label '$name' has been created in $TARGET_REPO."
        fi
      fi
    fi
  done

  echo "Label transfer completed successfully."
''
