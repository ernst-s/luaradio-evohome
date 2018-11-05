---
-- Squelch a real or complex valued signal by its average power.
--
-- $$ y[n] = \begin{cases} x[n] & \text{if } P_\text{average}(x[n]) > P_\text{threshold} \\ 0.0 & \text{otherwise} \end{cases} $$
--
-- @category Level Control
-- @block PowerSquelchGateBlock
-- @tparam number threshold Power threshold in dBFS
-- @tparam[opt=0.001] number tau Time constant of moving average filter in seconds
-- @signature in:Float32 > out:Float32
-- @signature in:ComplexFloat32 > out:ComplexFloat32
--
-- @usage
-- -- Squelch at -40 dBFS power
-- local squelch = radio.PowerSquelchGateBlock(-40)

local math = require('math')

local block = require('radio.core.block')
local types = require('radio.types')

local PowerSquelchGateBlock = block.factory("PowerSquelchGateBlock")

function PowerSquelchGateBlock:instantiate(threshold, cutoff)
    self.threshold = assert(threshold, "Missing argument #1 (threshold)")
    self.tau = tau or 0.001

    self:add_type_signature({block.Input("in", types.Float32)}, {block.Output("out", types.Float32)}, self.process_real)
    self:add_type_signature({block.Input("in", types.ComplexFloat32)}, {block.Output("out", types.ComplexFloat32)}, self.process_complex)
end

function PowerSquelchGateBlock:initialize()
    -- Compute normalized alpha
    self.alpha = 1/(1 + self.tau*self:get_rate())
    -- Initialize average power state
    self.average_power = 0.0
    -- Linearize logarithmic power threshold
    self.threshold = 10^(self.threshold/10)

    self.out = self:get_input_type().vector()
end

function PowerSquelchGateBlock:process_real(x)
    local out = self.out:resize(x.length)
    o = 0
    for i = 0, x.length-1 do
        self.average_power = (1 - self.alpha)*self.average_power + self.alpha*(x.data[i].value*x.data[i].value)

        if self.average_power >= self.threshold then
            out.data[o].value = x.data[i].value
	    o = o + 1
        end
    end
    out:resize(o)
    return out
end

function PowerSquelchGateBlock:process_complex(x)
    local out = self.out:resize(x.length)
    o = 0
    for i = 0, x.length-1 do
        self.average_power = (1 - self.alpha)*self.average_power + self.alpha*x.data[i]:abs_squared()

        if self.average_power >= self.threshold then
            out.data[o].real = x.data[i].real
            out.data[o].imag = x.data[i].imag
	    o = o + 1
        end
    end
    out:resize(o)
    return out
end

return PowerSquelchGateBlock
