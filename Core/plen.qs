//Registers
reglist = new Array("eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi");//arranged according to the register codes.
reg32 = new Object();
//Stack
stack = new Array();//each offset/4 is the actual used stack offset - assuming DWORDs
	
function ExtractPacketLen() {
	var offset = exe.findString("PACKET_CZ_ENTER", RVA);
	if (offset == -1) {
		throw "Failed to find PACKET_CZ_ENTER";
	}
	
	offset = exe.findCode("68" + offset.packToHex(4), PTYPE_HEX, false);
	if (offset == -1) {
		throw "Failed to find PACKET_CZ_ENTER reference";
	}
	
	offset = exe.find(" E8 AB AB AB AB 8B C8 E8 AB AB AB AB 50", PTYPE_HEX, true, "\xAB", offset + 5);
	if (offset == -1) {
		throw "Failed to find GetSize function call";
	}
	
	offset += 12 + exe.fetchDWord(offset+8);//RVA is same therefore not an issue to use RA
	
	var ecxOff = exe.find(" B9 AB AB AB 00 E8 AB AB AB AB 8B", PTYPE_HEX, true, "\xAB", offset);
	if (ecxOff == -1) {
		throw "Failed to find ECX this value";
	}
	
	ecxOff = exe.fetchHex(ecxOff,5);
		
	offset = exe.findCode(ecxOff + " E8 AB AB AB AB 68 AB AB AB 00 E8 AB AB AB AB 59 C3", PTYPE_HEX, true, "\xAB");
	if (offset == -1) {
		throw "Failed to find CRagConnection init function";
	}
	
	offset += 10 + exe.fetchDWord(offset+6);
	
	offset = exe.find(" 8B CE E8 AB AB AB AB C7", PTYPE_HEX, true, "\xAB", offset);
	if (offset == -1) {
		throw "Failed to find table generator function";
	}
	
	offset += 7 + exe.fetchDWord(offset+3); //the call is the table builder.
	
	var espdiff = exe.find(" 83 EC", PTYPE_HEX, false, " ", offset);
	if (espdiff == -1) {
		throw "Failed to find espdiff";
	}
	
	offset = espdiff+3;
	
	espdiff = exe.fetchByte(espdiff + 2);
	
	var espdiff2 = 0;
	var offset2 = 0;
	var skipper = 0;
	if (exe.getClientDate() >= 20120710 ) {
		offset2 = exe.find("E8 AB AB AB AB B8", PTYPE_HEX, true, "\xAB", offset) + 5; //Skip the first function call - it will be used as offset 2
		offset2 = offset2 + exe.fetchDWord(offset2-4);
		
		espdiff2 = exe.find(" 83 EC", PTYPE_HEX, false, " ", offset2);
		if (espdiff2 == -1) {
			throw "Failed to find espdiff2";
		}
		offset2 = espdiff2 + 3;
		
		espdiff2 = exe.fetchByte(espdiff2 + 2);
		
		skipper = 1;
	}
	
	fp = new TextFile();//Using global so functions can access
	fp.open(APP_PATH + "/Output/recvpackets_" + exe.getClientDate() + ".ini", "w");
	fp.writeline("//Extracted With DiffGen2");
	fp.writeline("\n[Old_Table]");
	
	if (!walkthrough(offset, espdiff, skipper, exe, false) ) {
		fp.close();
		throw "Failed at first walkthrough";
	}

	if(offset2 !== 0) {
		fp.writeline("\n[New_Table]");
		if (!walkthrough(offset2, espdiff2, skipper-1, exe, true) ) {
			fp.close();
			throw "Failed at second walkthrough";
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

function walkthrough(offset, spdiff, skipper, exe, shuffleDetect) {

	for (var i=0; i< reglist.length; i++) {
		reg32[ reglist[i] ] = 0;
	}
	skipFuncs = new Array();
	addSkipFuncs = true;
	
	reg32["ebp"] = 22000;//Dummy values - 20000 just to be safe.
	reg32["esp"] = 22000 - spdiff;
	
	//Miscellaneous
	var ptr = 0;
	var funcRVA = 0;
	var funcRVA2 = 0;//Direct Push calls
	var done = false;
	var status = true;
	var shufflePackets = new Array();
	var maxShuffles = 29;
	
	var packOffset = 1;
	var lenOffset = -1;
	if (exe.getClientDate() >= 20130320) {
		packOffset = 0;
	}
	if (exe.getClientDate() > 20130807) {
		packOffset = 1;
		lenOffset = 2;
	}
	
	while (!done) {
		var opcode = exe.fetchByte(offset+ptr);
		ptr++;
		if (opcode < 0) {//converting to positive for > 7F
			opcode = 256 + opcode;
		}

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
				stack[reg32["esp"]/4] = reg32[reglist[opcode-0x50]];
				debugThis("push @" + reg32["esp"] + " <= " + reglist[opcode-0x50] + " i.e. " + reg32[reglist[opcode-0x50]], offset+ptr);
				break;
			
			case 0x58://POP <reg32> 
			case 0x59:
			case 0x5A:
			case 0x5B:
			case 0x5C:
			case 0x5D:
			case 0x5E:
			case 0x5F:
				reg32[reglist[opcode-0x58]] = stack[reg32["esp"]/4];
				reg32["esp"]-=4;
				break;
				
			case 0x68://PUSH <dword>
				reg32["esp"]-=4;
				stack[reg32["esp"]/4] = exe.fetchDWord(offset+ptr);
				ptr += 4;
				debugThis("push @" + reg32["esp"] + " <= " + stack[reg32["esp"]/4], offset+ptr);
				break;
			
			case 0x6A:// PUSH sign extended byte.
				reg32["esp"]-=4;
				stack[reg32["esp"]/4] = exe.fetchByte(offset+ptr);
				ptr += 1;
				debugThis("push to stack hardcoded " + stack[reg32["esp"]/4], offset+ptr);
				break;
			
			case 0x8B:
			case 0x89: //MOV <reg32>, <value from reg32>
				var refObj = getOperand( exe.fetchByte(offset+ptr), offset+ptr, exe);
				ptr = refObj.offset - offset;
				if (opcode == 0x8B)	{
					reg32[refObj.reg2] = refObj.src;
				}
				else if (refObj.des != 0) {
					stack[refObj.des/4] = reg32[refObj.reg2];
					debugThis("mov to " + refObj.des + " <= " + refObj.reg2 + " i.e. " + reg32[refObj.reg2], offset+ptr);
				}
				else {
					reg32[refObj.reg1] = reg32[refObj.reg2];
				}
				break;
				
			case 0x31:
			case 0x33://XOR <reg32>, <value from reg32>
				var refObj = getOperand(exe.fetchByte(offset+ptr), offset+ptr, exe);
				ptr = refObj.offset - offset;
				if (opcode == 0x33) {
					reg32[refObj.reg2] ^= refObj.src;
				}
				else if (refObj.des != 0) {
					stack[refObj.des/4] ^= reg32[refObj.reg2];
					debugThis("Xor to segment  " + refObj.reg2 + " = " + reg32[refObj.reg2], offset+ptr);
				}
				else {
					reg32[refObj.reg1] ^= reg32[refObj.reg2];
				}
				break;
			
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
				
				var refObj = getOperand(exe.fetchByte(offset+ptr), offset+ptr, exe);
				var value = exe.fetchByte(refObj.offset);				
				ptr = refObj.offset - offset + 1;//1 For the immdediate byte
				
				if (refObj.des != 0) {
					debugThis(refObj.des + " pre-operation " + stack[refObj.des], offset+ptr);
					switch(refObj.reg2code) {
						case 0: 
						case 2: stack[refObj.des] += value; break;
						
						case 1: stack[refObj.des] |= value; break;
						
						case 3: 
						case 5: stack[refObj.des] -= value; break;

						case 4: stack[refObj.des] &= value; break;
						
						case 6: stack[refObj.des] ^= value; break;
						//since carry/borrow flag is not there, we are assuming it as blank - hopefully it will work
						//cannot consider case 7 right now . lets just hope it doesnt come up. else we will have to keep track of flags as well.
					}
					debugThis(refObj.des + " operated to " + stack[refObj.des], offset+ptr);
				}
				else {
					debugThis(refObj.reg1 + " pre-operation " + reg32[refObj.reg1], offset+ptr);
					switch(refObj.reg2code) {
						case 0:
						case 2: reg32[refObj.reg1] += value; break;

						case 1: reg32[refObj.reg1] |= value; break;

						case 3:
						case 5: reg32[refObj.reg1] -= value; break;

						case 4: reg32[refObj.reg1] &= value; break;

						case 6: reg32[refObj.reg1] ^= value; break;
						//since carry/borrow flag is not there, we are assuming it as blank - hopefully it will work
						//cannot consider case 7 right now . lets just hope it doesnt come up. else we will have to keep track of flags as well.						
					}
					debugThis(refObj.reg1 + " operated to " + reg32[refObj.reg1], offset+ptr);
				}
				break;
			
			case 0xB8:
			case 0xB9:
			case 0xBA:
			case 0xBB:
			case 0xBC:
			case 0xBD:
			case 0xBE:
			case 0xBF: //MOV reg32, imm32
				reg32[ reglist[opcode-0xB8] ] = exe.fetchDWord(offset+ptr);
				ptr+=4;
				break;
			
			case 0x8D: //LEA reg32, <value from reg32>
				var refObj = getOperand(exe.fetchByte(offset+ptr), offset+ptr, exe);
				ptr = refObj.offset - offset;
				reg32[refObj.reg2] = refObj.des;//des should not be 0 for LEA - else its an illegal instruction
				debugThis("LEA " + refObj.reg2 + " = " + refObj.des, offset+ptr);
				break;
			
			case 0xC7://MOV DWORD PTR DS:[reg32combo], Immediate value
				var refObj = getOperand(exe.fetchByte(offset+ptr), offset+ptr, exe);				
				stack[refObj.des/4] = exe.fetchDWord(refObj.offset);
				ptr = refObj.offset - offset + 4;
				debugThis("mov to segment @ " + refObj.des + " <= " + stack[refObj.des/4], offset+ptr);
				break;
				
			case 0x40:
			case 0x41:
			case 0x42:
			case 0x43:
			case 0x44:
			case 0x45:
			case 0x46:
			case 0x47: //INC reg32
				reg32[reglist[opcode-0x40]]++;
				break;
			
			case 0x48:
			case 0x49:
			case 0x4A:
			case 0x4B:
			case 0x4C:
			case 0x4D:
			case 0x4E:
			case 0x4F: //DEC reg32
				reg32[reglist[opcode-0x40]]--;
				break;
				
			case 0xEB:
				ptr+= 1 + exe.fetchByte(offset+ptr);
				break;
			
			case 0xE9:
				ptr+= 4 + exe.fetchDWord(offset+ptr);
				break;
			
			case 0xE8:				
				var callRVA = exe.Raw2Rva(offset+ptr+4) + exe.fetchDWord(offset+ptr);
				if (skipper === 0) {
					funcRVA = callRVA;
					debugThis("Function address", exe.Rva2Raw(funcRVA));
				}
				skipper--;
				
				if (addSkipFuncs && funcRVA !== callRVA) {//Only store function address between 1 iteration of calls of FuncRVA.
					skipFuncs.push(callRVA);
				}
				else if(!addSkipFuncs && skipFuncs.indexOf(callRVA) === -1 && funcRVA !== callRVA) {//a call other than the skipped addresses and the FuncRVA - meaning the direct push functions have started
					funcRVA2 = callRVA;
					debugThis("Function address 2", exe.Rva2Raw(funcRVA));
				}
				
				if (funcRVA === callRVA) {
					if (skipper !== -1) {//Only collect for one iteration
						addSkipFuncs = false;
					}
						
					var soff = stack[reg32["esp"]/4 + packOffset];
					var packet = stack[soff/4];
					
					if (lenOffset != -1) {
						soff = stack[reg32["esp"]/4 + lenOffset];
					}
					else {
						soff += 4;
					}
					
					var len = stack[soff/4];
					
					if (typeof(packet) !== "undefined") {
						packet = "0x" + convertToBE(packet.packToHex(2));
					}
					if (shuffleDetect && shufflePackets.length < maxShuffles) {
						shufflePackets.push(packet);
					}					
					fp.writeline(packet + " = " + len);
				}
				else if (funcRVA2 == callRVA) {//direct pushes : arg1 = PACKET ID, arg2 = LENGTH
					var packet = "0x" + convertToBE( (stack[reg32["esp"]/4]).packToHex(2) );
					var len = stack[reg32["esp"]/4 + 1];
					
					if (shuffleDetect && shufflePackets.length < maxShuffles) {
						shufflePackets.push(packet);
					}
					fp.writeline(packet + " = " + len);
				}
					
				ptr += 4;
				break;
				
			case 0xC3://RETN
				done = true;
				break;
			
			default:
				fp.writeline("//unrecognized opcode - " + opcode.packToHex(1));
				done = true;
				status = false;
				break;
		}
	}
	if (shuffleDetect && shufflePackets.length > 0) {
		fp.writeline("\n[Shuffle_Packets]");
		for (var i = 1; i <= shufflePackets.length; i++) {
			fp.writeline(shufflePackets[i-1] + " = " + i);
		}
	}
	return status;
}

function getOperand(modrm, offset, exe) {

	var ref = new Object();
	var mod = (modrm & 0xC0) >> 6;
	var reg1 = (modrm & 0x7);
	var src;
	var des;
	var computedreg = reg32[ reglist[reg1] ];
	if (reg1 == 0x4 && mod != 3) {//use SIB if ESP is reg1
		offset++;
		var sib = exe.fetchByte(offset);
		var scale = 1 << ((sib & 0xC0) >> 6);
		var index = reglist[ (sib & 0x38) >> 3];
		var base = reg32[ reglist[ (sib & 0x7)] ];
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
			des = computedreg;
			src = stack[des/4];
			break;
		case 1: 
			des = computedreg + exe.fetchByte(offset);
			src = stack[des/4]; 
			offset++;
			break;
		case 2: 
			des = computedreg + exe.fetchDword(offset);
			src = stack[des/4]; 
			offset += 4;
			break;
		case 3: //unaffected by SIB 
			des = 0;//no mem address.
			ref.reg1 = reglist[reg1];
			src = reg32[ref.reg1];
			break;
	}
	
	ref.reg2code = (modrm & 0x38) >> 3;
	ref.reg2 = reglist[ref.reg2code];
	ref.src = src;
	ref.des = des;
	ref.offset = offset;
	return ref;
}

function debugThis(msg, offset) {
//	fp.writeline("//DEBUG: 0x" + convertToBE(exe.Raw2Rva(offset).packToHex(4)) + " ::: " + msg);
}