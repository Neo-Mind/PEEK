function StructParserGen() {
	var intxt = new TextFile();
	var outtxt = new TextFile();
	if (!intxt.open(APP_PATH + "/Input/structs.c", "r") ) {
		throw "Unable to open Input/structs.c for reading";
	}
	if (!outtxt.open(APP_PATH + "/Output/structs.qs", "w") ) {
		throw "Unable to open Output/structs.qs for writing";
	}
	
	var packet_id = -1;
	var model_stack =  new Array();
	var tabbing = "";
	var spacing = "";
	var struct_chain = new Array();//needed for var identifications other than the ip & such
	
	while(!intxt.eof()) {
		var line = intxt.readline().trim();
		
		//Find the packet id comment
		if ( line.match(/^\/\/\s*packet\s+0x([0-9a-fA-F]+)/) ) {
			packet_id = RegExp.$1;
			continue;
		}
		
		//Start of main struct
		if ( line.match(/^struct\s+(\S*?)\s+{/) ) {
			if (packet_id === -1) {
				throw "Found struct without a packet id comment";
			}
			outtxt.writeline("\n//packet = 0x" + packet_id);
			outtxt.writeline("function " + RegExp.$1 + "() {");
			tabbing = "\t";
			outtxt.writeline(tabbing + "var result = '" + RegExp.$1 + " {\\n';");
			spacing = "    ";
			struct_chain.push(RegExp.$1);
			continue;
		}
		
		//Types in struct
		if ( line.match(/\/\*\s*this\+(0x\w+)\s*\*\/\s*(unsigned short|short|unsigned char|char|bool|unsigned long|long|unsigned int|int|int64|float)\s+(\w+)(?:\[(\d*|\.*)\])*/) ) {
			//skip the Packet ID
			if (RegExp.$3 === "PacketType") continue;
			
			outtxt.write(tabbing + "result += '" + spacing + RegExp.$3 + " = ' + ");
			switch(RegExp.$2) {
				case 'unsigned short':
				case 'short':
					var tmp = RegExp.$3;
					var tmp2 = RegExp.$4;
					if (tmp === "ITID" || tmp.match(/^card/i) ) {
						outtxt.write("getItemInfo()");
					}
					else if (tmp === "SKID") {
						outtxt.write("getSkillInfo()");
					}
					else if (tmp === "varID") {
						outtxt.write("getVarInfo()");
					}
					else if (tmp.match(/^job$/i)) {
						if (tmp2 === "") {
							outtxt.write("getJobInfo(2)");
						}
						else if(tmp2 === "...") {
							outtxt.write("getJobInfoList(-1, 2)");
						}
						else {
							outtxt.write("getJobInfoList(" + tmp2 + ",2)");
						}
					}
					else {
						if (tmp2 === "") {
							outtxt.write("parser.fetchWord()");
						}
						else if(tmp2 === "...") {
							outtxt.write("getWordList(-1)");
						}
						else {
							outtxt.write("getWordList(" + tmp2 + ")");
						}
					}
					break;
				
				case 'unsigned long':
					if (RegExp.$3 === "ip") {
						outtxt.write("getIPAddress()");
						break;
					}
					/*else if(RegExp.$3 === "statusType") {
						outtxt.write("getEFSTInfo()");
						break;
					}*/
					else if(RegExp.$3 === "ID") {//For Shortcut keys
						outtxt.write("getSkillOrItemInfo()");
						break;
					}
				case 'long':
					var tmp = RegExp.$3;
					var tmp2 = RegExp.$4;
					if (tmp.match(/^job$/i)) {
						if (tmp2 === "") {
							outtxt.write("getJobInfo(4)");
						}
						else if (tmp2 === "...") {
							outtxt.write("getJobInfoList(-1, 4)");
						}
						else {
							outtxt.write("getJobInfoList(" + tmp2 + ",4)");
						}
						break;
					}
				case 'unsigned int':
				case 'int'://WTF int and long are same?
					outtxt.write("parser.fetchDWord()");
					break;
					
				case 'int64'://highly unlikely
					outtxt.write("parser.fetchQWord()");
					break;
				
				case 'float':
					outtxt.write("parser.fetchFloat()");
					break;
					
				case 'unsigned char':
				case 'char':
					if (RegExp.$3 === "dir") {//not expected to be an array
						outtxt.write("getDir()");
					}
					else if (RegExp.$4 === "") {
						outtxt.write("parser.fetchByte()");
					}
					else if (RegExp.$4 === "...") {
						outtxt.write("'\"' + parser.fetchString(-1) + '\"'");
					}
					else if (RegExp.$4 === "3") {
						outtxt.write("getPos()");//Defined at bottom
					}
					else if (RegExp.$4 === "6") {
						outtxt.write("getMove()");//Defined at bottom
					}
					else {
						outtxt.write("'\"' + parser.fetchString(" + RegExp.$4 + ") + '\"'");
					}
					break;
					
				case 'bool':
					outtxt.write("parser.fetchBool()");
					break;
			}
			outtxt.writeline(" + '\\n';");
			continue;
		}
		
		//Start of Nested Struct
		if ( line.match(/\s*\/\*\s*this\+(0x\w+)\s*\*\/\s*struct\s*(\w+)\s*(\w+)(?:\[(\d*|\.*)\])*\s*{(?:\s*\/\/\s*Size\s*(\d*))*/) ) {
			outtxt.writeline(tabbing + "{");
			tabbing += "\t";
			if (RegExp.$4 === "") {
				model_stack.push(1);
				outtxt.writeline(tabbing + "result += '" + spacing + RegExp.$2 + " " + RegExp.$3 + " {\\n';");
			}
			else if (RegExp.$4 === "...") {
				model_stack.push(2);
				outtxt.writeline(tabbing + "var " + RegExp.$3 + " = parser.remainingLength()/" + RegExp.$5 + ";");
				outtxt.writeline(tabbing + "for (var i = 0; i < " + RegExp.$3 + "; i++) {");				
				tabbing += "\t";
				outtxt.writeline(tabbing + "result += '" + spacing + RegExp.$2 + " " + RegExp.$3 + "[' + i + '] {\\n';");
			}
			else {
				model_stack.push(2);
				outtxt.writeline(tabbing + "for (var i = 0; i < " + RegExp.$4 + "; i++) {");
				tabbing += "\t";
				outtxt.writeline(tabbing + "result += '" + spacing + RegExp.$2 + " " + RegExp.$3 + "[' + i + '] {\\n';");
			}
			spacing += "    ";
			struct_chain.push(RegExp.$2);//array index & struct varname not needed
			continue;
		}
		
		// End of Struct
		if (line.match(/^}/) ) {			
			spacing = spacing.substr(4);
			outtxt.writeline(tabbing + "result += '" + spacing + "}\\n';");
			
			if (model_stack.length === 0) {//Main
				outtxt.writeline(tabbing + "return result;");
				packet_id = -1;
			}
			
			var model = model_stack.pop();
			if (model === 2) {//Nested Struct with Loop - model 2
				tabbing = tabbing.substr(1);
				outtxt.writeline(tabbing + "}");
			}
			
			tabbing = tabbing.substr(1);
			outtxt.writeline(tabbing + "}");
			struct_chain.pop();
			continue;
		}
	}
	intxt.close();
	outtxt.close();
}


function getPos() {
	var p1 = parser.fetchByte();
	var p2 = parser.fetchByte();
	var p3 = parser.fetchByte();

	var data = p1 << 16 | p2 << 8 | p3;
	
	var dir = getDir(data & 0xF);
	var y = (data >>>  4) & 0x3FF;
	var x = (data >>> 14) & 0x3FF;
	
	return "[" + x + ", " + y + "] facing " + dir;
}

function getMove() {
	var p1 = parser.fetchByte();
	var p2 = parser.fetchByte();
	var p3 = parser.fetchByte();
	var p4 = parser.fetchByte();
	var p5 = parser.fetchByte();
	var p6 = parser.fetchByte();//contains only sx1 and sy1 hence discarded.

	var data = (p3 << 16 | p4 << 8 | p5); //3 Lower Bytes is needed for getting x2, y2
	var y2 = data & 0x3FF;
	var x2 = (data >>> 10) & 0x3FF;
	
	data >>>= 20;//Remove x2 and y2 data , 4 bits remain as part of y1
	data |= (p1 << 12 | p2 << 4);//insert remaining data bits
	var y1 = data & 0x3FF;
	var x1 = (data >>> 10) & 0x3FF;
	
	return "[" + x1 + "," + y1 + "] => [" + x2 + "," + y2 + "]";
}

function getDir(key) {
	if (key === "") {
		key = parser.fetchByte();
	}
	var dirs = new Array("North", "North East", "East", "South East", "South", "South West", "West", "North West");
	return dirs[key];
}

function getIPAddress() {
	var parts = new Array();
	for (var i = 0; i < 4; i++) {
		parts.push(parser.fetchByte());
	}
	return "[" + parts.join(".") + "]";
}

function getWordList(count) {
	if (count === -1) {
		count = parser.remainingLength()/2;
	}
	var words = new Array();
	for (var i = 0; i < count; i++) {
		words.push(parser.fetchWord());
	}
	return "[" + words.join(",") + "]";	
}

function getItemInfo() {
	var value = parser.fetchWord();
	if (value == 0) {
		return "None";
	}
	else {
		return value + " ("+ parser.getInfoFromDB("Items", value, "Undefined Item ID") + ")";
	}
}

function getSkillInfo() {
	var value = parser.fetchWord();
	return value + " ("+ parser.getInfoFromDB("Skills", value, "Undefined Skill ID") + ")";
}

function getSkillOrItemInfo() {
	var value = parser.fetchWord();
	if (value == 0) {
		return "None";
	}
	else {
		var infos = new Array();
		
		var info = parser.getInfoFromDB("Items", value);
		if (info !== "") infos.push(info);
		
		info = parser.getInfoFromDB("Skills", value);
		if (info !== "") infos.push(info);
		
		if (infos.length == 0) {
			return value + "( Undefined )";
		}
		else {
			return value + " ("+ infos.join(" or ") + ")";
		}
	}
}

function getEFSTInfo() {
	var value = parser.fetchWord();
	return value + " ("+ parser.getInfoFromDB("EffectStatus", value, "Undefined EFST value") + ")";
}

function getVarInfo() {
	var value = parser.fetchWord();
	return value + " ("+ parser.getInfoFromDB("Vars", value, "Undefined Var") + ")";
}

function getJobInfo(size) {
	if (size == 2) {
		var value = parser.fetchWord();
	}
	else {
		var value = parser.fetchDWord();
	}
	return value + " ("+ parser.getInfoFromDB("JobTypes", value, "Undefined Job ID") + ")";
}

function getJobInfoList(count, size) {
	if (count === -1) {
		count = parser.remainingLength()/size;
	}
	var values = new Array();
	for (var i = 0; i < count; i++) {
		if (size == 2) {
			var value = parser.fetchWord();
		}
		else {
			var value = parser.fetchDWord();
		}
		values.push(value + " ("+ parser.getInfoFromDB("JobTypes", value, "Undefined Job ID") + ")");
	}
	return "[" + values.join(",") + "]";
}
