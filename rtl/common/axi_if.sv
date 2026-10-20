interface axi_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4
) (
    input logic ACLK,
    input logic ARESETn
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // Write address channel
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awvalid;
    logic                  awready;

    // Write data channel
    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wlast;
    logic                  wvalid;
    logic                  wready;

    // Write response channel
    logic [ID_WIDTH-1:0] bid;
    logic [1:0]          bresp;
    logic                bvalid;
    logic                bready;

    // Read address channel
    logic [ID_WIDTH-1:0]   arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arvalid;
    logic                  arready;

    // Read data channel
    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic                  rvalid;
    logic                  rready;

    modport master (
        input  ACLK, ARESETn,

        output awid, awaddr, awlen, awsize, awburst, awvalid,
        input  awready,

        output wdata, wstrb, wlast, wvalid,
        input  wready,

        input  bid, bresp, bvalid,
        output bready,

        output arid, araddr, arlen, arsize, arburst, arvalid,
        input  arready,

        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );

    modport slave (
        input  ACLK, ARESETn,

        input  awid, awaddr, awlen, awsize, awburst, awvalid,
        output awready,

        input  wdata, wstrb, wlast, wvalid,
        output wready,

        output bid, bresp, bvalid,
        input  bready,

        input  arid, araddr, arlen, arsize, arburst, arvalid,
        output arready,

        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );

        modport write_master (
        input  ACLK, ARESETn,

        output awid, awaddr, awlen, awsize, awburst, awvalid,
        input  awready,

        output wdata, wstrb, wlast, wvalid,
        input  wready,

        input  bid, bresp, bvalid,
        output bready
    );

    modport write_slave (
        input  ACLK, ARESETn,

        input  awid, awaddr, awlen, awsize, awburst, awvalid,
        output awready,

        input  wdata, wstrb, wlast, wvalid,
        output wready,

        output bid, bresp, bvalid,
        input  bready
    );

    modport read_master (
        input  ACLK, ARESETn,

        output arid, araddr, arlen, arsize, arburst, arvalid,
        input  arready,

        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );

    modport read_slave (
        input  ACLK, ARESETn,

        input  arid, araddr, arlen, arsize, arburst, arvalid,
        output arready,

        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );

endinterface