module.exports = grammar({
  name: "hemar",

  rules: {
    source_file: $ => repeat($.element),

    element: $ => choice($.interpolation, $.segment, $.text, $.actual_bracket),

    interpolation: $ => seq("{[", $.path,  "]}"),

    segment:         $ => seq($.for, repeat($.element), $.done),


    for:                $ => seq("{[", "for", $.string, "in", $.path, "]}"),
    done:               $ => seq("{[", "done", "]}"),
    actual_bracket:     $ => seq("{[", "{[", "]}"),
    //include:         $ => seq("include", $.path),
    //call:            $ => seq("call", $.string, "in", $.language),
    //call_end:        $ => seq("end", $.string),
    //standalone_call: $ => seq("call", $.string, "end"),
    //language: $ => choice("dash", "plpgsql"),

    path: $ => choice(
      ".",
      seq(
        choice(
          $.string,
          $.index,
        ),
        repeat(seq(".", choice(
          $.string,
          $.index,
        ))),
      ),
    ),

    index: $ => seq(
      '[',
      choice(
        /\d/,        
        /[1-9]\d*/,  
        /-[1-9]/,    
        /-[1-9]\d*/  
      ),
      ']',
    ),

    // anything but space
    string: $ => choice(
      // no whitespace, [, ], {, }, \, ., "
      token(prec(-1, /[^]\[{} \n\t\r.\\"]+/)),
      // " ... " with "" = escaped "
      // if you need json string rules (?:[^"\\\x00-\x1F]|\\["\\/bfnrt]|\\u[0-9A-Fa-f]{4})*
      token(prec(-1, /"([^"]|"")*"/)),
    ),

    // anything but {[
    text: $ => token(prec(-1, /(?:\{[^\[]|[^{])+/)),
  }
});
