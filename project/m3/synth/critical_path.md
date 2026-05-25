# Critical Path Identification

OpenLane 2 v2.3.10 completed pre-PNR STA for the integrated M3 top. The worst
setup path is in the slow corner `nom_ss_100C_1v60`. It starts at flip-flop
`_3577_`, which drives the named net `compute_i.tap_index[0]`, and ends at
flip-flop `_3637_`, both clocked by `clk`. The path has 15.978312 ns data
arrival time, 9.493772 ns data required time, and -6.484541 ns setup slack at
the requested 10.0 ns period. Hold timing is clean; the slow-corner hold worst
slack is +0.7022 ns.

The logic stages match the expected compute-core bottleneck. `tap_index[0]`
feeds a `sky130_fd_sc_hd__mux4_2` selector used in packed tap selection, then
passes through a long chain of mapped Sky130 cells including `o221a_2`,
`a22oi_2`, `a211o_2`, `o21a_2`, `a21oi_2`, `and3b_2`, `or2_2`, `and2_2`,
`xnor2_2`, `nand2b_2`, `xor2_2`, `a2111o_2`, and additional `a21o_2` and
`and3_2` logic before reaching the endpoint flop. Functionally, this is the
dynamic INT8 tap-select and signed multiply/accumulate path in `compute_core`,
not the AXI4-Stream interface glue. It is the critical path because tap index
selection, operand muxing, multiplier partial-product logic, and accumulator
carry/sign logic are all being resolved inside one compute cycle. The most
direct fix is to pipeline the core: register the selected activation and weight,
register the signed product, and then feed the accumulator in a later cycle.
That would increase result latency but should reduce the slow-corner setup
delay without changing the host-visible AXI command protocol.
