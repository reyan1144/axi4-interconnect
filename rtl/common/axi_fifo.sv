// Synchronous FIFO with DEPTH entries (any DEPTH >= 1).
// Same valid/ready naming as axi_handshake_fifo, but deeper.
module axi_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 4,
    parameter int CNT_WIDTH  = $clog2(DEPTH + 1)
) (
    input  logic                  clk,
    input  logic                  resetn,

    input  logic                  s_valid,
    output logic                  s_ready,
    input  logic [DATA_WIDTH-1:0] s_data,

    output logic                  m_valid,
    input  logic                  m_ready,
    output logic [DATA_WIDTH-1:0] m_data,

    output logic [CNT_WIDTH-1:0]  count
);

    localparam int PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem [DEPTH];
    logic [PTR_WIDTH-1:0]  wr_ptr, rd_ptr;

    logic push, pop;

    assign s_ready = (count < CNT_WIDTH'(DEPTH));
    assign m_valid = (count != '0);
    assign m_data  = mem[rd_ptr];

    assign push = s_valid && s_ready;
    assign pop  = m_valid && m_ready;

    function automatic logic [PTR_WIDTH-1:0] next_ptr(input logic [PTR_WIDTH-1:0] p);
        return (p == PTR_WIDTH'(DEPTH - 1)) ? '0 : p + 1'b1;
    endfunction

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            for (int i = 0; i < DEPTH; i++)
                mem[i] <= '0;
            wr_ptr <= '0;
            rd_ptr <= '0;
            count  <= '0;
        end else begin
            if (push) begin
                mem[wr_ptr] <= s_data;
                wr_ptr      <= next_ptr(wr_ptr);
            end

            if (pop)
                rd_ptr <= next_ptr(rd_ptr);

            if (push && !pop)      count <= count + 1'b1;
            else if (pop && !push) count <= count - 1'b1;
        end
    end

endmodule
