//=============================================================================
// Test: test_burst_write_read
// Description: Directed test executing back-to-back burst writes of 8 words,
//              followed by back-to-back burst reads. Verifies FIFO data ordering.
//=============================================================================

task automatic run_test_burst_write_read();
    int errs;
    logic [7:0] wburst[8];
    logic [7:0] rdata;
    print_test_header("test_burst_write_read", "Burst write of 8 words followed by burst read.");

    driver.reset_dut(3);
    scoreboard.reset_model();
    driver.idle(2);

    // Populate test payload
    wburst[0] = 8'h11;
    wburst[1] = 8'h22;
    wburst[2] = 8'h33;
    wburst[3] = 8'h44;
    wburst[4] = 8'h55;
    wburst[5] = 8'h66;
    wburst[6] = 8'h77;
    wburst[7] = 8'h88;

    // Burst write (back-to-back)
    log_info("Driver: Starting back-to-back write burst of 8 items...");
    for (int i = 0; i < 8; i++) begin
        driver.drive_write(wburst[i]);
    end
    driver.drive_write_stop();
    driver.idle(3);

    // Check intermediate fill level
    if (dut.count !== 8) begin
        log_error($sformatf("After burst write: count=%0d (exp 8)", dut.count));
    end

    // Burst read (back-to-back)
    log_info("Driver: Starting back-to-back read burst of 8 items...");
    for (int i = 0; i < 8; i++) begin
        driver.drive_read(rdata);
    end
    driver.drive_read_stop();
    driver.idle(3);

    // Check intermediate fill level
    if (dut.count !== 0 || !dut.empty) begin
        log_error($sformatf("After burst read: count=%0d (exp 0), empty=%0b (exp 1)", dut.count, dut.empty));
    end

    driver.idle(5);
    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_burst_write_read", errs);
endtask
