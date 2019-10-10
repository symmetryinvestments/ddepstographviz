# ddepstographviz

[![Build Status](https://travis-ci.org/symmetryinvestments/ddepstographviz.svg?branch=master)](https://travis-ci.org/symmetryinvestments/ddepstographviz)

ddepstographviz takes the dmd output of the -deps flag and produces a file
that the graphviz package (use fdp) can turn into a pretty, colorful picture
of your app's dependencies.

## Usage

1. Get dmd deps file -deps="deps.txt"

2. Run ddepstographviz on it
```sh
$ dub run ddepstographviz -- -i deps.txt -o deps.dot
```

3. Run graphviz (fdp) on it
```sh
$ fdp deps.dot -T (svg,png,jpg) > deps.(svg,png,jpg)
```

## Example

We use the test of [graphqld](https://github.com/burner/graphqld) as an
example.

1. Displaying all the deps, is normally way to much to see anything.

![Image of all deps](https://github.com/symmetryinvestments/ddepstographviz/raw/master/deps_all.png "All deps")

2. We can exclude package by use of the -e options

```sh
$ dub run ddepstographviz -- -i deps.txt -o deps.dot -e std,vibe,mir,nullablestore,core,object,diet,taggedalgebraic,taggedunion,eventcore,fixedsizearray
```

![Image of all deps without libs](https://github.com/symmetryinvestments/ddepstographviz/raw/master/deps_nolib.png "No libraries")

3. The graph is still to messy.

So we remove edges between module in the same package, and dependencies that
point down in the module tree.

```sh
$ dub run ddepstographviz -- -i deps.txt -o deps.dot -e std,vibe,mir,nullablestore,core,object,diet,taggedalgebraic,taggedunion,eventcore,fixedsizearray -t true -d true
```

![Image of all deps without libs and less internal edges](https://github.com/symmetryinvestments/ddepstographviz/raw/master/deps_nolib_no_package_internal.png "No libraries and no package internal edges")




About Kaleidic Associates
-------------------------
We are a boutique consultancy that advises a small number of hedge fund clients.
We are not accepting new clients currently, but if you are interested in working
either remotely or locally in London or Hong Kong, and if you are a talented
hacker with a moral compass who aspires to excellence then feel free to drop me
a line: laeeth at kaleidic.io

We work with our partner Symmetry Investments, and some background on the firm
can be found here:

http://symmetryinvestments.com/about-us/
