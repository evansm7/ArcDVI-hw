# Makefile for ArcDVI
#
# Copyright 2021-2022 Matt Evans
#


HIRES_MODE ?= 0
PCLK_MULT ?= 1.5

TARGET ?= normal

VERILOG_FILES = src/soc_top_arcdvi.v
VERILOG_FILES += src/soc_top_test.v
VERILOG_FILES += src/vidc_capture.v
VERILOG_FILES += src/video.v
VERILOG_FILES += src/video_timing.v
VERILOG_FILES += src/video_test_pattern.v
VERILOG_FILES += src/video_pixel_demux.v
VERILOG_FILES += src/demux_32_2.v
VERILOG_FILES += src/clocks.v
VERILOG_FILES += src/spir.v


all:	tb_top_arcdvi.wave

clean:
	rm -f *~ src/*~ tb/*~ *.vvp *.vcd *.bit *.asc *.json src/pll.vh

################################################################################

VDEFS=

# Build options
ifneq ($(HIRES_MODE), 0)
	PCLK_MULT = 4
	VDEFS += -DHIRES_MODE=1
endif

ifeq ("$(TARGET)", "test")
# Engineering test build
	VDEFS += -DTEST_BUILD=1
	ARCDVI_TOP_MODULE = soc_top_test
	CLK_IN = 62.5
else
# Regular build
	ARCDVI_TOP_MODULE = soc_top_arcdvi
	CLK_IN = 24
endif

VDEFS += -DPCLK_MULT=$(PCLK_MULT)

# Test/sim stuff:
IVERILOG = iverilog
IVPATHS = -y src -y external-src
IVOPTS = -g2005-sv
IVOPTS += $(VDEFS)


.PHONY: wave
wave:	tb_top_arcdvi.wave

.PHONY:	sim
sim:	tb_top_arcdvi.vcd

%.vcd:	%.vvp
	vvp $<

.PHONY: %.wave
%.wave:	%.vcd
	gtkwave $<

tb_top_arcdvi.vvp:	tb/tb_top_arcdvi.v
	$(IVERILOG) $(IVOPTS) $(IVPATHS) -DARCDVI_ICE40 -o $@ $<

%.vvp:	tb/%.v
	$(IVERILOG) $(IVOPTS) $(IVPATHS) -o $@ $^


################################################################################

YOSYS ?= yosys
NEXTPNR-ICE40 ?= nextpnr-ice40
ICEPACK ?= icepack

NEXTPNR_OPTIONS = --timing-allow-fail
NEXTPNR_OPTIONS += --report timing.json --placer heap --router router1 --starttemp 20

PLATFORM = arcdvi-ice40-v2

bitstream: arcdvi-bitstream
arcdvi-bitstream: arcdvi-ice40.bit

arcdvi-ice40.json: $(VERILOG_FILES) src/pll.vh
	$(YOSYS) $(VDEFS) -DARCDVI_ICE40 \
	-p "synth_ice40 ${YOSYS_OPTIONS} -json $@ -device hx -abc2 -top ${ARCDVI_TOP_MODULE}" \
	$(VERILOG_FILES)

%.asc: %.json
	$(NEXTPNR-ICE40) --freq 100 --timing-allow-fail --top $(ARCDVI_TOP_MODULE) \
	--json $< --seed $(shell date +%s) --hx4k --package tq144 --pcf platform/$(PLATFORM)/$(subst .json,,$<).pcf \
	--asc $@

%.bit: %.asc
	$(ICEPACK) $< $@

src/pll.vh:
	@echo "Input clock $(CLK_IN)MHz"
	icepll -i $(CLK_IN) -o $(shell echo "$(CLK_IN) * $(PCLK_MULT)" | bc) -f $@
