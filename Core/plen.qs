//Registers
regName = ["eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi"];//arranged according to the register codes.
flagName = ["ZF", "CF", "OF", "SF"];
	
function ExtractPacketLen() {
	//Registers
	reg32 = new Object();
	flags = new Object();
	
	//Stack
	stack = [];//each offset/4 is the actual used stack offset - assuming DWORDs

	//Find PACKET_CZ_ENTER
	var offset = exe.findString("PACKET_CZ_ENTER", RVA);
	if (offset == -1) {
		throw "Failed to find PACKET_CZ_ENTER";
	}
	
	//Find its reference
	offset = exe.findCode("68" + offset.packToHex(4), PTYPE_HEX, false);
	if (offset == -1) {
		throw "Failed to find PACKET_CZ_ENTER reference";
	}
	
	//Find the GetSize Function
	offset = exe.find(" E8 AB AB AB AB 8B C8 E8 AB AB AB AB 50", PTYPE_HEX, true, "\xAB", offset + 5);
	if (offset == -1) {
		throw "Failed to find GetSize function call";
	}	
	offset += 12 + exe.fetchDWord(offset+8);//RVA is same therefore not an issue to use RA
	
	//Get ECXOff
	var ecxOff = exe.find(" B9 AB AB AB 00 E8 AB AB AB AB 8B", PTYPE_HEX, true, "\xAB", offset);
	if (ecxOff == -1) {
		throw "Failed to find ECX this value";
	}	
	ecxOff = exe.fetchHex(ecxOff,5);
	
	//Find CRagConnection::init
	offset = exe.findCode(ecxOff + " E8 AB AB AB AB 68 AB AB AB 00 E8 AB AB AB AB 59 C3", PTYPE_HEX, true, "\xAB");
	if (offset == -1) {
		throw "Failed to find CRagConnection init function";
	}	
	offset += 10 + exe.fetchDWord(offset+6);
	
	//Find Packet Table Maker
	offset = exe.find(" 8B CE E8 AB AB AB AB C7", PTYPE_HEX, true, "\xAB", offset);
	if (offset == -1) {
		throw "Failed to find table generator function";
	}	
	offset += 7 + exe.fetchDWord(offset+3); //the call is the table builder.
	
	//Find the ESP offset for our Extractor
	var espdiff = exe.find(" 83 EC", PTYPE_HEX, false, " ", offset);
	if (espdiff == -1) {
		throw "Failed to find espdiff";
	}	
	offset = espdiff+3;	
	espdiff = exe.fetchByte(espdiff + 2);
	
	//Find New Packet Table Location & ESP Offset - if the client has it
	var espdiff2 = 0;
	var offset2 = 0;
	if (exe.getClientDate() >= 20120710 ) {
		offset2 = exe.find("E8 AB AB AB AB B8", PTYPE_HEX, true, "\xAB", offset) + 5; //Skip the first function call - it will be used as offset 2
		offset2 = offset2 + exe.fetchDWord(offset2-4);
		
		espdiff2 = exe.find(" 83 EC", PTYPE_HEX, false, " ", offset2);
		if (espdiff2 == -1) {
			throw "Failed to find espdiff2";
		}
		offset2 = espdiff2 + 3;
		espdiff2 = exe.fetchByte(espdiff2 + 2);
	}
	
	//Setup the Output file - Global pointer
	fp = new TextFile();//Using global so functions can access
	fp.open(APP_PATH + "/Output/recvpackets_" + exe.getClientDate() + ".ini", "w");
	fp.writeline("//Extracted With DiffGen2");
	fp.writeline("\n[Old_Table]");
	
	//Extract the regular old table
	if (!ExtractTable(offset, espdiff, false) ) {
		fp.close();
		throw "Failed at first Set";
	}

	//Extract the shuffled new table
	if(offset2 !== 0) {
		fp.writeline("\n[New_Table]");
		if (!ExtractTable(offset2, espdiff2, true) ) {
			fp.close();
			throw "Failed at second Set";
		}
	}
	
	//Find the encryption keys.
	var keys = new Array();
	keys = fetchPacketKeys(exe);
	
	fp.writeline("\n[Encryption]");
	fp.writeline("Key1 = 0x" + convertToBE(keys[0].packToHex(4)));
	fp.writeline("Key2 = 0x" + convertToBE(keys[1].packToHex(4)));
	fp.writeline("Key3 = 0x" + convertToBE(keys[2].packToHex(4)));
    fp.close();
}

