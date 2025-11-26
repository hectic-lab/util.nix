grammar Hemar;

// ----------------- parser rules -----------------

hemar
    : elements? EOF
    ;

elements
    : element+
    ;

element
    : tag
    | TEXT
    ;

// tag
tag
    : OPEN path          CLOSE
    | OPEN loopStatement CLOSE
    | OPEN includeHeader CLOSE
    | OPEN 'end'         CLOSE
    | OPEN function      CLOSE
    | OPEN OPEN          CLOSE      // literal "{[" output
    ;

// loop tag: "for" string "in" path
loopStatement
    : 'for' STRING 'in' path
    ;

// include tag: "include" path
includeHeader
    : 'include' path
    ;

// function tag
function
    : 'compute' language functionBody?   // "compute" language body
    | 'compute' '-'      functionBody?   // "compute" - body
    ;

language
    : 'dash'
    | 'plpgsql'
    ;

// everything up to (but not including) "]}"
// (raw body, including "{[" etc, at *token* level)
functionBody
    : ( ~CLOSE )*
    ;

// path
path
    : '.'
    | segmentedPath
    ;

segmentedPath
    : segment ('.' segment)*
    ;

segment
    : STRING
    | index
    ;

// index: \0 .. \9, \1.. \9\d*, and negative forms
index
    : '\\' DIGIT
    | '\\' ONENINE DIGITS?
    | '\\' '-' DIGIT
    | '\\' '-' ONENINE DIGITS?
    ;

// ----------------- lexer rules -----------------

OPEN  : '{[';
CLOSE : ']}';

// text outside tags: anything except the "{[" sequence
TEXT
    : TEXT_CHAR+
    ;

/*
 * Strings used in paths/loop variables:
 *   "..." with escapes similar to your spec.
 */
STRING
    : '"' ( ESC | STRING_CHAR )* '"'
    ;

fragment STRING_CHAR
    : ~["\\\r\n]
    ;

/*
 * Escapes:
 *   .   (literal dot)
 *   ]}  (literal "]}")   -- note this is two chars after '\'
 *   "   \" 
 *   \   \\
 *   /   \/
 *   b f n r t
 *   uXXXX (hex)
 *   whitespace after backslash (your ws-in-escape)
 */
fragment ESC
    : '\\'
      (
          '.'
        | ']}'
        | '"'
        | '\\'
        | '/'
        | 'b'
        | 'f'
        | 'n'
        | 'r'
        | 't'
        | 'u' HEX HEX HEX HEX
        | WS_CHAR
      )
    ;

// digits / hex
DIGITS : DIGIT+ ;
DIGIT  : [0-9] ;
ONENINE: [1-9] ;
HEX    : [0-9a-fA-F] ;

// whitespace for normal lexing
WS
    : [ \t\r\n]+ -> skip
    ;

// whitespace used inside escapes
fragment WS_CHAR
    : [ \t\r\n]
    ;


fragment TEXT_CHAR
    : ~'{'              // any except '{'
    | '{' ~'['          // '{' only if not starting OPEN
    ;
