//=============================================================================
// Package: fifo_pkg
// Description: Shared package providing types, transaction structures, logging
//              utilities, error accounting, and configuration for sync_fifo TB.
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

    // Global package-level error counter to ensure any logged error propagates
    int pkg_error_count = 0;

    // Logging helpers with standardized prefix formatting
    task automatic log_info(string msg);
        $display("[INFO]  [%0t ns] %s", $time, msg);
    endtask

    task automatic log_warn(string msg);
        $display("[WARN]  [%0t ns] %s", $time, msg);
    endtask

    task automatic log_error(string msg);
        pkg_error_count++;
        $display("*** ERROR: [%0t ns] %s", $time, msg);
    endtask

    task automatic log_fatal(string msg);
        pkg_error_count++;
        $display("*** FATAL: [%0t ns] %s", $time, msg);
    endtask

    function automatic int get_pkg_error_count();
        return pkg_error_count;
    endfunction

    function automatic void reset_pkg_error_count();
        pkg_error_count = 0;
    endfunction

endpackage
