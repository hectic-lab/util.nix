## interpolation tag
context
```json
  {
    "name": "Ioan", 
    "person": { "name": "Oleg" }, 
    "family": {"person": { "name": "Taras" }}, 
  }
```

template
```hmpl
  {{name}}
  {{person.name}}
  {{family.person.name}}
```

result
```hmpl
  Ioan
  Oleg
  Taras
```

## section/iteration tag
context
```json
  {
    "person": {"name": "persons"},
    "persons": [
      {"name": "Ioan", "number": 2}, 
      {"name": "Oleg", "number": 1}, 
    ]
  }
```

template # raise_exception
```hmpl
  {{#{{person.name}} p}}
    {{p.name}} is {{p.number}}
  {{/persons}}
```

result
```hmpl
  Ioan is 2
  Oleg is 1
```

## include tag
json
```json
```

template
```hmpl
  {{>template_name}}
```

result
```hmpl
```

## Order
used plain render
interpolation->section->include

so you cannot render interpolation in interpolation or section

Not allowed:
```hmpl
{{name_{{subname}}}}
{{#array_{{subname}}}}
```

But:
```hmpl
{{>{{template_name}}}}
```
allowed;

№ эксепшн на нераскрытые 
