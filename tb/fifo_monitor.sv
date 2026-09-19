//=============================================================================
// Module: fifo_monitor
// Description: Passive transaction monitor for sync_fifo.
//              Observes DUT interface signals on active clock edges, qualifies
//              valid write and read transactions, and actively forwards observed
//              transactions and status checks to the independent scoreboard.
//
// Data Path Architecture:
// Driver -> DUT -> Monitor -> Scoreboard -> PASS/FAIL
//=============================================================================

`timescale 1ns / 1ps

import fifo_pkg::*;

module fifo_monitor #(
    parameter int DATA_WIDTH          = 8,
    parameter int DEPTH               = 16,
    parameter int ALMOST_FULL_THRESH  = 2,
    parameter int ALMOST_EMPTY_THRESH = 2
) (
    input logic                  clk,
    input logic                  rst_n,
    input logic                  wr_en,
    input logic [DATA_WIDTH-1:0] wr_data,
    input logic                  rd_en,
    input logic [DATA_WIDTH-1:0] rd_data,
    input logic                  full,
    input logic                  empty,
    input logic                  almost_full,
    input logic                  almost_empty,
    input logic                  overflow,
    input logic                  underflow,
    input logic [$clog2(DEPTH+1)-1:0] count
);

    // Monitoring transaction counters
    int monitored_writes;
    int monitored_reads;

    // Sample state prior to active clock edge for valid write/read qualification
    logic full_sample;
    logic empty_sample;

    initial begin
        monitored_writes = 0;
        monitored_reads  = 0;
        full_sample      = 1'b0;
        empty_sample     = 1'b1;
    end

    // Pre-edge boundary sampling
    always @(posedge clk) begin
        full_sample  <= full;
        empty_sample <= empty;
    end

    // Active sampling and forwarding to scoreboard
    always @(posedge clk) begin
        if (rst_n) begin
            #1ps; // Settle post-clock-edge non-blocking register updates

            // 1. Monitor accepted write transaction
            if (wr_en && (!full_sample || rd_en)) begin
                monitored_writes++;
                tb_top.scoreboard.write_sample(wr_data);
            end

            // 2. Monitor valid read transaction
            if (rd_en && !empty_sample) begin
                monitored_reads++;
                tb_top.scoreboard.read_sample(rd_data);
            end

            // 3. Monitor and forward comprehensive status flags to scoreboard
            tb_top.scoreboard.check_state(full, empty, almost_full, almost_empty, count);
        end
    end

    function automatic int get_monitored_writes();
        return monitored_writes;
    endfunction

    function automatic int get_monitored_reads();
        return monitored_reads;
    endfunction

    task automatic report_monitor();
        $display("--------------------------------------------------");
        $display("           MONITOR VERIFICATION REPORT            ");
        $display("--------------------------------------------------");
        $display("  Total Monitored Writes  : %0d", monitored_writes);
        $display("  Total Monitored Reads   : %0d", monitored_reads);
        $display("--------------------------------------------------");
    endtask

endmodule
