parser grammar HemarParser;

options { tokenVocab=HemarLexer; }

hemar   : element*? EOF ;

element
  : TEXT
  | segment
  | interpoltion
  ;

segment      : for element*? end;

for : LeftBrace For Path In Path RightBrace;
end : LeftBrace End RightBrace;

interpoltion : LeftBrace Path RightBrace;
