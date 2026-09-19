//=============================================================================
// File: test_base.sv
// Description: Base test utilities, common reporting banners, and helper tasks
//              used across all sync_fifo verification test cases.
//=============================================================================

`ifndef TEST_BASE_SV
`define TEST_BASE_SV

task automatic print_test_header(input string test_name, input string description);
    $display("\n================================================================================");
    $display("  STARTING TEST: %s", test_name);
    $display("  Description  : %s", description);
    $display("================================================================================");
endtask

task automatic print_test_footer(input string test_name, input int errors);
    $display("================================================================================");
    if (errors == 0) begin
        $display("=== TEST PASSED: %s ===", test_name);
    end else begin
        $display("=== TEST FAILED: %s (Detected %0d errors) ===", test_name, errors);
    end
    $display("================================================================================\n");
endtask

`endif // TEST_BASE_SV
