import std.stdio;

import std.array : array, empty, front, popBack, popFront, replace;
import std.algorithm.searching : canFind, find, startsWith;
import std.algorithm.iteration : each, filter, map, joiner, splitter;
import std.algorithm.sorting : sort;
import std.algorithm.iteration : uniq;
import std.exception : enforce;
import std.typecons : nullable, Nullable;
import std.format : format, formattedWrite;
import std.range : tee;
import std.string : split;
import std.getopt;

void main(string[] args) {
	string[] toExcludeInput;
	auto goRslt = getopt(args, 
			"e|exclude", "Symbols to exclude, can be comma seperated",
				&toExcludeInput,
			"t|trimPackageInternal", 
				"Remove edges between module inside the same package",
				&_options.trimPackageInternal,
			"d|trimPackageDownEdges", 
				"Remove edges that point down the package tree",
				&_options.trimPackageDownEdges,
			"o|outputfilename", "The filename of the output file",
				&_options.outputFileName,
			"i|inputfilename", "The filename of the input file",
				&_options.inputFileName
			);

	if(goRslt.helpWanted) {
		defaultGetoptPrinter(
`Take dmd -deps output and turn it into pretty colorful pictures.
After the output was written use the dot language (graphviz) tool fdp to turn
the output file into a viewable picture.

For example:
$ ddepstographvic -e std,core,object -i deps.txt -o deps.dot
$ fdp -T svg deps.dot > deps.svg

Options:`,
			goRslt.options);
		return;
	}

	_options.toExclude = toExcludeInput
		.map!(it => it.splitter(","))
		.joiner
		.map!(it => Exclude(it))
		.array;
	auto f = File(options.inputFileName, "r");
	Line[] lines = splitInput(f.byLine);
	//writefln("%(%s\n%)", lines);
	Node[] nodes = linesToNodes(lines);
	//print(nodes);
	if(options.outputFileName.empty) {
		toDOT(stdout.lockingTextWriter, nodes);
	} else {
		auto of = File(options.outputFileName, "w");
		auto ltw = of.lockingTextWriter();
		toDOT(ltw, nodes);
	}
}

struct Options {
	string inputFileName = "deps.txt";
	string outputFileName = "deps.dot";
	bool trimPackageInternal = false;
	bool trimPackageDownEdges = false;
	Exclude[] toExclude;
}

private Options _options;
@property ref const(Options) options() {
	return _options;
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
	string visibility;
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
	l.visibility = sp.pop().strip;
	if(!canFind(["private", "public", "protected"], l.visibility)) {
		return Nullable!(Line).init;
	}
	l.to = sp.pop().strip().dropAfterSpace();
	if(!sp.empty) {
		l.what = sp.front.split(',');
	}
	return nullable(l);
}

