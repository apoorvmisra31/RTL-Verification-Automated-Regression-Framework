//=============================================================================
// Module: sync_fifo
// Description: Parameterized Synchronous FIFO with status flags, threshold
//              watermarks, overflow/underflow protection, and simultaneous
//              read/write resolution.
// Includes compile-time macros for controlled defect injection verification.
//=============================================================================

`timescale 1ns / 1ps

module sync_fifo #(
    parameter int DATA_WIDTH         = 8,
    parameter int DEPTH              = 16,
    parameter int ALMOST_FULL_THRESH = 2,
    parameter int ALMOST_EMPTY_THRESH= 2
) (
    input  logic                  clk,
    input  logic                  rst_n,
    
    // Write Interface
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    
    // Read Interface
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    
    // Status Flags
    output logic                  full,
    output logic                  empty,
    output logic                  almost_full,
    output logic                  almost_empty,
    
    // Error Flags (pulse high on illegal transaction attempt)
    output logic                  overflow,
    output logic                  underflow,
    
    // Occupancy Count
    output logic [$clog2(DEPTH+1)-1:0] count
);

    // Derived parameter for pointer width
    localparam int ADDR_WIDTH  = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);

    // Storage memory
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Pointers and internal state (initialized to default reset values)
    logic [ADDR_WIDTH-1:0] wr_ptr = '0;
    logic [ADDR_WIDTH-1:0] rd_ptr = '0;
    logic [COUNT_WIDTH-1:0] count_reg = '0;

    // Internal operation qualifier signals
    logic do_write;
    logic do_read;
    logic overflow_event;
    logic underflow_event;

    //-------------------------------------------------------------------------
    // Operational Condition Qualification
    //-------------------------------------------------------------------------
`ifdef BUG_INJECT_OVERFLOW
    // BUG INJECTION: Disables overflow write protection.
    assign do_write        = wr_en;
    assign overflow_event  = 1'b0;
`else
    assign do_write        = wr_en && (!full || rd_en);
    assign overflow_event  = wr_en && full && !rd_en;
`endif

    assign do_read         = rd_en && !empty;

`ifdef BUG_INJECT_UNDERFLOW_FLAG
    // BUG INJECTION: Masks underflow flag generation
    assign underflow_event = 1'b0;
`else
    assign underflow_event = rd_en && empty;
`endif

    //-------------------------------------------------------------------------
    // Memory Write & Read Logic
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr    <= '0;
            rd_ptr    <= '0;
            rd_data   <= '0;
`ifdef BUG_INJECT_RESET_NEGLECT
            // BUG INJECTION: Reset fails to clear error flags
`else
            overflow  <= 1'b0;
            underflow <= 1'b0;
`endif
        end else begin
            // Update error flags
            overflow  <= overflow_event;
            underflow <= underflow_event;

            // Handle Memory Write
            if (do_write) begin
                mem[wr_ptr] <= wr_data;
                if (wr_ptr == ADDR_WIDTH'(DEPTH - 1))
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            // Handle Memory Read
            if (do_read) begin
                rd_data <= mem[rd_ptr];
                if (rd_ptr == ADDR_WIDTH'(DEPTH - 1))
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Occupancy Counter Management
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_reg <= '0;
        end else begin
            case ({do_write, do_read})
                2'b10: begin
                    count_reg <= count_reg + 1'b1;
                end
                2'b01: begin
                    count_reg <= count_reg - 1'b1;
                end
                2'b11: begin
`ifdef BUG_INJECT_COUNT_SIMULTANEOUS
                    if (count_reg == COUNT_WIDTH'(DEPTH))
                        count_reg <= count_reg + 1'b1;
                    else
                        count_reg <= count_reg;
`else
                    count_reg <= count_reg;
`endif
                end
                default: begin
                    count_reg <= count_reg;
                end
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Status Flag Assignments
    //-------------------------------------------------------------------------
    assign count = count_reg;
    assign empty = (count_reg == '0);
    assign full  = (count_reg == COUNT_WIDTH'(DEPTH));

`ifdef BUG_INJECT_ALMOST_FULL
    assign almost_full = (count_reg < COUNT_WIDTH'(DEPTH - ALMOST_FULL_THRESH));
`else
    assign almost_full = (count_reg >= COUNT_WIDTH'(DEPTH - ALMOST_FULL_THRESH));
`endif

    assign almost_empty = (count_reg <= COUNT_WIDTH'(ALMOST_EMPTY_THRESH)) && (count_reg > '0);

endmodule
