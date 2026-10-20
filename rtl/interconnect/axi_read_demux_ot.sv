// Per-master read router with multiple outstanding transactions.
// AR: routed by address. Up to MAX_OUTSTANDING reads in flight.
//     Same-ID rule: a new AR may only go to the slave that already
//     holds this ID's outstanding reads, so R for one ID stays in order.
// R:  round-robin across slaves; a granted slave keeps the R channel
//     until RLAST so burst beats are never mixed.
module axi_read_demux_ot #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int NUM_SLAVES = 3,
    parameter int DEFAULT_SLAVE = -1,
    parameter int MAX_OUTSTANDING = 4,

    parameter logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]
        SLAVE_BASE_ADDR = '0,

    parameter logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]
        SLAVE_ADDR_SIZE = '0
) (
    axi_if.read_slave  s_axi,
    axi_if.read_master m_axi [NUM_SLAVES]
);

    localparam int INDEX_WIDTH = (NUM_SLAVES <= 1) ? 1 : $clog2(NUM_SLAVES);
    localparam int CNT_WIDTH   = $clog2(MAX_OUTSTANDING + 1);
    localparam int NUM_IDS     = 2 ** ID_WIDTH;

    logic [NUM_SLAVES-1:0]  raw_select, decoded_select;
    logic                   raw_address_valid, address_valid;
    logic [INDEX_WIDTH-1:0] raw_index, target_index;

    logic [NUM_SLAVES-1:0] downstream_arready;
    logic [NUM_SLAVES-1:0] downstream_rvalid;
    logic [NUM_SLAVES-1:0] downstream_rlast;
    logic [NUM_SLAVES-1:0][ID_WIDTH-1:0]   downstream_rid;
    logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0] downstream_rdata;
    logic [NUM_SLAVES-1:0][1:0]            downstream_rresp;

    axi_addr_decoder #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .NUM_SLAVES      (NUM_SLAVES),
        .SLAVE_BASE_ADDR (SLAVE_BASE_ADDR),
        .SLAVE_ADDR_SIZE (SLAVE_ADDR_SIZE)
    ) decoder (
        .address       (s_axi.araddr),
        .slave_select  (raw_select),
        .slave_index   (raw_index),
        .address_valid (raw_address_valid)
    );

    // Day 26: reject an INCR burst crossing 4KB before any real slave sees it.
    logic cross_4k;
    axi_4kb_check #(.ADDR_WIDTH(ADDR_WIDTH)) boundary_check (
        .addr(s_axi.araddr), .len(s_axi.arlen),
        .size(s_axi.arsize), .burst(s_axi.arburst),
        .cross_4k(cross_4k)
    );

    // Crossings share the decode-error endpoint. Without a default, stall.

    always_comb begin
        decoded_select = cross_4k ? '0 : raw_select;
        address_valid  = raw_address_valid && !cross_4k;
        target_index   = raw_index;

        if ((!raw_address_valid || cross_4k) &&
            DEFAULT_SLAVE >= 0 &&
            DEFAULT_SLAVE < NUM_SLAVES) begin

            decoded_select = '0;
            decoded_select[DEFAULT_SLAVE] = 1'b1;
            address_valid = 1'b1;
            target_index  = INDEX_WIDTH'(DEFAULT_SLAVE);
        end
    end

    // Outstanding limit (Day 22 tracker, read half only)
    logic ar_fire, r_fire, r_last_fire;
    logic rd_allow;
    logic [CNT_WIDTH-1:0] rd_count;

    axi_outstanding_tracker #(
        .MAX_OUTSTANDING(MAX_OUTSTANDING)
    ) tracker (
        .clk         (s_axi.ACLK),
        .rst_n       (s_axi.ARESETn),
        .aw_fire     (1'b0),
        .b_fire      (1'b0),
        .ar_fire     (ar_fire),
        .r_last_fire (r_last_fire),
        .wr_count    (),
        .rd_count    (rd_count),
        .wr_allow    (),
        .rd_allow    (rd_allow),
        .wr_idle     (),
        .rd_idle     (),
        .error       ()
    );

    // Per-ID table: how many reads of this ID are in flight, and where
    logic [CNT_WIDTH-1:0]   id_count [NUM_IDS];
    logic [INDEX_WIDTH-1:0] id_slave [NUM_IDS];
    logic                   id_ok;

    assign id_ok = (id_count[s_axi.arid] == '0) ||
                   (id_slave[s_axi.arid] == target_index);

    // Gated by ARVALID because ARID/ARADDR may be X while ARVALID is low
    logic ar_allow;
    assign ar_allow = s_axi.ARESETn && s_axi.arvalid && address_valid &&
                      rd_allow && id_ok;

    // R arbitration across slaves, held until RLAST
    logic [NUM_SLAVES-1:0]  r_grant;
    logic                   r_grant_valid;
    logic [INDEX_WIDTH-1:0] r_index;

    axi_arbiter_rr #(
        .NUM_REQUESTERS(NUM_SLAVES)
    ) r_arbiter (
        .clk         (s_axi.ACLK),
        .resetn      (s_axi.ARESETn),
        .request     (downstream_rvalid),
        .grant_ready (r_last_fire),
        .grant       (r_grant),
        .grant_valid (r_grant_valid),
        .grant_index (r_index)
    );

    // Constant interface-array indices for Vivado
    generate
        for (genvar g = 0; g < NUM_SLAVES; g++) begin : gen_ports

            assign downstream_arready[g] = m_axi[g].arready;
            assign downstream_rid[g]     = m_axi[g].rid;
            assign downstream_rdata[g]   = m_axi[g].rdata;
            assign downstream_rresp[g]   = m_axi[g].rresp;
            assign downstream_rlast[g]   = m_axi[g].rlast;
            assign downstream_rvalid[g]  = m_axi[g].rvalid;

            assign m_axi[g].arid    = s_axi.arid;
            assign m_axi[g].araddr  = s_axi.araddr;
            assign m_axi[g].arlen   = s_axi.arlen;
            assign m_axi[g].arsize  = s_axi.arsize;
            assign m_axi[g].arburst = s_axi.arburst;
            assign m_axi[g].arvalid = ar_allow && decoded_select[g] && s_axi.arvalid;

            assign m_axi[g].rready = s_axi.ARESETn && r_grant[g] && s_axi.rready;
        end
    endgenerate

    assign s_axi.arready = ar_allow && |(decoded_select & downstream_arready);

    assign s_axi.rvalid = s_axi.ARESETn && r_grant_valid && downstream_rvalid[r_index];
    assign s_axi.rid    = downstream_rid[r_index];
    assign s_axi.rdata  = downstream_rdata[r_index];
    assign s_axi.rresp  = downstream_rresp[r_index];
    assign s_axi.rlast  = downstream_rlast[r_index];

    assign ar_fire     = s_axi.arvalid && s_axi.arready;
    assign r_fire      = s_axi.rvalid  && s_axi.rready;
    assign r_last_fire = r_fire && s_axi.rlast;

    always_ff @(posedge s_axi.ACLK or negedge s_axi.ARESETn) begin
        if (!s_axi.ARESETn) begin
            for (int i = 0; i < NUM_IDS; i++) begin
                id_count[i] <= '0;
                id_slave[i] <= '0;
            end
        end else begin
            for (int i = 0; i < NUM_IDS; i++) begin
                if (ar_fire && s_axi.arid == i && !(r_last_fire && s_axi.rid == i))
                    id_count[i] <= id_count[i] + 1'b1;
                else if (r_last_fire && s_axi.rid == i && !(ar_fire && s_axi.arid == i))
                    id_count[i] <= id_count[i] - 1'b1;

                if (ar_fire && s_axi.arid == i)
                    id_slave[i] <= target_index;
            end
        end
    end

    // synthesis translate_off
    always @(posedge s_axi.ACLK) begin
        if (s_axi.ARESETn && r_last_fire && id_count[s_axi.rid] == '0)
            $error("axi_read_demux_ot: RLAST with ID %0h that has no read in flight", s_axi.rid);
    end
    // synthesis translate_on

endmodule
