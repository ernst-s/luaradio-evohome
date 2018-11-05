---
-- Sink evohome frames to udp

local bit = require('bit')

local block = require('radio.core.block')
local types = require('radio.types')
local socket = require('socket')
local udp = socket.udp()
local EvohomeFrameType = require('blocks.evohomeframer').EvohomeFrameType


local EvohomeUDPSinkBlock = block.factory("EvohomeUDPSinkBlock")

function EvohomeUDPSinkBlock:instantiate()
    self:add_type_signature({block.Input("in", EvohomeFrameType)}, {block.Output("out", EvohomeFrameType)})
end


function EvohomeUDPSinkBlock:process(x)
    for i = 0, x.length-1 do
	local frame,raw_frame = "", ""
	for j = 0, x.data[i].raw_frame_length -1 do
            raw_frame = raw_frame .. string.char(x.data[i].raw_frame[j])
	end
	for j = 0, x.data[i].frame_length -1 do
            frame = frame .. string.char(x.data[i].raw_frame[j])
	end
	udp:setsockname('*', '9000')
        assert(udp:sendto(raw_frame, "127.0.0.1", 8888))
        assert(udp:sendto(frame , "127.0.0.1", 8889))
   end
   return
end

return EvohomeUDPSinkBlock