bool mustBeExcluded(Line line, const(Exclude[]) toExclude) {
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

Line[] splitInput(IRange)(IRange input) {
	import std.array : array;
	import std.algorithm.iteration : map, splitter, filter;
	return input
		.filter!(line => !line.empty)
		.map!((line) => splitLine(line))
		.filter!(nullLine => !nullLine.isNull())
		.map!(notNullLine => notNullLine.get())
		.filter!(line => !line.mustBeExcluded(options.toExclude))
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
	const(Node) parent;
	string name;
	string color;
	Edge[] connections;
	Node[] subNodes;
	
	this(Line l) {
		this(l, null);
 	}

	this(Line l, Node parent) {
		this.name = l.from.front;
		this.subNodes = new Node[0];
		this.connections = [ Edge(l) ];
		this.parent = parent;
 	}

	@property bool isCluster() const {
		return !this.subNodes.empty;
	}

	@property bool isOnRootLevel() const {
		return parent is null;
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
	//formattedWrite(o, "\tcompound=true;\n");
 
	foreach(n; nodes) {
		toDOT(o, n, [n.name]);
	}
	formattedWrite(o, "\n\n");	
	foreach(n; nodes) {
		toDOTEdges(o, n, [n.name], nodes);
	}
	formattedWrite(o, "}\n");	
}

void toDOT(Out)(auto ref Out o, Node node, string[] stack) {
	indent(o, stack.length);
	if(node.isCluster) {
		string n = node.name.replace('.', '_');
		n = n == "graph" ? "_graph" : n;
		formattedWrite(o, "subgraph cluster%-(%s_%) {\n", 
				stack.map!(it => it == "graph" ?  "_graph" : it));
		//indent(o, stack.length + 1);
		//formattedWrite(o, "compound=true;\n");
		indent(o, stack.length + 1);
		formattedWrite(o, "rankdir=\"%s\";\n", 
				stack.length % 2 == 0 ? "TB" : "LR");
		indent(o, stack.length + 1);
		formattedWrite(o, "label=\"%s\";\n", node.name);
		indent(o, stack.length + 1);
		formattedWrite(o, "labeljust=l;\n");
		indent(o, stack.length + 1);
		formattedWrite(o, "color=\"%s\";\n", node.color);
		foreach(sn; node.subNodes) {
			stack ~= sn.name;
			toDOT(o, sn, stack);
			stack.popBack();
		}
		indent(o, stack.length);
		formattedWrite(o, "}\n");
	} else {
		formattedWrite(o, "%-(%s_%) [label=\"%s\",color=\"%s\"];\n", 
				stack.map!(it => it == "graph" ?  "_graph" : it),
				node.name, node.color);
	}
}

void toDOTEdges(Out)(auto ref Out o, Node node, string[] stack, 
		const(Node)[] graph) 
{
	foreach(e; node.connections.filter!(con => !con.to.empty)) {
		const(Node) toNode = graph.findNode(e.to);
		if(toNode is null) {
			writefln("Couldn't find '%s' in the graph", e.to);
			continue;
		}

		// Exclude same level edges
		const(Node) toParent = toNode.parent;
		const(Node) fromParent = node.parent;
		if(options.trimPackageInternal
				&& toParent !is null
				&& toParent is fromParent)
		{
			continue;
		}

		if(options.trimPackageDownEdges
				&& fromParent !is null
				&& fromParent.subNodes.containsNode(toNode))
		{
			continue;
		}

		string to = format("%s", e.to
			.splitter(".")
			.map!(it => it == "graph" ?  "_graph" : it)
			.joiner("_"));
		to = toNode.isCluster ? "cluster" ~ to : to;

		string from = format("%-(%s_%)", 
				stack.map!(it => it == "graph" ?  "_graph" : it));
		from = node.isCluster ? "cluster" ~ from : from;

		// No internal edges
		auto f = node.subNodes
				.find!( (const(Node) n, const(Node) o) => n.name == o.name)(toNode);

		if(!f.empty) {
			continue;
		}

		const ltail = node.isCluster ? format("ltail=%s", from) : "";
		const lhead = toNode.isCluster ? format("lhead=%s", to) : "";
		const th = ltail.empty && lhead.empty 
				? "[" 
				: format("[%s %s, ", ltail, lhead);
		const color = format("color=\"%s\", ", node.color);
		const label = "label=\"*\", ";
		const labeltooltip = canFind(e.fields, "package") 
			? "labeltooltip=\"package\"" 
			: format("labeltooltip=\"%-(%s\\n%)\"", e.fields);

		const bool atLeastOnCluster = node.isCluster || toNode.isCluster;

		formattedWrite(o, "\t%s -> %s%s%s%s%s]\n", from, to,
				th, color, label, labeltooltip);
	}
	foreach(sn; node.subNodes) {
		stack ~= sn.name;
		toDOTEdges(o, sn, stack, graph);
		stack.popBack();
	}
}

bool containsNode(const(Node)[] graph, const(Node) toFind) {
	if(toFind is null) {
		return false;
	}

	foreach(it; graph) {
		if(it is toFind) {
			return true;
		}
		if(containsNode(it.subNodes, toFind)) {
			return true;
		}
	}
	return false;
}

const(Node) findNode(const(Node)[] graph, string to) {
	return findNodeImpl(graph, to.split("."));
}

const(Node) findNodeImpl(const(Node)[] graph, string[] to) {
	auto f = graph.find!( (const(Node) n, string name) => n.name == name)(to.front);
	to.popFront();
	return to.empty && !f.empty 
		? f.front 
		: !to.empty && !f.empty
			? findNodeImpl(f.front.subNodes, to)
			: null;
}

Node[] linesToNodes(Line[] lines) {
	Node[] nodes = new Node[0];
	// The lines
	lines
		//.filter!(line => line.from.front == "ngd")
		.each!(line => insertInto(line, nodes, null));

	// Turn the connections into lines as well
	lines
		.map!(line => toLineSimple(line.to))
		//.filter!(line => line.from.front == "ngd")
		.each!(line => insertInto(line, nodes, null));

	return nodes;
}

void insertInto(Line line, ref Node[] nodes, Node parent) {
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
		nodes ~= new Node(line, parent);
		nodes.back.color = nextColor();
		//writeln(nodes.back);
		return;
	} else {
		Line c = line;
		//writefln("Before %s", c);
		c.from.popFront();
		//writefln("After  %s", c);
		insertInto(c, n.front.subNodes, n.front);
		return;
	}
	assert(false, format("%s", line));
}

immutable(string[]) colors = [
	"cadetblue2", "darkolivegreen", "darkviolet", "darkseagreen1",
	"floralwhite", "darkgoldenrod", "aquamarine1", "black", "chartreuse3",
	"gold3", "darkseagreen2", "cyan2", "bisque4", "antiquewhite",
	"darkseagreen", "forestgreen", "coral4", "darkgoldenrod2", "dodgerblue3",
	"darkorange2", "antiquewhite3", "chartreuse2", "goldenrod1", "goldenrod4",
	"dodgerblue", "darkorange3", "chocolate3", "burlywood3", "crimson",
	"antiquewhite4", "darkslategrey", "darkslategray1", "firebrick1",
	"chartreuse", "dimgrey", "darkgreen", "darkgoldenrod3", "aquamarine2",
	"bisque3", "cyan4", "bisque2", "coral", "goldenrod", "burlywood2",
	"deeppink1", "deepskyblue1", "deepskyblue3", "bisque1", "cadetblue",
	"blue3", "dodgerblue1", "deeppink", "coral1", "darkorchid3",
	"antiquewhite1", "bisque", "firebrick3", "blue2", "gold", "blueviolet",
	"goldenrod3", "burlywood4", "cyan3", "firebrick2", "firebrick",
	"darkorange", "beige", "darkseagreen3", "darkolivegreen1", "gold4",
	"firebrick4", "burlywood", "darkslategray3", "cornflowerblue",
	"blanchedalmond", "brown1", "aquamarine", "chocolate", "darkorchid4",
	"darkslategray2", "chocolate4", "deepskyblue", "azure", "gold2",
	"aquamarine3", "darkseagreen4", "darkolivegreen2", "cornsilk1", "brown3",
	"chartreuse4", "azure1", "darkkhaki", "goldenrod2", "darkorchid",
	"deepskyblue2", "deepskyblue4", "darksalmon", "deeppink2", "gold1",
	"cornsilk", "burlywood1", "blue1", "darkgoldenrod4", "darkturquoise",
	"cyan1", "chartreuse1", "darkorange4", "cyan", "darkolivegreen4",
	"blue4", "darkolivegreen3", "cornsilk4", "aquamarine4", "brown2", "coral3",
	"darkslateblue", "aliceblue", "cadetblue3", "cadetblue1", "brown",
	"gainsboro", "antiquewhite2", "coral2", "chocolate2", "darkslategray4",
	"azure2", "darkorchid2", "deeppink4", "darkslategray", "blue", "cornsilk2",
	"ghostwhite", "azure3", "darkgoldenrod1", "darkorange1", "azure4",
	"chocolate1", "darkorchid1", "dodgerblue2", "dimgray", "dodgerblue4",
	"cornsilk3", "cadetblue4", "brown4", "deeppink3"
];

string nextColor() {
	static size_t idx;
	string ret = colors[idx];
	idx = (idx + 1) % colors.length;
	return ret;
}
