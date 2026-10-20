// Burst-capable AXI memory slave (one write and one read burst at a time).
// Beat addresses come from axi_burst_addr_gen (FIXED / INCR / WRAP).
// SLVERR is returned (and memory left untouched) for illegal bursts,
// INCR bursts that cross 4KB, and writes whose WLAST is on the wrong beat.
module axi_slave_burst #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int MEM_DEPTH  = 1024    // words, power of 2
) (
    axi_if.slave axi
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    localparam int ADDR_LSB   = $clog2(STRB_WIDTH);
    localparam int MEM_BITS   = $clog2(MEM_DEPTH);

    localparam logic [1:0] OKAY   = 2'b00;
    localparam logic [1:0] SLVERR = 2'b10;

    logic [DATA_WIDTH-1:0] mem [MEM_DEPTH];

    initial begin
        for (int i = 0; i < MEM_DEPTH; i++)
            mem[i] = '0;
    end

    // Write path
    typedef enum logic [1:0] { W_IDLE, W_DATA, W_RESP } wstate_t;
    wstate_t wstate;

    logic [ADDR_WIDTH-1:0] w_addr;
    logic                  w_last_beat, w_active;
    logic                  w_bad_burst, w_cross_4k;
    logic                  w_err;          // this burst will get SLVERR
    logic [ID_WIDTH-1:0]   w_id;

    logic aw_fire, w_fire;
    assign aw_fire = axi.awvalid && axi.awready;
    assign w_fire  = axi.wvalid  && axi.wready;

    axi_burst_addr_gen #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) w_gen (
        .clk         (axi.ACLK),
        .rst_n       (axi.ARESETn),
        .load        (aw_fire),
        .start_addr  (axi.awaddr),
        .len         (axi.awlen),
        .size        (axi.awsize),
        .burst       (axi.awburst),
        .next        (w_fire),
        .addr        (w_addr),
        .beat        (),
        .active      (w_active),
        .last        (w_last_beat),
        .burst_error (w_bad_burst),
        .cross_4k    (w_cross_4k)
    );

    assign axi.awready = axi.ARESETn && (wstate == W_IDLE);
    assign axi.wready  = axi.ARESETn && (wstate == W_DATA);
    assign axi.bvalid  = axi.ARESETn && (wstate == W_RESP);
    assign axi.bid     = w_id;
    assign axi.bresp   = w_err ? SLVERR : OKAY;

    // Error for the beat being accepted now (WLAST on the wrong beat)
    logic w_beat_err;
    assign w_beat_err = (axi.wlast != w_last_beat) || !w_active;

    always_ff @(posedge axi.ACLK or negedge axi.ARESETn) begin
        if (!axi.ARESETn) begin
            wstate <= W_IDLE;
            w_id   <= '0;
            w_err  <= 1'b0;
        end else begin
            case (wstate)
                W_IDLE: begin
                    if (aw_fire) begin
                        w_id   <= axi.awid;
                        w_err  <= w_bad_burst || w_cross_4k;
                        wstate <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (w_fire) begin
                        if (!w_err && !w_beat_err) begin
                            for (int i = 0; i < STRB_WIDTH; i++)
                                if (axi.wstrb[i])
                                    mem[w_addr[ADDR_LSB +: MEM_BITS]][i*8 +: 8] <= axi.wdata[i*8 +: 8];
                        end
                        if (w_beat_err)
                            w_err <= 1'b1;
                        // The master's WLAST ends the burst
                        if (axi.wlast)
                            wstate <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (axi.bready) begin
                        w_err  <= 1'b0;
                        wstate <= W_IDLE;
                    end
                end

                default: wstate <= W_IDLE;
            endcase
        end
    end

    // Read path
    typedef enum logic { R_IDLE, R_DATA } rstate_t;
    rstate_t rstate;

    logic [ADDR_WIDTH-1:0] r_addr;
    logic                  r_last_beat;
    logic                  r_bad_burst, r_cross_4k;
    logic                  r_err;
    logic [ID_WIDTH-1:0]   r_id;

    logic ar_fire, r_fire;
    assign ar_fire = axi.arvalid && axi.arready;
    assign r_fire  = axi.rvalid  && axi.rready;

    axi_burst_addr_gen #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) r_gen (
        .clk         (axi.ACLK),
        .rst_n       (axi.ARESETn),
        .load        (ar_fire),
        .start_addr  (axi.araddr),
        .len         (axi.arlen),
        .size        (axi.arsize),
        .burst       (axi.arburst),
        .next        (r_fire),
        .addr        (r_addr),
        .beat        (),
        .active      (),
        .last        (r_last_beat),
        .burst_error (r_bad_burst),
        .cross_4k    (r_cross_4k)
    );

    // R outputs come from registers and the generator, so they hold while stalled
    assign axi.arready = axi.ARESETn && (rstate == R_IDLE);
    assign axi.rvalid  = axi.ARESETn && (rstate == R_DATA);
    assign axi.rid     = r_id;
    assign axi.rdata   = r_err ? '0 : mem[r_addr[ADDR_LSB +: MEM_BITS]];
    assign axi.rresp   = r_err ? SLVERR : OKAY;
    assign axi.rlast   = r_last_beat;

    always_ff @(posedge axi.ACLK or negedge axi.ARESETn) begin
        if (!axi.ARESETn) begin
            rstate <= R_IDLE;
            r_id   <= '0;
            r_err  <= 1'b0;
        end else begin
            case (rstate)
                R_IDLE: begin
                    if (ar_fire) begin
                        r_id   <= axi.arid;
                        r_err  <= r_bad_burst || r_cross_4k;
                        rstate <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (r_fire && r_last_beat) begin
                        r_err  <= 1'b0;
                        rstate <= R_IDLE;
                    end
                end

                default: rstate <= R_IDLE;
            endcase
        end
    end

endmodule
