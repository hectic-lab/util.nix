#!/bin/dash

# Hemar Renderer
# Takes tree-sitter AST (as JSON via yq) and a data model, produces rendered output

set -eu

# Usage: render.sh <ast.json> <model.json>
# Or pipe AST: cat ast.json | render.sh - <model.json>

# Colors for logging
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2
}

# Parse arguments
AST_FILE="${1:--}"
MODEL_FILE="${2:-}"

if [ -z "$MODEL_FILE" ]; then
    log_error "Usage: $0 <ast.json> <model.json>"
    exit 1
fi

if [ ! -f "$MODEL_FILE" ]; then
    log_error "Model file not found: $MODEL_FILE"
    exit 1
fi

# Read AST
if [ "$AST_FILE" = "-" ]; then
    AST_JSON=$(cat)
else
    if [ ! -f "$AST_FILE" ]; then
        log_error "AST file not found: $AST_FILE"
        exit 1
    fi
    AST_JSON=$(cat "$AST_FILE")
fi

# Save to temp files for yq processing
AST_TEMP=$(mktemp)
MODEL_TEMP=$(mktemp)
trap 'rm -f "$AST_TEMP" "$MODEL_TEMP"' EXIT INT HUP

printf '%s' "$AST_JSON" > "$AST_TEMP"
cat "$MODEL_FILE" > "$MODEL_TEMP"

# resolve_path(path_array, model, scope_stack)
# Resolves a path in the data model
# path_array: JSON array of path segments from AST
# model: the data model
# scope_stack: JSON array of loop scopes (for nested loops)
resolve_path() {
    local path_json="$1"
    local model_file="$2"
    local scope_stack="$3"
    
    # Build yq path expression
    local num_segments
    num_segments=$(printf '%s' "$path_json" | yq 'length')
    
    if [ "$num_segments" -eq 0 ]; then
        log_error "Empty path"
        return 1
    fi
    
    # Check if first segment is root (.)
    local first_type
    first_type=$(printf '%s' "$path_json" | yq '.[0].type' 2>/dev/null || echo "null")
    
    local yq_path="."
    local start_idx=0
    
    if [ "$first_type" = "root" ]; then
        # Root path - start from model root
        yq_path="."
        start_idx=1
    fi
    
    # Build path from segments
    local i="$start_idx"
    while [ "$i" -lt "$num_segments" ]; do
        local seg_type
        seg_type=$(printf '%s' "$path_json" | yq ".[$i].type")
        
        case "$seg_type" in
            key)
                local key
                key=$(printf '%s' "$path_json" | yq ".[$i].key")
                # Remove quotes from string if present
                if [ "${key#\"}" != "$key" ]; then
                    key="${key#\"}"
                    key="${key%\"}"
                fi
                yq_path="${yq_path}.\"$key\""
                ;;
            index)
                local idx
                idx=$(printf '%s' "$path_json" | yq ".[$i].index")
                yq_path="${yq_path}[$idx]"
                ;;
            *)
                log_error "Unknown path segment type: $seg_type"
                return 1
                ;;
        esac
        i=$((i + 1))
    done
    
    # Resolve in model
    local result
    result=$(yq -r "$yq_path" "$model_file" 2>/dev/null || echo "null")
    
    if [ "$result" = "null" ]; then
        log_warn "Path not found in model: $yq_path"
        printf ""
    else
        printf '%s' "$result"
    fi
}

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

# render_element(element_json, model_file, scope_stack, depth)
# Recursively renders an element
render_element() {
    local element="$1"
    local model_file="$2"
    local scope_stack="$3"
    local depth="${4:-0}"
    
    local elem_temp=$(mktemp)
    trap 'rm -f "$elem_temp"' EXIT INT HUP
    printf '%s' "$element" > "$elem_temp"
    
    # Get element name (tag name from tree-sitter XML)
    local elem_name
    elem_name=$(yq -r 'keys | .[0]' "$elem_temp" 2>/dev/null || echo "")
    
    case "$elem_name" in
        interpolation)
            # Extract path from interpolation node
            local path_json
            path_json=$(yq -o j '.interpolation.path' "$elem_temp")
            
            if [ "$path_json" != "null" ]; then
                # Resolve and output the value
                local value
                value=$(resolve_path "$path_json" "$model_file" "$scope_stack")
                printf '%s' "$value"
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
                trap 'rm -f "$array_temp"' EXIT INT HUP
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
                    trap 'rm -f "$scoped_model"' EXIT INT HUP
                    
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
                    
                    rm -f "$scoped_model"
                    i=$((i + 1))
                done
                
                rm -f "$array_temp"
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
            log_warn "Unknown element type: $elem_name"
            ;;
    esac
    
    rm -f "$elem_temp"
}

# Main rendering loop
# The AST is in yq format: sources.source.source_file
main() {
    # Extract source_file element array
    local elements_json
    elements_json=$(yq -o j '.sources.source.source_file.element' "$AST_TEMP")
    
    if [ "$elements_json" = "null" ]; then
        log_error "No elements found in AST"
        exit 1
    fi
    
    # Check if single element or array
    local is_array
    is_array=$(printf '%s' "$elements_json" | yq -r 'type')
    
    if [ "$is_array" = "!!seq" ]; then
        # Multiple elements
        local num_elements
        num_elements=$(printf '%s' "$elements_json" | yq 'length')
        
        local i=0
        while [ "$i" -lt "$num_elements" ]; do
            local elem
            elem=$(printf '%s' "$elements_json" | yq -o j ".[$i]")
            render_element "$elem" "$MODEL_TEMP" "[]" 0
            i=$((i + 1))
        done
    else
        # Single element
        render_element "$elements_json" "$MODEL_TEMP" "[]" 0
    fi
}

main

