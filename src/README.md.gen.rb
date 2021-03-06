require_relative "code-gen"
require "erb"
require "cairo"

langs = CodeGen::List.reverse.flat_map {|c| c.steps.map {|step| step.name } }
cmds = CodeGen::List.reverse.flat_map {|c| c.steps.map {|step| step.cmd } }
srcs = CodeGen::List.reverse.flat_map {|c| c.steps.map {|step| step.src } }
apts = CodeGen::List.reverse.flat_map {|c| c.steps.map {|step| step.apt } }

rows = [["language", "ubuntu package", "version"]]
rows += (langs.zip(apts) + [["(extra)", "tcc"]]).map do |lang, apt|
    if apt
      pkg = `dpkg -p #{ apt } 2>/dev/null`
      version = $?.success? && pkg.b[/^Version: (.*)/, 1]
    end
    [lang, apt || "(none)", version || '-']
  end

ws = rows.transpose.map {|row| row.map {|s| s.size }.max + 1 }
rows[1, 0] = [ws.map {|w| "-" * w }]
rows = rows.map do |col|
  (col.zip(ws).map {|s, w| s.ljust(w) } * "|").rstrip
end

apt_get = "sudo apt-get install #{ (apts + ["tcc"]).compact.uniq.sort * " " }"
apt_get.gsub!(/.{,70}( |\z)/) do
  $&[-1] == " " ? $& + "\\\n      " : $&
end

cmds = cmds.zip(srcs.drop(1) + ["QR.rb"]).map do |cmd, src|
  cmd.gsub("OUTFILE", src).gsub(/mv QR\.c(\.bak)? QR\.c(\.bak)? && /, "")
end
cmds[-1].gsub!("QR.rb", "QR2.rb")

File.write("../README.md", ERB.new(DATA.read, nil, "%").result(binding))


__END__
# Quine Relay

### What this is

This is a <%= langs[0] %> program that generates
<%= langs[1] %> program that generates
<%= langs[2] %> program that generates
...(through <%= langs.size %> languages)...
<%= langs[-1] %> program that generates
the original <%= langs[0] %> code again.

The high-level structure of this project itself is rather unconventional. It's written in Ruby, yet it's not a 'gem'. Files in `src/` directory are responsible for dynamic generation of the whole project. These scripts utilize tools such as `rake`, `erb` and `cairo`. Generated files, namely `QR.rb`, `README.md` and `langs.png`, are placed in project's main directory.

`README.md`: it contains instructions and a list of packages that is dynamically generated.
`QR.rb`: the quine script. Note that it has form `eval($s = "string")`. It is entirely generated by executing another script...
#### `src/QR.rb.gen.rb`
Here, the quine is assembled from pieces. It imports file `src/code-gen.rb`.

The first line of code assigns just one string. However, it's an important foundation. We will start here and transform this piece multiple times.
```ruby
s = '%(eval$s=%q(#$s))'
```
This variable holds a string within a string. In Ruby, there are at least 7 ways to write a string literal. Three of them that are nested here look like this: `'string'`, `%(string)` and `%q(string)`. Also, `#$global` within a string is equivalent to [`#{ $global }` - interpolation](http://en.wikibooks.org/wiki/Ruby_Programming/Syntax/Literals#Interpolation). It has effect only when placed in `""`, `%()` or `%Q()`, but not in single quotes such as `''` or `%q()`.

It closely resembles another complete single quine in Ruby: `eval s=%q(puts "eval s = %q(#{s})")`. Let's construct it:
```ruby
> one = %q(#{s}) # does s.to_s when evaluated
=> "\#{s}"
> two = "eval s = %q(#{ one })" # does s = s.to_s when evaluated
=> "eval s = %q(\#{s})"
> three = %(puts "#{ two }") # prints itself when evaluated
=> "puts \"eval s = %q(\#{s})\""
> puts "eval s = %q(#{ three })" # the last step
eval s = %q(puts "eval s = %q(#{s})")
=> nil
> puts %q(eval s = %q(puts "eval s = %q(#{s})")) # deconstructed!
eval s = %q(puts "eval s = %q(#{s})")
=> nil
```

As we can see, lazy interpolation is used in a clever way to insert a string within itself using very little code. Printing one string twice is basically what most quines do. There's also similar Python version.
```python
a= 'print "a=",repr(a);print "exec(a)"'
exec(a)
```
Furher, the code undergoes 49 transformations, involving all languages except Ruby, which was actually the basis.
```ruby
s = CodeGen::List[0..-2].inject('%(eval$s=%q(#$s))') {|c, lang|
  lang.gen_code(c).tr(" \\","X`")
}
```
Finally, the code is encased in yet another layer that handles escaping and gets converted into ASCII art later.

ASCII art does work thanks to [one w](https://github.com/mame/quine-relay/blob/master/src/QR.rb.gen.rb#L7)! The outermost layer is not entirely repositioned, since there are 3 full lines. In Ruby, `%w(s1 s2)` is just like `%(s1 s2)`, except it also does `%(s1 s2).split`, which results in an array `["s1", "s2"]`. `w` stands for word. An array can be joined with [`Array#*('')`](http://www.ruby-doc.org/core-2.0/Array.html#method-i-2A). That means `%w(s1 s2 s3)*''` is in other terms `%(s1 s2 s3).split.join('')` or `%(s1 s2 s3).gsub(/\s/, '')` which gets rid of whitespace. Damn, Ruby is terse.

