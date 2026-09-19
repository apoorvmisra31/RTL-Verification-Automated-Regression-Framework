//=============================================================================
// Module: fifo_driver
// Description: Active stimulus driver for sync_fifo testbench. Provides clean,
//              cycle-accurate tasks for reset, single/burst writes, single/burst
//              reads, simultaneous transactions, and idle insertion.
//=============================================================================

`timescale 1ns / 1ps

import fifo_pkg::*;

module fifo_driver #(
    parameter int DATA_WIDTH = 8
) (
    input  logic                  clk,
    output logic                  rst_n,
    output logic                  wr_en,
    output logic [DATA_WIDTH-1:0] wr_data,
    output logic                  rd_en,
    input  logic [DATA_WIDTH-1:0] rd_data
);

    `include "fifo_logging.svh"

    // Initial driver pin states (reset active at power-on)
    initial begin
        rst_n   = 1'b0;
        wr_en   = 1'b0;
        wr_data = '0;
        rd_en   = 1'b0;
    end

    // Task: Apply synchronous/asynchronous reset
    task automatic reset_dut(input int cycles = 3);
        log_info($sformatf("Driver: Applying reset for %0d cycles...", cycles));
        @(negedge clk);
        rst_n   = 1'b0;
        wr_en   = 1'b0;
        wr_data = '0;
        rd_en   = 1'b0;

        repeat (cycles) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        log_info("Driver: Reset released.");
        @(posedge clk);
    endtask

    // Task: Drive write line active for 1 cycle (chainable for back-to-back bursts)
    task automatic drive_write(input logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        wr_en   = 1'b1;
        wr_data = data;
        @(posedge clk);
    endtask

    // Task: Deassert write line
    task automatic drive_write_stop();
        @(negedge clk);
        wr_en   = 1'b0;
        wr_data = '0;
    endtask

    // Task: Drive read line active for 1 cycle (chainable for back-to-back bursts)
    task automatic drive_read(output logic [DATA_WIDTH-1:0] data);
        @(negedge clk);
        rd_en = 1'b1;
        @(posedge clk);
        #1ps;
        data = rd_data;
    endtask

    // Task: Deassert read line
    task automatic drive_read_stop();
        @(negedge clk);
        rd_en = 1'b0;
    endtask

    // Task: Write a single data word into FIFO
    task automatic write_single(input logic [DATA_WIDTH-1:0] data);
        drive_write(data);
        drive_write_stop();
    endtask

    // Task: Read a single data word from FIFO
    task automatic read_single(output logic [DATA_WIDTH-1:0] data);
        drive_read(data);
        drive_read_stop();
    endtask

    // Task: Simultaneously perform a write and a read in the same cycle
    task automatic simultaneous_rw(
        input  logic [DATA_WIDTH-1:0] wdata,
        output logic [DATA_WIDTH-1:0] rdata
    );
        @(negedge clk);
        wr_en   = 1'b1;
        wr_data = wdata;
        rd_en   = 1'b1;
        @(posedge clk);
        #1ps;
        rdata = rd_data;
        @(negedge clk);
        wr_en   = 1'b0;
        wr_data = '0;
        rd_en   = 1'b0;
    endtask

    // Task: Idle for specified clock cycles
    task automatic idle(input int cycles = 1);
        @(negedge clk);
        wr_en   = 1'b0;
        wr_data = '0;
        rd_en   = 1'b0;
        repeat (cycles) @(posedge clk);
    endtask

endmodule
