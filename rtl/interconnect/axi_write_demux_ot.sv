// Per-master write router with multiple outstanding transactions.
// AW: routed by address. Up to MAX_OUTSTANDING writes in flight.
//     Same-ID rule: a new AW may only go to the slave that already
//     holds this ID's outstanding writes, so B for one ID stays in order.
// W:  follows AW order (route FIFO of slave indexes).
// B:  round-robin across slaves back to the master.
module axi_write_demux_ot #(
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
    axi_if.write_slave  s_axi,
    axi_if.write_master m_axi [NUM_SLAVES]
);

    localparam int INDEX_WIDTH = (NUM_SLAVES <= 1) ? 1 : $clog2(NUM_SLAVES);
    localparam int CNT_WIDTH   = $clog2(MAX_OUTSTANDING + 1);
    localparam int NUM_IDS     = 2 ** ID_WIDTH;

    logic [NUM_SLAVES-1:0]  raw_select, decoded_select;
    logic                   raw_address_valid, address_valid;
    logic [INDEX_WIDTH-1:0] raw_index, target_index;

    logic [NUM_SLAVES-1:0] downstream_awready;
    logic [NUM_SLAVES-1:0] downstream_wready;
    logic [NUM_SLAVES-1:0] downstream_bvalid;
    logic [NUM_SLAVES-1:0][ID_WIDTH-1:0] downstream_bid;
    logic [NUM_SLAVES-1:0][1:0]          downstream_bresp;

    axi_addr_decoder #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .NUM_SLAVES      (NUM_SLAVES),
        .SLAVE_BASE_ADDR (SLAVE_BASE_ADDR),
        .SLAVE_ADDR_SIZE (SLAVE_ADDR_SIZE)
    ) decoder (
        .address       (s_axi.awaddr),
        .slave_select  (raw_select),
        .slave_index   (raw_index),
        .address_valid (raw_address_valid)
    );

    // Day 26: reject an INCR burst crossing 4KB before any real slave sees it.
    logic cross_4k;
    axi_4kb_check #(.ADDR_WIDTH(ADDR_WIDTH)) boundary_check (
        .addr(s_axi.awaddr), .len(s_axi.awlen),
        .size(s_axi.awsize), .burst(s_axi.awburst),
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

    // Outstanding limit (Day 22 tracker, write half only)
    logic aw_fire, w_fire, b_fire;
    logic wr_allow;
    logic [CNT_WIDTH-1:0] wr_count;

    axi_outstanding_tracker #(
        .MAX_OUTSTANDING(MAX_OUTSTANDING)
    ) tracker (
        .clk         (s_axi.ACLK),
        .rst_n       (s_axi.ARESETn),
        .aw_fire     (aw_fire),
        .b_fire      (b_fire),
        .ar_fire     (1'b0),
        .r_last_fire (1'b0),
        .wr_count    (wr_count),
        .rd_count    (),
        .wr_allow    (wr_allow),
        .rd_allow    (),
        .wr_idle     (),
        .rd_idle     (),
        .error       ()
    );

    // Per-ID table: how many writes of this ID are in flight, and where
    logic [CNT_WIDTH-1:0]   id_count [NUM_IDS];
    logic [INDEX_WIDTH-1:0] id_slave [NUM_IDS];
    logic                   id_ok;

    assign id_ok = (id_count[s_axi.awid] == '0) ||
                   (id_slave[s_axi.awid] == target_index);

    // W route FIFO: slave index of each accepted AW, in order
    logic                   wroute_ready, wroute_valid;
    logic [INDEX_WIDTH-1:0] w_slave;

    axi_fifo #(
        .DATA_WIDTH (INDEX_WIDTH),
        .DEPTH      (MAX_OUTSTANDING)
    ) w_route_fifo (
        .clk     (s_axi.ACLK),
        .resetn  (s_axi.ARESETn),
        .s_valid (aw_fire),
        .s_ready (wroute_ready),
        .s_data  (target_index),
        .m_valid (wroute_valid),
        .m_ready (w_fire && s_axi.wlast),
        .m_data  (w_slave),
        .count   ()
    );

    // Only depends on state that cannot drop while AW waits,
    // so AWVALID stays stable downstream. Gated by AWVALID because
    // AWID/AWADDR may be X while AWVALID is low.
    logic aw_allow;
    assign aw_allow = s_axi.ARESETn && s_axi.awvalid && address_valid &&
                      wr_allow && id_ok && wroute_ready;

    // B arbitration across slaves
    logic [NUM_SLAVES-1:0]  b_grant;
    logic                   b_grant_valid;
    logic [INDEX_WIDTH-1:0] b_index;

    axi_arbiter_rr #(
        .NUM_REQUESTERS(NUM_SLAVES)
    ) b_arbiter (
        .clk         (s_axi.ACLK),
        .resetn      (s_axi.ARESETn),
        .request     (downstream_bvalid),
        .grant_ready (b_fire),
        .grant       (b_grant),
        .grant_valid (b_grant_valid),
        .grant_index (b_index)
    );

    // Constant interface-array indices for Vivado
    generate
        for (genvar g = 0; g < NUM_SLAVES; g++) begin : gen_ports

            assign downstream_awready[g] = m_axi[g].awready;
            assign downstream_wready[g]  = m_axi[g].wready;
            assign downstream_bid[g]     = m_axi[g].bid;
            assign downstream_bresp[g]   = m_axi[g].bresp;
            assign downstream_bvalid[g]  = m_axi[g].bvalid;

            assign m_axi[g].awid    = s_axi.awid;
            assign m_axi[g].awaddr  = s_axi.awaddr;
            assign m_axi[g].awlen   = s_axi.awlen;
            assign m_axi[g].awsize  = s_axi.awsize;
            assign m_axi[g].awburst = s_axi.awburst;
            assign m_axi[g].awvalid = aw_allow && decoded_select[g] && s_axi.awvalid;

            assign m_axi[g].wdata  = s_axi.wdata;
            assign m_axi[g].wstrb  = s_axi.wstrb;
            assign m_axi[g].wlast  = s_axi.wlast;
            assign m_axi[g].wvalid = s_axi.ARESETn && wroute_valid &&
                                     (w_slave == g) && s_axi.wvalid;

            assign m_axi[g].bready = s_axi.ARESETn && b_grant[g] && s_axi.bready;
        end
    endgenerate

    assign s_axi.awready = aw_allow && |(decoded_select & downstream_awready);
    assign s_axi.wready  = s_axi.ARESETn && wroute_valid && downstream_wready[w_slave];

    assign s_axi.bvalid = s_axi.ARESETn && b_grant_valid && downstream_bvalid[b_index];
    assign s_axi.bid    = downstream_bid[b_index];
    assign s_axi.bresp  = downstream_bresp[b_index];

    assign aw_fire = s_axi.awvalid && s_axi.awready;
    assign w_fire  = s_axi.wvalid  && s_axi.wready;
    assign b_fire  = s_axi.bvalid  && s_axi.bready;

    always_ff @(posedge s_axi.ACLK or negedge s_axi.ARESETn) begin
        if (!s_axi.ARESETn) begin
            for (int i = 0; i < NUM_IDS; i++) begin
                id_count[i] <= '0;
                id_slave[i] <= '0;
            end
        end else begin
            for (int i = 0; i < NUM_IDS; i++) begin
                if (aw_fire && s_axi.awid == i && !(b_fire && s_axi.bid == i))
                    id_count[i] <= id_count[i] + 1'b1;
                else if (b_fire && s_axi.bid == i && !(aw_fire && s_axi.awid == i))
                    id_count[i] <= id_count[i] - 1'b1;

                if (aw_fire && s_axi.awid == i)
                    id_slave[i] <= target_index;
            end
        end
    end

    // synthesis translate_off
    always @(posedge s_axi.ACLK) begin
        if (s_axi.ARESETn && b_fire && id_count[s_axi.bid] == '0)
            $error("axi_write_demux_ot: B with ID %0h that has no write in flight", s_axi.bid);
    end
    // synthesis translate_on

endmodule
