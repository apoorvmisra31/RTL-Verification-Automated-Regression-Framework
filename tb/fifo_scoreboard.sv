//=============================================================================
// Module: fifo_scoreboard
// Description: Independent reference model and scoreboard for sync_fifo.
//              Maintains a golden reference queue, validates data ordering,
//              tracks expected occupancy, and verifies all status/error flags.
//=============================================================================

`timescale 1ns / 1ps

import fifo_pkg::*;

module fifo_scoreboard #(
    parameter int DATA_WIDTH          = 8,
    parameter int DEPTH               = 16,
    parameter int ALMOST_FULL_THRESH  = 2,
    parameter int ALMOST_EMPTY_THRESH = 2
) (
    input logic clk,
    input logic rst_n
);

    // Independent Golden Reference Model Queue
    logic [DATA_WIDTH-1:0] ref_queue[$];

    // Verification Accounting Counters
    int total_writes;
    int total_reads;
    int matched_reads;
    int mismatched_reads;
    int overflow_checks;
    int underflow_checks;
    int flag_errors;
    int total_state_checks;

    // Initialize counters
    initial begin
        total_writes        = 0;
        total_reads         = 0;
        matched_reads       = 0;
        mismatched_reads    = 0;
        overflow_checks     = 0;
        underflow_checks    = 0;
        flag_errors         = 0;
        total_state_checks  = 0;
    end

    // Task: Reset golden reference model
    task automatic reset_model();
        ref_queue.delete();
        log_info("Scoreboard: Golden reference queue reset.");
    endtask

    // Task: Push transaction into golden reference model
    task automatic write_sample(input logic [DATA_WIDTH-1:0] data);
        ref_queue.push_back(data);
        total_writes++;
    endtask

    // Task: Compare read data against golden reference queue head
    task automatic read_sample(input logic [DATA_WIDTH-1:0] actual_data);
        logic [DATA_WIDTH-1:0] expected_data;
        total_reads++;

        if (ref_queue.size() == 0) begin
            mismatched_reads++;
            log_error($sformatf("Scoreboard: Read occurred but Reference Queue is EMPTY! Actual data: 0x%02h", actual_data));
        end else begin
            expected_data = ref_queue.pop_front();
            if (actual_data === expected_data) begin
                matched_reads++;
            end else begin
                mismatched_reads++;
                log_error($sformatf("Scoreboard: Data MISMATCH! Expected: 0x%02h, Actual: 0x%02h (Ref Queue remaining: %0d)",
                                    expected_data, actual_data, ref_queue.size()));
            end
        end
    endtask

    // Task: Record and verify overflow handling
    task automatic note_overflow_event(input logic overflow_flag, input logic expected_overflow);
        overflow_checks++;
        if (overflow_flag !== expected_overflow) begin
            flag_errors++;
            log_error($sformatf("Scoreboard: Overflow flag mismatch! Expected: %0b, Got: %0b",
                                expected_overflow, overflow_flag));
        end
    endtask

    // Task: Record and verify underflow handling
    task automatic note_underflow_event(input logic underflow_flag, input logic expected_underflow);
        underflow_checks++;
        if (underflow_flag !== expected_underflow) begin
            flag_errors++;
            log_error($sformatf("Scoreboard: Underflow flag mismatch! Expected: %0b, Got: %0b",
                                expected_underflow, underflow_flag));
        end
    endtask

    // Task: Verify comprehensive FIFO state and flags against independent model
    task automatic check_state(
        input logic full,
        input logic empty,
        input logic almost_full,
        input logic almost_empty,
        input logic [$clog2(DEPTH+1)-1:0] count
    );
        int expected_size;
        logic exp_full;
        logic exp_empty;
        logic exp_almost_full;
        logic exp_almost_empty;

        total_state_checks++;
        expected_size    = ref_queue.size();
        exp_empty        = (expected_size == 0);
        exp_full         = (expected_size == DEPTH);
        exp_almost_full  = (expected_size >= (DEPTH - ALMOST_FULL_THRESH));
        exp_almost_empty = (expected_size <= ALMOST_EMPTY_THRESH) && (expected_size > 0);

        // Check occupancy count
        if (int'(count) !== expected_size) begin
            flag_errors++;
            log_error($sformatf("Scoreboard: Occupancy COUNT mismatch! Expected: %0d, Got: %0d",
                                expected_size, int'(count)));
        end

        // Check empty flag
        if (empty !== exp_empty) begin
            flag_errors++;
            log_error($sformatf("Scoreboard: EMPTY flag mismatch! Expected: %0b, Got: %0b (Count=%0d)",
                                exp_empty, empty, expected_size));
        end

        // Check full flag
        if (full !== exp_full) begin
            flag_errors++;
            log_error($sformatf("Scoreboard: FULL flag mismatch! Expected: %0b, Got: %0b (Count=%0d)",
                                exp_full, full, expected_size));
        end

        // Check almost full flag
        if (almost_full !== exp_almost_full) begin
            flag_errors++;
            log_error($sformatf("Scoreboard: ALMOST_FULL flag mismatch! Expected: %0b, Got: %0b (Count=%0d)",
                                exp_almost_full, almost_full, expected_size));
        end

        // Check almost empty flag
        if (almost_empty !== exp_almost_empty) begin
            flag_errors++;
            log_error($sformatf("Scoreboard: ALMOST_EMPTY flag mismatch! Expected: %0b, Got: %0b (Count=%0d)",
                                exp_almost_empty, almost_empty, expected_size));
        end
    endtask

    // Function: Return total cumulative errors detected by the scoreboard
    function automatic int get_total_errors();
        return mismatched_reads + flag_errors;
    endfunction

    // Function: Return number of items remaining in golden reference queue
    function automatic int get_pending_items();
        return ref_queue.size();
    endfunction

    // Task: Print final scoreboard report
    task automatic report_summary(output int total_errs);
        total_errs = get_total_errors();
        if (ref_queue.size() != 0) begin
            log_warn($sformatf("Scoreboard: %0d unread items left in reference queue at end of test.", ref_queue.size()));
        end

        $display("--------------------------------------------------");
        $display("          SCOREBOARD VERIFICATION REPORT          ");
        $display("--------------------------------------------------");
        $display("  Total Writes Monitored  : %0d", total_writes);
        $display("  Total Reads Monitored   : %0d", total_reads);
        $display("  Matched Data Reads      : %0d", matched_reads);
        $display("  Mismatched Data Reads   : %0d", mismatched_reads);
        $display("  State/Flag Checks       : %0d", total_state_checks);
        $display("  State/Flag Errors       : %0d", flag_errors);
        $display("  Items Remaining in FIFO : %0d", ref_queue.size());
        $display("  Total Scoreboard Errors : %0d", total_errs);
        $display("--------------------------------------------------");
    endtask

endmodule