That's the entire inner work. We need some theory.
#### Theory
Let `f` be an identity function `f(x) -> x`. `x` is the code of a quine and `f` is the programming language runtime. We run an interpreter/compiler with `f(x)` and get output that is `x`. For example, if `QR.rb` is a quine, then `ruby QR.rb > QR2.rb` and *QR.rb = QR2.rb*.

A multi-quine may introduce one or more intermediate programs that just print a certain string. So it can be notated as `a b c d e f ... x -> x`. Transformations I mentioned earlier can be simply represented as function compositions: `(... ∘ f ∘ e ∘ d ∘ c ∘ b ∘ a)(x) = multi-quine(x) = x`.

See [Kleene's recursion theorem](http://en.wikipedia.org/wiki/Kleene's_recursion_theorem) :wink:
#### `src/code-gen.rb`
Take a look at [lines in `src/code-gen.rb` that start with `Code = ...` or `def code`](https://github.com/mame/quine-relay/blob/master/src/code-gen.rb#L76). They contain code in 49 languages that prints strings which seem to be escaped properly in `PREV`. The high-level idea is quite simple, but an implementation is complex and very time consuming.

How to make a multi-quine? By using the Python code above and wrapping (interleaving?) it in another code. Choice of the second language is largely unimportant, because we only need it for `print` etc, so I'll use Ruby.
```ruby
puts %(a= 'print("a=",repr(a)); print("exec(a)")'
exec(a))
```
We must go back to Python and insert `puts %(``)` prefix/suffix that we just added.
```python
a= 'print("       a=",repr(a)); print("exec(a) ")'; exec(a)
# insert  ^puts %(                           ^)
```
[It](http://ideone.com/2mOamF) [works](http://ideone.com/jR6gTN)!
```ruby
puts %(a= 'print("puts %(a=",repr(a)); print("exec(a))")'
exec(a))
```

![Language Uroboros][langs]

[langs]: https://raw.github.com/mame/quine-relay/master/langs.png

### Usage

#### 1. Install all interpreters/compilers.

You are fortunate if you are using Ubuntu 13.04 (Raring Ringtail).
You just have to type the following apt-get command to install all of them.

    $ <%= apt_get %>

You may find [instructions for Arch Linux and other platforms in the wiki](https://github.com/mame/quine-relay/wiki/Installation).

If you are not using these Linux distributions, please find your way yourself.
If you could do it, please let me know.  Good luck.

#### 2. Run each program on each interpreter/compiler.

% cmds.each do |cmd|
    $ <%= cmd %>
% end

You will see that `QR.rb` is the same as `QR2.rb`.

    $ diff QR.rb QR2.rb

Alternatively, just type `make`.

    $ make

Note: It may require huge memory to compile some files.

### Tested interpreter/compiler versions

As I said above, I tested the program on Ubuntu.
It does not provide Unlambda and Whitespace interpreters,
so this repository includes my own implementations.
For other languages, I used the following deb packages:

% rows.each do |row|
<%= row %>
% end

Note: `tcc` is used to compile FORTRAN77 and INTERCAL sources
with less memory.

### How to re-generate the source

    $ cd src
    $ rake

### to do
#### polyglot programs
Here's a fun program that I created. The catch is that it's a C quine and simultaneously a valid Ruby quine. I believe you can create polyglot multi-quines.
```c
#define eval(...) char *f="#define eval(...) char *f=%c%s%c;main() {printf(f,34,f,34,10,#__VA_ARGS__,10);}%ceval(%s)%c";main() {printf(f,34,f,34,10,#__VA_ARGS__,10);}
eval(s=%q(puts "#define eval(...) char *f=\"#define eval(...) char *f=%c%s%c;main() {printf(f,34,f,34,10,#__VA_ARGS__,10);}%ceval(%s)%c\";main() {printf(f,34,f,34,10,#__VA_ARGS__,10);}\neval(s=%q(#{s}))"))
```
Is it also possible to decompress intermediate strings with a library such as `zlib`?

### License

Copyright (c) 2013 Yusuke Endoh (@mametter), @hirekoke

MIT License

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
