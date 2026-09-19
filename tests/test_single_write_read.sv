//=============================================================================
// Test: test_single_write_read
// Description: Directed test executing a single word write followed by a
//              single word read. Validates 1-item latency and empty transition.
//=============================================================================

task automatic run_test_single_write_read();
    int errs;
    logic [7:0] rdata;
    print_test_header("test_single_write_read", "Single word write followed by single word read.");

    driver.reset_dut(3);
    scoreboard.reset_model();
    driver.idle(2);

    // Single write
    log_info("Writing 8'hA5...");
    driver.write_single(8'hA5);
    driver.idle(2);

    // Verify empty transitioned to 0
    if (dut.empty !== 1'b0 || dut.count !== 1) begin
        log_error($sformatf("After write: empty=%0b (exp 0), count=%0d (exp 1)", dut.empty, dut.count));
    end

    // Single read
    log_info("Reading single item...");
    driver.read_single(rdata);
    driver.idle(2);

    // Verify empty returned to 1
    if (dut.empty !== 1'b1 || dut.count !== 0) begin
        log_error($sformatf("After read: empty=%0b (exp 1), count=%0d (exp 0)", dut.empty, dut.count));
    end

    driver.idle(5);
    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_single_write_read", errs);
endtask
