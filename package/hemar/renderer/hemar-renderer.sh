#!/bin/dash

# Hemar - Template renderer
# Parses a template file using tree-sitter and renders it with a data model

set -eu

# Colors for logging
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Global list of temp files to clean up
TEMP_FILES=""

# add_temp(path)
# Add temp file to cleanup list
add_temp() {
    local temp="$1"
    if [ -z "$TEMP_FILES" ]; then
        TEMP_FILES="$temp"
    else
        TEMP_FILES="$TEMP_FILES $temp"
    fi
}

# cleanup_temps()
cleanup_temps() {
    for f in $TEMP_FILES; do
        rm -f "$f" 2>/dev/null || true
    done
}

trap cleanup_temps EXIT INT HUP TERM

TEMPLATE="${1:-"${TEMPLATE_PATH:-}"}"
MODEL="${2:-"${MODEL:-}"}"

if [ -z "$TEMPLATE" ] || [ -z "$MODEL" ]; then
    printf "Usage: %s <template> <model.json>\n" "$0" >&2
    exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
    log error "Template file not found: ${WHITE}$TEMPLATE${NC}"
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    log error "Model file not found: ${WHITE}$MODEL${NC}"
    exit 1
fi


AST_XML=$(hemar-parser --xml "$TEMPLATE" 2>/dev/null)

AST_TEMP=$(mktemp)
MODEL_TEMP=$(mktemp)
add_temp "$AST_TEMP"
add_temp "$MODEL_TEMP"

printf '%s' "$AST_XML" > "$AST_TEMP"
cat "$MODEL" > "$MODEL_TEMP"

# extract_string_value(string_node_content)
# Extracts the actual string value from a tree-sitter string node
extract_string_value() {
    local str="$1"
    
    # Remove surrounding quotes if present
    if [ "${str#\"}" != "$str" ] && [ "${str%\"}" != "$str" ]; then
        str="${str#\"}"
        str="${str%\"}"
        # Unescape doubled quotes: "" -> "
        str=$(printf '%s' "$str" | sed 's/""/"/g')
    fi
    
    printf '%s' "$str"
}

# render_interpolation(elem_file, model_file, scope_stack)
# Renders an interpolation element {[path]}
render_interpolation() {
    local elem_file="$1"
    local model_file="$2"
    local scope_stack="$3"
    
    # Build yq path from path segments (strings and indexes)
    local num_children
    num_children=$(xmlstarlet sel -t -v 'count(/element/interpolation/path/*)' "$elem_file")
    
    log debug "Interpolation: num_path_segments=${WHITE}$num_children${NC}"
    
    if [ "$num_children" -eq "0" ]; then
        # Empty path - shouldn't happen
        printf ""
        return
    fi
    
    local yq_path=""
    local i=1
    while [ "$i" -le "$num_children" ]; do
        # Get element name (string or index) - use *[$i] to get i-th child regardless of type
        local elem_name
        elem_name=$(xmlstarlet sel -t -v "name(/element/interpolation/path/*[$i])" "$elem_file")
        
        case "$elem_name" in
            string)
                local key
                key=$(xmlstarlet sel -t -v "/element/interpolation/path/*[$i]" "$elem_file"; echo x)
                # NOTE: This is a kludge to preserve trailing newlines in command substitution
                key=${key%x}
                key=$(extract_string_value "$key")
                if [ -z "$yq_path" ]; then
                    yq_path=".\"$key\""
                else
                    yq_path="${yq_path}.\"$key\""
                fi
                ;;
            index)
                local idx
                idx=$(xmlstarlet sel -t -v "/element/interpolation/path/*[$i]/integer_index" "$elem_file")
                yq_path="${yq_path}[$idx]"
                ;;
        esac
        i=$((i + 1))
    done
    
    log debug "  yq_path: ${WHITE}$yq_path${NC}"
    log debug "  Model file: ${WHITE}$model_file${NC}"
    
    local value
    value=$(yq -r "$yq_path" "$model_file" 2>&1 || echo "ERROR")
    log debug "  Value from model: ${WHITE}[$value]${NC}"
    if [ "$value" = "null" ] || [ "$value" = "ERROR" ]; then
        printf ""
    else
        printf '%s' "$value"
    fi
}

