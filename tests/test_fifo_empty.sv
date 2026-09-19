//=============================================================================
// Test: test_fifo_empty
// Description: Validates empty flag behavior during transition from occupied
//              to drained state. Checks that empty asserts immediately upon
//              the final item read and remains stable.
//=============================================================================

task automatic run_test_fifo_empty();
    int errs;
    logic [7:0] rdata;
    print_test_header("test_fifo_empty", "Drain FIFO and verify empty flag timing and stability.");

    driver.reset_dut(3);
    scoreboard.reset_model();
    driver.idle(2);

    // Initial check: empty at start
    if (!dut.empty) begin
        log_error("FIFO not empty after reset!");
    end

    // Fill with 4 items
    driver.drive_write(8'hE1);
    driver.drive_write(8'hE2);
    driver.drive_write(8'hE3);
    driver.drive_write(8'hE4);
    driver.drive_write_stop();
    driver.idle(2);

    if (dut.empty || dut.count !== 4) begin
        log_error("FIFO state incorrect after 4 writes!");
    end

    // Drain 4 items
    driver.drive_read(rdata);
    driver.drive_read(rdata);
    driver.drive_read(rdata);
    driver.drive_read(rdata);
    driver.drive_read_stop();
    driver.idle(2);

    // Verify empty asserted
    if (!dut.empty || dut.count !== 0) begin
        log_error($sformatf("FIFO should be empty! empty=%0b, count=%0d", dut.empty, dut.count));
    end

    // Verify empty remains stable across idle cycles
    driver.idle(5);
    if (!dut.empty || dut.count !== 0) begin
        log_error("Empty flag became unstable during idle!");
    end

    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_fifo_empty", errs);
endtask
