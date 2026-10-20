// Combinational INCR-only 4KB boundary check. ADDR_WIDTH must be >= 12.
// Legal FIXED and WRAP bursts cannot cross 4KB (AxSIZE <= 7).
// This is NOT a general AXI legality checker.
module axi_4kb_check #(
    parameter int ADDR_WIDTH = 32
) (
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [7:0] len,
    input logic [2:0] size,
    input logic [1:0] burst,
    output logic cross_4k
);
    logic [15:0] bytes_per_beat, aligned_offset, end_exclusive;
    always_comb begin
        bytes_per_beat = 16'd1 << size;
        aligned_offset = {4'b0, addr[11:0]} & ~(bytes_per_beat - 16'd1);
        // Widen BEFORE adding one: LEN=255 means 256, not zero.
        end_exclusive = aligned_offset + (({8'b0, len} + 16'd1) << size);
        cross_4k = (burst == 2'b01) && (end_exclusive > 16'd4096);
    end
endmodule
