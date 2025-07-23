path="$1"
base_path_name="$(basename "$path")"
sha256="$(nix-hash --type sha256 "$path")"
temp_dir="$(mktemp -d)"
temp_file="${temp_dir}/${base_path_name}.str"
printf "source:sha256:%s:/nix/store:%s" "$sha256" "$base_path_name" > "$temp_file"
nix-hash --type sha256 --truncate --base32 --flat "$temp_file"

rm -rf "${temp_dir:?}"
