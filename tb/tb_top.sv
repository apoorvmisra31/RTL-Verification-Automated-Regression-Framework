//=============================================================================
// Module: tb_top
// Description: Top-level verification testbench for sync_fifo. Instantiates DUT,
//              driver, monitor, scoreboard, assertions, clock generator,
//              plusarg dispatcher, and simulation watchdog timer.
//=============================================================================

`timescale 1ns / 1ps

import fifo_pkg::*;

module tb_top;

    `include "fifo_logging.svh"

    // Testbench Parameters
    localparam int DATA_WIDTH          = 8;
    localparam int DEPTH               = 16;
    localparam int ALMOST_FULL_THRESH  = 2;
    localparam int ALMOST_EMPTY_THRESH = 2;
    localparam int COUNT_WIDTH         = $clog2(DEPTH + 1);

    // Clock and Reset Signals
    logic clk;
    logic rst_n;

    // DUT Interface Signals
    logic                  wr_en;
    logic [DATA_WIDTH-1:0] wr_data;
    logic                  rd_en;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  full;
    logic                  empty;
    logic                  almost_full;
    logic                  almost_empty;
    logic                  overflow;
    logic                  underflow;
    logic [COUNT_WIDTH-1:0] count;

    // Runtime Control Variables
    string test_name;
    int    seed;
    int    dump_wave;
    int    total_test_errors;

    // 100MHz Clock Generation (10ns Period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    //-------------------------------------------------------------------------
    sync_fifo #(
        .DATA_WIDTH         (DATA_WIDTH),
        .DEPTH              (DEPTH),
        .ALMOST_FULL_THRESH (ALMOST_FULL_THRESH),
        .ALMOST_EMPTY_THRESH(ALMOST_EMPTY_THRESH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (wr_en),
        .wr_data     (wr_data),
        .rd_en       (rd_en),
        .rd_data     (rd_data),
        .full        (full),
        .empty       (empty),
        .almost_full (almost_full),
        .almost_empty(almost_empty),
        .overflow    (overflow),
        .underflow   (underflow),
        .count       (count)
    );

    //-------------------------------------------------------------------------
    // Verification Components Instantiation
    //-------------------------------------------------------------------------
    // Stimulus Driver
    fifo_driver #(.DATA_WIDTH(DATA_WIDTH)) driver (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (wr_en),
        .wr_data(wr_data),
        .rd_en  (rd_en),
        .rd_data(rd_data)
    );

    // Independent Scoreboard & Reference Model
    fifo_scoreboard #(
        .DATA_WIDTH         (DATA_WIDTH),
        .DEPTH              (DEPTH),
        .ALMOST_FULL_THRESH (ALMOST_FULL_THRESH),
        .ALMOST_EMPTY_THRESH(ALMOST_EMPTY_THRESH)
    ) scoreboard (
        .clk  (clk),
        .rst_n(rst_n)
    );

    // Protocol & Invariant Assertions
    fifo_assertions #(
        .DATA_WIDTH         (DATA_WIDTH),
        .DEPTH              (DEPTH),
        .ALMOST_FULL_THRESH (ALMOST_FULL_THRESH),
        .ALMOST_EMPTY_THRESH(ALMOST_EMPTY_THRESH)
    ) assertions (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (wr_en),
        .wr_data     (wr_data),
        .rd_en       (rd_en),
        .rd_data     (rd_data),
        .full        (full),
        .empty       (empty),
        .almost_full (almost_full),
        .almost_empty(almost_empty),
        .overflow    (overflow),
        .underflow   (underflow),
        .count       (count)
    );

    // Passive Monitor
    fifo_monitor #(
        .DATA_WIDTH         (DATA_WIDTH),
        .DEPTH              (DEPTH),
        .ALMOST_FULL_THRESH (ALMOST_FULL_THRESH),
        .ALMOST_EMPTY_THRESH(ALMOST_EMPTY_THRESH)
    ) monitor (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (wr_en),
        .wr_data     (wr_data),
        .rd_en       (rd_en),
        .rd_data     (rd_data),
        .full        (full),
        .empty       (empty),
        .almost_full (almost_full),
        .almost_empty(almost_empty),
        .overflow    (overflow),
        .underflow   (underflow),
        .count       (count)
    );

    //-------------------------------------------------------------------------
    // Include Test Sequences
    //-------------------------------------------------------------------------
    `include "test_base.sv"
    `include "test_reset.sv"
    `include "test_single_write_read.sv"
    `include "test_burst_write_read.sv"
    `include "test_fifo_full.sv"
    `include "test_fifo_empty.sv"
    `include "test_simultaneous_rw.sv"
    `include "test_overflow.sv"
    `include "test_underflow.sv"
    `include "test_almost_flags.sv"
    `include "test_random_traffic.sv"

    //-------------------------------------------------------------------------
    // Test Dispatcher
    //-------------------------------------------------------------------------
    task automatic dispatch_test(input string name, input int test_seed);
        if (name == "test_reset") begin
            run_test_reset();
        end else if (name == "test_single_write_read") begin
            run_test_single_write_read();
        end else if (name == "test_burst_write_read") begin
            run_test_burst_write_read();
        end else if (name == "test_fifo_full") begin
            run_test_fifo_full();
        end else if (name == "test_fifo_empty") begin
            run_test_fifo_empty();
        end else if (name == "test_simultaneous_rw") begin
            run_test_simultaneous_rw();
        end else if (name == "test_overflow") begin
            run_test_overflow();
        end else if (name == "test_underflow") begin
            run_test_underflow();
        end else if (name == "test_almost_flags") begin
            run_test_almost_flags();
        end else if (name == "test_random_traffic") begin
            run_test_random_traffic(test_seed);
        end else begin
            log_fatal($sformatf("Unknown test name '%s'", name));
            $fatal(1, "Test dispatch error");
        end
    endtask

    //-------------------------------------------------------------------------
    // Simulation Execution Thread
    //-------------------------------------------------------------------------
    initial begin
        // Parse plusargs
        if (!$value$plusargs("TESTNAME=%s", test_name)) begin
            test_name = "test_single_write_read";
        end
        if (!$value$plusargs("SEED=%d", seed)) begin
            seed = 42;
        end
        dump_wave = $test$plusargs("DUMP_WAVE");

        if (dump_wave) begin
            $display("[INFO]  Waveform dumping enabled: waves/%s.vcd", test_name);
            $dumpfile({"waves/", test_name, ".vcd"});
            $dumpvars(0, tb_top);
        end

        $display("--------------------------------------------------------------------------------");
        $display("  SYNC FIFO VERIFICATION ENVIRONMENT");
        $display("  Active Test : %s", test_name);
        $display("  Random Seed : %0d", seed);
        $display("--------------------------------------------------------------------------------");

        // Execute selected test
        dispatch_test(test_name, seed);

        // Final verification check
        total_test_errors = scoreboard.get_total_errors() + assertions.get_assertion_failures() + fifo_pkg::get_pkg_error_count();
        if (total_test_errors == 0) begin
            $display("[STATUS] All checks passed cleanly: Scoreboard errs=%0d, SVA fails=%0d, Logged errs=%0d.",
                     scoreboard.get_total_errors(), assertions.get_assertion_failures(), fifo_pkg::get_pkg_error_count());
            $finish(0);
        end else begin
            $fatal(1, $sformatf("Test '%s' failed with %0d error(s) [Scoreboard: %0d, SVA: %0d, Logged: %0d]",
                                test_name, total_test_errors,
                                scoreboard.get_total_errors(), assertions.get_assertion_failures(), fifo_pkg::get_pkg_error_count()));
        end
    end

    //-------------------------------------------------------------------------
    // Watchdog Timer
    //-------------------------------------------------------------------------
    initial begin
        #500_000; // 500 us timeout (50,000 clock cycles at 100MHz)
        $fatal(1, $sformatf("Simulation WATCHDOG TIMEOUT expired at %0t ns!", $time));
    end

endmodule
