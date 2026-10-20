// Counts in-flight write and read transactions for ONE master.
// A write is in flight from AW handshake until B handshake.
// A read is in flight from AR handshake until the last R beat (RLAST).
// wr_allow / rd_allow go low when the limit is reached, so the crossbar
// can hold off new AW / AR commands (back-pressure).
module axi_outstanding_tracker #(
    parameter int MAX_OUTSTANDING = 4,
    parameter int CNT_WIDTH       = $clog2(MAX_OUTSTANDING + 1)
) (
    input  logic                 clk,
    input  logic                 rst_n,

    // Handshake events from the master's port
    input  logic                 aw_fire,     // awvalid && awready
    input  logic                 b_fire,      // bvalid  && bready
    input  logic                 ar_fire,     // arvalid && arready
    input  logic                 r_last_fire, // rvalid  && rready && rlast

    output logic [CNT_WIDTH-1:0] wr_count,
    output logic [CNT_WIDTH-1:0] rd_count,
    output logic                 wr_allow,    // new AW may be accepted
    output logic                 rd_allow,    // new AR may be accepted
    output logic                 wr_idle,     // no writes in flight
    output logic                 rd_idle,     // no reads in flight
    output logic                 error        // sticky: overflow or underflow seen
);

    // Allow only when below the limit. No same-cycle bypass on completion,
    // so there is no combinational path from B/R back to AW/AR ready.
    assign wr_allow = (wr_count < CNT_WIDTH'(MAX_OUTSTANDING));
    assign rd_allow = (rd_count < CNT_WIDTH'(MAX_OUTSTANDING));
    assign wr_idle  = (wr_count == '0);
    assign rd_idle  = (rd_count == '0);

    logic wr_overflow, wr_underflow, rd_overflow, rd_underflow;
    assign wr_overflow  = aw_fire     && !b_fire      && !wr_allow;
    assign wr_underflow = b_fire      && !aw_fire     &&  wr_idle;
    assign rd_overflow  = ar_fire     && !r_last_fire && !rd_allow;
    assign rd_underflow = r_last_fire && !ar_fire     &&  rd_idle;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_count <= '0;
            rd_count <= '0;
            error    <= 1'b0;
        end else begin
            // Issue and complete in the same cycle -> count unchanged
            if (aw_fire && !b_fire && !wr_overflow)       wr_count <= wr_count + 1'b1;
            else if (b_fire && !aw_fire && !wr_underflow) wr_count <= wr_count - 1'b1;

            if (ar_fire && !r_last_fire && !rd_overflow)       rd_count <= rd_count + 1'b1;
            else if (r_last_fire && !ar_fire && !rd_underflow) rd_count <= rd_count - 1'b1;

            if (wr_overflow || wr_underflow || rd_overflow || rd_underflow)
                error <= 1'b1;
        end
    end

    // synthesis translate_off
    initial begin
        if (MAX_OUTSTANDING < 1)
            $error("axi_outstanding_tracker: MAX_OUTSTANDING must be >= 1");
        if ((2 ** CNT_WIDTH) <= MAX_OUTSTANDING)
            $error("axi_outstanding_tracker: CNT_WIDTH too small for MAX_OUTSTANDING");
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (wr_overflow)  $error("tracker: AW accepted while write limit reached");
            if (wr_underflow) $error("tracker: B received with no write in flight");
            if (rd_overflow)  $error("tracker: AR accepted while read limit reached");
            if (rd_underflow) $error("tracker: RLAST received with no read in flight");
        end
    end
    // synthesis translate_on

endmodule