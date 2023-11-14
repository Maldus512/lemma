# Raw Grammar

module = expr | simplified_let

simplified_let = [assignment ';']* [[assignment]? 'in' expr]?

expr =  lambda | literal | id | control | constructor | 'import' expr | expr operator expr
operator = '-' | '+' | '/' | '\*' | '|>' | ':' | ''
lambda = 'fn' ['<' [id ',']* id? '>'] [aliased_pattern]+ ['->' expr]? '=>' expr

control = 'let' [assignment ';']* [assignment]? 'in' expr  | 'match' expr 'with' [aliased_pattern => expr,]+ | 'if' expr 'then' expr ['elif' expr 'then']* 'else' expr

assignment = aliased_pattern ['?' expr ]? '=' expr
aliased_pattern = anonymous_pattern ['as' id]?
anonymous_pattern = record_pattern | tuple_constructor | list_constructor | list_pattern | atom_constructor | id | pattern [: expr]?
list_pattern = '[' [ [aliased_pattern ',']+ aliased_pattern | aliased_pattern ] [';' list_pattern]? ']' | '[]'
record_pattern = '{' [field_pattern ',']* [field_pattern]? '}'
field_pattern  = id '=' aliased_pattern 

constructor = record_constructor | tuple_constructor | list_constructor | atom_constructor | string_constructor | number_constructor
atom_constructor = '@' id 
record_assignment = assignment | id
record_constructor = '{'[record_assignment ',']* [record_assignment | '..' id]?'}'
tuple_constructor = '(' [expr ',']* [expr]? ')'
list_constructor = '[' [expr ',']* [expr]? ']'
string_constructor = '"' [.]* '"' 
number_constructor = TODO


## Missing

 - ~Record update syntax `{ field = value, ..id }`~
 - ~Default value syntax `{ x ? 0 = Int }`~
 - Boolean operators `&& ||`
