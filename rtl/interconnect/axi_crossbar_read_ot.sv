module axi_crossbar_read_ot #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,

    parameter int NUM_MASTERS = 4,
    parameter int NUM_SLAVES  = 3,

    // Upper ID bits that carry the master index
    parameter int MASTER_BITS = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1,

    // -1 = stall unmapped addresses, otherwise route them to this port
    parameter int DEFAULT_SLAVE = -1,

    // In-flight transactions allowed per master
    parameter int MAX_OUTSTANDING = 4,

    parameter logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]
        SLAVE_BASE_ADDR = '0,

    parameter logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]
        SLAVE_ADDR_SIZE = '0
) (
    axi_if.read_slave  s_axi [NUM_MASTERS],
    axi_if.read_master m_axi [NUM_SLAVES]
);

    generate
        // One destination-routing row per master
        for (genvar master = 0;
             master < NUM_MASTERS;
             master++) begin : gen_master_rows

            axi_if #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .ID_WIDTH(ID_WIDTH)
            ) row_axi [NUM_SLAVES] (
                .ACLK(s_axi[0].ACLK),
                .ARESETn(s_axi[0].ARESETn)
            );

            axi_read_demux_ot #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .ID_WIDTH(ID_WIDTH),
                .NUM_SLAVES(NUM_SLAVES),
                .DEFAULT_SLAVE(DEFAULT_SLAVE),
                .MAX_OUTSTANDING(MAX_OUTSTANDING),
                .SLAVE_BASE_ADDR(SLAVE_BASE_ADDR),
                .SLAVE_ADDR_SIZE(SLAVE_ADDR_SIZE)
            ) master_read_router (
                .s_axi(s_axi[master]),
                .m_axi(row_axi)
            );

            // Connect this row to each slave's arbitration column.
            for (genvar slave = 0;
                 slave < NUM_SLAVES;
                 slave++) begin : gen_links

                // Read address
                assign gen_slave_columns[slave].column_axi[master].arid =
                    row_axi[slave].arid;

                assign gen_slave_columns[slave].column_axi[master].araddr =
                    row_axi[slave].araddr;

                assign gen_slave_columns[slave].column_axi[master].arlen =
                    row_axi[slave].arlen;

                assign gen_slave_columns[slave].column_axi[master].arsize =
                    row_axi[slave].arsize;

                assign gen_slave_columns[slave].column_axi[master].arburst =
                    row_axi[slave].arburst;

                assign gen_slave_columns[slave].column_axi[master].arvalid =
                    row_axi[slave].arvalid;

                assign row_axi[slave].arready =
                    gen_slave_columns[slave].column_axi[master].arready;

                // Read response
                assign row_axi[slave].rid =
                    gen_slave_columns[slave].column_axi[master].rid;

                assign row_axi[slave].rdata =
                    gen_slave_columns[slave].column_axi[master].rdata;

                assign row_axi[slave].rresp =
                    gen_slave_columns[slave].column_axi[master].rresp;

                assign row_axi[slave].rlast =
                    gen_slave_columns[slave].column_axi[master].rlast;

                assign row_axi[slave].rvalid =
                    gen_slave_columns[slave].column_axi[master].rvalid;

                assign gen_slave_columns[slave].column_axi[master].rready =
                    row_axi[slave].rready;
            end
        end

        // One independent arbitration column per slave
        for (genvar slave = 0;
             slave < NUM_SLAVES;
             slave++) begin : gen_slave_columns

            axi_if #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .ID_WIDTH(ID_WIDTH)
            ) column_axi [NUM_MASTERS] (
                .ACLK(s_axi[0].ACLK),
                .ARESETn(s_axi[0].ARESETn)
            );

            axi_read_mux_ot #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .ID_WIDTH(ID_WIDTH),
                .NUM_MASTERS(NUM_MASTERS),
                .MASTER_BITS(MASTER_BITS)
            ) slave_read_arb_mux (
                .s_axi(column_axi),
                .m_axi(m_axi[slave])
            );
        end
    endgenerate

endmodule