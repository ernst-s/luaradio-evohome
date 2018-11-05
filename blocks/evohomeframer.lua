---
-- Detect, validate, and extract HoneyWell evohome frames from a bit stream.
-- Each frame contains a single message with type, data
--
-- @category Protocol
-- @block EvohomeFramerBlock
--
-- @signature in:Bit > out:EvohomeFrameType
--
-- @usage
-- local framer = radio.EvohomeFramerBlock()

---
-- Evohome frame type, a Lua object with properties:
--
-- ``` text
-- {
--   command = <2 byte command>,
--   data = {<byte>, ...},
-- }
-- ```
--
-- @type EvoHomeFrameType
-- @category Protocol
-- @datatype EvohomeFramerBlock.EvohomeFrameType

local ffi = require('ffi')
local bit = require('bit')

local block = require('radio.core.block')
local debug = require('radio.core.debug')
local types = require('radio.types')

-- POCSAG Related constants

local EvohomeFramerState = { FRAME_SYNC = 1, END =2 }
local EVOHOME_FRAME_SYNC_CODEWORD_BITS = types.Bit.vector_from_array(
    {0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1}
)
local EVOHOME_MAX_LENGTH = 255
local EVOHOME_HEAD_ARRAY  = {0x33, 0x55, 0x53}
local EVOHOME_END_BYTE = 0x35

local EVOHOME_MANCHESTER_MATRIX = {
    [0xaa] = 0x00, [0xa9] = 0x01, [0xa6] = 0x02, [0xa5] = 0x03,
    [0x9a] = 0x04, [0x99] = 0x05, [0x96] = 0x06, [0x95] = 0x07,
    [0x6a] = 0x08, [0x69] = 0x09, [0x66] = 0x0a, [0x65] = 0x0b,
    [0x5a] = 0x0c, [0x59] = 0x0d, [0x56] = 0x0e, [0x55] = 0x0f
}

-- Evohome frame type
--
ffi.cdef[[
    typedef struct {
	unsigned char frame_length;
	unsigned char frame[256];
	unsigned char raw_frame_length;
	unsigned char raw_frame[256];
    } evohome_frame_t
]]
        
local evohome_frame_type_mt = {
    __tostring = function (self)
      local frame_text=""
      for i = 0 , self.frame_length-1 do
           frame_text = frame_text .. string.format("%02x", self.frame[i])
      end
      return frame_text
      end,
}

local EvohomeFrameType = types.CStructType.factory("evohome_frame_t", evohome_frame_type_mt)

-- Evohome Frame Block

local EvohomeFramerBlock = block.factory("EvohomeFramerBlock")

function EvohomeFramerBlock:instantiate()
    -- Raw frame buffer
    self.buffer = types.Bit.vector(EVOHOME_MAX_LENGTH*10)
    self.buffer_length = 0
    self.raw_frame = types.Byte.vector(EVOHOME_MAX_LENGTH)
    self.raw_frame_length = 0
    self.state = EvohomeFramerState.FRAME_SYNC
    -- Current frame
    self.frame = nil
    self:add_type_signature({block.Input("in", types.Bit)}, {block.Output("out", EvohomeFrameType)})
end

EvohomeFramerBlock.EvohomeFrameType = EvohomeFrameType

-- Check frame and decode frame

local function parseframe(raw_frame,raw_frame_length)
    if raw_frame_length < 12 then
       debug.printf('frame too short\n')
       return nil
    end
    debug.printf('frame length %x\n', raw_frame_length)
    if raw_frame_length%2 ~= 0 then
       debug.printf('Invalid frame length\n')
       return nil
    end
    local frame_data_length = raw_frame_length/2-4
    local frame_data = types.Byte.vector(256)
    local n=0
    for i=0,raw_frame_length - 2 do
        if i < 3 then
	    if raw_frame.data[i].value ~= EVOHOME_HEAD_ARRAY[i+1] then
                debug.printf('No evohome header in frame %x = %x\n',raw_frame.data[i].value, EVOHOME_HEAD_ARRAY[i+1])
		return nil
	    end
        elseif i%2==1 and EVOHOME_MANCHESTER_MATRIX[raw_frame.data[i].value] and EVOHOME_MANCHESTER_MATRIX[raw_frame.data[i+1].value] then
            frame_data.data[n].value = 16 * EVOHOME_MANCHESTER_MATRIX[raw_frame.data[i].value] + EVOHOME_MANCHESTER_MATRIX[raw_frame.data[i + 1].value] 
	    n = n + 1
	elseif i%2==1 then
           debug.printf('Manchester decoding failed\n')
		return nil
        end
    end
    local frame_text=""
      for i = 0 , raw_frame_length-1 do
           frame_text = frame_text .. string.format("%x", raw_frame.data[i].value)
      end
      debug.print(frame_text)
    local frame = EvohomeFrameType()
    frame.frame_length = frame_data_length
    ffi.C.memcpy(frame.frame, frame_data.data[0], frame_data_length)
    frame.raw_frame_length = raw_frame_length
    ffi.C.memcpy(frame.raw_frame, raw_frame.data[0], raw_frame_length)
    return frame
