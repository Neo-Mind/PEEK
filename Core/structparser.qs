function StructParser() {  
  var infile = new TextFile();
  if (!infile.open(APP_PATH + "/Input/structs.h", "r") ) {
    throw "Unable to open structs.h for reading";
  }
  
  var outfile = new TextFile();
  if (!outfile.open(APP_PATH + "/Output/structs.qs", "w") ) {
    throw "Unable to open structs.qs for writing";
  }
  
  var knownDefines = [];
  var knownStructs = [];
  
  var typeMap = {
    "uint64_t":0,
    
    "int64_t":1,
    
    "unsigned long":2,
		"unsigned int":2,
		"uint32_t":2,
    
    "long":3,
		"int":3,
		"int32_t":3,
    
    "unsigned short":4,
		"uint16_t":4,
    
    "short":5,
		"int16_t":5,
		
    "unsigned char":6,
    "unsigned byte":6,
		"uint8_t":6,
    
    "char":7,
    "byte":7,
		"int8_t":7,
    
    "bool":8,
    
    "float":9,
    
    "double":10
  };
  
  var funcList = [
    "fetchUint64",
    "fetchInt64",
    "fetchUint32",
    "fetchInt32",
    "fetchUint16",
    "fetchInt16",
    "fetchUint8",
    "fetchInt8",
    "fetchBool",
    "fetchFloat",
    "fetchDouble"
  ];

  outfile.writeline("var indent = '';");
  
  var sName = "";
  while (!infile.eof()) {
    var line = infile.readline().trim();
    
    if (line.match(/^\s*\/\//) || line.match(/^\s*\/\*.*\*\/\s*$/)) {//Comment alone
      continue;
    }
    else if (line.match(/^\s*};/)) {//End of Struct
      outfile.writeline("  indent = indent.slice(0, -1);");
      outfile.writeline("  result += indent + '}\\n';");
      outfile.writeline("  return result;");
      outfile.writeline("}");
      sName = "";
      continue;
    }
    else if (line.match(/^\s*struct\s+(\S+)/)) {//Struct declaration
      sName = RegExp.$1;
      
      knownStructs.push(sName);
      outfile.writeline("function " + sName + "() {");
      outfile.writeline("  var result = indent + '" + sName + " {\\n';");
      outfile.writeline("  indent += '\\t';");
        
      if (line.match(/:\s+public\s+(\S+)\s+{/)) {//Inheritance
        outfile.writeline("  result += " + RegExp.$1 + "();");
      }
      
      continue;
    }
    else if (line.match(/^\s*#define\s+(\S+)\s+(\S+)/)) {//Macro declaration
      if (isNaN(RegExp.$2)) {
        knownDefines[RegExp.$1] = RegExp.$2;//For substituting later
      }
      else {
        outfile.writeline("var " + RegExp.$1 + " = " + RegExp.$2 + ";");
      }
    }
    else {//Struct Member Declarations
      line = line.replace(/\/\*.*\*\//, "");//Remove Block Comments
      if (line.match(/\s*(.*)\s+(\S+);$/)) {
        var vtype = RegExp.$1;
        var vname = RegExp.$2;
        
        if (vtype in knownDefines)
          vtype = knownDefines[vtype];
        
        if (vtype in typeMap) {
          var funcEval = "reader." + funcList[typeMap[vtype]] + "()";
          var array_count = 1;
          
          if (vname.match(/\[(\w*)\]\[(\w*)\]/)) {
            funcEval = "reader." + funcList[typeMap[vtype]] + "Arr(" + RegExp.$2 + ")";
            array_count = RegExp.$1;
          }
          else if (vname.match(/\[(\w*)\]/)) {
            funcEval = "reader." + funcList[typeMap[vtype]] + "Arr(" + RegExp.$1 + ")";
          }
          
          funcEval = parseVarName(vname, funcEval);
          
          if (array_count !== 1) {
            outfile.writeline("  for (var i = 0; i < " + array_count + "; i++) {");
            outfile.writeline("    result += indent + '" + vname.replace(array_count, "' + i + '") + " = ' + " + funcEval + " + '\\n';");
            outfile.writeline("  }");
          }
          else {
            outfile.writeline("  result += indent + '" + vname + " = ' + " + funcEval + " + '\\n';"); 
          }
        }
        else if (vtype.indexOf("struct ") != -1) {
          vtype = vtype.replace("struct ", "");
          if (knownStructs.indexOf(vtype) !== -1) {
            if (vname.match(/\[(\w*)\]/)) {
              vname = vname.replace(/\[(\w*)\]/, "");
              if (RegExp.$1 === "") {
                outfile.writeline("  for (var i = 0; !reader.atEnd(); i++) {");
              }
              else {
                outfile.writeline("  for (var i = 0; i < " + RegExp.$1 + "; i++) {");
              }
              outfile.writeline("    result += " + vtype + "().replace('" + vtype+ "', '" + vtype + " " + vname + "[' + i + ']');");
              outfile.writeline("  }");
            }
            else {
              outfile.writeline("  result += " + vtype + "().replace('" + vtype+ "', '" + vtype + " " + vname + "');");
            }
          }
          else
          {
            outfile.writeline("//Unknown struct found (maybe defined later?): " + vtype);
          }
        }
        else {
          outfile.writeline("//Unable to parse => " + line);
        }
      }
    }
  }
  
  infile.close();
  outfile.close();
}

function parseVarName(vname, funcEval) {
  vname = vname.replace(/\[.*\]/g, '');
  if (vname.match(/name|string|desc/i) || vname === "Passwd" || vname === "msg") {
    funcEval = "changeToString(" + funcEval + ")";
  }
  else if (vname === "ITID" || vname.match(/^card/i)) {
    funcEval = "appendItemName(" + funcEval + ")";
  }
  else if (vname === "SKID") {
    funcEval = "appendSkillName(" + funcEval + ")";
  }
  else if (vname === "ID") {
    if (funcEval.indexOf("nt32") !== -1)
      funcEval = "appendShortcutName(" + funcEval + ")";
    else
      funcEval = "changeToString(" + funcEval + ")";
  }
  else if (vname === "varID") {
    funcEval = "appendVarName(" + funcEval + ")";
  }
  else if (vname.match(/^job$/i)) {
    funcEval = "appendJobName(" + funcEval + ")";
  }
  else if (vname === "ip") {
    funcEval = "changeToIPAddress(" + funcEval + ")";
  }
  else if (vname === "dir") {
    funcEval = "changeToDirection(" + funcEval + ")";
  }
  return funcEval;
}

function changeToString(fetchedValue) {
  var charArray = fetchedValue.remove(/[\[\]]/g, "").split(", ");
  var result = "";
  for (var i = 0; i < charArray.length && charArray[i] !== "00"; i++) {
    result += String.fromCharCode(parseInt(charArray[i]));
  }
  if (result === "")
    result = fetchedValue;
  
  return result;
}

function appendItemName(fetchedValue) {//assumed non Array value 
  var itemName  = reader.getInfoFromDB("Items", fetchedValue, "Unknown Item");
  return fetchedValue + " (" + itemName + ")";
}

function appendSkillName(fetchedValue) {//assumed non Array value 
  var skillName = reader.getInfoFromDB("Skills", fetchedValue, "Unknown Skill");
  return fetchedValue + " (" + skillName + ")";
}

function appendShortcutName(fetchedValue) {//assumed non Array value 
  var itemName  = reader.getInfoFromDB("Items", fetchedValue, "Unknown Item");
  var skillName = reader.getInfoFromDB("Skills", fetchedValue, "Unknown Skill");
  
  return fetchedValue + " (" + itemName + " or " + skillName + ")";
}
    
function appendVarName(fetchedValue) {//assumed non Array value 
  var vName = reader.getInfoFromDB("Vars", fetchedValue, "Unknown Variable");
  return fetchedValue + " (" + vName + ")";
}

function appendJobName(fetchedValue) {
  var values = fetchedValue.replace(/[\[\]]/, '').split(", ");
  var jobNames = [];
  for (var i = 0; i < values.length; i++) {
    jobNames.push(reader.getInfoFromDB("JobTypes", fetchedValue, "Unknown Job"));
  }
  return fetchedValue + " (" + jobNames.join(",") + ")";
}

function changeToIPAddress(fetchedValue) {//assumed non Array value 
  var parts = []
  for (var i = 0; i < 4; i++) {
    parts.push((fetchedValue >> (6-i*2)) & 0xFF);
  }
  return "[" + parts.join(".") + "]";
}

function changeToDirection(fetchedValue) {//assumed non Array value 
  var dirs = ["North", "North East", "East", "South East", "South", "South West", "West", "North West"];
  return dirs[fetchedValue];
}

StructParser();