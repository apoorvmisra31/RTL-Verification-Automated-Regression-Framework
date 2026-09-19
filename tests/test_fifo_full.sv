//=============================================================================
// Test: test_fifo_full
// Description: Fills the FIFO to maximum capacity (DEPTH=16). Verifies that
//              full and almost_full flags assert, and that reading one item
//              clears the full flag immediately.
//=============================================================================

task automatic run_test_fifo_full();
    int errs;
    logic [7:0] rdata;
    print_test_header("test_fifo_full", "Fill FIFO to capacity, check full flag, and verify recovery.");

    driver.reset_dut(3);
    scoreboard.reset_model();
    driver.idle(2);

    // Burst write 16 elements
    log_info("Driver: Writing 16 elements back-to-back to reach capacity...");
    for (int i = 0; i < 16; i++) begin
        driver.drive_write(8'hC0 + i[7:0]);
    end
    driver.drive_write_stop();
    driver.idle(2);

    // Verify FULL condition
    if (dut.full !== 1'b1) begin
        log_error($sformatf("FIFO should be FULL, but full=%0b (count=%0d)", dut.full, dut.count));
    end
    if (dut.almost_full !== 1'b1) begin
        log_error("almost_full should be asserted when full!");
    end
    if (dut.empty !== 1'b0) begin
        log_error("empty should be 0 when full!");
    end

    // Read 1 item
    log_info("Reading 1 item from full FIFO to test flag deassertion...");
    driver.read_single(rdata);
    driver.idle(2);

    // Verify FULL deasserts
    if (dut.full !== 1'b0) begin
        log_error($sformatf("FIFO full flag did not deassert after reading 1 item! (count=%0d)", dut.count));
    end

    // Read remaining 15 items
    log_info("Reading remaining 15 items back-to-back...");
    for (int i = 0; i < 15; i++) begin
        driver.drive_read(rdata);
    end
    driver.drive_read_stop();
    driver.idle(3);

    if (dut.empty !== 1'b1 || dut.count !== 0) begin
        log_error($sformatf("FIFO should be empty after draining! empty=%0b, count=%0d", dut.empty, dut.count));
    end

    driver.idle(5);
    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_fifo_full", errs);
endtask
