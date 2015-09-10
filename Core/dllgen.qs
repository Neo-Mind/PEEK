function DllGen() {
  //Step 1 - Find the GetPacketSize function call
  var template =
    " E8 AB AB AB AB" //CALL CRagConnection::instanceR
  + " 8B C8"          //MOV ECX, EAX
  + " E8 AB AB AB AB" //CALL func
  ;
  
  var code =
    template //CALL CRagConnection::instanceR
             //MOV ECX, EAX
             //CALL CRagConnection::GetPacketSize
  + " 50"    //PUSH EAX
  + template //CALL CRagConnection::instanceR
             //MOV ECX, EAX
             //CALL CRagConnection::SendPacket
  + " 6A 01" //PUSH 1
  + template //CALL CRagConnection::instanceR
             //MOV ECX, EAX
             //CALL CConnection::SetBlock
  + " 6A 06" //PUSH 6
  ;
  
  var refOffset = exe.findCode(code, PTYPE_HEX, true, "\xAB");
  if (refOffset === -1)
    throw "Reference Location not found";
  
  //----- Getting PktOffset -----//
  
  //Step 2a - Go Inside the GetPacketSize function
  var offset = refOffset + template.hexlength();
  offset += exe.fetchDWord(offset - 4);
  
  //Step 2b - Look for g_PacketLenMap reference and the pktLen function call following it
  code =
    " B9 AB AB AB 00" //MOV ECX, g_PacketLenMap
  + " E8 AB AB AB AB" //CALL addr; gets the address pointing to the packet followed by len
  + " 8B AB 04"       //MOV reg32_A, [EAX+4]
  ;
  
  offset = exe.find(code, PTYPE_HEX, true, "\xAB", offset, offset + 0x60);
  if (offset === -1)
    throw "g_PacketLenMap not found";
  
  //Step 2c - Extract the g_PacketLenMap assignment
  var gPacketLenMap = exe.fetchHex(offset, 5);
  
  //Step 2d - Go inside the pktLen function following the assignment
  offset += exe.fetchDWord(offset+6) + 10;
  
  //Step 2e - Look for the pattern that checks the length with -1 
  code = 
      " 8B AB AB" //MOV reg32_A, DWORD DS:[reg32_B+lenOffset]; lenOffset = PktOffset+4
    + " 83 AB FF" //CMP reg32_A, -1
    + " 75 AB"    //JNE addr
    + " 8B"       //MOV reg32_A, DWORD DS:[reg32_B+lenOffset+4]
    ;
  
  var offset2 = exe.find(code, PTYPE_HEX, true, "\xAB", offset, offset + 0x60);
  if (offset2 === -1)
    throw "PktOffset not found";
  
  //Step 2f - Extract the displacement - 4 which will be PktOffset
  var PktOffset = exe.fetchByte(offset2 + 2) - 4;
  
  //----- Getting ExitAddr -----//
  
  //Step 3a - Find the InitPacketMap function call using g_PacketLenMap
  code =
    gPacketLenMap     //MOV ECX, g_PacketLenMap
  + " E8 AB AB AB AB" //CALL CRagConnection::InitPacketMap
  + " 68 AB AB AB 00" //PUSH addr1
  + " E8 AB AB AB AB" //CALL addr2
  + " 59"             //POP ECX
  + " C3"             //RETN
  ;

  offset = exe.findCode(code, PTYPE_HEX, true, "\xAB");
  if (offset === -1)
    throw "InitPacketMap not found";
  
  //Step 3b - Save the address after the call which will serve as the ExitAddr
  var ExitAddr = exe.Raw2Rva(offset + 15);
  
  //----- Getting HookAddrs -----//
  
  //Step 4a - Go Inside InitPacketMap
  offset += exe.fetchDWord(offset + 6) + 10;
  
  //Step 4b - Look for InitPacketLenWithClient call
  code = 
    " 8B CE"          //MOV ECX, ESI
  + " E8 AB AB AB AB" //CALL InitPacketLenWithClient
  + " C7"             //MOV DWORD PTR SS:[LOCAL.x], -1
  ;
  
  offset = exe.find(code, PTYPE_HEX, true, "\xAB", offset, offset + 0x140);
  if (offset === -1)
    throw "InitPacketLenWithClient not found";

  //Step 4c - Go Inside InitPacketLenWithClient
  offset += exe.fetchDWord(offset + 3) + 7;
  
  //Step 4d - Now comes the tricky part. We need to get all the functions called till a repeat is found.
  //          Last unrepeated call is the std::map function we need
  var funcs = [];
  while (1) {
    offset = exe.find(" E8 AB AB FF FF", PTYPE_HEX, true, "\xAB", offset+1);//CALL std::map
    if (offset === -1) break;
    var func = offset + exe.fetchDWord(offset+1) + 5;
    if (funcs.indexOf(func) !== -1) break;
    funcs.push(func);
  }
  
  if (offset === -1 || funcs.length === 0)
    throw "std::map not found";
  
  //Step 4e - Go Inside std::map
  offset = funcs[funcs.length-1];

  //Step 4f - Look for all calls to std::_tree (should be either 1 or 2 calls)
  //          The called Locations serve as our Hook Addresses
  code = 
    " E8 AB AB FF FF" //CALL std::_tree
  + " 8B AB"          //MOV reg32_A, [EAX]
  + " 8B"             //MOV EAX, DWORD PTR SS:[ARG.1]
  ;
  
  var HookAddrs = exe.findAll(code, PTYPE_HEX, true, "\xAB", offset, offset+0x100);
  if (HookAddrs.length < 1 || HookAddrs.length > 2)
    throw "std::_tree call count is different";
  
  //----- Getting KeyFetcher and Keys -----//
  
  //Step 5a - Look for First Pattern (Keys are Pushed before call)
  var KeyFetcher = 0;
  var Keys = [0, 0, 0];
  code =
    " 8B 0D AB AB AB 00" //MOV ECX, DWORD PTR DS:[addr1]
  + " 68 AB AB AB AB"    //PUSH key3
  + " 68 AB AB AB AB"    //PUSH key2
  + " 68 AB AB AB AB"    //PUSH key1
  + " E8"                //CALL encryptor
  ;
  
  offset = exe.find(code, PTYPE_HEX, true, "\xAB", refOffset - 0x100, refOffset);
  if (offset !== -1) {
    offset += code.hexlength();
    Keys = [exe.fetchDWord(offset - 5), exe.fetchDWord(offset - 10), exe.fetchDWord(offset - 15)];
  }
  else {
    //Step 5b - Look for 2nd Pattern with a combined function call which is the KeyFetcher 
    KeyFetcher = -1;
    code = 
      " 8B 0D AB AB AB 00" //MOV ecx, DS:[ADDR1] dont care what
    + " 6A 01"             //PUSH 1
    + " E8"                //CALL combofunction - encryptor and key fetcher combined.
    ;
    
    offset = exe.find(code, PTYPE_HEX, true, "\xAB", refOffset - 0x100, refOffset);
  }
  
  if (offset === -1) {
    throw "Packet Key Patterns not found";
  }
  else if (KeyFetcher === -1) {
    offset += code.hexlength();
    KeyFetcher = exe.Raw2Rva(offset + 4) + exe.fetchDWord(offset);
  }
  
  //----- Getting ShuffleCount and ClientDate-----//
  var ShuffleCount = 29;
  var ClientDate = exe.getClientDate().toString().toHex();
  
  //----- Now to put it all into the DLL -----//
  
  //Step 6a - Load the template DLL file
  var fp = new BinFile();
  if (!fp.open(APP_PATH + "/Input/ws2_pe_template.dll"))
    throw "Template DLL missing from Input Folder";
 
  var contents = fp.readHex(0, 0x1E00);
  fp.close();  
  
  //Step 5a - Replace the dddddddd with the Client Date inside Output Length FileName
  contents = contents.replace(" 64 64 64 64 64 64 64 64", ClientDate);
  
  //Step 5b - Replace PktOffset, ExitAddr , HookAddrs and ShuffleCount
  code = PktOffset.packToHex(4) + ExitAddr.packToHex(4) + exe.Raw2Rva(HookAddrs[0]).packToHex(4);
  
  if (HookAddrs.length === 2)
    code += exe.Raw2Rva(HookAddrs[1]).packToHex(4);
  else
    code += " 00 00 00 00";
  
  code += ShuffleCount.packToHex(4);
  
  contents = contents.replace(/ FF 00 FF 01 FF 00 FF 02 FF 00 FF 03 FF 00 FF 04 FF 00 FF 05/i, code);
  
  //Step 5c - Replace Keys and KeyFetcher
  code = Keys[0].packToHex(4) + Keys[1].packToHex(4) + Keys[2].packToHex(4) + KeyFetcher.packToHex(4);
  
  contents = contents.replace(/ FF 00 FF 10 FF 00 FF 11 FF 00 FF 12 FF 00 FF 13/i, code);
  
  //Step 5d - Write the modified contents to new DLL
  if (!fp.open(APP_PATH + "/Output/ws2_pe.dll", "w"))
    throw "Unable to create dll file in Ouput folder";
  
  fp.writeHex(0, contents);
  fp.close();
}