package shaders;

class ShaderCompatibility
{
	/** Warning dell'ultima chiamata a adaptRuntimeShaderCode (il chiamante decide se stamparli). */
	public static var warnings:Array<String> = [];

	public static function adaptRuntimeShaderCode(source:String, shaderName:String = null, stage:String = "fragment"):String
	{
		if (source == null)
			return null;

		var code:String = source.replace("\r\n", "\n").replace("\r", "\n");
		var dialect:String = getShaderDialect(code, shaderName);

		if (dialect != null)
			code = stripDialectPragmas(code);
		warnings = [];
		code = stripUniformInitializers(code);
		code = fixMainImageEntry(code);
		code = localizeOpenFLGlobalInitializers(code);
		warnUnsupportedUniforms(code);

		if (stage == "fragment" && dialect != null)
		{
			switch (dialect)
			{
				case "notitg":
					code = adaptNotITGFragment(code);
				case "shadertoy":
					code = adaptShadertoyFragment(code);
				default:
			}
		}

		return normalizeStrictConstructors(code);
	}

	static function getShaderDialect(source:String, shaderName:String):String
	{
		var lower:String = source.toLowerCase();
		if (hasDialectFlag(lower, "notitg"))
			return "notitg";
		if (hasDialectFlag(lower, "shadertoy"))
			return "shadertoy";

		if (shaderName != null)
		{
			var name:String = shaderName.toLowerCase();
			if (StringTools.startsWith(name, "notitg:") || StringTools.startsWith(name, "notitg/"))
				return "notitg";
			if (StringTools.startsWith(name, "shadertoy:") || StringTools.startsWith(name, "shadertoy/"))
				return "shadertoy";
		}

		return null;
	}

	static function hasDialectFlag(source:String, dialect:String):Bool
	{
		return source.indexOf("#pragma " + dialect) != -1
			|| source.indexOf("#pragma shader_dialect " + dialect) != -1
			|| source.indexOf("#pragma shader-dialect " + dialect) != -1
			|| source.indexOf("@shader_dialect " + dialect) != -1
			|| source.indexOf("@shader-dialect " + dialect) != -1;
	}

	static function stripDialectPragmas(source:String):String
	{
		var lines:Array<String> = source.split("\n");
		for (i in 0...lines.length)
		{
			var line:String = lines[i];
			var lower:String = StringTools.trim(line).toLowerCase();
			if (StringTools.startsWith(lower, "#pragma notitg")
				|| StringTools.startsWith(lower, "#pragma shadertoy")
				|| StringTools.startsWith(lower, "#pragma shader_dialect")
				|| StringTools.startsWith(lower, "#pragma shader-dialect")
				|| lower.indexOf("@shader_dialect ") != -1
				|| lower.indexOf("@shader-dialect ") != -1)
			{
				lines[i] = "";
			}
		}
		return lines.join("\n");
	}

	static function stripVersionPragmas(source:String):String
	{
		var version:EReg = ~/^\s*#version\s+[0-9]+\s*.*$/gm;
		return version.replace(source, "");
	}

