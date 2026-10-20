module axi_id_remap #(
    parameter int S_ID_WIDTH   = 4,
    parameter int NUM_MASTERS  = 4,
    parameter int MASTER_INDEX = 0,

    // At least 1 bit, even for a single master
    parameter int MASTER_BITS  =
        (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1,

    parameter int M_ID_WIDTH   = S_ID_WIDTH + MASTER_BITS
) (
    // Upstream: original master, narrow IDs
    axi_if.slave  s_axi,

    // Downstream: toward the crossbar, widened IDs
    axi_if.master m_axi
);

    // Master index placed in the upper ID bits
    localparam logic [MASTER_BITS-1:0] MASTER_TAG = MASTER_INDEX;

    // Write address: widen ID
    assign m_axi.awid    = {MASTER_TAG, s_axi.awid};
    assign m_axi.awaddr  = s_axi.awaddr;
    assign m_axi.awlen   = s_axi.awlen;
    assign m_axi.awsize  = s_axi.awsize;
    assign m_axi.awburst = s_axi.awburst;
    assign m_axi.awvalid = s_axi.awvalid;
    assign s_axi.awready = m_axi.awready;

    // Write data: no ID in AXI4
    assign m_axi.wdata  = s_axi.wdata;
    assign m_axi.wstrb  = s_axi.wstrb;
    assign m_axi.wlast  = s_axi.wlast;
    assign m_axi.wvalid = s_axi.wvalid;
    assign s_axi.wready = m_axi.wready;

    // Write response: strip master index
    assign s_axi.bid    = m_axi.bid[S_ID_WIDTH-1:0];
    assign s_axi.bresp  = m_axi.bresp;
    assign s_axi.bvalid = m_axi.bvalid;
    assign m_axi.bready = s_axi.bready;

    // Read address: widen ID
    assign m_axi.arid    = {MASTER_TAG, s_axi.arid};
    assign m_axi.araddr  = s_axi.araddr;
    assign m_axi.arlen   = s_axi.arlen;
    assign m_axi.arsize  = s_axi.arsize;
    assign m_axi.arburst = s_axi.arburst;
    assign m_axi.arvalid = s_axi.arvalid;
    assign s_axi.arready = m_axi.arready;

    // Read data: strip master index
    assign s_axi.rid    = m_axi.rid[S_ID_WIDTH-1:0];
    assign s_axi.rdata  = m_axi.rdata;
    assign s_axi.rresp  = m_axi.rresp;
    assign s_axi.rlast  = m_axi.rlast;
    assign s_axi.rvalid = m_axi.rvalid;
    assign m_axi.rready = s_axi.rready;

    // synthesis translate_off

    // Configuration checks at time zero
    initial begin
        if (MASTER_INDEX < 0 || MASTER_INDEX >= NUM_MASTERS)
            $fatal(1, "axi_id_remap: MASTER_INDEX=%0d out of range",
                   MASTER_INDEX);

        if ((1 << MASTER_BITS) < NUM_MASTERS)
            $fatal(1, "axi_id_remap: MASTER_BITS=%0d too small for %0d masters",
                   MASTER_BITS, NUM_MASTERS);

        if (M_ID_WIDTH != S_ID_WIDTH + MASTER_BITS)
            $fatal(1, "axi_id_remap: M_ID_WIDTH must be S_ID_WIDTH + MASTER_BITS");

        if ($bits(s_axi.awid) != S_ID_WIDTH)
            $fatal(1, "axi_id_remap: s_axi ID width %0d != S_ID_WIDTH %0d",
                   $bits(s_axi.awid), S_ID_WIDTH);

        if ($bits(m_axi.awid) != M_ID_WIDTH)
            $fatal(1, "axi_id_remap: m_axi ID width %0d != M_ID_WIDTH %0d",
                   $bits(m_axi.awid), M_ID_WIDTH);

        if ($bits(s_axi.awaddr) != $bits(m_axi.awaddr) ||
            $bits(s_axi.wdata)  != $bits(m_axi.wdata))
            $fatal(1, "axi_id_remap: address/data widths must match");
    end

    // A response reaching this port must carry this master's index
    always @(posedge s_axi.ACLK) begin
        if (s_axi.ARESETn) begin
            if (m_axi.bvalid &&
                m_axi.bid[M_ID_WIDTH-1 -: MASTER_BITS] !== MASTER_TAG)
                $error("axi_id_remap[%0d]: B response with foreign ID %h",
                       MASTER_INDEX, m_axi.bid);

            if (m_axi.rvalid &&
                m_axi.rid[M_ID_WIDTH-1 -: MASTER_BITS] !== MASTER_TAG)
                $error("axi_id_remap[%0d]: R response with foreign ID %h",
                       MASTER_INDEX, m_axi.rid);
        end
    end

    // synthesis translate_on

endmodule