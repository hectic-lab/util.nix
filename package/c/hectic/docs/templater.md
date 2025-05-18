# Templater Configuration Documentation

The templating engine supports flexible customization of tag syntax parameters. Each parameter can be overridden in the configuration file. Below are the main groups of parameters with usage examples and configuration notes.

## Legend

---

## General Parameters

- **Open Brace**  
  A non-empty string marking the beginning of a tag.  
  *Example:* `{{`

- **Close Brace**  
  A non-empty string marking the end of a tag.  
  *Example:* `}}`

---

## Section Tags

Parameters defining syntax for blocks controlling loops or nested structures.

- **Prefix**  
  Marks the start of a section (e.g., loops).  
  *Example:* `for ` | *(Empty)*

- **Suffix**  
  Delimiter between variables and collections.  
  *Example:* ` in ` | `#`

- **Post-Suffix**  
  Finalizes the section block.  
  *Example:* `end ` | `/`

*Example*

*Section Example:*
```tpl
{{ for item in items }}
  {{ item.name }}
  some text
  {{ for inner_item in item.inner_items join '\n' }}
    <p>some other text</p>
    {{ inner_item }}
  {{ end }}
  \n
{{ end }}
```
*Context Example:*
```json
{
  "items": [
    {
      "name": "some name",
      "inner_items": ["value1", "value2"]
    }
  ]
}
```

## Interpolation Tags
Inserts variable values or expression results directly into templates.
- **Prefix**  
  Indicates an interpolation operation.  
  *Example:* `$` | *(Empty)*

*Interpolation Example:*
```tpl
  {{ interpolation_field }}
```
*Context Example:*
```json
{ 
    "interpolation_field": "some value",
    "interpolation_field_null": null
}
```

## Include Tags
Includes content from other templates.
- **Prefix**  
  Marks the tag as an inclusion operation.  
  *Example:* `include ` | `+` | `<`

*Include Example:*
```tpl
  text before
  {{ include inner_template }}
  <div id="footer">...</div>
```
*Context Examples:*
```json
// Separate context
{
  "include": {
  "inner_template": {
      "template": "{{ field }}",
      "context": { "field": "value" }
    }
  }
}

// Shared root context
{
  "field": "value",
  "include": {
    "inner_template": {
      "template": "{{ field }}"
    }
  }
}

// Plain text inclusion
{
  "field": "value",
  "include": {
    "inner_template": {
      "content": "<p>value</p>"
    }
  }
}
```

## Execution Tags
**Note:** implemented as a wrapper on applicable platforms, in that case must evel Postgresql functions.
Enables calling functions with arguments, or execute code. Have hardcoded context var - alows use template context 
- **Prefix**  
  Denotes a function call.  
  *Example:* `exec` | *(Empty)*

*Function Example:*
```tpl
  {{ exec RETURN my_function(context->arg1, context->arg2, 'literal') }}
  {{ exec RETURN 'aaaaa' }}
```

## Notes
- **Unique Tags:** `Open Brace`, `Close Brace`, and `Null Handler` must be distinct.
- **Nested Constructs:** Supported.
- **Unclosed Tags:** Must return an error.
- **Missing Fields/Functions/Templates:** Configurable to either return an error or warning.
- **Circular Includes:** Detect when possible.
- **No Shadowing:** Variables defined in section tags must not conflict with context variable names, otherwise, return an error.


## Shared example
```tpl
  <div>text before<div>

  {{ include inner_template }}

  {{ name }}

  {{ for item in array }}
    some text: {{ name2 }}
    {{ item.name }}
  {{ end }}

  <div>code insertion:</div>
  {{ execute
    context + '{"name3": "zalupa"}';

    IF context->condition THEN
      RAISE INFO 'some log';

      RETURN 'some text';
    END
    RETURN 'some other text';
  }}

  <div id="footer">...</div>
```