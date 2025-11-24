. "${WORKSPACE:?}/src/plex/plex.sh"
init_plex yq-go

plex_set ZALUPA zalupa apulaz
log error "struct: $WHITE$(yq . "$PLEX_TEMP/ZALUPA")$NC"

plex_set ZALUPA zalupa.zalupa apulaz