function ExtractTable(offset, spdiff, recordShuffle) {
	//Initialize
	for (var i=0; i< regName.length; i++) {
		reg32[ regName[i] ] = 0;
	}
	reg32["ebp"] = 22000;//Dummy values - 20000 just to be safe.
	reg32["esp"] = 22000 - spdiff;

	var pktFunc = false;//The packet table addition function
	var stOffset = false;//To facilitate packet function call and return
	var depth = 1;//Depth of function calls -> 1 = top level
	var shuffles = [];
	var shuffleCount = 29;
		
	while (depth > 0) {
		var retval = WalkThrough(offset);
		if (!retval) {//no address => return from function call.
			depth--;
			offset = stack[reg32["esp"]/4];//Get address from stack and pop 
			reg32["esp"]+=4;
		}
		else if (retval == -1) {//Opcode unrecognized
			return false;
		}
		else {//Address returned => Function call 
			var callRVA = exe.Raw2Rva(retval+4) + exe.fetchDWord(retval);
			var callRAW = exe.Rva2Raw(callRVA);
			if (!pktFunc && depth === 1 && callRAW !== -1) {//Grab Packet Function Address if not already found
				var res = exe.find("8B AB 8B AB 04 8B AB 04 80 78 1D 00", PTYPE_HEX, true, "\xAB", callRAW, callRAW + 0x20);
				if (res !== -1) {//Found it
					pktFunc = callRVA;
					res = exe.find("C6 40 04 01", PTYPE_HEX, false, "", callRAW, callRAW+0x90);
					if (res == -1) {
						fp.writeline("//Unable to find Stack Offset - Part 1 Fail");
						return false;
					}
					res = exe.find("C2 AB 00 E8", PTYPE_HEX, true, "\xAB", res, res+0x10);
					if (res == -1) {
						fp.writeline("//Unable to find Stack Offset - Part 2 Fail");
						return false;
					}
					stOffset = exe.fetchByte(res+1);
				}
			}
			
			if (callRAW !== -1) {//Valid Function Call
				if (pktFunc === callRVA) {//Packet Function Call -  Get the info & Emulate the call
					offset = retval+4;//adjust the offset to skip the function
					reg32["esp"] += stOffset - 4;//adjust the stack to skip.
					
					var packet = stack[stack[reg32["esp"]/4]/4];
					var length = stack[stack[reg32["esp"]/4]/4 + 1];
					
					reg32["esp"] += 4;//the function releases some of the stack
					
					packet = "0x" + convertToBE(packet.packToHex(2));
					fp.writeline(packet + " = " + length);
					if (recordShuffle && shuffleCount > 0) {
						shuffles.push(packet);
						shuffleCount--;
					}
				}
				else {//Other functions - pass control
					reg32["esp"] -= 4;
					stack[reg32["esp"]/4] = retval+4;
					offset = callRAW;
					depth++;
				}
			}
			else {
				offset = retval+4;
			}
		}
	}
	if (recordShuffle) {
		fp.writeline("[Shuffle_Packets]");
		for (var i in shuffles) {
			fp.writeline(shuffles[i] + " = " + i);
		}
	}
	return true;
}

