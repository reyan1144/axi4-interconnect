// Per-slave read arbiter with multiple outstanding transactions.
// AR: round-robin across masters.
// R:  routed back using the master tag in the upper RID bits.
module axi_read_mux_ot #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int ID_WIDTH    = 6,
    parameter int NUM_MASTERS = 4,
    parameter int MASTER_BITS = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1
) (
    axi_if.read_slave  s_axi [NUM_MASTERS],
    axi_if.read_master m_axi
);

    localparam int INDEX_WIDTH = (NUM_MASTERS <= 1) ? 1 : $clog2(NUM_MASTERS);

    logic [NUM_MASTERS-1:0]  ar_request;
    logic [NUM_MASTERS-1:0]  ar_grant;
    logic                    ar_grant_valid;
    logic [INDEX_WIDTH-1:0]  ar_index;

    logic [NUM_MASTERS-1:0][ID_WIDTH-1:0]   upstream_arid;
    logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0] upstream_araddr;
    logic [NUM_MASTERS-1:0][7:0]            upstream_arlen;
    logic [NUM_MASTERS-1:0][2:0]            upstream_arsize;
    logic [NUM_MASTERS-1:0][1:0]            upstream_arburst;
    logic [NUM_MASTERS-1:0]                 upstream_rready;

    logic ar_fire;

    // Master tag carried in the upper ID bits (added by axi_id_remap)
    logic [MASTER_BITS-1:0] r_master;
    logic                   r_master_ok;

    assign r_master    = m_axi.rid[ID_WIDTH-1 -: MASTER_BITS];
    assign r_master_ok = (r_master < NUM_MASTERS);

    axi_arbiter_rr #(
        .NUM_REQUESTERS(NUM_MASTERS)
    ) ar_arbiter (
        .clk         (m_axi.ACLK),
        .resetn      (m_axi.ARESETn),
        .request     (ar_request),
        .grant_ready (ar_fire),
        .grant       (ar_grant),
        .grant_valid (ar_grant_valid),
        .grant_index (ar_index)
    );

    // Constant interface-array indices for Vivado
    generate
        for (genvar g = 0; g < NUM_MASTERS; g++) begin : gen_ports

            assign ar_request[g] = m_axi.ARESETn && s_axi[g].arvalid;

            assign upstream_arid[g]    = s_axi[g].arid;
            assign upstream_araddr[g]  = s_axi[g].araddr;
            assign upstream_arlen[g]   = s_axi[g].arlen;
            assign upstream_arsize[g]  = s_axi[g].arsize;
            assign upstream_arburst[g] = s_axi[g].arburst;
            assign upstream_rready[g]  = s_axi[g].rready;

            assign s_axi[g].arready = ar_grant[g] && m_axi.arready;

            assign s_axi[g].rid    = m_axi.rid;
            assign s_axi[g].rdata  = m_axi.rdata;
            assign s_axi[g].rresp  = m_axi.rresp;
            assign s_axi[g].rlast  = m_axi.rlast;
            assign s_axi[g].rvalid = m_axi.ARESETn && m_axi.rvalid &&
                                     r_master_ok && (r_master == g);
        end
    endgenerate

    assign m_axi.arvalid = ar_grant_valid;
    assign m_axi.arid    = upstream_arid[ar_index];
    assign m_axi.araddr  = upstream_araddr[ar_index];
    assign m_axi.arlen   = upstream_arlen[ar_index];
    assign m_axi.arsize  = upstream_arsize[ar_index];
    assign m_axi.arburst = upstream_arburst[ar_index];

    // Gated by RVALID: RID may be X while RVALID is low
    assign m_axi.rready = m_axi.ARESETn && m_axi.rvalid &&
                          r_master_ok && upstream_rready[r_master];

    assign ar_fire = m_axi.arvalid && m_axi.arready;

    // synthesis translate_off
    always @(posedge m_axi.ACLK) begin
        if (m_axi.ARESETn && m_axi.rvalid && !r_master_ok)
            $error("axi_read_mux_ot: RID %0h has no valid master tag", m_axi.rid);
    end
    // synthesis translate_on

endmodule
