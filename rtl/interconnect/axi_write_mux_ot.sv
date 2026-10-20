// Per-slave write arbiter with multiple outstanding transactions.
// AW: round-robin across masters; the winner's index goes into a W order FIFO.
// W:  forwarded from the master at the FIFO head until WLAST.
// B:  routed back using the master tag in the upper BID bits.
module axi_write_mux_ot #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int ID_WIDTH    = 6,
    parameter int NUM_MASTERS = 4,
    parameter int MASTER_BITS = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1,
    parameter int MAX_OUTSTANDING = 4    // depth of the W order FIFO
) (
    axi_if.write_slave  s_axi [NUM_MASTERS],
    axi_if.write_master m_axi
);

    localparam int INDEX_WIDTH = (NUM_MASTERS <= 1) ? 1 : $clog2(NUM_MASTERS);

    logic [NUM_MASTERS-1:0]  aw_request;
    logic [NUM_MASTERS-1:0]  aw_grant;
    logic                    aw_grant_valid;
    logic [INDEX_WIDTH-1:0]  aw_index;

    logic [NUM_MASTERS-1:0][ID_WIDTH-1:0]     upstream_awid;
    logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0]   upstream_awaddr;
    logic [NUM_MASTERS-1:0][7:0]              upstream_awlen;
    logic [NUM_MASTERS-1:0][2:0]              upstream_awsize;
    logic [NUM_MASTERS-1:0][1:0]              upstream_awburst;
    logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]   upstream_wdata;
    logic [NUM_MASTERS-1:0][DATA_WIDTH/8-1:0] upstream_wstrb;
    logic [NUM_MASTERS-1:0]                   upstream_wlast;
    logic [NUM_MASTERS-1:0]                   upstream_wvalid;
    logic [NUM_MASTERS-1:0]                   upstream_bready;

    logic aw_fire, w_last_fire;
    logic worder_ready, worder_valid;
    logic [INDEX_WIDTH-1:0] w_master;

    // Master tag carried in the upper ID bits (added by axi_id_remap)
    logic [MASTER_BITS-1:0] b_master;
    logic                   b_master_ok;

    assign b_master    = m_axi.bid[ID_WIDTH-1 -: MASTER_BITS];
    assign b_master_ok = (b_master < NUM_MASTERS);

    axi_arbiter_rr #(
        .NUM_REQUESTERS(NUM_MASTERS)
    ) aw_arbiter (
        .clk         (m_axi.ACLK),
        .resetn      (m_axi.ARESETn),
        .request     (aw_request),
        .grant_ready (aw_fire),
        .grant       (aw_grant),
        .grant_valid (aw_grant_valid),
        .grant_index (aw_index)
    );

    // Order in which W bursts must be forwarded to this slave
    axi_fifo #(
        .DATA_WIDTH (INDEX_WIDTH),
        .DEPTH      (MAX_OUTSTANDING)
    ) w_order_fifo (
        .clk     (m_axi.ACLK),
        .resetn  (m_axi.ARESETn),
        .s_valid (aw_fire),
        .s_ready (worder_ready),
        .s_data  (aw_index),
        .m_valid (worder_valid),
        .m_ready (w_last_fire),
        .m_data  (w_master),
        .count   ()
    );

    // Constant interface-array indices for Vivado
    generate
        for (genvar g = 0; g < NUM_MASTERS; g++) begin : gen_ports

            assign aw_request[g] = m_axi.ARESETn && s_axi[g].awvalid;

            assign upstream_awid[g]    = s_axi[g].awid;
            assign upstream_awaddr[g]  = s_axi[g].awaddr;
            assign upstream_awlen[g]   = s_axi[g].awlen;
            assign upstream_awsize[g]  = s_axi[g].awsize;
            assign upstream_awburst[g] = s_axi[g].awburst;

            assign upstream_wdata[g]  = s_axi[g].wdata;
            assign upstream_wstrb[g]  = s_axi[g].wstrb;
            assign upstream_wlast[g]  = s_axi[g].wlast;
            assign upstream_wvalid[g] = s_axi[g].wvalid;
            assign upstream_bready[g] = s_axi[g].bready;

            assign s_axi[g].awready = aw_grant[g] && worder_ready && m_axi.awready;

            assign s_axi[g].wready = m_axi.ARESETn && worder_valid &&
                                     (w_master == g) && m_axi.wready;

            assign s_axi[g].bid    = m_axi.bid;
            assign s_axi[g].bresp  = m_axi.bresp;
            assign s_axi[g].bvalid = m_axi.ARESETn && m_axi.bvalid &&
                                     b_master_ok && (b_master == g);
        end
    endgenerate

    // AW to the slave only when the W order FIFO has space
    assign m_axi.awvalid = aw_grant_valid && worder_ready;
    assign m_axi.awid    = upstream_awid[aw_index];
    assign m_axi.awaddr  = upstream_awaddr[aw_index];
    assign m_axi.awlen   = upstream_awlen[aw_index];
    assign m_axi.awsize  = upstream_awsize[aw_index];
    assign m_axi.awburst = upstream_awburst[aw_index];

    assign m_axi.wvalid = m_axi.ARESETn && worder_valid && upstream_wvalid[w_master];
    assign m_axi.wdata  = upstream_wdata[w_master];
    assign m_axi.wstrb  = upstream_wstrb[w_master];
    assign m_axi.wlast  = upstream_wlast[w_master];

    // Gated by BVALID: BID may be X while BVALID is low
    assign m_axi.bready = m_axi.ARESETn && m_axi.bvalid &&
                          b_master_ok && upstream_bready[b_master];

    assign aw_fire     = m_axi.awvalid && m_axi.awready;
    assign w_last_fire = m_axi.wvalid && m_axi.wready && m_axi.wlast;

    // synthesis translate_off
    always @(posedge m_axi.ACLK) begin
        if (m_axi.ARESETn && m_axi.bvalid && !b_master_ok)
            $error("axi_write_mux_ot: BID %0h has no valid master tag", m_axi.bid);
    end
    // synthesis translate_on

endmodule
