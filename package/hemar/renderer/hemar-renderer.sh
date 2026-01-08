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

# Add temp file to cleanup list
add_temp() {
    local temp="$1"
    if [ -z "$TEMP_FILES" ]; then
        TEMP_FILES="$temp"
    else
        TEMP_FILES="$TEMP_FILES $temp"
    fi
}

# Cleanup function
cleanup_temps() {
    for f in $TEMP_FILES; do
        rm -f "$f" 2>/dev/null || true
    done
}

# Set up trap for cleanup
trap cleanup_temps EXIT INT HUP TERM

# Parse command line arguments
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


# Parse template with tree-sitter and convert to JSON
# Requires: tree-sitter, yq
AST_JSON=$(hemar-parser --xml "$TEMPLATE" 2>/dev/null | yq -p=xml -o=json)

# Save to temp files for yq processing
AST_TEMP=$(mktemp)
MODEL_TEMP=$(mktemp)
add_temp "$AST_TEMP"
add_temp "$MODEL_TEMP"

printf '%s' "$AST_JSON" > "$AST_TEMP"
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

# resolve_path(path_json, model, scope_stack)
# Resolves a path in the data model
# path_json: JSON object representing path node from AST (with .string field)
# model: the data model
# scope_stack: JSON array of loop scopes (for nested loops)
resolve_path() {
    local path_json="$1"
    local model_file="$2"
    local scope_stack="$3"
    
    local path_temp=$(mktemp)
    add_temp "$path_temp"
    printf '%s' "$path_json" > "$path_temp"
    
    # Check if path.string is an array or a single object
    local string_type
    string_type=$(yq -r '.string | type' "$path_temp" 2>/dev/null || echo "null")
    
    local yq_path=""
    
    if [ "$string_type" = "!!seq" ]; then
        # Dotted path: user.name -> path.string[0], path.string[1]
        local num_segments
        num_segments=$(yq '.string | length' "$path_temp")
        
        local i=0
        while [ "$i" -lt "$num_segments" ]; do
            local key
            key=$(yq -r ".string[$i].\"+content\"" "$path_temp" 2>/dev/null || echo "")
            if [ -n "$key" ]; then
                key=$(extract_string_value "$key")
                if [ -z "$yq_path" ]; then
                    yq_path=".\"$key\""
                else
                    yq_path="${yq_path}.\"$key\""
                fi
            fi
            i=$((i + 1))
        done
    else
        # Simple path: name -> path.string."+content"
        local key
        key=$(yq -r '.string."+content"' "$path_temp" 2>/dev/null || echo "")
        if [ -n "$key" ]; then
            key=$(extract_string_value "$key")
            yq_path=".\"$key\""
        fi
    fi
    
    # Resolve in model
    local result
    result=$(yq -r "$yq_path" "$model_file" 2>/dev/null || echo "null")
    
    if [ "$result" = "null" ]; then
        log warning "Path not found in model: ${WHITE}$yq_path${NC}"
        printf ""
    else
        printf '%s' "$result"
    fi
}

