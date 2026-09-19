//=============================================================================
// Module: fifo_assertions
// Description: SystemVerilog Assertions (SVA) for sync_fifo.
//              Implements genuine SystemVerilog Immediate Assertions evaluated
//              at clock boundaries to enforce protocol rules, safety invariants,
//              and watermark flag validity.
//
// Note on Simulator Capabilities:
// - Open-source Icarus Verilog (-g2012) supports SystemVerilog Immediate
//   Assertions (`assert (...) else ...`), which are fully implemented here.
// - Concurrent assertions with temporal sequence expressions (`assert property`)
//   are an invalid module item in Icarus Verilog and are documented as a
//   toolchain limitation in docs/verification_plan.md.
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

    // Pipeline registers to evaluate multi-cycle protocol responses
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
    // SystemVerilog Immediate Assertions (Clock-Synchronous Invariants)
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        #1ps; // Sample settled values post clock-edge

        if (!rst_n) begin
            // 1. Reset Invariant: All status flags must settle to default values
            A_RESET_FLAGS: assert (empty === 1'b1 && full === 1'b0 && count === '0)
                else begin
                    assertion_failures++;
                    $error("*** ASSERTION FAILED [A_RESET_FLAGS]: empty=%0b (exp 1), full=%0b (exp 0), count=%0d (exp 0)",
                           empty, full, count);
                end

            A_RESET_ERROR_FLAGS: assert (overflow === 1'b0 && underflow === 1'b0)
                else begin
                    assertion_failures++;
                    $error("*** ASSERTION FAILED [A_RESET_ERROR_FLAGS]: overflow=%0b, underflow=%0b (both exp 0)",
                           overflow, underflow);
                end
        end else begin
            // 2. Mutual Exclusion: FIFO cannot be simultaneously full and empty
            A_MUTEX_FULL_EMPTY: assert (!(full && empty))
                else begin
                    assertion_failures++;
                    $error("*** ASSERTION FAILED [A_MUTEX_FULL_EMPTY]: full and empty are BOTH asserted simultaneously at count=%0d", count);
                end

            // 3. Occupancy Upper Bound: count can never exceed configured DEPTH
            A_COUNT_LIMIT: assert (int'(count) <= DEPTH)
                else begin
                    assertion_failures++;
                    $error("*** ASSERTION FAILED [A_COUNT_LIMIT]: count=%0d exceeds configured DEPTH=%0d", count, DEPTH);
                end

            // 4. Full Flag Invariant: full must match (count == DEPTH)
            A_FULL_FLAG_INVARIANT: assert (full === (int'(count) == DEPTH))
                else begin
                    assertion_failures++;
                    $error("*** ASSERTION FAILED [A_FULL_FLAG_INVARIANT]: full=%0b but count=%0d (DEPTH=%0d)", full, count, DEPTH);
                end

            // 5. Empty Flag Invariant: empty must match (count == 0)
            A_EMPTY_FLAG_INVARIANT: assert (empty === (int'(count) == 0))
                else begin
                    assertion_failures++;
                    $error("*** ASSERTION FAILED [A_EMPTY_FLAG_INVARIANT]: empty=%0b but count=%0d", empty, count);
                end

            // 6. Almost Full Rule: almost_full must assert when count >= DEPTH - ALMOST_FULL_THRESH
            A_ALMOST_FULL_RULE: assert (almost_full === (int'(count) >= (DEPTH - ALMOST_FULL_THRESH)))
                else begin
                    assertion_failures++;
                    $error("*** ASSERTION FAILED [A_ALMOST_FULL_RULE]: almost_full=%0b with count=%0d (Threshold=%0d)",
                           almost_full, count, DEPTH - ALMOST_FULL_THRESH);
                end

            // 7. Almost Empty Rule: almost_empty must assert when count <= ALMOST_EMPTY_THRESH && count > 0
            A_ALMOST_EMPTY_RULE: assert (almost_empty === ((int'(count) <= ALMOST_EMPTY_THRESH) && (int'(count) > 0)))
                else begin
                    assertion_failures++;
                    $error("*** ASSERTION FAILED [A_ALMOST_EMPTY_RULE]: almost_empty=%0b with count=%0d (Threshold=%0d)",
                           almost_empty, count, ALMOST_EMPTY_THRESH);
                end

            // 8. Overflow Protocol Assertion:
            // If illegal write was attempted on previous cycle (wr_en && full && !rd_en), overflow must pulse
            if (wr_en_d1 && full_d1 && !rd_en_d1) begin
                A_OVERFLOW_PROTOCOL: assert (overflow === 1'b1)
                    else begin
                        assertion_failures++;
                        $error("*** ASSERTION FAILED [A_OVERFLOW_PROTOCOL]: overflow was not asserted following illegal write to full FIFO");
                    end
            end

            // 9. Underflow Protocol Assertion:
            // If illegal read was attempted on previous cycle (rd_en && empty), underflow must pulse
            if (rd_en_d1 && empty_d1) begin
                A_UNDERFLOW_PROTOCOL: assert (underflow === 1'b1)
                    else begin
                        assertion_failures++;
                        $error("*** ASSERTION FAILED [A_UNDERFLOW_PROTOCOL]: underflow was not asserted following illegal read to empty FIFO");
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