end

function EvohomeFramerBlock:process(x)
    local out = EvohomeFrameType.vector()
    local i = 0
    while i < x.length or self.buffer_length >= 20 do
        -- Shift in as many bits as we can into the frame buffer
        if self.buffer_length < EVOHOME_MAX_LENGTH*10 then
            -- Calculate the maximum number of bits we can shift
            local n = math.min(EVOHOME_MAX_LENGTH*10 - self.buffer_length, x.length-i)
            ffi.C.memcpy(self.buffer.data[self.buffer_length], x.data[i], n*ffi.sizeof(self.buffer.data[0]))
            i, self.buffer_length = i + n, self.buffer_length + n
        end
        if self.state == EvohomeFramerState.FRAME_SYNC and self.buffer_length >= 20 then
	    while self.buffer_length >= 20 do
                if types.Bit.tonumber(self.buffer,0, 20) == types.Bit.tonumber(EVOHOME_FRAME_SYNC_CODEWORD_BITS,0, 20) then
                    -- Shift the FRAME_SYNC_CODEWORD out
		    ffi.C.memmove(self.buffer.data, self.buffer.data[10*2], self.buffer_length - 10*2)
		    self.buffer_length = self.buffer_length - 10*2
		    self.state = EvohomeFramerState.END
        	    debug.printf('got sync\n')
		    break
		end
		-- Shift the buffer down one bit
                ffi.C.memmove(self.buffer.data, self.buffer.data[1], self.buffer_length - 1)
                self.buffer_length = self.buffer_length - 1
            end
	end
        if self.state == EvohomeFramerState.END and self.buffer_length >= 10 then
	   while self.buffer_length >= 10 do
                -- Check start stop bits and add bytes to self.raw_frame
		if self.buffer.data[0].value == 0 and self.buffer.data[10-1].value == 1 then
		   self.raw_frame.data[self.raw_frame_length].value = types.Bit.tonumber(self.buffer, 1, 8, "lsb")
		   self.raw_frame_length = self.raw_frame_length + 1
		   if self.raw_frame.data[self.raw_frame_length-1].value == EVOHOME_END_BYTE then
		       debug.printf('End byte detected parsing frame\n')
		       local frame = parseframe(self.raw_frame, self.raw_frame_length)
		       if frame then
			   debug.printf('frame added to out \n')
		           out:append(frame)
		       end
		       self.state = EvohomeFramerState.FRAME_SYNC
		       self.raw_frame_length = 0
		       break
		   end
                   ffi.C.memmove(self.buffer.data, self.buffer.data[10], self.buffer_length - 10)
                   self.buffer_length = self.buffer_length - 10
		   if self.raw_frame_length == 256 then
		       debug.printf('Frame length exceeded frame discarded\n')
		       self.state = EvohomeFramerState.FRAME_SYNC
		       self.raw_frame_length = 0
		   end
	        else
                    debug.printf('Invalid start-stop bit detected frame discarded\n')
                    ffi.C.memmove(self.buffer.data, self.buffer.data[10], self.buffer_length - 10)
                    self.buffer_length = self.buffer_length - 10
		    self.state = EvohomeFramerState.FRAME_SYNC
		    self.raw_frame_length = 0
		    break
		end
            end
        end
    end
  return out
end

return EvohomeFramerBlock
