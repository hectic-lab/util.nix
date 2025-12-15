# Syntax scheme:
 hemar
   elements
 
 elements
   element
   element elements
 
 element
   tag
   text
 
 text
   text-item
   text-item text
 
 text-item
   '0020' . '10FFFF' - '{'
   nopatern
 
 tag
   '{[' ws path           ws ']}'
   '{[' ws for            ws ']}'
   '{[' ws "done"         ws ']}'
   '{[' ws '{['           ws ']}'
 
 # loop tag
 for
   "for" ws string ws "in" ws path
 
 # path
 path
   '.'
   segmented-path
 
 segmented-path
   segment
   segment '.' segmented-path
 
 segment
   string
   index
 
 index
   '['     digit           ']'
   '['     onenine digits  ']'
   '[' '-' onenine         ']'
   '[' '-' onenine digits  ']'
 
 # types
 string
   unquoted-string
   quoted-string

 unquoted-string
   unquoted-character
   unquoted-character quoted-string

 unquoted-character
   '0020' . '10FFFF' - '"' - '\' - '.' - '[' - ']' - '{' - '}'

 quoted-string
   unquoted-character
   unquoted-character string
 
 quoted-character
   '0000' . '10FFFF' - '"'
   '"' '"'
 
 digits
   digit
   digit digits
 
 digit
   '0'
   onenine
 
 onenine
   '1' . '9'
 
 # paterns
 ws
   ''
   '\x20' ws
   '\x0a' ws
   '\x0d' ws
   '\x09' ws
 
 nopatern
   '{' '0020' . '10FFFF' - '['
