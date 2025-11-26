lexer grammar HemarLexer;

// ---------- default mode: plain text ----------

// Everything that is not the start of "{[" is TEXT
TEXT
  : ( ~'{' | '{' ~'[' )+
  ;

// When we see "{[", emit LeftBrace and enter TAG mode
LeftBrace
  : '{[' -> pushMode(TAG)
  ;

// skip whitespace in plain text if you want
SKIP_WS
  : [ \t\r\n]+ -> skip
  ;

// ---------- TAG mode: inside {[ ... ]} ----------

mode TAG;

fragment WS: [ \t\r\n] ;

For : 'for';
In  : 'in';
End : 'end';

// identifier inside tag
Path
  : String
  | String '.' Path
  ;

String
  : ( ~[.\] \t\r\n] | ']' ~[}. \t\r\n] )+
  | '"' ( ~'"' | '\\' '"'  )+ '"'
  ;

// closing "]}": emit RightBrace and go back to default mode
RightBrace
  : ']}' -> popMode
  ;

// skip whitespace inside tag
SKIP_TAG_WS
  : WS+ -> skip
  ;
