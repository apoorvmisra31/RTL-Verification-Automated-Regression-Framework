//=============================================================================
// Test: test_underflow
// Description: Validates underflow protection mechanism. Attempts illegal reads
//              from an empty FIFO, verifies that underflow error flag asserts,
//              and confirms that subsequent valid transactions succeed.
//=============================================================================

task automatic run_test_underflow();
    int errs;
    logic [7:0] rdata;
    print_test_header("test_underflow", "Attempt illegal reads from empty FIFO, check underflow flag.");

    driver.reset_dut(3);
    scoreboard.reset_model();
    driver.idle(2);

    if (!dut.empty || dut.count !== 0) begin
        log_error("FIFO is not empty before underflow test!");
    end

    // 1. Attempt 5 illegal reads while empty
    log_info("Attempting 5 illegal reads on EMPTY FIFO (underflow condition)...");
    for (int i = 0; i < 5; i++) begin
        @(negedge clk);
        driver.rd_en = 1'b1;
        driver.wr_en = 1'b0;
        @(posedge clk);
        #1ps;
        if (dut.count !== 0 || !dut.empty) begin
            log_error($sformatf("Count/empty changed on illegal read! count=%0d, empty=%0b", dut.count, dut.empty));
        end
        // On iteration i >= 1, the previous illegal read must have asserted underflow
        if (i >= 1 && !dut.underflow) begin
            log_error($sformatf("Underflow flag was NOT asserted on cycle %0d of illegal read!", i));
        end
    end

    @(negedge clk);
    driver.rd_en = 1'b0;
    @(posedge clk);
    #1ps;

    // Verify underflow flag deasserts once illegal reads stop
    if (dut.underflow) begin
        log_error("Underflow flag failed to deassert after illegal read stopped!");
    end

    driver.idle(3);

    // 2. Verify subsequent valid write and read succeed
    log_info("Verifying normal operation recovery after underflow attempts...");
    driver.write_single(8'h7E);
    driver.idle(2);

    driver.read_single(rdata);
    driver.idle(2);

    if (rdata !== 8'h7E) begin
        log_error($sformatf("Recovery read mismatch! Expected 0x7E, got 0x%02h", rdata));
    end

    driver.idle(5);
    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_underflow", errs);
endtask
