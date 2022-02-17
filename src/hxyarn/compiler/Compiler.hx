package src.hxyarn.compiler;

import src.hxyarn.compiler.DeclarationVisitor.DeclaractionVisitor;
import src.hxyarn.program.types.BuiltInTypes;
import src.hxyarn.compiler.Stmt.StmtDialogue;
import src.hxyarn.program.Operand;
import src.hxyarn.program.Instruction;
import sys.FileSystem;
import src.hxyarn.program.Node;
import sys.io.File;
import src.hxyarn.program.Program;

class Compiler {
	var labelCount = 0;

	public var currentNode:Node;

	var rawTextNode = false; // TODO
	var program:Program;
	var fileName:String;

	public function new(fileName:String) {
		program = new Program();
		this.fileName = fileName;
	}

	public static function compileFile(path:String):CompilationResult {
		var string = File.read(path).readAll().toString();
		var directories = FileSystem.absolutePath(path).split('/');
		var fileName = directories[directories.length - 1];

		return handleYarn(string, fileName);
	}

	static function handleYarn(yarn:String, fileName:String):CompilationResult {
		var compiler = new Compiler(fileName);

		return compiler.compileYarn(yarn);
	}

	function compileYarn(yarn:String):CompilationResult {
		var tokens = Scanner.scan(yarn);
		var dialogue = new StmtParser(tokens).parse();

		var stringTableManager = new StringTableManager();

		var derivedVariableDeclarations = new Array<Declaration>();
		var knownVariableDeclarations = new Array<Declaration>();
		var typeDelaractions = BuiltInTypes.all;

		registerStrings(fileName, stringTableManager, dialogue);

		for (node in dialogue.nodes) {
			currentNode = new Node();
			for (header in node.headers) {
				if (header.id.lexeme == "title") {
					currentNode.name = StringTools.trim(header.value.lexeme);
				}
				if (header.id.lexeme == "tags") {
					var tags = [];
					if (header.value != null)
						tags = header.value.lexeme.split(',');

					currentNode.tags.concat(tags);
				}
			}
			currentNode.labels.set(registerLabel(), currentNode.instructions.length);
			var declaractionVisitor = new DeclaractionVisitor(fileName, knownVariableDeclarations, typeDelaractions);
			declaractionVisitor.visitNode(node);
			derivedVariableDeclarations = derivedVariableDeclarations.concat(declaractionVisitor.newDeclarations);
			knownVariableDeclarations = knownVariableDeclarations.concat(declaractionVisitor.newDeclarations);
			var checker = new TypeCheckVisitor(fileName, knownVariableDeclarations, typeDelaractions);
			checker.visitNode(node);
			var visitor = new CodeGenerationVisitor(this);
			visitor.visitNode(node);
			var hasRemainingOptions = false;
			for (instruction in currentNode.instructions) {
				if (instruction.opcode == OpCode.ADD_OPTIONS)
					hasRemainingOptions = true;

				if (instruction.opcode == OpCode.SHOW_OPTIONS)
					hasRemainingOptions = false;
			}

			if (hasRemainingOptions) {
				emit(OpCode.SHOW_OPTIONS, []);
				emit(OpCode.RUN_NODE, []);
			} else {
				emit(OpCode.STOP, []);
			}

			program.nodes.set(currentNode.name, currentNode);
		}

		var results = new CompilationResult();
		results.program = program;
		results.stringTable = stringTableManager.stringTable;
		results.declarations = derivedVariableDeclarations;

		return results;
	}

	function registerStrings(fileName:String, stringTableManager:StringTableManager, dialogue:StmtDialogue) {
		var visitor = new StringTableGeneratorVisitor(fileName, stringTableManager, this);
		visitor.visitDialogue(dialogue);
	}

	public function emit(opCode:OpCode, operands:Array<Operand>) {
		var instruction = new Instruction();
		instruction.opcode = opCode;
		instruction.operands = operands;

		currentNode.instructions.push(instruction);
	}

	public function getLineIdTag(hashtags:Array<String>):String {
		if (hashtags == null)
			return null;

		for (hashtag in hashtags) {
			if (StringTools.startsWith(hashtag, "line:"))
				return hashtag;
		}

		return null;
	}

	public function registerLabel(?commentary:String = null) {
		return 'L${labelCount++}$commentary';
	}
}
