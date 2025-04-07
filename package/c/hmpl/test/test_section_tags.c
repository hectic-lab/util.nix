#include "../hmpl.h"
#include "hectic.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>

const HmplOptions options = {
  .section_tags_options = {
    .prefix_start = "",
    .prefix_end = "/",
    .separator_pattern = "#"
  },
  .interpolation_tags_options = {
    .prefix = ""
  }
};

// Function for comparing results
void assert_rendered(const char* template, const char* expected, const char* json_str) {
  Arena arena = arena_init(MEM_KiB);
  
  // Parse JSON string into an object
  Json *json = json_parse(&arena, &json_str);
  if (!json) {
    printf("ERROR: Failed to parse JSON: %s\n", json_str);
    exit(1);
  }
  
  // Create a copy of the template for modification
  char *result = arena_strdup(&arena, template);
  
  // Render the template
  hmpl_render_with_arena(&arena, &result, json, &options);
  
  // Check the result
  if (strcmp(result, expected) != 0) {
    printf("ERROR:\n");
    printf("Template: %s\n", template);
    printf("Expected: %s\n", expected);
    printf("Received: %s\n", result);
    exit(1);
  } else {
    printf("SUCCESS: Template correctly rendered\n");
  }
  
  arena_free(&arena);
}

// --------------------------------------------------
// -- Simple section tag with surrounding text     --
// --------------------------------------------------

#define TEST_SIMPLE_SECTION_CONTEXT \
  "{"                               \
  "  \"users\": ["                  \
  "    {\"name\": \"John\", \"age\": 30},"   \
  "    {\"name\": \"Mary\", \"age\": 25},"  \
  "    {\"name\": \"Alex\", \"age\": 35}" \
  "  ],"                            \
  "  \"count\": 3"                  \
  "}"

#define TEST_SIMPLE_SECTION_TEMPLATE \
  "User list:\n"          \
  "{{item#users}}<li>{{item.name}}, age: {{item.age}}</li>{{/users}}\n" \
  "Total users: {{count}}"

#define TEST_SIMPLE_SECTION_RESULT \
  "User list:\n"        \
  "<li>John, age: 30</li><li>Mary, age: 25</li><li>Alex, age: 35</li>\n" \
  "Total users: 3"

void test_simple_section_tags(Arena *arena) {
  raise_notice("Testing simple section tag with surrounding text");
  const char *context_text = arena_strdup(arena, TEST_SIMPLE_SECTION_CONTEXT);
  Json *context = json_parse(arena, &context_text);
  if (!context) { raise_exception("Malformed json"); exit(1); }

  char *text = arena_strdup(arena, TEST_SIMPLE_SECTION_TEMPLATE);
  raise_notice("Template:\n%s", text);
  raise_notice("Context: %s", json_to_string(arena, context));

  hmpl_render_with_arena(arena, &text, context, &options);
  raise_notice("Result:\n%s", text);
  
  assert(strcmp(text, TEST_SIMPLE_SECTION_RESULT) == 0);
}

// -----------------------------------
// -- Nested section tags          --
// -----------------------------------

#define TEST_NESTED_SECTION_CONTEXT \
  "{"                               \
  "  \"department\": \"Development\","  \
  "  \"teams\": ["                  \
  "    {"                           \
  "      \"name\": \"Frontend\","   \
  "      \"members\": ["            \
  "        {\"name\": \"John\", \"role\": \"Developer\"}," \
  "        {\"name\": \"Mary\", \"role\": \"Designer\"}"    \
  "      ]"                         \
  "    },"                          \
  "    {"                           \
  "      \"name\": \"Backend\","     \
  "      \"members\": ["            \
  "        {\"name\": \"Alex\", \"role\": \"Developer\"}," \
  "        {\"name\": \"Helen\", \"role\": \"Tester\"}"    \
  "      ]"                         \
  "    }"                           \
  "  ]"                             \
  "}"

#define TEST_NESTED_SECTION_TEMPLATE \
  "Department: {{department}}\n"          \
  "{{item#teams}}Team: {{item.name}}\n"  \
  "  {{item#item.members}}Member: {{item.name}} ({{item.role}}){{/item.members}}\n" \
  "{{/teams}}"

