local radio = require('radio')

local frequency = 868.3e6
local tune_offset = -300e3
local baudrate = 38400
local fskdist  = 100e3
local gainfactor = 1

-- Custom Blocks

local evohome = {
	PowerSquelchGateBlock = require('blocks.powersquelchgate'),
	EvohomeFramerBlock = require('blocks.evohomeframer'),
	EvohomeUDPSink = require('blocks.evohomeudpsink')
}

-- Blocks
 local source = radio.RtlSdrSource(frequency + tune_offset, 1800000, {rf_gain = 20.0})
-- local source = radio.IQFileSource("evohome.capture","f32le", 1152000, false )
local tuner = radio.TunerBlock(tune_offset, 2*fskdist , 1)
local squelch = evohome.PowerSquelchGateBlock(-50)
local space_filter = radio.ComplexBandpassFilterBlock(129, {0, -fskdist})
local space_magnitude = radio.ComplexMagnitudeBlock()
local mark_filter = radio.ComplexBandpassFilterBlock(129, {0, fskdist})
local mark_magnitude = radio.ComplexMagnitudeBlock()
local subtractor = radio.SubtractBlock()
local multiplygain = radio.MultiplyConstantBlock(gainfactor)
local data_filter = radio.LowpassFilterBlock(128, baudrate)
local clock_recoverer = radio.ZeroCrossingClockRecoveryBlock(baudrate)
local sampler = radio.SamplerBlock()
local bit_slicer = radio.SlicerBlock()
local framer = evohome.EvohomeFramerBlock()
local sink = evohome.EvohomeUDPSink()
-- local sinkdemod = radio.RawFileSink("evohome.demod")

-- Plotting sinks
-- local plot1 = radio.GnuplotSpectrumSink(2048, 'RF Spectrum', {yrange = {-120, -20}})
-- local plot2 = radio.GnuplotPlotSink(10000, 'Demodulated Bitstream', {yrange = {-1, 1}})

-- Connections
local top = radio.CompositeBlock()
top:connect(source, tuner, squelch )
top:connect(squelch, space_filter, space_magnitude)
top:connect(squelch, mark_filter, mark_magnitude)
top:connect(mark_magnitude, 'out', subtractor, 'in1')
top:connect(space_magnitude, 'out', subtractor, 'in2')
top:connect(subtractor, multiplygain,  data_filter, clock_recoverer)
top:connect(data_filter, 'out', sampler, 'data')
top:connect(clock_recoverer, 'out', sampler, 'clock')
top:connect(sampler, bit_slicer, framer, sink)
-- top:connect(data_filter, sinkdemod)
-- if os.getenv('DISPLAY') then
--     top:connect(tuner, plot1)
--     top:connect(clock_recoverer, plot2)
-- end

top:run()