	static function stripUniformInitializers(source:String):String
	{
		var uniformInit:EReg = ~/^(\s*uniform\s+(?:(?:lowp|mediump|highp)\s+)?[A-Za-z_][A-Za-z0-9_]*\s+[A-Za-z_][A-Za-z0-9_]*(?:\s*\[[^\]]+\])?)\s*=\s*[^;]+;\s*$/;
		var lines:Array<String> = source.split("\n");
		for (i in 0...lines.length)
		{
			var line:String = lines[i];
			if (uniformInit.match(line))
				lines[i] = uniformInit.matched(1) + ";";
		}
		return lines.join("\n");
	}

	/**
	 * Un global con inizializzatore che dipende da openfl_* (varying/uniform di runtime)
	 * non e' valido in GLSL stretto. Lo trasformiamo in:
	 *   - dichiarazione globale SENZA inizializzatore (cosi' resta visibile a tutte le funzioni)
	 *   - assegnazione come prime righe di main()
	 * Non dichiariamo mai una variabile nuova dentro main: un `vec2 uv = ...;` locale dell'utente
	 * nello stesso scope darebbe "redefinition" e quindi nero.
	 */
	static function localizeOpenFLGlobalInitializers(source:String):String
	{
		var lines:Array<String> = source.split("\n");
		var clean:Array<String> = stripComments(lines);
		var assignments:Array<String> = [];
		var globalInit:EReg = ~/^(\s*(?:(?:lowp|mediump|highp)\s+)?(?:float|int|bool|vec[234]|mat[234])\s+([A-Za-z_][A-Za-z0-9_]*))\s*=\s*([^;]*openfl_[^;]*);\s*$/;
		var depth:Int = 0;

		for (i in 0...lines.length)
		{
			var line:String = clean[i];
			if (depth == 0 && globalInit.match(line))
			{
				assignments.push("\t" + globalInit.matched(2) + " = " + StringTools.trim(globalInit.matched(3)) + ";");
				lines[i] = globalInit.matched(1) + ";";
			}

			depth += countChar(line, "{");
			depth -= countChar(line, "}");
			if (depth < 0)
				depth = 0;
		}

		if (assignments.length == 0)
			return source;

		var mainDecl:EReg = ~/^\s*void\s+main\s*\(/;
		var mainLine:Int = -1;
		for (i in 0...lines.length)
		{
			if (mainDecl.match(clean[i]))
			{
				mainLine = i;
				break;
			}
		}

		// Cerca la prima '{' a partire dalla riga di main.
		var braceLine:Int = -1;
		var braceIdx:Int = -1;
		if (mainLine != -1)
		{
			for (j in mainLine...lines.length)
			{
				braceIdx = clean[j].indexOf("{");
				if (braceIdx != -1)
				{
					braceLine = j;
					break;
				}
			}
		}

		if (braceLine == -1)
		{
			warnings.push("Global con openfl_* trovati ma nessun void main() valido: shader lasciata invariata.");
			return source;
		}

		var raw:String = lines[braceLine];
		lines[braceLine] = raw.substr(0, braceIdx + 1) + "\n" + assignments.join("\n") + "\n" + raw.substr(braceIdx + 1);
		return lines.join("\n");
	}

	/**
	 * `void mainImage()` (senza argomenti, stile template Psych) + `#define mainImage main`
	 * -> `void main()`, rimuovendo la define. La firma Shadertoy completa
	 * `mainImage(out vec4, in vec2)` NON viene toccata qui (la gestisce il dialetto "shadertoy").
	 */
	static function fixMainImageEntry(source:String):String
	{
		var noArgMainImage:EReg = ~/\bvoid\s+mainImage\s*\(\s*(?:void)?\s*\)/;
		if (!noArgMainImage.match(source))
			return source;

		var hasMain:EReg = ~/\bvoid\s+main\s*\(/;
		if (hasMain.match(source))
			return source;

		var defineMain:EReg = ~/^[ \t]*#define[ \t]+mainImage[ \t]+main[ \t]*$/gm;
		var code:String = defineMain.replace(source, "");
		return noArgMainImage.replace(code, "void main()");
	}

	static function warnUnsupportedUniforms(source:String):Void
	{
		var clean:String = stripComments(source.split("\n")).join("\n");
		for (name in ["iChannel1", "iChannel2", "iChannel3", "iMouse", "iDate", "iFrame"])
			if (new EReg("\\b" + name + "\\b", "").match(clean))
				warnings.push(name + " non e' supportato da Psych: la shader potrebbe non compilare o dare risultati errati.");
	}

	/** Sostituisce i commenti con spazi, mantenendo numero di righe e posizioni dei caratteri. */
	static function stripComments(lines:Array<String>):Array<String>
	{
		var result:Array<String> = [];
		var inBlock:Bool = false;
		for (line in lines)
		{
			var out:StringBuf = new StringBuf();
			var i:Int = 0;
			while (i < line.length)
			{
				var c:String = line.charAt(i);
				var n:String = i + 1 < line.length ? line.charAt(i + 1) : "";
				if (inBlock)
				{
					if (c == "*" && n == "/")
					{
						inBlock = false;
						out.add("  ");
						i += 2;
					}
					else
					{
						out.add(" ");
						i++;
					}
				}
				else if (c == "/" && n == "*")
				{
					inBlock = true;
					out.add("  ");
					i += 2;
				}
				else if (c == "/" && n == "/")
				{
					for (_ in i...line.length)
						out.add(" ");
					i = line.length;
				}
				else
				{
					out.add(c);
					i++;
				}
			}
			result.push(out.toString());
		}
		return result;
	}

	static function countChar(source:String, char:String):Int
	{
		var count:Int = 0;
		for (i in 0...source.length)
			if (source.charAt(i) == char)
				count++;
		return count;
	}

	static function adaptNotITGFragment(source:String):String
	{
		var code:String = source;
		var needsHeader:Bool = code.indexOf("#pragma header") == -1;
		var usedLegacyColor:Bool = code.indexOf("color") != -1;

		code = stripVersionPragmas(code);
		code = removeBuiltinDeclarations(code);
		code = replaceWord(code, "sampler0", "bitmap");
		code = replaceWord(code, "imageCoord", "openfl_TextureCoordv");
		code = replaceWord(code, "textureCoord", "openfl_TextureCoordv");
		code = replaceWord(code, "imageSize", "openfl_TextureSize");
		code = replaceWord(code, "textureSize", "openfl_TextureSize");
		code = replaceWord(code, "resolution", "openfl_TextureSize");
		code = replaceTexture2DBiasCalls(code);

		if (usedLegacyColor)
			code = "#define color vec4(1.0)\n" + code;
		if (needsHeader)
			code = "#pragma header\n\n" + code;

		return code;
	}

	static function adaptShadertoyFragment(source:String):String
	{
		var code:String = stripVersionPragmas(source);
		var needsHeader:Bool = code.indexOf("#pragma header") == -1;
		var usesITime:Bool = code.indexOf("iTime") != -1;
		var hasITimeUniform:Bool = code.indexOf("uniform float iTime") != -1;

		code = removeBuiltinDeclarations(code, [
			"iResolution" => true,
			"iChannel0" => true
		]);
		code = replaceWord(code, "iResolution", "vec3(openfl_TextureSize, 1.0)");
		code = replaceWord(code, "iChannel0", "bitmap");
		code = replaceWord(code, "texture", "texture2D");

		if (usesITime && !hasITimeUniform)
			code = "uniform float iTime;\n" + code;

		if (code.indexOf("void mainImage") != -1 && code.indexOf("void main()") == -1)
		{
			code += "\n\nvoid main()\n{\n\tvec4 fragColor = vec4(0.0);\n\tmainImage(fragColor, openfl_TextureCoordv * openfl_TextureSize);\n\tgl_FragColor = fragColor;\n}\n";
		}

		if (needsHeader)
			code = "#pragma header\n\n" + code;

		return code;
	}

	static function removeBuiltinDeclarations(source:String, ?builtins:Map<String, Bool>):String
	{
		var lines:Array<String> = source.split("\n");
		if (builtins == null)
		{
			builtins = [
				"color" => true,
				"textureCoord" => true,
				"imageCoord" => true,
				"textureSize" => true,
				"imageSize" => true,
				"resolution" => true,
				"sampler0" => true
			];
		}

		for (i in 0...lines.length)
		{
			var trimmed:String = StringTools.trim(lines[i]);
			if (isBuiltinDeclaration(trimmed, builtins))
				lines[i] = "";
		}
		return lines.join("\n");
	}

	static function isBuiltinDeclaration(line:String, builtins:Map<String, Bool>):Bool
	{
		if (!(StringTools.startsWith(line, "uniform ") || StringTools.startsWith(line, "varying ")))
			return false;
		if (!StringTools.endsWith(line, ";"))
			return false;

		var declaration:String = line.substr(0, line.length - 1);
		var parts:Array<String> = declaration.split(" ");
		if (parts.length < 3)
			return false;

		var name:String = parts[parts.length - 1];
		var bracket:Int = name.indexOf("[");
		if (bracket != -1)
			name = name.substr(0, bracket);
		return builtins.exists(name);
	}

	static function replaceTexture2DBiasCalls(source:String):String
	{
		var code:String = source;
		var search:String = "texture2D(";
		var index:Int = code.indexOf(search);
		while (index != -1)
		{
			var startArgs:Int = index + search.length;
			var end:Int = findMatchingParen(code, startArgs - 1);
			if (end == -1)
				break;

			var args:String = code.substr(startArgs, end - startArgs);
			var split:Array<String> = splitTopLevelArgs(args);
			if (split.length >= 2)
			{
				var sampler:String = StringTools.trim(split[0]);
				var coord:String = StringTools.trim(split[1]);
				var functionName:String = sampler == "bitmap" ? "flixel_texture2D" : "texture2D";
				var replacement:String = functionName + "(" + sampler + ", " + coord + ")";
				code = code.substr(0, index) + replacement + code.substr(end + 1);
				index = code.indexOf(search, index + replacement.length);
			}
			else
				index = code.indexOf(search, end + 1);
		}
		return code;
	}

	static function splitTopLevelArgs(args:String):Array<String>
	{
		var result:Array<String> = [];
		var depth:Int = 0;
		var start:Int = 0;
		for (i in 0...args.length)
		{
			var char:String = args.charAt(i);
			switch (char)
			{
				case "(":
					depth++;
				case ")":
					if (depth > 0)
						depth--;
				case ",":
					if (depth == 0)
					{
						result.push(args.substr(start, i - start));
						start = i + 1;
					}
				default:
			}
		}
		result.push(args.substr(start));
		return result;
	}

	static function findMatchingParen(source:String, openIndex:Int):Int
	{
		var depth:Int = 0;
		for (i in openIndex...source.length)
		{
			var char:String = source.charAt(i);
			if (char == "(")
				depth++;
			else if (char == ")")
			{
				depth--;
				if (depth == 0)
					return i;
			}
		}
		return -1;
	}

	static function normalizeStrictConstructors(source:String):String
	{
		var code:String = source;
		for (typeName in ["mat2", "mat3", "mat4", "vec2", "vec3", "vec4"])
		{
			code = code.replace(typeName + "(0)", typeName + "(0.0)");
			code = code.replace(typeName + "(1)", typeName + "(1.0)");
		}
		return code;
	}

	static function hasAny(source:String, needles:Array<String>):Bool
	{
		for (needle in needles)
			if (source.indexOf(needle) != -1)
				return true;
		return false;
	}

	static function replaceWord(source:String, word:String, replacement:String):String
	{
		var reg:EReg = new EReg("\\b" + word + "\\b", "g");
		return reg.replace(source, replacement);
	}
}

