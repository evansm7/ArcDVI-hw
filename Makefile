# Makefile for ArcDVI
#
# Copyright 2021-2022 Matt Evans
#


HIRES_MODE ?= 0

VERILOG_FILES = src/soc_top_arcdvi.v
VERILOG_FILES += src/vidc_capture.v
VERILOG_FILES += src/video.v
VERILOG_FILES += src/video_timing.v
VERILOG_FILES += src/clocks.v
VERILOG_FILES += src/spir.v

ARCDVI_TOP_MODULE = soc_top_arcdvi


all:	tb_top_arcdvi.wave

clean:
	rm -f *~ src/*~ tb/*~ *.vvp *.vcd *.bit *.asc *.json

################################################################################

VDEFS=

# Build options
ifneq ($(HIRES_MODE), 0)
	VDEFS += -DHIRES_MODE=1
endif

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

tb_top.vvp:	tb/tb_top.v
	$(IVERILOG) $(IVOPTS) $(IVPATHS) -o $@ $<

tb_top_arcdvi.vvp:	tb/tb_top_arcdvi.v
	$(IVERILOG) $(IVOPTS) $(IVPATHS) -DARCDVI_ICE40 -o $@ $<

tb_comp_video_timing.vvp:	tb/tb_comp_video_timing.v
	$(IVERILOG) $(IVOPTS) $(IVPATHS) -o $@ $^

tb_comp_spir.vvp:	tb/tb_comp_spir.v
	$(IVERILOG) $(IVOPTS) $(IVPATHS) -o $@ $^


################################################################################

YOSYS ?= yosys
NEXTPNR-ICE40 ?= nextpnr-ice40
ICEPACK ?= icepack

NEXTPNR_OPTIONS = --timing-allow-fail
NEXTPNR_OPTIONS += --report timing.json --placer heap --router router1 --starttemp 20

bitstream: arcdvi-bitstream
arcdvi-bitstream: arcdvi-ice40.bit

arcdvi-ice40.json: $(VERILOG_FILES)
	$(YOSYS) $(VDEFS) -DARCDVI_ICE40 \
	-p "synth_ice40 ${YOSYS_OPTIONS} -json $@ -device hx -abc2 -top ${ARCDVI_TOP_MODULE}" \
	$(VERILOG_FILES)

%.asc: %.json
	$(NEXTPNR-ICE40) --freq 100 --timing-allow-fail --top $(ARCDVI_TOP_MODULE) \
	--json $< --seed $(shell date +%s) --hx4k --package tq144 --pcf platform/arcdvi-ice40/$(subst .json,,$<).pcf \
	--asc $@

%.bit: %.asc
	$(ICEPACK) $< $@

