--
-- required packages for this script
--
local bin = require "bin"
local nmap = require "nmap"
local shortport = require "shortport"
local stdnse = require "stdnse"
local string = require "string"
local table = require "table"


description = [[
Enumerates Siemens S7 PLC Devices and collects their device information. This
NSE is based off PLCScan that was developed by Positive Research and
Scadastrangelove (https://code.google.com/p/plcscan/). This script is meant to
provide the same functionality as PLCScan inside of Nmap. Some of the
information that is collected by PLCScan was not ported over to this NSE, this
information can be parsed out of the packets that are received.

Thanks to Positive Research, and Dmitry Efanov for creating PLCScan
]]

author = "Stephen Hilt (Digital Bond)"
license = "Same as Nmap--See http://nmap.org/book/man-legal.html"
categories = {"discovery","intrusive"}

---
-- @usage
-- nmap -sP --script s7-discover.nse -p 102 <host/s>
--
-- @output
--102/tcp open  Siemens S7 315 PLC
--| s7-discover:
--|   Basic Hardware: 6ES7 315-2AG10-0AB0
--|   System Name: SIMATIC 300(1)
--|   Copyright: Original Siemens Equipment
--|   Version: 2.6.9
--|   Module Type: CPU 315-2 DP
--|   Module: 6ES7 315-2AG10-0AB0
--|_  Serial Number: S C-X4U421302009
--
--
-- @xmloutput
--<elem key="Basic Hardware">6ES7 315-2AG10-0AB0</elem>
--<elem key="System Name">SIMATIC 300(1)</elem>
--<elem key="Copyright">Original Siemens Equipment</elem>
--<elem key="Version">2.6.9</elem>
--<elem key="Object Name">SimpleServer</elem>
--<elem key="Module Type">CPU 315-2 DP</elem>
--<elem key="Module">6ES7 315-2AG10-0AB0</elem>
--<elem key="Serial Number">S C-X4U421302009</elem>
--<elm key="Plant Identification"></elem>


-- port rule for devices running on TCP/102
portrule = shortport.port_or_service(102, "iso-tsap", "tcp")

---
-- Function to send and receive the S7COMM Packet
--
-- First argument is the socket that was created inside of the main Action
-- this will be utilized to send and receive the packets from the host.
-- the second argument is the query to be sent, this is passed in and is created
-- inside of the main action.
-- @param socket the socket that was created in Action.
-- @param query the specific query that you want to send/receive on.
function send_receive(socket, query)
  local sendstatus, senderr = socket:send(query)
  if(sendstatus == false) then
    return "Error Sending S7COMM"
  end
  -- receive response
  local rcvstatus,response = socket:receive()
  if(rcvstatus == false) then
    return "Error Reading S7COMM"
  end
  return response
end

---
-- Function to parse the first SZL Request response that was received from the S7 PLCC
--
-- First argument is the socket that was created inside of the main Action
-- this will be utilized to send and receive the packets from the host.
-- the second argument is the query to be sent, this is passed in and is created
-- inside of the main action.
-- @param response Packet response that was received from S7 host.
-- @param host The host hat was passed in via Nmap, this is to change output of host/port
-- @param port The port that was passed in via Nmap, this is to change output of host/port
-- @param output Table used for output for return to Nmap
function parse_response(response, host, port, output)
  -- unpack the protocol ID
  local pos, value = bin.unpack("C", response, 8)
  -- unpack the second byte of the SZL-ID
  local pos, szl_id = bin.unpack("C", response, 31)
  -- set the offset to 0
  local offset = 0
  -- if the protocol ID is 0x32
  if (value == 0x32) then
    local pos
    -- unpack the module information
    pos, output["Module"] = bin.unpack("z", response, 44)
    -- unpack the basic hardware information
    pos, output["Basic Hardware"] = bin.unpack("z", response, 72)
    -- set version number to 0
    local version = 0
    -- parse version number
    local pos, char1,char2,char3 = bin.unpack("CCC", response, 123)
    -- concatenate string, or if string is nil make version number 0.0
    output["Version"] = table.concat({char1 or "0.0", char2, char3}, ".")
    -- return the output table
    return output
  else
    return nil
  end
end

---
-- Function to parse the second SZL Request response that was received from the S7 PLC
--
-- First argument is the socket that was created inside of the main Action
-- this will be utilized to send and receive the packets from the host.
-- the second argument is the query to be sent, this is passed in and is created
-- inside of the main action.
-- @param response Packet response that was received from S7 host.
-- @param output Table used for output for return to Nmap
function second_parse_response(response, output)
  local offset = 0
  -- unpack the protocol ID
  local pos, value = bin.unpack("C", response, 8)
  -- unpack the second byte of the SZL-ID
  local pos, szl_id = bin.unpack("C", response, 31)
  -- if the protocol ID is 0x32
  if (value == 0x32) then
    -- if the szl-ID is not 0x1c
    if( szl_id ~= 0x1c ) then
      -- change offset to 4, this is where most ov valid PLCs will fall
      offset = 4
    end
    -- parse system name
    pos, output["System Name"] = bin.unpack("z", response, 40 + offset)
    -- parse module type
    pos, output["Module Type"] = bin.unpack("z", response, 74 + offset)
    -- parse serial number
    pos, output["Serial Number"] = bin.unpack("z", response, 176 + offset)
    -- parse plant identification
    pos, output["Plant Identification"] = bin.unpack("z", response, 108 + offset)
    -- parse copyright
    pos, output["Copyright"] = bin.unpack("z", response, 142 + offset)

    -- for each element in the table, if it is nil, then remove the information from the table
    for key,value in pairs(output) do
      if(string.len(output[key]) == 0) then
        output[key] = nil
      end
    end
    -- return output
    return output
  else
    return nil
  end
end
---
--  Function to set the nmap output for the host, if a valid S7COMM packet
--  is received then the output will show that the port is open
--  and change the output to reflect an S7 PLC
--
-- @param host Host that was passed in via nmap
-- @param port port that S7COMM is running on
function set_nmap(host, port)
  --set port Open
  port.state = "open"
  -- set that detected an Siemens S7
  port.version.name = "iso-tsap"
  port.version.devicetype = "specialized"
  port.version.product = "Siemens S7 PLC"
  nmap.set_port_version(host, port)
  nmap.set_port_state(host, port, "open")

end
---
--  Action Function that is used to run the NSE. This function will send the initial query to the
--  host and port that were passed in via nmap. The initial response is parsed to determine if host
--  is a S7COMM device. If it is then more actions are taken to gather extra information.
--
-- @param host Host that was scanned via nmap
-- @param port port that was scanned via nmap
action = function(host,port)
  -- COTP packet with a dst of 102
  local COTP = bin.pack("H","0300001611e00000001400c1020100c2020" .. "102" .. "c0010a")
  -- COTP packet with a dst of 200
  local alt_COTP = bin.pack("H","0300001611e00000000500c1020100c2020" .. "200" .. "c0010a")
  -- setup the ROSCTR Packet
  local ROSCTR_Setup = bin.pack("H","0300001902f08032010000000000080000f0000001000101e0")
  -- setup the Read SZL information packet
  local Read_SZL = bin.pack("H","0300002102f080320700000000000800080001120411440100ff09000400110001")
  -- setup the first SZL request (gather the basic hardware and version number)
  local first_SZL_Request = bin.pack("H","0300002102f080320700000000000800080001120411440100ff09000400110001")
  -- setup the second SZL request
  local second_SZL_Request = bin.pack("H","0300002102f080320700000000000800080001120411440100ff090004001c0001")
  -- response is used to collect the packet responses
  local response
  -- output table for Nmap
  local output = stdnse.output_table()
  -- create socket for communications
  local sock = nmap.new_socket()
  -- connect to host
  local constatus,conerr = sock:connect(host,port)
  if not constatus then
    stdnse.print_debug(1,
      'Error establishing connection for %s - %s', host,conerr
      )
    return nil
  end
  -- send and receive the COTP Packet
  response  = send_receive(sock, COTP)
  -- unpack the PDU Type
  local pos, CC_connect_confirm = bin.unpack("C", response, 6)
  -- if PDU type is not 0xd0, then not a successful COTP connection
  if ( CC_connect_confirm ~= 0xd0) then
    return nil
  end
  -- send and receive the ROSCTR Setup Packet
  response  = send_receive(sock, ROSCTR_Setup)
  -- unpack the protocol ID
  local pos, protocol_id = bin.unpack("C", response, 8)
  -- if protocol ID is not 0x32 then return nil
  if ( protocol_id ~= 0x32) then
    return nil
  end
  -- send and receive the READ_SZL packet
  response  = send_receive(sock, Read_SZL)
  local pos, protocol_id = bin.unpack("C", response, 8)
  -- if protocol ID is not 0x32 then return nil
  if ( protocol_id ~= 0x32) then
    return nil
  end
  -- send and receive the first SZL Request packet
  response  = send_receive(sock, first_SZL_Request)
  -- parse the response for basic hardware information
  output = parse_response(response, host, port, output)
  -- send and receive the second SZL Request packet
  response = send_receive(sock, second_SZL_Request)
  -- parse the response for more information
  output = second_parse_response(response, output)
  -- if nothing was parsed from the previous two responses
  if(output == nil) then
    -- re initialize the table
    output = stdnse.output_table()
    -- re connect to the device ( a RST packet was sent in the previous attempts)
    local constatus,conerr = sock:connect(host,port)
    if not constatus then
      stdnse.print_debug(1,
        'Error establishing connection for %s - %s', host,conerr
        )
      return nil
    end
    -- send and receive the alternate COTP Packet, the dst is 200 instead of 102( do nothing with result)
    response  = send_receive(sock, alt_COTP)
    local pos, CC_connect_confirm = bin.unpack("C", response, 6)
    -- if PDU type is not 0xd0, then not a successful COTP connection
    if ( CC_connect_confirm ~= 0xd0) then
      stdnse.print_debug(1, "Not a successful COTP Packet")
      return nil
    end
    -- send and receive the packets as before.
    response  = send_receive(sock, ROSCTR_Setup)
    -- unpack the protocol ID
    local pos, protocol_id = bin.unpack("C", response, 8)
    -- if protocol ID is not 0x32 then return nil
    if ( protocol_id ~= 0x32) then
      stdnse.print_debug(1, "Not a successful S7COMM Packet")
      return nil
    end
    response  = send_receive(sock, Read_SZL)
    -- unpack the protocol ID
    local pos, protocol_id = bin.unpack("C", response, 8)
    -- if protocol ID is not 0x32 then return nil
    if ( protocol_id ~= 0x32) then
      stdnse.print_debug(1, "Not a successful S7COMM Packet")
      return nil
    end
    response  = send_receive(sock, first_SZL_Request)
    output = parse_response(response, host, port, "ONE", output)
    response = send_receive(sock, second_SZL_Request)
    output = parse_response(response, host, port, "TWO", output)
  end
  -- close the socket
  sock:close()
  
  -- If we parsed anything, then set the version info for Nmap
  if #output > 0 then
    set_nmap(host, port)
  end
  -- return output to Nmap
  return output

end

