module.exports = grammar({
  name: "hemar",

  rules: {
    source_file: $ => repeat($.element),

    element: $ => choice($.interpolation, $.segment, $.text),

    interpolation: $ => seq("{[", $.path,  "]}"),

    segment:         $ => seq($.for, repeat($.element), $.done),


    for:   $ => seq("{[", "for", $.string, "in", $.path, "]}"),
    done:     $ => seq("{[", "done", "]}"),
    //include:         $ => seq("include", $.path),
    //call:            $ => seq("call", $.string, "in", $.language),
    //call_end:        $ => seq("end", $.string),
    //standalone_call: $ => seq("call", $.string, "end"),
    //language: $ => choice("dash", "plpgsql"),

    path: $ => choice(
      ".",
      seq(
        $.string,
        repeat(seq(".", $.string)),
      ),
    ),

    // anything but space
    string: $ => choice(
      // no whitespace, ], \, ., "
      token(prec(-1, /[^] .\\"]+/)),
      // " ... " with "" = escaped "
      token(prec(-1, /"([^"]|"")*"/)),
    ),

    // anything but {[
    text: $ => token(prec(-1, /(?:\{[^\[]|[^{])+/)),
  }
});
