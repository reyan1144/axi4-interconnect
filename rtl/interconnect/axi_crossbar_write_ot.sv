module axi_crossbar_write_ot #(
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
    axi_if.write_slave  s_axi [NUM_MASTERS],
    axi_if.write_master m_axi [NUM_SLAVES]
);

    generate
        // Each master gets a row of possible slave destinations.
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

            axi_write_demux_ot #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .ID_WIDTH(ID_WIDTH),
                .NUM_SLAVES(NUM_SLAVES),
                .DEFAULT_SLAVE(DEFAULT_SLAVE),
                .MAX_OUTSTANDING(MAX_OUTSTANDING),
                .SLAVE_BASE_ADDR(SLAVE_BASE_ADDR),
                .SLAVE_ADDR_SIZE(SLAVE_ADDR_SIZE)
            ) master_demux (
                .s_axi(s_axi[master]),
                .m_axi(row_axi)
            );

            // Connect this master's row to each slave's column.
            for (genvar slave = 0;
                 slave < NUM_SLAVES;
                 slave++) begin : gen_links

                // Write address
                assign gen_slave_columns[slave].column_axi[master].awid =
                    row_axi[slave].awid;

                assign gen_slave_columns[slave].column_axi[master].awaddr =
                    row_axi[slave].awaddr;

                assign gen_slave_columns[slave].column_axi[master].awlen =
                    row_axi[slave].awlen;

                assign gen_slave_columns[slave].column_axi[master].awsize =
                    row_axi[slave].awsize;

                assign gen_slave_columns[slave].column_axi[master].awburst =
                    row_axi[slave].awburst;

                assign gen_slave_columns[slave].column_axi[master].awvalid =
                    row_axi[slave].awvalid;

                assign row_axi[slave].awready =
                    gen_slave_columns[slave].column_axi[master].awready;

                // Write data
                assign gen_slave_columns[slave].column_axi[master].wdata =
                    row_axi[slave].wdata;

                assign gen_slave_columns[slave].column_axi[master].wstrb =
                    row_axi[slave].wstrb;

                assign gen_slave_columns[slave].column_axi[master].wlast =
                    row_axi[slave].wlast;

                assign gen_slave_columns[slave].column_axi[master].wvalid =
                    row_axi[slave].wvalid;

                assign row_axi[slave].wready =
                    gen_slave_columns[slave].column_axi[master].wready;

                // Write response
                assign row_axi[slave].bid =
                    gen_slave_columns[slave].column_axi[master].bid;

                assign row_axi[slave].bresp =
                    gen_slave_columns[slave].column_axi[master].bresp;

                assign row_axi[slave].bvalid =
                    gen_slave_columns[slave].column_axi[master].bvalid;

                assign gen_slave_columns[slave].column_axi[master].bready =
                    row_axi[slave].bready;
            end
        end

        // Each slave gets an independent arbiter across all masters.
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

            axi_write_mux_ot #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .ID_WIDTH(ID_WIDTH),
                .NUM_MASTERS(NUM_MASTERS),
                .MASTER_BITS(MASTER_BITS),
                .MAX_OUTSTANDING(MAX_OUTSTANDING)
            ) slave_arb_mux (
                .s_axi(column_axi),
                .m_axi(m_axi[slave])
            );
        end
    endgenerate

endmodule