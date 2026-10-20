module axi_crossbar_top #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,   // master-side ID width

    parameter int NUM_MASTERS = 4,
    parameter int NUM_SLAVES  = 3,

    // In-flight writes and reads allowed per master
    parameter int MAX_OUTSTANDING = 4,

    parameter logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]
        SLAVE_BASE_ADDR = '0,

    parameter logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]
        SLAVE_ADDR_SIZE = '0
) (
    axi_if s_axi [NUM_MASTERS],     // ID_WIDTH-bit IDs
    axi_if m_axi [NUM_SLAVES]       // M_ID_WIDTH-bit IDs
);

    // Slave-side IDs carry the master index in the upper bits
    localparam int MASTER_BITS =
        (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1;
    localparam int M_ID_WIDTH = ID_WIDTH + MASTER_BITS;

    localparam int TOTAL_PORTS = NUM_SLAVES + 1;
    localparam int ERROR_PORT = NUM_SLAVES;

    // The error endpoint has no normal address region.
    localparam logic [TOTAL_PORTS-1:0][ADDR_WIDTH-1:0]
        INTERNAL_BASE = {
            {ADDR_WIDTH{1'b0}},
            SLAVE_BASE_ADDR
        };

    localparam logic [TOTAL_PORTS-1:0][ADDR_WIDTH-1:0]
        INTERNAL_SIZE = {
            {ADDR_WIDTH{1'b0}},
            SLAVE_ADDR_SIZE
        };

    axi_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(M_ID_WIDTH)
    ) routed_axi [TOTAL_PORTS] (
        .ACLK(s_axi[0].ACLK),
        .ARESETn(s_axi[0].ARESETn)
    );

    // Master ports after ID widening
    axi_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(M_ID_WIDTH)
    ) remapped_axi [NUM_MASTERS] (
        .ACLK(s_axi[0].ACLK),
        .ARESETn(s_axi[0].ARESETn)
    );

    generate
        for (genvar g = 0; g < NUM_MASTERS; g++) begin : gen_id_remap
            axi_id_remap #(
                .S_ID_WIDTH(ID_WIDTH),
                .NUM_MASTERS(NUM_MASTERS),
                .MASTER_INDEX(g),
                .MASTER_BITS(MASTER_BITS),
                .M_ID_WIDTH(M_ID_WIDTH)
            ) id_remap (
                .s_axi(s_axi[g]),
                .m_axi(remapped_axi[g])
            );
        end
    endgenerate

    axi_crossbar_write_ot #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(M_ID_WIDTH),
        .NUM_MASTERS(NUM_MASTERS),
        .NUM_SLAVES(TOTAL_PORTS),
        .MASTER_BITS(MASTER_BITS),
        .DEFAULT_SLAVE(ERROR_PORT),
        .MAX_OUTSTANDING(MAX_OUTSTANDING),
        .SLAVE_BASE_ADDR(INTERNAL_BASE),
        .SLAVE_ADDR_SIZE(INTERNAL_SIZE)
    ) write_crossbar (
        .s_axi(remapped_axi),
        .m_axi(routed_axi)
    );

    axi_crossbar_read_ot #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(M_ID_WIDTH),
        .NUM_MASTERS(NUM_MASTERS),
        .NUM_SLAVES(TOTAL_PORTS),
        .MASTER_BITS(MASTER_BITS),
        .DEFAULT_SLAVE(ERROR_PORT),
        .MAX_OUTSTANDING(MAX_OUTSTANDING),
        .SLAVE_BASE_ADDR(INTERNAL_BASE),
        .SLAVE_ADDR_SIZE(INTERNAL_SIZE)
    ) read_crossbar (
        .s_axi(remapped_axi),
        .m_axi(routed_axi)
    );

    axi_decode_error_slave #(
        .ID_WIDTH(M_ID_WIDTH)
    ) error_slave (
        .axi(routed_axi[ERROR_PORT])
    );

    generate
        for (genvar g = 0; g < NUM_SLAVES; g++) begin : gen_external_ports

            // Write address
            assign m_axi[g].awid    = routed_axi[g].awid;
            assign m_axi[g].awaddr  = routed_axi[g].awaddr;
            assign m_axi[g].awlen   = routed_axi[g].awlen;
            assign m_axi[g].awsize  = routed_axi[g].awsize;
            assign m_axi[g].awburst = routed_axi[g].awburst;
            assign m_axi[g].awvalid = routed_axi[g].awvalid;

            assign routed_axi[g].awready = m_axi[g].awready;

            // Write data
            assign m_axi[g].wdata  = routed_axi[g].wdata;
            assign m_axi[g].wstrb  = routed_axi[g].wstrb;
            assign m_axi[g].wlast  = routed_axi[g].wlast;
            assign m_axi[g].wvalid = routed_axi[g].wvalid;

            assign routed_axi[g].wready = m_axi[g].wready;

            // Write response
            assign routed_axi[g].bid    = m_axi[g].bid;
            assign routed_axi[g].bresp  = m_axi[g].bresp;
            assign routed_axi[g].bvalid = m_axi[g].bvalid;

            assign m_axi[g].bready = routed_axi[g].bready;

            // Read address
            assign m_axi[g].arid    = routed_axi[g].arid;
            assign m_axi[g].araddr  = routed_axi[g].araddr;
            assign m_axi[g].arlen   = routed_axi[g].arlen;
            assign m_axi[g].arsize  = routed_axi[g].arsize;
            assign m_axi[g].arburst = routed_axi[g].arburst;
            assign m_axi[g].arvalid = routed_axi[g].arvalid;

            assign routed_axi[g].arready = m_axi[g].arready;

            // Read response
            assign routed_axi[g].rid    = m_axi[g].rid;
            assign routed_axi[g].rdata  = m_axi[g].rdata;
            assign routed_axi[g].rresp  = m_axi[g].rresp;
            assign routed_axi[g].rlast  = m_axi[g].rlast;
            assign routed_axi[g].rvalid = m_axi[g].rvalid;

            assign m_axi[g].rready = routed_axi[g].rready;
        end
    endgenerate

    // synthesis translate_off

    // The slave-side interfaces must be declared with M_ID_WIDTH
    initial begin
        if ($bits(s_axi[0].awid) != ID_WIDTH)
            $fatal(1, "axi_crossbar_top: s_axi ID width %0d != ID_WIDTH %0d",
                   $bits(s_axi[0].awid), ID_WIDTH);

        if ($bits(m_axi[0].awid) != M_ID_WIDTH)
            $fatal(1, "axi_crossbar_top: m_axi ID width %0d != %0d (ID_WIDTH + MASTER_BITS)",
                   $bits(m_axi[0].awid), M_ID_WIDTH);
    end

    // synthesis translate_on

endmodule