#define TEST_NESTED_SECTION_RESULT \
  "Department: Development\n"            \
  "Team: Frontend\n"            \
  "  Member: John (Developer)Member: Mary (Designer)\n" \
  "Team: Backend\n"              \
  "  Member: Alex (Developer)Member: Helen (Tester)\n"

void test_nested_section_tags(Arena *arena) {
  raise_notice("Testing nested section tags");
  const char *context_text = arena_strdup(arena, TEST_NESTED_SECTION_CONTEXT);
  Json *context = json_parse(arena, &context_text);
  if (!context) { raise_exception("Malformed json"); exit(1); }

  char *text = arena_strdup(arena, TEST_NESTED_SECTION_TEMPLATE);
  raise_notice("Template:\n%s", text);
  raise_notice("Context: %s", json_to_string(arena, context));

  hmpl_render_with_arena(arena, &text, context, &options);
  raise_notice("Result:\n%s", text);
  
  assert(strcmp(text, TEST_NESTED_SECTION_RESULT) == 0);
}

// -----------------------------------
// -- Empty array in section tag    --
// -----------------------------------

#define TEST_EMPTY_ARRAY_CONTEXT \
  "{"                            \
  "  \"tasks\": []"              \
  "}"

#define TEST_EMPTY_ARRAY_TEMPLATE \
  "Tasks: {{item#tasks}}ID: {{item.id}} - {{item.description}}{{/tasks}}"

#define TEST_EMPTY_ARRAY_RESULT \
  "Tasks: "

void test_empty_array_section_tags(Arena *arena) {
  raise_notice("Testing empty array in section tag");
  const char *context_text = arena_strdup(arena, TEST_EMPTY_ARRAY_CONTEXT);
  Json *context = json_parse(arena, &context_text);
  if (!context) { raise_exception("Malformed json"); exit(1); }

  char *text = arena_strdup(arena, TEST_EMPTY_ARRAY_TEMPLATE);
  raise_notice("Template:\n%s", text);
  raise_notice("Context: %s", json_to_string(arena, context));

  hmpl_render_with_arena(arena, &text, context, &options);
  raise_notice("Result:\n%s", text);
  
  assert(strcmp(text, TEST_EMPTY_ARRAY_RESULT) == 0);
}

// -----------------------------------
// -- HTML template with section tags --
// -----------------------------------

#define TEST_HTML_CONTEXT                                   \
  "{"                                                       \
  "  \"title\": \"My List\","                               \
  "  \"items\": ["                                          \
  "    {\"name\": \"Item 1\", \"type\": \"important\"},"    \
  "    {\"name\": \"Item 2\", \"type\": \"normal\"},"       \
  "    {\"name\": \"Item 3\", \"type\": \"normal\"}"        \
  "  ],"                                                    \
  "  \"footer\": \"© 2023\""                                \
  "}"

#define TEST_HTML_TEMPLATE                                                       \
  "<!DOCTYPE html>\n"                                                            \
  "<html>\n"                                                                     \
  "<head>\n"                                                                     \
  "  <title>{{title}}</title>\n"                                                 \
  "</head>\n"                                                                    \
  "<body>\n"                                                                     \
  "  <h1>{{title}}</h1>\n"                                                       \
  "  <ul>\n"                                                                     \
  "    {{item#items}}<li class=\"{{item.type}}\">{{item.name}}</li>{{/items}}\n" \
  "  </ul>\n"                                                                    \
  "  <footer>{{footer}}</footer>\n"                                              \
  "</body>\n"                                                                    \
  "</html>"

#define TEST_HTML_RESULT                                                                                      \
  "<!DOCTYPE html>\n"                                                                                         \
  "<html>\n"                                                                                                  \
  "<head>\n"                                                                                                  \
  "  <title>My List</title>\n"                                                                                \
  "</head>\n"                                                                                                 \
  "<body>\n"                                                                                                  \
  "  <h1>My List</h1>\n"                                                                                      \
  "  <ul>\n"                                                                                                  \
  "    <li class=\"important\">Item 1</li><li class=\"normal\">Item 2</li><li class=\"normal\">Item 3</li>\n" \
  "  </ul>\n"                                                                                                 \
  "  <footer>© 2023</footer>\n"                                                                               \
  "</body>\n"                                                                                                 \
  "</html>"

