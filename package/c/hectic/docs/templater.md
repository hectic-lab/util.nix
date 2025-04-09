# Templater Configuration Documentation

The templating engine supports flexible customization of tag syntax parameters. Each parameter can be overridden in the configuration file. Below are the main groups of parameters with usage examples and configuration notes.

## Legend

---

## General Parameters

- **Open Brace**  
  A non-empty string marking the beginning of a tag.  
  *Example:* `{%`

- **Close Brace**  
  A non-empty string marking the end of a tag.  
  *Example:* `%}`

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
  Finalizes the section declaration block.  
  *Example:* `do ` | `:`

*Section Example:*
```tpl
{% for item in items do
  {% item.name %}
  some text
  {% for inner_item in item.inner_items join '\n' do
    <p>some other text</p>
    {% inner_item %}
  %}
  \n
%}
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
  {% interpolation_field %}
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
  {% include inner_template %}
  <div id="footer">...</div>
```
*Context Examples:*
```json
// Separate context
{
  "include inner_template": [
    {
      "template": "{% field %}",
      "context": { "field": "value" }
    }
  ]
}

// Shared root context
{
  "field": "value",
  "include inner_template": [
    {
      "template": "{% field %}"
    }
  ]
}

// Plain text inclusion
{
  "field": "value",
  "include inner_template": [
    {
      "content": "<p>value</p>"
    }
  ]
}
```

## Function Tags
**Note:** Currently not included in C library; implemented as a wrapper on applicable platforms.
Enables calling functions with arguments.
- **Prefix**  
  Denotes a function call.  
  *Example:* `exec` | *(Empty)*

*Function Example:*
```tpl
  {% exec my_function(arg1, arg2, 'literal') %}
  {% exec RETURN 'aaaaa' %}
```

## Notes
- **Unique Tags:** `Open Brace`, `Close Brace`, and `Null Handler` must be distinct.
- **Nested Constructs:** Supported.
- **Unclosed Tags:** Must return an error.
- **Missing Fields/Functions/Templates:** Configurable to either return an error or warning.
- **Circular Includes:** Detect when possible.
- **No Shadowing:** Variables defined in section tags must not conflict with context variable names, otherwise, return an error.