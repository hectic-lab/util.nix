grammar Hemar;

// ----------------- parser rules -----------------

hemar: elements? EOF ;

elements: element+ ;

element
  : segment
  | interpoltion 
  ;

segment : for elements? end ;

for : 'for' 'in' ;

end: 'end' ;

interpoltion : 'mcha' ;

OPEN  : '{[' ;
CLOSE : ']}' ;

WS  :   [ \t\n\r]+ -> skip ;
LEADING_TEXT : { getCharPositionInLine() == 0 }? (~'{'|'{'~'[')* OPEN -> skip;
MIDLE_TEXT   : CLOSE (~'{'|'{'~'[')* OPEN -> skip;
ENDING_TEXT : CLOSE (~'{'|'{'~'[')* EOF -> skip ;
