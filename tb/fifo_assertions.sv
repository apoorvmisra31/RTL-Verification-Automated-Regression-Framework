//=============================================================================
// Module: fifo_assertions
// Description: SystemVerilog verification assertions for sync_fifo.
//              Enforces protocol rules, safety invariants, and flag validity
//              at every clock edge.
//=============================================================================

`timescale 1ns / 1ps

import fifo_pkg::*;

module fifo_assertions #(
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

    int assertion_failures;

    initial begin
        assertion_failures = 0;
    end

    // Pipeline registers to check multi-cycle protocol responses
    logic wr_en_d1, rd_en_d1, full_d1, empty_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_en_d1 <= 1'b0;
            rd_en_d1 <= 1'b0;
            full_d1  <= 1'b0;
            empty_d1 <= 1'b1;
        end else begin
            wr_en_d1 <= wr_en;
            rd_en_d1 <= rd_en;
            full_d1  <= full;
            empty_d1 <= empty;
        end
    end

    //-------------------------------------------------------------------------
    // Procedural Safety Invariant Assertions
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        #1ps; // Sample post-clock-edge settled values
        if (!rst_n) begin
            // 1. Reset State Verification
            if (empty !== 1'b1 || full !== 1'b0 || count !== '0) begin
                assertion_failures++;
                log_error($sformatf("A_RESET_STATE failed: empty=%0b (exp 1), full=%0b (exp 0), count=%0d (exp 0)",
                                    empty, full, count));
            end
            if (overflow !== 1'b0 || underflow !== 1'b0) begin
                assertion_failures++;
                log_error($sformatf("A_RESET_ERROR_FLAGS failed: overflow=%0b, underflow=%0b (both exp 0)",
                                    overflow, underflow));
            end
        end else begin
            // 2. Mutual Exclusion: FIFO cannot be simultaneously full and empty
            if (full && empty) begin
                assertion_failures++;
                log_error($sformatf("A_MUTEX_FULL_EMPTY failed: full and empty are BOTH asserted simultaneously at count=%0d", count));
            end

            // 3. Occupancy Upper Bound: count cannot exceed maximum DEPTH
            if (int'(count) > DEPTH) begin
                assertion_failures++;
                log_error($sformatf("A_COUNT_LIMIT failed: count=%0d exceeds configured DEPTH=%0d", count, DEPTH));
            end

            // 4. Full Flag Invariant: full must match (count == DEPTH)
            if (full !== (int'(count) == DEPTH)) begin
                assertion_failures++;
                log_error($sformatf("A_FULL_FLAG_INVARIANT failed: full=%0b but count=%0d (DEPTH=%0d)", full, count, DEPTH));
            end

            // 5. Empty Flag Invariant: empty must match (count == 0)
            if (empty !== (int'(count) == 0)) begin
                assertion_failures++;
                log_error($sformatf("A_EMPTY_FLAG_INVARIANT failed: empty=%0b but count=%0d", empty, count));
            end

            // 6. Almost Full Rule: almost_full must assert when count >= DEPTH - ALMOST_FULL_THRESH
            if (almost_full !== (int'(count) >= (DEPTH - ALMOST_FULL_THRESH))) begin
                assertion_failures++;
                log_error($sformatf("A_ALMOST_FULL_RULE failed: almost_full=%0b with count=%0d (Threshold=%0d)",
                                    almost_full, count, DEPTH - ALMOST_FULL_THRESH));
            end

            // 7. Almost Empty Rule: almost_empty must assert when count <= ALMOST_EMPTY_THRESH && !empty
            if (almost_empty !== ((int'(count) <= ALMOST_EMPTY_THRESH) && (int'(count) > 0))) begin
                assertion_failures++;
                log_error($sformatf("A_ALMOST_EMPTY_RULE failed: almost_empty=%0b with count=%0d (Threshold=%0d)",
                                    almost_empty, count, ALMOST_EMPTY_THRESH));
            end

            // 8. Overflow Protocol Assertion:
            // If illegal write was attempted on previous cycle (wr_en && full && !rd_en), overflow must pulse
            if (wr_en_d1 && full_d1 && !rd_en_d1) begin
                if (overflow !== 1'b1) begin
                    assertion_failures++;
                    log_error("A_OVERFLOW_PROTOCOL failed: overflow was not asserted following illegal write to full FIFO");
                end
            end

            // 9. Underflow Protocol Assertion:
            // If illegal read was attempted on previous cycle (rd_en && empty), underflow must pulse
            if (rd_en_d1 && empty_d1) begin
                if (underflow !== 1'b1) begin
                    assertion_failures++;
                    log_error("A_UNDERFLOW_PROTOCOL failed: underflow was not asserted following illegal read to empty FIFO");
                end
            end
        end
    end

    function automatic int get_assertion_failures();
        return assertion_failures;
    endfunction

    task automatic report_assertions(output int total_fails);
        total_fails = assertion_failures;
        $display("--------------------------------------------------");
        $display("          ASSERTIONS VERIFICATION REPORT          ");
        $display("--------------------------------------------------");
        $display("  Total Assertion Failures: %0d", total_fails);
        $display("--------------------------------------------------");
    endtask

endmodule