# render_element(element_json, model_file, scope_stack, depth?)
# Recursively renders an element
render_element() {
    local element="$1"
    local model_file="$2"
    local scope_stack="$3"
    local depth="${4:-0}"
    
    local elem_temp=$(mktemp)
    add_temp "$elem_temp"
    printf '%s' "$element" > "$elem_temp"
    
    # Get element name (tag name from tree-sitter XML)
    # Filter out XML attributes (keys starting with +@)
    local elem_name
    elem_name=$(yq -r 'keys | .[]' "$elem_temp" 2>/dev/null | grep -v '^+@' | head -n 1 || echo "")
    
    if [ -z "$elem_name" ]; then
        return 0
    fi
    
    case "$elem_name" in
        interpolation)
            # Extract path from interpolation node
            local path_json
            path_json=$(yq -o j '.interpolation.path' "$elem_temp")
            
            if [ "$path_json" != "null" ]; then
                # Check if it's a simple string path (single identifier)
                local path_temp=$(mktemp)
                add_temp "$path_temp"
                printf '%s' "$path_json" > "$path_temp"
                
                local has_string
                has_string=$(yq -r '.string."+content" // empty' "$path_temp" 2>/dev/null || echo "")
                
                if [ -n "$has_string" ]; then
                    # Simple string path - extract and resolve directly
                    local key
                    key=$(extract_string_value "$has_string")
                    local value
                    value=$(yq -r ".\"$key\" // empty" "$model_file" 2>/dev/null || echo "")
                    printf '%s' "$value"
                else
                    # Complex path - use resolve_path (expects array format)
                    local value
                    value=$(resolve_path "$path_json" "$model_file" "$scope_stack")
                    printf '%s' "$value"
                fi
            fi
            ;;
        segment)
            # For loop: {[ for var in path ]} ... {[ done ]}
            local for_json
            for_json=$(yq -o j '.segment.for' "$elem_temp")
            
            # Extract variable name
            local var_name
            var_name=$(printf '%s' "$for_json" | yq -r '.string."+content"' 2>/dev/null || echo "")
            var_name=$(extract_string_value "$var_name")
            
            # Extract path
            local path_json
            path_json=$(printf '%s' "$for_json" | yq -o j '.path')
            
            # Resolve array from model
            local array_json
            array_json=$(resolve_path "$path_json" "$model_file" "$scope_stack")
            
            # Check if it's an array
            if [ -n "$array_json" ] && [ "$array_json" != "null" ]; then
                local array_temp=$(mktemp)
                add_temp "$array_temp"
                printf '%s' "$array_json" > "$array_temp"
                
                local array_len
                array_len=$(yq 'length' "$array_temp" 2>/dev/null || echo "0")
                
                # Get body elements (everything between for and done)
                local body_json
                body_json=$(yq -o j '.segment.element' "$elem_temp")
                
                # Iterate over array
                local i=0
                while [ "$i" -lt "$array_len" ]; do
                    local item
                    item=$(yq -o j ".[$i]" "$array_temp")
                    
                    # Create new scope with variable binding
                    # TODO: Implement scope stack for nested loops
                    # For now, create a temporary model with the variable
                    local scoped_model=$(mktemp)
                    add_temp "$scoped_model"
                    
                    # Merge current item as variable into model
                    # This is a simplified version - proper implementation would use scope stack
                    yq -o j ". * {\"$var_name\": $item}" "$model_file" > "$scoped_model"
                    
                    # Render body with scoped model
                    if [ "$body_json" != "null" ]; then
                        # Check if body is array or single element
                        local body_is_array
                        body_is_array=$(printf '%s' "$body_json" | yq -r 'type')
                        
                        if [ "$body_is_array" = "!!seq" ]; then
                            # Multiple elements
                            local body_len
                            body_len=$(printf '%s' "$body_json" | yq 'length')
                            local j=0
                            while [ "$j" -lt "$body_len" ]; do
                                local body_elem
                                body_elem=$(printf '%s' "$body_json" | yq -o j ".[$j]")
                                render_element "$body_elem" "$scoped_model" "$scope_stack" "$((depth + 1))"
                                j=$((j + 1))
                            done
                        else
                            # Single element
                            render_element "$body_json" "$scoped_model" "$scope_stack" "$((depth + 1))"
                        fi
                    fi
                    
                    i=$((i + 1))
                done
            fi
            ;;
        text)
            # Plain text - output as-is
            local text_content
            text_content=$(yq -r '.text."+content"' "$elem_temp" 2>/dev/null || echo "")
            printf '%s' "$text_content"
            ;;
        actual_bracket)
            # Escaped bracket: {[ {[ ]} -> output {[
            printf '{['
            ;;
        *)
            log warning "Unknown element type: ${WHITE}$elem_name${NC}"
            ;;
    esac
}

# main()
# Main rendering loop
main() {
    local elements_json
    elements_json=$(yq -o j '.source_file.element' "$AST_TEMP")
    
    log trace "Elements JSON: $WHITE$elements_json"

    if [ "$elements_json" = "null" ]; then
        log error "No elements found in AST"
        exit 1
    fi
    
    local is_array
    is_array=$(printf '%s' "$elements_json" | yq -r 'type')
    
    if [ "$is_array" = "!!seq" ]; then
        local num_elements
        num_elements=$(printf '%s' "$elements_json" | yq 'length')
        log debug "Rendering array with ${WHITE}$num_elements${NC} elements"
        
        local i=0
        while [ "$i" -lt "$num_elements" ]; do
            log debug "Rendering element ${WHITE}$i${NC} of ${WHITE}$num_elements${NC}"
            local elem
            elem=$(printf '%s' "$elements_json" | yq -o j ".[$i]")
            render_element "$elem" "$MODEL_TEMP" "[]" 0
            i=$((i + 1))
        done
    else
        log debug "Rendering single element"
        render_element "$elements_json" "$MODEL_TEMP" "[]" 0
    fi
}

if ! [ "${AS_LIBRARY+x}" ]; then
  main
fi