function WalkThrough(offset) {
	//Miscellaneous
	var ptr = 0;
	var calledPoint = false;
	var done = false;
	var opSize = 32;
	
	while (!done) {
		var opcode = exe.fetchByte(offset+ptr);
		if (opcode < 0) {//converting to positive for > 7F
			opcode = 256 + opcode;
		}
		ptr++;
		switch(opcode) {
			case 0x50://PUSH <reg32> 
			case 0x51:
			case 0x52:
			case 0x53:
			case 0x54:
			case 0x55:
			case 0x56:
			case 0x57:
				reg32["esp"]-=4;
				stack[reg32["esp"]/4] = reg32[regName[opcode-0x50]];
				break;
			
			case 0x58://POP <reg32> 
			case 0x59:
			case 0x5A:
			case 0x5B:
			case 0x5C:
			case 0x5D:
			case 0x5E:
			case 0x5F:
				reg32[regName[opcode-0x58]] = stack[reg32["esp"]/4];
				reg32["esp"]+=4;
				break;
				
			case 0x68://PUSH <dword>
				reg32["esp"]-=4;
				stack[reg32["esp"]/4] = exe.fetchDWord(offset+ptr);
				ptr += 4;
				break;
			
			case 0x6A:// PUSH sign extended byte.
				reg32["esp"]-=4;
				stack[reg32["esp"]/4] = exe.fetchByte(offset+ptr);
				ptr += 1;
				break;
			
			case 0x8B:
			case 0x89: //MOV <reg32>, <value from reg32>
			case 0x88: //MOV <reg8>, <value from reg8>
				if (opcode == 0x88) {
					opSize = 8;
				}				
				var refObj = getOperand(offset+ptr);
				ptr = refObj.offset - offset;
				if (opcode === 0x8B)	{
					movData(refObj.reg2, refObj.src, opSize);
				}
				else if (refObj.des != 0) {
					movData(refObj.des/4, reg32[refObj.reg2], opSize);
				}
				else {
					movData(refObj.reg1, reg32[refObj.reg2], opSize);
				}
				break;
				
			case 0x31:
			case 0x33://XOR <reg32>, <value from reg32>
				var refObj = getOperand(offset+ptr);
				ptr = refObj.offset - offset;
				if (opcode == 0x33) {
					movData(refObj.reg2, operate(refObj.reg2, "^", refObj.src, opSize), opSize);
				}
				else if (refObj.des != 0) {
					movData(refObj.des/4, operate(stack[refObj.des/4], "^", refObj.reg2, opSize), opSize);
				}
				else {
					movData(refObj.reg1, operate(refObj.reg1, "^", refObj.reg2, opSize), opSize);
				}
				break;
			
			case 0x80:
			case 0x82:
			case 0x83://Special opcode - here reg1 or des gets modified according to offset value and reg2 determines the operation
				//reg2:
				//000 = ADD
				//001 = OR
				//010 = ADC
				//011 = SBB
				//100 = AND
				//101 = SUB
				//110 = XOR
				//111 = CMP
				if (opcode != 0x83) opSize = 8;
				var refObj = getOperand(offset+ptr);
				var value = exe.fetchByte(refObj.offset);				
				ptr = refObj.offset - offset + 1;//1 For the immdediate byte
				switch(refObj.reg2code) {
					case 2: 
						if (flags["CF"]) value++;//ADD the carry
					case 0: 
						var arop = "+";
						break;
					case 3:
						if (flags["CF"]) value++;//ADD the Borrow
					case 5: 
						var arop = "-";
						break;
					case 1: 	
						var arop = "|";
						break;
					case 4: 
						var arop = "&";
						break;
					case 6: 
						var arop = "^";
						break;
					case 7: 
						if (refObj.des != 0) {
							operate(stack[refObj.des], "-", value);
						}
						else {
							operate(refObj.reg1, "-", value);
						}
						break;						
				}
				if (refObj.reg2code != 7) {
					if (refObj.des != 0) {
						movData(refObj.des, operate(stack[refObj.des], arop, value, opSize), opSize);
					}
					else {
						movData(refObj.reg1, operate(refObj.reg1, arop, value, opSize), opSize);
					}						
				}
				break;
			
			case 0xB0:
			case 0xB1:
			case 0xB2:
			case 0xB3:
			case 0xB4:
			case 0xB5:
			case 0xB6:
			case 0xB7: //MOV reg8, imm8			
				movData(regName[opcode-0xB0], exe.fetchByte(offset+ptr), 8);
				ptr++;
				break;
			
			case 0xB8:
			case 0xB9:
			case 0xBA:
			case 0xBB:
			case 0xBC:
			case 0xBD:
			case 0xBE:
			case 0xBF: //MOV reg32, imm32
				var value = exe.fetchHex(offset+ptr, opSize/8).unpackToInt();
				movData(regName[opcode-0xB8], value, opSize);
				ptr+=opSize/8;
				break;
			
			case 0x8D: //LEA reg32, <value from reg32>
				var refObj = getOperand(offset+ptr);
				ptr = refObj.offset - offset;
				reg32[refObj.reg2] = refObj.des;//des should not be 0 for LEA - else its an illegal instruction
				break;
			
			case 0xC7://MOV DWORD PTR DS:[reg32combo], Immediate value
				var refObj = getOperand(offset+ptr);				
				stack[refObj.des/4] = exe.fetchDWord(refObj.offset);
				ptr = refObj.offset - offset + 4;
				break;
				
			case 0x40:
			case 0x41:
			case 0x42:
			case 0x43:
			case 0x44:
			case 0x45:
			case 0x46:
			case 0x47: //INC reg32
				movData(regName[opcode-0x40], operate(regName[opcode-0x40], "+", 1, opSize), opSize);
				break;
			
			case 0x48:
			case 0x49:
			case 0x4A:
			case 0x4B:
			case 0x4C:
			case 0x4D:
			case 0x4E:
			case 0x4F: //DEC reg32
				movData(regName[opcode-0x48], operate(regName[opcode-0x48], "-", 1, opSize), opSize);
				break;
				
			case 0x74: //JE short			
			case 0x75: //JNE short
				if (opcode == 0x74 && !flags["ZF"]) {//Check for Fail conditions otherwise go on to JUMP short
					ptr++;
					break;
				}
				if (opcode == 0x75 &&  flags["ZF"]) {
					ptr++;
				}
				
			case 0xEB: //JMP short
				ptr+= 1 + exe.fetchByte(offset+ptr);
				break;
			
			case 0xE9: //JMP long
				ptr+= 4 + exe.fetchDWord(offset+ptr);
				break;
			
			case 0x90: //NOP
			case 0x64: //FS modifier -  Currently not doing anything about FS
				break;
				
			case 0x66: //OPSIZE modifier 32 -> 16
				opSize = 16;
				break;
			
			case 0xA1: //MOV EAX, [addr]
				movData("eax", stack[exe.fetchDWord(offset+ptr)], opSize);				
				ptr+= opSize/8;
				break;
				
			case 0xA3: //MOV [addr], EAX
				movData(exe.fetchDWord(offset+ptr), reg32["eax"], opSize);
				ptr+= opSize/8;
				break;

			case 0x3B: //CMP reg32, reg32 
				var refObj = getOperand(offset+ptr);
				ptr = refObj.offset - offset;
				if (refObj.des != 0) {
					operate(stack[refObj.des/4], "-", reg32[refObj.reg2], opSize);
				}
				else {
					operate(refObj.reg1, "-", reg32[refObj.reg2], opSize);
				}
				break;
			
			case 0x84:
			case 0x85: //TEST reg32, reg32
				if (opcode == 0x84) opSize = 8;
				var refObj = getOperand(offset+ptr);
				ptr = refObj.offset - offset;
				if (refObj.des != 0) {
					operate(stack[refObj.des/4], "&", reg32[refObj.reg2], opSize);
				}
				else {
					operate(refObj.reg1, "&", reg32[refObj.reg2], opSize);
				}
				break;
				
			case 0xE8: //CALL <fnoffset>
				calledPoint = offset+ptr;
				ptr+= 2;
				
			case 0xC2://RETN bytes - 2 bytes need are also specified but we dont need to handle them.
			case 0xC3://RETN
				done = true;
				break;
				
			case 0xFF: //JMP DWORD PTR DS:[external function] -- we will return back instead since we dont have the function.
				reg32["eax"] = 1;//Return status
				done = true;
				break;
			
			case 0x0F: //Special OPCode indicating two byte opcode
				var opcode2 = exe.fetchByte(offset+ptr);
				if (opcode2 < 0) 	opcode2 = 256 + opcode2;
				ptr++;
				if (opcode2 == 0x9C) {
					var refObj = getOperand(offset+ptr);
					ptr = refObj.offset - offset;
					opSize = 8;
					if (refObj.des != 0) {
						if (flags["SF"] != flags["OF"]) {
							movData(refObj.des/4, 1, opSize);
						}
					}
					else {
						if (flags["SF"] != flags["OF"]) {
							movData(refObj.reg1, 1, opSize);
						}
					}
					break;
				}
			default:
				fp.writeline("//unrecognized opcode - " + opcode.packToHex(1) + " @ " + (offset+ptr-1) );
				calledPoint = -1;
				done = true;
		}
		if (opcode != 0x66) {
			opSize = 32;//Set Opsize unless the opcode set it manually with 66 prefix
		}
	}
	return calledPoint;
}

