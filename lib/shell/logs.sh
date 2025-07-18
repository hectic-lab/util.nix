RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
MAGENTA="$PURPLE"
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

LOG_PATH="/var/log/hectic/activation.log"

if ! mkdir -p "$(dirname "$LOG_PATH")" 2>/dev/null; then
  LOG_PATH="/dev/null"
fi

log_info()    { text=$1; shift; printf "%b ${text}%b\n" "$BLUE"   "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
log_success() { text=$1; shift; printf "%b ${text}%b\n" "$GREEN"  "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
log_warning() { text=$1; shift; printf "%b ${text}%b\n" "$YELLOW" "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
log_error()   { text=$1; shift; printf "%b ${text}%b\n" "$RED"    "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
log_step()    { text=$1; shift; printf "%b ${text}%b\n" "$PURPLE" "$@" "$NC" | tee -a "$LOG_PATH" >&2; }

log_header() { printf "\n%b=== %s ===%b\n" "$WHITE" "$@" "$NC" | tee -a "$LOG_PATH" >&2; }
