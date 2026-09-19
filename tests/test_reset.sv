//=============================================================================
// Test: test_reset
// Description: Validates asynchronous and synchronous reset behavior. Verifies
//              that reset drives default values, that writes/reads during reset
//              are safely ignored, and that post-reset operation is normal.
//=============================================================================

task automatic run_test_reset();
    int errs;
    print_test_header("test_reset", "Verify reset sequence, default flags, and post-reset functionality.");

    // 1. Apply reset
    driver.reset_dut(5);
    scoreboard.reset_model();

    // 2. Check initial reset flags
    driver.idle(2);
    if (!dut.empty || dut.full || dut.count !== 0 || dut.overflow || dut.underflow) begin
        log_error("Reset test: Flags did not settle to default values post-reset!");
    end

    // 3. Attempt write and read WHILE in reset
    log_info("Applying stimulus while rst_n is held active-low...");
    @(negedge clk);
    driver.rst_n = 1'b0;
    driver.wr_en = 1'b1;
    driver.wr_data = 8'hDE;
    driver.rd_en = 1'b1;
    repeat (3) @(posedge clk);

    @(negedge clk);
    driver.wr_en = 1'b0;
    driver.rd_en = 1'b0;
    driver.rst_n = 1'b1; // Release reset
    log_info("Reset released.");
    driver.idle(3);

    // Verify FIFO is still empty and count is 0
    if (!dut.empty || dut.count !== 0) begin
        log_error("Reset test: Write during reset was erroneously accepted!");
    end

    // 4. Verify post-reset functionality with a valid write and read
    log_info("Testing valid post-reset write and read...");
    driver.write_single(8'h5A);
    driver.idle(2);

    begin
        logic [7:0] rdata;
        driver.read_single(rdata);
        if (rdata !== 8'h5A) begin
            log_error($sformatf("Post-reset read mismatch! Expected 0x5A, got 0x%02h", rdata));
        end
    end

    driver.idle(5);
    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_reset", errs);
endtask