# render_segment(elem_file, model_file, scope_stack, depth)
# Renders a for loop segment
render_segment() {
    local elem_file="$1"
    local model_file="$2"
    local scope_stack="$3"
    local depth="$4"
    
    # Extract variable name from for loop
    local var_name
    var_name=$(xmlstarlet sel -t -v '/element/segment/for/string' "$elem_file")
    var_name=$(extract_string_value "$var_name")
    log debug "For loop: var=${WHITE}$var_name${NC}"
    
    # Extract path to iterate over
    local num_strings
    num_strings=$(xmlstarlet sel -t -v 'count(/element/segment/for/path/string)' "$elem_file")
    
    # Build yq path for array
    local yq_path=""
    if [ "$num_strings" = "1" ]; then
        local key
        key=$(xmlstarlet sel -t -v '/element/segment/for/path/string' "$elem_file")
        key=$(extract_string_value "$key")
        yq_path=".\"$key\""
    elif [ "$num_strings" -gt "1" ]; then
        local i=1
        while [ "$i" -le "$num_strings" ]; do
            local key
            key=$(xmlstarlet sel -t -v "/element/segment/for/path/string[$i]" "$elem_file")
            key=$(extract_string_value "$key")
            if [ -z "$yq_path" ]; then
                yq_path=".\"$key\""
            else
                yq_path="${yq_path}.\"$key\""
            fi
            i=$((i + 1))
        done
    fi
    
    log debug "  Array path: ${WHITE}$yq_path${NC}"
    
    # Resolve array from model
    local array_json
    array_json=$(yq -r "$yq_path" "$model_file" 2>&1 || echo "ERROR")
    log debug "  Array JSON: ${WHITE}$array_json${NC}"
    
    if [ -n "$array_json" ] && [ "$array_json" != "null" ] && [ "$array_json" != "ERROR" ]; then
        local array_temp=$(mktemp)
        add_temp "$array_temp"
        printf '%s' "$array_json" > "$array_temp"
        
        local array_len
        array_len=$(yq 'length' "$array_temp" 2>/dev/null || echo "0")
        log debug "  Array length: ${WHITE}$array_len${NC}"
        
        local num_body_elements
        num_body_elements=$(xmlstarlet sel -t -v 'count(/element/segment/element)' "$elem_file")
        log debug "  Body elements: ${WHITE}$num_body_elements${NC}"
        
        local i=0
        while [ "$i" -lt "$array_len" ]; do
            log debug "  Iteration ${WHITE}$i${NC}"
            local item
            item=$(yq -o j ".[$i]" "$array_temp")
            
            # Create scoped model with variable binding
            local scoped_model=$(mktemp)
            add_temp "$scoped_model"
            yq -o j ". * {\"$var_name\": $item}" "$model_file" > "$scoped_model"
            
            # Render each body element
            local j=1
            while [ "$j" -le "$num_body_elements" ]; do
                local body_elem_xml
                body_elem_xml=$(xmlstarlet sel -t -c "/element/segment/element[$j]" "$elem_file")
                render_element "$body_elem_xml" "$scoped_model" "$scope_stack" "$((depth + 1))"
                j=$((j + 1))
            done
            
            i=$((i + 1))
        done
    else
        log debug "  No array to iterate (empty/null/error)"
    fi
}

# render_element(element_xml, model_file, scope_stack, depth?)
# Recursively renders an element
render_element() {
    local element_xml="$1"
    local model_file="$2"
    local scope_stack="$3"
    local depth="${4:-0}"
    
    local elem_temp=$(mktemp)
    add_temp "$elem_temp"
    printf '%s' "$element_xml" > "$elem_temp"
    
    # Detect element type by checking which child elements exist
    # The element structure is: <element><TYPE>...</TYPE></element>
    local has_interpolation has_segment has_text has_actual_bracket
    has_interpolation=$(xmlstarlet sel -t -v 'count(/element/interpolation)' "$elem_temp")
    has_segment=$(xmlstarlet sel -t -v 'count(/element/segment)' "$elem_temp")
    has_text=$(xmlstarlet sel -t -v 'count(/element/text)' "$elem_temp")
    has_actual_bracket=$(xmlstarlet sel -t -v 'count(/element/actual_bracket)' "$elem_temp")
    
    log debug "  Element type: text=${WHITE}$has_text${NC} interp=${WHITE}$has_interpolation${NC} seg=${WHITE}$has_segment${NC}"
    
    if [ "$has_text" != "0" ]; then
        # Plain text - output as-is (whitespace preserved!)
        # Use sentinel character 'x' to preserve trailing newlines (command substitution strips them)
        local text_content
        text_content=$(xmlstarlet sel -t -v '/element/text' "$elem_temp"; echo x)
        # NOTE: This is a kludge to preserve trailing newlines in command substitution
        text_content=${text_content%x}

        log debug "  Text content: ${WHITE}[$text_content]${NC}"
        printf '%s' "$text_content"
    elif [ "$has_interpolation" != "0" ]; then
        # Interpolation: {[path]}
        render_interpolation "$elem_temp" "$model_file" "$scope_stack"
    elif [ "$has_segment" != "0" ]; then
        # For loop: {[ for var in path ]} ... {[ done ]}
        render_segment "$elem_temp" "$model_file" "$scope_stack" "$depth"
    elif [ "$has_actual_bracket" != "0" ]; then
        # Escaped bracket: {[ {[ ]} -> output {[
        printf '{['
    fi
}

# main()
# Main rendering loop
main() {
    local num_elements
    num_elements=$(xmlstarlet sel -t -v 'count(/source_file/element)' "$AST_TEMP")
    
    log trace "Elements XML from: ${WHITE}$AST_TEMP"
    log debug "Model: ${WHITE}$(cat "$MODEL_TEMP")${NC}"

    if [ "$num_elements" = "0" ]; then
        log error "No elements found in AST"
        exit 1
    fi
    
    log debug "Rendering ${WHITE}$num_elements${NC} elements"
    
    local i=1
    while [ "$i" -le "$num_elements" ]; do
        log debug "Rendering element ${WHITE}$i${NC} of ${WHITE}$num_elements${NC}"
        # Extract element as XML and render it
        local elem_xml
        elem_xml=$(xmlstarlet sel -t -c "/source_file/element[$i]" "$AST_TEMP")
        render_element "$elem_xml" "$MODEL_TEMP" "[]" 0
        i=$((i + 1))
    done
}

if ! [ "${AS_LIBRARY+x}" ]; then
  main
fi
