{pkgs, ...}:
pkgs.writeShellScriptBin "unpack" ''
  #!/usr/bin/env sh
  set -e

  # Determine the Git repository root or default to current directory
  GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

  SILENT=false
  AUTO_YES=false
  ZIPFILE=

  # Save the user's original directory
  ORIGINAL_DIR="$(pwd)"

  # Check if the user is inside the 'web' directory or any of its subdirectories
  RELATIVE_PATH="$(realpath --relative-to="$GIT_ROOT" "$ORIGINAL_DIR")"

  IN_WEB=false
  if [ "$RELATIVE_PATH" = "web" ] || echo "$RELATIVE_PATH" | grep -qE '^web(/|$)'; then
    IN_WEB=true
    # Change to the Git root to safely remove 'web' directory
    cd "$GIT_ROOT"
  fi

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes)
        AUTO_YES=true
        shift
        ;;
      -S|--silent)
        SILENT=true
        shift
        ;;
      *)
        ZIPFILE="$1"
        shift
        ;;
    esac
  done

  # Function to print usage
  print_usage() {
    echo "Usage: $0 [-y|--yes] [-S|--silent] <file.zip>"
  }

  # Check if ZIPFILE is provided
  if [ -z "$ZIPFILE" ]; then
    if [ "$SILENT" = false ]; then
      print_usage
    fi
    # If the user was inside 'web', attempt to return
    if [ "$IN_WEB" = true ]; then
      if [ -d "$ORIGINAL_DIR" ]; then
        cd "$ORIGINAL_DIR"
      else
        cd "$GIT_ROOT"
      fi
    fi
    exit 1
  fi

  # Define paths relative to GIT_ROOT
  WEB_DIR="$GIT_ROOT/web"
  SUPABASE_DIR="$WEB_DIR/supabase"
  TMP_DIR="$(mktemp -d)"
  SRC_PROJECT_DIR="$TMP_DIR/project"
  SRC_CONFIG="$GIT_ROOT/supabase/config.toml"
  DEST_CONFIG="$SUPABASE_DIR/config.toml"

  # Check if 'web' directory exists
  if [ -d "$WEB_DIR" ]; then
    if [ "$AUTO_YES" = false ]; then
      if [ "$SILENT" = false ]; then
        echo "Remove existing 'web' directory at $WEB_DIR? (y/N)"
        read ans
        if [ "$ans" != "y" ] && [ "$ans" != "Y" ]; then
          # If user declined and was inside 'web', attempt to return
          if [ "$IN_WEB" = true ]; then
            if [ -d "$ORIGINAL_DIR" ]; then
              cd "$ORIGINAL_DIR"
            else
              cd "$GIT_ROOT"
            fi
          fi
          exit 1
        fi
      else
        # In silent mode without confirmation
        # If user was inside 'web', attempt to return
        if [ "$IN_WEB" = true ]; then
          if [ -d "$ORIGINAL_DIR" ]; then
            cd "$ORIGINAL_DIR"
          else
            cd "$GIT_ROOT"
          fi
        fi
        exit 1
      fi
    fi
    rm -rf "$WEB_DIR"
  fi

  # Create a temporary directory for unpacking
  trap 'rm -rf "$TMP_DIR"' EXIT

  # Unzip the provided ZIPFILE into the temporary directory
  ${pkgs.unzip}/bin/unzip -q "$ZIPFILE" -d "$TMP_DIR"

  # Move the 'project' directory to 'web' within GIT_ROOT
  mv "$SRC_PROJECT_DIR" "$WEB_DIR"

  cd "$WEB_DIR"
  ${pkgs.nodejs_22}/bin/npm isntall

  # Handle the config.toml file
  if [ ! -f "$SRC_CONFIG" ]; then
    if [ "$SILENT" = false ]; then
      echo "Source config.toml not found at $SRC_CONFIG. Skipping copy."
    fi
  else
    if [ -f "$DEST_CONFIG" ]; then
      if [ "$AUTO_YES" = true ]; then
        cp "$SRC_CONFIG" "$DEST_CONFIG"
        if [ "$SILENT" = false ]; then
          echo "Overwritten existing config.toml at $DEST_CONFIG."
        fi
      elif [ "$SILENT" = false ]; then
        echo "config.toml already exists at $DEST_CONFIG. Overwrite? (y/N)"
        read ans
        if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
          cp "$SRC_CONFIG" "$DEST_CONFIG"
          echo "Overwritten existing config.toml."
        else
          echo "Skipped copying config.toml."
        fi
      fi
      # In silent mode without AUTO_YES, skip copying
    else
      # Destination config.toml does not exist; proceed to copy
      cp "$SRC_CONFIG" "$DEST_CONFIG"
      if [ "$SILENT" = false ]; then
        echo "Copied config.toml to $DEST_CONFIG."
      fi
    fi
  fi

  if [ "$SILENT" = false ]; then
    echo "Directory 'web' created at $WEB_DIR."
  fi

  # Return to the original directory if the user was inside 'web'
  #if [ "$IN_WEB" = true ]; then
  #  if [ -d "$ORIGINAL_DIR" ]; then
  #    cd "$ORIGINAL_DIR"
  #    echo "Returned you to the original directory $ORIGINAL_DIR."
  #  else
  #    cd "$GIT_ROOT"
  #    echo "Original directory $ORIGINAL_DIR does not exist. Now in $GIT_ROOT."
  #  fi
  #fi
''
