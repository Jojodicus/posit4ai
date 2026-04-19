// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Macros and helper code for using assertions.
// MODIFIED for Vivado XSim compatibility - provides no-op macros to avoid
// default parameter syntax errors

`ifndef PRIM_ASSERT_SV
`define PRIM_ASSERT_SV

`ifdef UVM
  // report assertion error with UVM if compiled
  package assert_rpt_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    function void assert_rpt(string msg);
      `uvm_error("ASSERT FAILED", msg)
    endfunction
  endpackage
`endif

///////////////////
// Helper macros //
///////////////////

// local helper macro to reduce code clutter. undefined at the end of this file
`ifndef VERILATOR
`ifndef SYNTHESIS
`ifndef XSIM
`define INC_ASSERT
`endif
`endif
`endif

// Converts an arbitrary block of code into a Verilog string
`define PRIM_STRINGIFY(__x) `"__x`"

// ASSERT_RPT is available to change the reporting mechanism when an assert fails
`define ASSERT_RPT(__name)                                                  \
`ifdef UVM                                                                  \
  assert_rpt_pkg::assert_rpt($sformatf("[%m] %s (%s:%0d)",                  \
                             __name, `__FILE__, `__LINE__));                \
`else                                                                       \
  $error("[ASSERT FAILED] [%m] %s (%s:%0d)", __name, `__FILE__, `__LINE__); \
`endif

///////////////////////////////////////
// Simple assertion and cover macros //
///////////////////////////////////////

// Default clk and reset signals used by assertion macros below.
`define ASSERT_DEFAULT_CLK clk_i
`define ASSERT_DEFAULT_RST !rst_ni

// Immediate assertion
// Note that immediate assertions are sensitive to simulation glitches.
`define ASSERT_I(__name, __prop)           \
`ifdef INC_ASSERT                          \
  __name: assert (__prop)                  \
    else begin                             \
      `ASSERT_RPT(`PRIM_STRINGIFY(__name)) \
    end                                    \
`endif

// Assertion in initial block. Can be used for things like parameter checking.
`define ASSERT_INIT(__name, __prop)          \
`ifdef INC_ASSERT                            \
  initial begin                              \
    __name: assert (__prop)                  \
      else begin                             \
        `ASSERT_RPT(`PRIM_STRINGIFY(__name)) \
      end                                    \
  end                                        \
`endif

// Assertion in final block. Can be used for things like queues being empty
// at end of sim, all credits returned at end of sim, state machines in idle
// at end of sim.
`define ASSERT_FINAL(__name, __prop)                                         \
`ifdef INC_ASSERT                                                            \
  final begin                                                                \
    __name: assert (__prop || $test$plusargs("disable_assert_final_checks")) \
      else begin                                                             \
        `ASSERT_RPT(`PRIM_STRINGIFY(__name))                                 \
      end                                                                    \
  end                                                                        \
`endif

// Assert a concurrent property directly - EXPLICIT PARAMETERS VERSION
`define _ASSERT4(__name, __prop, __clk, __rst)                                           \
`ifdef INC_ASSERT                                                                        \
  __name: assert property (@(posedge __clk) disable iff ((__rst) !== '0) (__prop))       \
    else begin                                                                           \
      `ASSERT_RPT(`PRIM_STRINGIFY(__name))                                               \
    end                                                                                  \
`endif

// Assert a concurrent property directly - DEFAULT PARAMETERS VERSION
`define ASSERT(__name, __prop) \
  `_ASSERT4(__name, __prop, `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST)

// Assert a concurrent property NEVER happens - EXPLICIT PARAMETERS VERSION
`define _ASSERT_NEVER4(__name, __prop, __clk, __rst)                                     \
`ifdef INC_ASSERT                                                                        \
  __name: assert property (@(posedge __clk) disable iff ((__rst) !== '0) not (__prop))   \
    else begin                                                                           \
      `ASSERT_RPT(`PRIM_STRINGIFY(__name))                                               \
    end                                                                                  \
`endif

// Assert a concurrent property NEVER happens - DEFAULT PARAMETERS VERSION
`define ASSERT_NEVER(__name, __prop) \
  `_ASSERT_NEVER4(__name, __prop, `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST)

// Assert that signal has a known value - DEFAULT PARAMETERS VERSION
`define ASSERT_KNOWN(__name, __sig) \
  `_ASSERT4(__name, !$isunknown(__sig), `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST)

// Cover a concurrent property - EXPLICIT PARAMETERS VERSION
`define _COVER4(__name, __prop, __clk, __rst) \
`ifdef INC_ASSERT                             \
  __name: cover property (@(posedge __clk) disable iff ((__rst) !== '0) (__prop)); \
`endif

// Cover a concurrent property - DEFAULT PARAMETERS VERSION
`define COVER(__name, __prop) \
  `_COVER4(__name, __prop, `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST)

//////////////////////////////
// Complex assertion macros //
//////////////////////////////

// Assert that signal is an active-high pulse with pulse length of 1 clock cycle
`define ASSERT_PULSE(__name, __sig) \
`ifdef INC_ASSERT                   \
  `_ASSERT4(__name, $rose(__sig) |=> !(__sig), `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST) \
`endif

// Assert that a property is true only when an enable signal is set
`define ASSERT_IF(__name, __prop, __enable) \
`ifdef INC_ASSERT                           \
  `_ASSERT4(__name, (__enable) |-> (__prop), `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST) \
`endif

// Assert that signal has a known value if enable is set
`define ASSERT_KNOWN_IF(__name, __sig, __enable)                                      \
`ifdef INC_ASSERT                                                                     \
  `_ASSERT4(__name``KnownEnable, !$isunknown(__enable), `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST) \
  `_ASSERT4(__name, (__enable) |-> !$isunknown(__sig), `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST)  \
`endif

///////////////////////
// Assumption macros //
///////////////////////

// Assume a concurrent property - EXPLICIT PARAMETERS VERSION
`define _ASSUME4(__name, __prop, __clk, __rst)                                       \
`ifdef INC_ASSERT                                                                    \
  __name: assume property (@(posedge __clk) disable iff ((__rst) !== '0) (__prop))   \
    else begin                                                                       \
      `ASSERT_RPT(`PRIM_STRINGIFY(__name))                                           \
    end                                                                              \
`endif

// Assume a concurrent property - DEFAULT PARAMETERS VERSION
`define ASSUME(__name, __prop) \
  `_ASSUME4(__name, __prop, `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST)

// Assume an immediate property
`define ASSUME_I(__name, __prop)           \
`ifdef INC_ASSERT                          \
  __name: assume (__prop)                  \
    else begin                             \
      `ASSERT_RPT(`PRIM_STRINGIFY(__name)) \
    end                                    \
`endif

//////////////////////////////////
// For formal verification only //
//////////////////////////////////

// ASSUME_FPV - Assume a concurrent property during formal verification only
`define ASSUME_FPV(__name, __prop) \
`ifdef FPV_ON                      \
   `_ASSUME4(__name, __prop, `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST) \
`endif

// ASSUME_I_FPV - Assume a concurrent property during formal verification only
`define ASSUME_I_FPV(__name, __prop) \
`ifdef FPV_ON                        \
   `ASSUME_I(__name, __prop)         \
`endif

// COVER_FPV - Cover a concurrent property during formal verification
`define COVER_FPV(__name, __prop) \
`ifdef FPV_ON                     \
   `_COVER4(__name, __prop, `ASSERT_DEFAULT_CLK, `ASSERT_DEFAULT_RST) \
`endif

`endif // PRIM_ASSERT_SV