function getOperand(offset) {
	var modrm = exe.fetchByte(offset);
	var ref = new Object();
	var mod = (modrm & 0xC0) >> 6;
	var reg1 = (modrm & 0x7);
	var src;
	var des;
	var computedreg = reg32[ regName[reg1] ];
	if (reg1 == 0x4 && mod != 3) {//use SIB if ESP is reg1
		offset++;
		var sib = exe.fetchByte(offset);
		var scale = 1 << ((sib & 0xC0) >> 6);
		var index = regName[ (sib & 0x38) >> 3];
		var base = reg32[ regName[ (sib & 0x7)] ];
		if (index == "esp") {//ESP cannot be scaled
			computedreg = base;
		}
		else {
			computedreg = scale*index + base;
		}
	}
	
	offset++;

	switch(mod) {
		case 0: 
			if (reg1 == 0x5) {//EBP
				des = exe.fetchDWord(offset);
				offset += 4;
			}
			else {
				des = computedreg;
			}
			src = stack[des/4];
			break;
		case 1: 
			des = computedreg + exe.fetchByte(offset);
			src = stack[des/4]; 
			offset++;
			break;
		case 2: 
			des = computedreg + exe.fetchDWord(offset);
			src = stack[des/4]; 
			offset += 4;
			break;
		case 3: //unaffected by SIB 
			des = 0;//no mem address.
			ref.reg1 = regName[reg1];
			src = reg32[ref.reg1];
			break;
	}
	
	ref.reg2code = (modrm & 0x38) >> 3;
	ref.reg2 = regName[ref.reg2code];
	ref.src = src;
	ref.des = des;
	ref.offset = offset;
	ref.mod = mod;
	return ref;
}

