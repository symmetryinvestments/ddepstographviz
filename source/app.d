import std.stdio;

import std.array : array, empty, front, popBack, replace;
import std.algorithm.searching : find, startsWith;
import std.algorithm.iteration : each, filter, map, joiner, splitter;
import std.algorithm.sorting : sort;
import std.algorithm.iteration : uniq;
import std.typecons : nullable, Nullable;
import std.format : format, formattedWrite;
import std.range : tee;
import std.string : split;
import std.getopt;

void main(string[] args) {
	string[] toExcludeInput;
	auto goRslt = getopt(args, "e|exclude", &toExcludeInput);

	Exclude[] toExclude = toExcludeInput
		.map!(it => it.splitter(","))
		.joiner
		.map!(it => Exclude(it))
		.array;
	auto f = File("deps.txt", "r");
	Line[] lines = splitInput(f.byLine, toExclude);
	//writefln("%(%s\n%)", lines);
	Node[] nodes = linesToNodes(lines);
	//print(nodes);
	toDOT(stdout.lockingTextWriter, nodes);
}

struct Exclude {
	string full;
	string[] seg;

	this(string s) {
		this.full = s;
		this.seg = s.split('.');
	}
}

struct Line {
	string[] from;
	string visability;
	string to;
	string[] what;
}

Line toLineSimple(string s) {
	Line ret;
	ret.from = s.split(".");
	return ret;
}

string dropAfterSpace(string s) {
	import std.string : indexOf;
	auto i = s.indexOf(' ');
	return i == -1 ? s : s[0 .. i];
}

Nullable!Line splitLine(char[] lineIn) {
	import std.algorithm.iteration : splitter;
	import std.string : split, strip;
	string line = lineIn.idup;
	auto sp = line.splitter(":");
	if(sp.empty) {
		return Nullable!(Line).init;
	}
	Line l;
	l.from = sp.pop().strip().dropAfterSpace().split('.');
	l.visability = sp.pop().strip;
	l.to = sp.pop().strip().dropAfterSpace();
	if(!sp.empty) {
		l.what = sp.front.split(',');
	}
	return nullable(l);
}

bool mustBeExcluded(Line line, Exclude[] toExclude) {
	foreach(it; toExclude) {
		if(line.from.startsWith(it.seg)) {
			return true;
		}
		if(line.to.startsWith(it.full)) {
			return true;
		}
	}
	return false;
}

Line[] splitInput(IRange)(IRange input, Exclude[] toExclude) {
	import std.array : array;
	import std.algorithm.iteration : map, splitter, filter;
	return input
		.filter!(line => !line.empty)
		.map!((line) => splitLine(line))
		.filter!(nullLine => !nullLine.isNull())
		.map!(notNullLine => notNullLine.get())
		.filter!(line => !line.mustBeExcluded(toExclude))
		.array;
}

auto pop(R)(auto ref R range) {
	scope (success)
		range.popFront();

	return range.front;
}

struct Edge {
	string to;
	string[] fields;

	this(Line l) {
		this.to = l.to;
		if(l.what.empty) {
			this.fields ~= "package";
		} else {
			this.fields ~= l.what;
		}
	}

	string toString() const {
		return format("Edge(to: %s, fields: [%(%s,%)])",
				this.to, this.fields);
	}
}

class Node {
	string name;
	Edge[] connections;
	Node[] subNodes;

	this(Line l) {
		this.name = l.from.front;
		this.subNodes = new Node[0];
		this.connections = [ Edge(l) ];
 	}

	void add(Edge con) {
		auto f = this.connections.find!( (o, n) => o.to == n.to)(con);
		if(f.empty) {
			this.connections ~= con;
		} else {
			f.front.fields ~= con.fields;
			f.front.fields = f.front.fields.sort.uniq.array;
		}
	}

	override string toString() const {
		return format(
			"Node(name: %s, subNodes: [%(%s,%)], connections: [%(%s,%)])", 
				this.name, this.subNodes, this.connections);
	}
}

