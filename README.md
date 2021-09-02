# hs-code-nudge

**PRE-RELEASE**

**UNDER DEVELOPMENT**

Extract `TODO`, `XXX` and `FIXME` comments from source code.

Like [`leasot`][leasot] (Hebrew for "to-do"), except not written in node.js.

[leasot]: https://github.com/pgilad/leasot

An unspeakable, unholy melding of Haskell and C++.

Building the library or executable requires the GNU [source-highlight][source-highlight] library
(not distributed with this package), which is licensed under the GPL (version 3).
So any binaries produced from it are presumably distributable under the terms of the GPL v 3,
too.

[source-highlight]: https://www.gnu.org/software/src-highlite/

## Quick usage

```
code-nudge [-r] [-v] [FILE..]
```

Takes a list of files and/or directories to extract TODO's from and prints them
on standard output, like this:

```
$ code-nudge -r src
src/SourceHighlight.hs:
  TODO: rewrite it all in C++, w/ CLI11 for command-line option parsing.
```

The `-r` option processes any directories in the list recursively. 
The `-v` option makes the program report on standard error if it couldn't
recognize the language a file is written in.

## Building

Building requires you have the [GNU Source-highlight][gnu-shl-lib] library header files
installed. On Ubuntu, you can install these with

```
$ sudo apt install -y --no-install-recommends libsource-highlight-dev
```

Once that's done, you can build this package using [Stack][stack] with

```
$ stack --stack-yaml stack-lts-13.yaml build
```

(And presumably also with cabal.)

[gnu-shl-lib]: https://www.gnu.org/software/src-highlite/source-highlight-lib.html
[stack]: https://github.com/commercialhaskell/stack

Assuming all goes well, you can then install it to `~/.local/bin` with

```
$ stack --stack-yaml stack-lts-13.yaml install
```

## Limitations

code-nudge detects any line of text in a comment which (after stripping leading
whitespace) begins with one of:

- `TODO`
- `FIXME`
- `XXX`
- `NOTE`
- `ATTN`

These need not be followed by whitespace or any punctuation. It only prints the
line in which the "to-do" is found - it won't handle multi-line to-do's.

## Languages supported

The languages supported are exactly those supported by
GNU source-highlight. There are listed on the [GNU source-highlight
web page][source-highlight], and as of September 2021, include such
well-known languages as:

- C and C++
- C# and Java
- Cobol
- Haskell
- JavaScript and CoffeScript
- Makefiles, and
- shell script (what sort? I don't know, the page doesn't say).

## Reporting bugs

I have hardly tested this at all, and any use of it is at your own risk.
If you do find any bugs, though, feel free to open an issue.