void test_html_section_tags(Arena *arena) {
  raise_notice("Testing HTML template with section tags");
  const char *context_text = arena_strdup(arena, TEST_HTML_CONTEXT);
  Json *context = json_parse(arena, &context_text);
  if (!context) { raise_exception("Malformed json"); exit(1); }

  char *text = arena_strdup(arena, TEST_HTML_TEMPLATE);
  raise_notice("Template:\n%s", text);
  raise_notice("Context: %s", json_to_string(arena, context));

  hmpl_render_with_arena(arena, &text, context, &options);
  raise_notice("Result:\n%s", text);
  
  assert(strcmp(text, TEST_HTML_RESULT) == 0);
}

// -----------------------------------
// -- Report with nested sections    --
// -----------------------------------

#define TEST_REPORT_CONTEXT                               \
  "{"                                                     \
  "  \"period\": \"March 2023\","                         \
  "  \"data\": ["                                         \
  "    {"                                                 \
  "      \"title\": \"Sales\","                           \
  "      \"value\": 1000,"                                \
  "      \"details\": ["                                  \
  "        {\"name\": \"Product A\", \"value\": 500},"    \
  "        {\"name\": \"Product B\", \"value\": 300},"    \
  "        {\"name\": \"Product C\", \"value\": 200}"     \
  "      ]"                                               \
  "    },"                                                \
  "    {"                                                 \
  "      \"title\": \"Expenses\","                        \
  "      \"value\": 700,"                                 \
  "      \"details\": ["                                  \
  "        {\"name\": \"Rent\", \"value\": 300},"         \
  "        {\"name\": \"Salary\", \"value\": 400}"        \
  "      ]"                                               \
  "    }"                                                 \
  "  ],"                                                  \
  "  \"summary\": 300"                                    \
  "}"

#define TEST_REPORT_TEMPLATE                                                          \
  "Report for {{period}}\n\n"                                                         \
  "{{row#data}}* {{row.title}}: {{row.value}}\n"                                      \
  "  {{detail#row.details}}  - {{detail.name}}: {{detail.value}}\n{{/row.details}}\n" \
  "{{/data}}\n"                                                                       \
  "Total: {{summary}}"

#define TEST_REPORT_RESULT                                         \
  "Report for March 2023\n\n"                                      \
  "* Sales: 1000\n"                                                \
  "  - Product A: 500\n  - Product B: 300\n  - Product C: 200\n\n" \
  "* Expenses: 700\n"                                              \
  "  - Rent: 300\n  - Salary: 400\n\n"                             \
  "Total: 300"

void test_report_section_tags(Arena *arena) {
  raise_notice("Testing report with nested sections");
  const char *context_text = arena_strdup(arena, TEST_REPORT_CONTEXT);
  Json *context = json_parse(arena, &context_text);
  if (!context) { raise_exception("Malformed json"); exit(1); }

  char *text = arena_strdup(arena, TEST_REPORT_TEMPLATE);
  raise_notice("Template:\n%s", text);
  raise_notice("Context: %s", json_to_string(arena, context));

  hmpl_render_with_arena(arena, &text, context, &options);
  raise_notice("Result:\n%s", text);
  
  assert(strcmp(text, TEST_REPORT_RESULT) == 0);
}

int main(void) {
  init_logger();
  Arena arena = arena_init(MEM_MiB);
  
  test_simple_section_tags(&arena);
  arena_reset(&arena);
  test_nested_section_tags(&arena);
  //arena_reset(&arena);
  //test_empty_array_section_tags(&arena);
  //arena_reset(&arena);
  //test_html_section_tags(&arena);
  //arena_reset(&arena);
  //test_report_section_tags(&arena);
  
  printf("All tests passed successfully!\n");
  
  arena_free(&arena);
  return 0;
} 