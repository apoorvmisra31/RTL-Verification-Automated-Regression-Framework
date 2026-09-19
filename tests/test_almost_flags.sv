//=============================================================================
// Test: test_almost_flags
// Description: Step-by-step verification of watermark threshold status flags
//              (almost_empty and almost_full) during incremental fill and drain.
//=============================================================================

task automatic run_test_almost_flags();
    int errs;
    logic [7:0] rdata;
    print_test_header("test_almost_flags", "Validate almost_empty and almost_full thresholds during fill/drain.");

    driver.reset_dut(3);
    scoreboard.reset_model();
    driver.idle(2);

    // Initial check: count=0
    if (dut.almost_empty || dut.almost_full) begin
        log_error("almost flags asserted when count=0!");
    end

    // Step 1: Write 1 item -> count=1. almost_empty should assert.
    driver.write_single(8'h01);
    driver.idle(1);
    if (!dut.almost_empty) begin
        log_error("almost_empty did not assert at count=1!");
    end

    // Step 2: Write 2nd item -> count=2. almost_empty should stay asserted.
    driver.write_single(8'h02);
    driver.idle(1);
    if (!dut.almost_empty) begin
        log_error("almost_empty did not assert at count=2!");
    end

    // Step 3: Write 3rd item -> count=3. almost_empty should DEASSERT.
    driver.write_single(8'h03);
    driver.idle(1);
    if (dut.almost_empty) begin
        log_error("almost_empty remained asserted at count=3!");
    end

    // Step 4: Write items 4 through 13. almost_full should be 0.
    for (int i = 4; i <= 13; i++) begin
        driver.write_single(8'h00 + i[7:0]);
    end
    driver.idle(1);

    if (dut.almost_full) begin
        log_error("almost_full prematurely asserted at count=13!");
    end

    // Step 5: Write item 14 -> count=14 (DEPTH - 2). almost_full MUST assert!
    driver.write_single(8'h0E);
    driver.idle(1);
    if (!dut.almost_full) begin
        log_error("almost_full did not assert at count=14!");
    end

    // Step 6: Write item 15 -> count=15. almost_full stays asserted.
    driver.write_single(8'h0F);
    driver.idle(1);
    if (!dut.almost_full) begin
        log_error("almost_full not asserted at count=15!");
    end

    // Step 7: Write item 16 -> count=16. full=1 and almost_full=1.
    driver.write_single(8'h10);
    driver.idle(1);
    if (!dut.full || !dut.almost_full) begin
        log_error($sformatf("Full state incorrect at count=16! full=%0b, almost_full=%0b", dut.full, dut.almost_full));
    end

    // Step 8: Read 3 items -> count goes from 16 -> 13. almost_full should DEASSERT at count=13.
    driver.read_single(rdata);
    driver.read_single(rdata);
    driver.read_single(rdata);
    driver.idle(1);

    if (dut.count !== 13 || dut.almost_full) begin
        log_error($sformatf("almost_full did not deassert at count=13! count=%0d, almost_full=%0b", dut.count, dut.almost_full));
    end

    // Step 9: Read down to count=2. almost_empty should RE-ASSERT!
    while (dut.count > 2) begin
        driver.read_single(rdata);
    end
    driver.idle(1);

    if (!dut.almost_empty) begin
        log_error("almost_empty did not assert after draining down to count=2!");
    end

    // Step 10: Drain remaining 2 items to empty
    driver.read_single(rdata);
    driver.read_single(rdata);
    driver.idle(2);

    if (!dut.empty || dut.almost_empty) begin
        log_error($sformatf("Empty state incorrect at count=0! empty=%0b, almost_empty=%0b", dut.empty, dut.almost_empty));
    end

    driver.idle(5);
    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_almost_flags", errs);
endtask
