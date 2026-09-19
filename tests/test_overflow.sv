//=============================================================================
// Test: test_overflow
// Description: Validates overflow protection mechanism. Fills FIFO to capacity,
//              attempts illegal writes without reading, verifies that the overflow
//              error flag asserts, and proves that original data is NOT corrupted.
//=============================================================================

task automatic run_test_overflow();
    int errs;
    logic [7:0] rdata;
    print_test_header("test_overflow", "Attempt illegal writes to full FIFO, check overflow flag and data protection.");

    driver.reset_dut(3);
    scoreboard.reset_model();
    driver.idle(2);

    // 1. Fill FIFO to capacity with 16 known words
    log_info("Filling FIFO to capacity with 16 known words...");
    for (int i = 0; i < 16; i++) begin
        driver.drive_write(8'h30 + i[7:0]);
    end
    driver.drive_write_stop();
    driver.idle(2);

    if (!dut.full || dut.count !== 16) begin
        log_error("Failed to fill FIFO to capacity!");
    end

    // 2. Attempt 5 illegal writes to the full FIFO
    log_info("Attempting 5 illegal writes to FULL FIFO (overflow condition)...");
    for (int i = 0; i < 5; i++) begin
        @(negedge clk);
        driver.wr_en   = 1'b1;
        driver.wr_data = 8'hEE; // Illegal corrupting data
        driver.rd_en   = 1'b0;
        @(posedge clk);
        #1ps;
        if (dut.count !== 16) begin
            log_error($sformatf("Count changed on illegal write! count=%0d (exp 16)", dut.count));
        end
    end

    @(negedge clk);
    driver.wr_en   = 1'b0;
    driver.wr_data = '0;
    @(posedge clk);
    #1ps;

    // Verify overflow flag was asserted
    if (!dut.overflow) begin
        log_error("Overflow flag was NOT asserted after illegal writes to full FIFO!");
    end

    driver.idle(3);

    // 3. Read back all 16 original words to verify memory contents were NOT corrupted
    log_info("Reading back 16 words to verify stored data integrity...");
    for (int i = 0; i < 16; i++) begin
        driver.drive_read(rdata);
    end
    driver.drive_read_stop();
    driver.idle(3);

    if (!dut.empty || dut.count !== 0) begin
        log_error($sformatf("FIFO should be empty after reading all 16 items! count=%0d", dut.count));
    end

    driver.idle(5);
    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_overflow", errs);
endtask
