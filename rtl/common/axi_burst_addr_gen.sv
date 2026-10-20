// Generates the address of every beat in an AXI burst.
// load: capture AxADDR/AxLEN/AxSIZE/AxBURST, addr = first beat address.
// next: step to the following beat (ignored after the last beat).
// burst_error / cross_4k describe the burst on the load inputs, so a
// slave or interconnect can reject it before accepting the command.
module axi_burst_addr_gen #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  load,
    input  logic [ADDR_WIDTH-1:0] start_addr,
    input  logic [7:0]            len,        // beats - 1
    input  logic [2:0]            size,       // bytes per beat = 2**size
    input  logic [1:0]            burst,      // 00 FIXED, 01 INCR, 10 WRAP

    input  logic                  next,

    output logic [ADDR_WIDTH-1:0] addr,       // current beat address
    output logic [7:0]            beat,       // current beat number (0 = first)
    output logic                  active,     // a burst is in progress
    output logic                  last,       // current beat is the last one

    output logic                  burst_error, // illegal type, size or WRAP setup
    output logic                  cross_4k     // INCR burst crosses a 4KB boundary
);

    localparam logic [1:0] FIXED = 2'b00;
    localparam logic [1:0] INCR  = 2'b01;
    localparam logic [1:0] WRAP  = 2'b10;

    localparam int MAX_SIZE = $clog2(DATA_WIDTH / 8);

    // Captured burst
    logic [7:0]            len_r;
    logic [1:0]            burst_r;
    logic [ADDR_WIDTH-1:0] bytes_r;     // 2**size
    logic [ADDR_WIDTH-1:0] wrap_mask_r; // wrap window size - 1

    // Checks on the load inputs
    logic [ADDR_WIDTH-1:0] in_bytes, in_aligned, in_last_addr;
    logic                  wrap_len_ok;

    always_comb begin
        in_bytes     = ADDR_WIDTH'(1) << size;
        in_aligned   = start_addr & ~(in_bytes - 1'b1);
        in_last_addr = in_aligned + ADDR_WIDTH'(len) * in_bytes;

        wrap_len_ok = (len == 8'd1) || (len == 8'd3) ||
                      (len == 8'd7) || (len == 8'd15);

        burst_error = (burst == 2'b11) ||
                      (int'(size) > MAX_SIZE) ||
                      ((burst == WRAP) && (!wrap_len_ok || start_addr != in_aligned));

        cross_4k = (burst == INCR) &&
                   (start_addr[ADDR_WIDTH-1:12] != in_last_addr[ADDR_WIDTH-1:12]);
    end

    assign last = active && (beat == len_r);

    // Address of the following beat
    logic [ADDR_WIDTH-1:0] incr_addr, next_addr;

    always_comb begin
        // After the first beat every address is size-aligned
        incr_addr = (addr & ~(bytes_r - 1'b1)) + bytes_r;

        case (burst_r)
            FIXED:   next_addr = addr;
            WRAP:    next_addr = (addr & ~wrap_mask_r) | (incr_addr & wrap_mask_r);
            default: next_addr = incr_addr;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr        <= '0;
            beat        <= '0;
            active      <= 1'b0;
            len_r       <= '0;
            burst_r     <= INCR;
            bytes_r     <= ADDR_WIDTH'(1);
            wrap_mask_r <= '0;
        end else if (load) begin
            addr        <= start_addr;
            beat        <= '0;
            active      <= 1'b1;
            len_r       <= len;
            burst_r     <= burst;
            bytes_r     <= in_bytes;
            wrap_mask_r <= (in_bytes * (ADDR_WIDTH'(len) + 1'b1)) - 1'b1;
        end else if (next && active) begin
            if (last) begin
                active <= 1'b0;
            end else begin
                addr <= next_addr;
                beat <= beat + 1'b1;
            end
        end
    end

endmodule