void indent(Out)(auto ref Out o, size_t d) {
	for(size_t i = 0; i < d; ++i) {
		formattedWrite(o, "\t");
	}
}

void print(Node[] nodes) {
	nodes.each!(node => print(node, 0))();
}

void print(Node node, int depth) {
	indent(stdout.lockingTextWriter(), depth);
	writefln("%2d Node(name: %s", depth, node.name);
	indent(stdout.lockingTextWriter(), depth + 1);
	writefln("connections:", node.name);
	foreach(e; node.connections) {
		indent(stdout.lockingTextWriter(), depth + 2);
		writeln(e);
	}
	indent(stdout.lockingTextWriter(), depth + 1);
	writeln("subNodes:");
	foreach(sn; node.subNodes) {
		print(sn, depth + 2);
	}
}

void toDOT(Out)(auto ref Out o, Node[] nodes) {
	formattedWrite(o, "digraph Deps {\n");	
	foreach(n; nodes) {
		toDOT(o, n, [n.name]);
	}
	formattedWrite(o, "\n\n");	
	foreach(n; nodes) {
		toDOTEdges(o, n, [n.name]);
	}
	formattedWrite(o, "}\n");	
}

void toDOT(Out)(auto ref Out o, Node node, string[] stack) {
	indent(o, stack.length);
	if(node.subNodes.empty) {
		formattedWrite(o, "%-(%s_%) [label=\"%s\"];\n", 
				stack.map!(it => it == "graph" ?  "_graph" : it),
				node.name);
	} else {
		string n = node.name.replace('.', '_');
		n = n == "graph" ? "_graph" : n;
		formattedWrite(o, "subgraph cluster%s {\n", n);
		indent(o, stack.length + 1);
		formattedWrite(o, "label=\"%s\";\n", n);
		indent(o, stack.length + 1);
		formattedWrite(o, "labeljust=l;\n");
		foreach(sn; node.subNodes) {
			stack ~= sn.name;
			toDOT(o, sn, stack);
			stack.popBack();
		}
		indent(o, stack.length);
		formattedWrite(o, "}\n");
	}
}

void toDOTEdges(Out)(auto ref Out o, Node node, string[] stack) {
	foreach(e; node.connections.filter!(con => !con.to.empty)) {
		string to = format("%s", e.to
			.splitter(".")
			.map!(it => it == "graph" ?  "_graph" : it)
			.joiner("_"));
		//to = to == "graph" ? "_graph" : to;
		string from = format("%-(%s_%)", 
				stack.map!(it => it == "graph" ?  "_graph" : it));
		from = node.subNodes.empty ? from : "cluster" ~ from;
		if(from.startsWith("cluster")) {
			continue;
		}
		//from = from == "graph" ? "_graph" : from;
		formattedWrite(o, "\t%s -> %s;\n", from, to);
	}
	foreach(sn; node.subNodes) {
		stack ~= sn.name;
		toDOTEdges(o, sn, stack);
		stack.popBack();
	}
}

Node[] linesToNodes(Line[] lines) {
	Node[] nodes = new Node[0];
	// The lines
	lines
		//.filter!(line => line.from.front == "ngd")
		.each!(line => insertInto(line, nodes));

	// Turn the connections into lines as well
	lines
		.map!(line => toLineSimple(line.to))
		//.filter!(line => line.from.front == "ngd")
		.each!(line => insertInto(line, nodes));

	return nodes;
}

void insertInto(Line line, ref Node[] nodes) {
	import std.array : back, popFront;
	auto n = nodes.find!( (n, l) => n.name == l.from.front)(line);
	if(!n.empty 
			&& line.from.length == 1 
			&& n.front.name == line.from.front) 
	{
		if(!line.to.empty) {
			n.front.add(Edge(line));
		}
		return;
	} else if(n.empty || line.from.length == 1) {
		nodes ~= new Node(line);
		//writeln(nodes.back);
		return;
	} else {
		Line c = line;
		//writefln("Before %s", c);
		c.from.popFront();
		//writefln("After  %s", c);
		insertInto(c, n.front.subNodes);
		return;
	}
	assert(false, format("%s", line));
}
