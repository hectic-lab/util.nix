. "${WORKSPACE:?}/src/plex/plex.sh"
init_plex yq-go

plex_set ZALUPA zalupa apulaz
log error "struct:\n$WHITE$(yq . "$PLEX_TEMP/ZALUPA.json")$NC"

plex_set ZALUPA kek.zalupa apulaz

log error "struct:\n$WHITE$(yq . "$PLEX_TEMP/ZALUPA.json")$NC"

plex_set ZALUPA zalupa apulaz

log error "struct:\n$WHITE$(yq . "$PLEX_TEMP/ZALUPA.json")$NC"

plex_val ZALUPA zalupa

plex_child ZALUPA kek

plex_fetch ZALUPA kek
