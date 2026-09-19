//=============================================================================
// Module: fifo_monitor
// Description: Passive transaction monitor for sync_fifo. Samples DUT interface
//              signals on active clock edges and forwards observed transactions
//              and status flags to the independent scoreboard.
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

    // Connected to scoreboard via hierarchical reference or direct instance
    // Scoreboard instance handle will be resolved in tb_top

    // Internal flags to track expected error event pulses
    logic prev_overflow_event;
    logic prev_underflow_event;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_overflow_event  <= 1'b0;
            prev_underflow_event <= 1'b0;
        end else begin
            // An overflow event occurs when wr_en is high while full without reading
            prev_overflow_event  <= wr_en && full && !rd_en;
            // An underflow event occurs when rd_en is high while empty
            prev_underflow_event <= rd_en && empty;
        end
    end

endmodule