function operate(val1, op, val2, opSize) {
	for(var i in flagName) {
		flags[flagName[i]] = false;
	}
	if (typeof(val1) == "string") {//Dst Register value
		val1 = reg32[val1];
	}
	if (typeof(val2) == "string") {//Src Register value
		val2 = reg32[val2];
	}
	
	var maxVal = Math.pow(2, opSize-1) - 1;
	val1 = val1 & (Math.pow(2, opSize) - 1);
	val2 = val2 & (Math.pow(2, opSize) - 1);
	
	var result = eval(val1 + op + val2);
	//Zero
	if (result == 0) {
		flags["ZF"] = true;
	}
	//Carry
	if (result > maxVal) {
		flags["CF"] = true;
		result = result & maxVal;
	}
	//Overflow
	if (result < -maxVal) {
		flags["OF"] = true;
	}
	//Borrow
	if (op == "-" && val1 < val2) {
		flags["CF"] = true;
	}
	//Sign
	if (result < 0) {
		flags["SF"] = true;
	}
	return result;
}

function movData(tgt, src, opSize) {
	var mask2 = Math.pow(2,opSize) - 1;
	var mask1 = 0xFFFFFFFF - mask2;
	if (typeof(tgt) == "string") {//Reg Name
		reg32[tgt] = (reg32[tgt] & mask1) | (src & mask2);
	}
	else {
		stack[tgt] = (stack[tgt] & mask1) | (src & mask2);
	}
}