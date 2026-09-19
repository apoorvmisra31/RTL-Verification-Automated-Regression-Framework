//=============================================================================
// Package: fifo_pkg
// Description: Shared package providing types, transaction structures, logging
//              utilities, and configuration for the sync_fifo testbench.
//=============================================================================

`timescale 1ns / 1ps

package fifo_pkg;

    // Transaction operation types
    typedef enum logic [1:0] {
        OP_IDLE  = 2'b00,
        OP_WRITE = 2'b01,
        OP_READ  = 2'b10,
        OP_RW    = 2'b11
    } op_type_e;

    // Packed transaction struct for stimulus and monitoring
    typedef struct packed {
        op_type_e op;
        logic [7:0] data;
        logic full_at_sample;
        logic empty_at_sample;
        logic overflow_at_sample;
        logic underflow_at_sample;
    } fifo_item_s;

    // Logging helpers with standardized prefix formatting
    function automatic void log_info(string msg);
        $display("[INFO]  [%0t ns] %s", $time, msg);
    endfunction

    function automatic void log_warn(string msg);
        $display("[WARN]  [%0t ns] %s", $time, msg);
    endfunction

    function automatic void log_error(string msg);
        $display("*** ERROR: [%0t ns] %s", $time, msg);
    endfunction

    function automatic void log_fatal(string msg);
        $display("*** FATAL: [%0t ns] %s", $time, msg);
    endfunction

endpackage
