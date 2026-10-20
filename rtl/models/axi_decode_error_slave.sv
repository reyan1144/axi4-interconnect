// Burst-capable DECERR sink. One write and one read burst concurrently.
// Consume every W beat through WLAST before B. Return ARLEN+1 R beats.
// AW and W may arrive independently. Assumes protocol-correct WLAST.
module axi_decode_error_slave #(
    parameter int ID_WIDTH = 4
) (
    axi_if.slave axi
);
    logic aw_received, w_received;
    logic [ID_WIDTH-1:0] awid_reg;
    logic [8:0] r_remaining;

    assign axi.awready = axi.ARESETn && !aw_received && !axi.bvalid;
    assign axi.wready  = axi.ARESETn && !w_received && !axi.bvalid;
    assign axi.arready = axi.ARESETn && !axi.rvalid;
    assign axi.bresp = 2'b11;
    assign axi.rresp = 2'b11;
    assign axi.rdata = '0;
    assign axi.rlast = axi.rvalid && (r_remaining == 9'd1);

    always_ff @(posedge axi.ACLK or negedge axi.ARESETn) begin
        if (!axi.ARESETn) begin
            aw_received <= 0; w_received <= 0; awid_reg <= '0;
            axi.bid <= '0; axi.bvalid <= 0;
        end else begin
            if (axi.awvalid && axi.awready) begin
                awid_reg <= axi.awid;
                aw_received <= 1;
            end
            if (axi.wvalid && axi.wready && axi.wlast)
                w_received <= 1;
            if (aw_received && w_received && !axi.bvalid) begin
                axi.bid <= awid_reg;
                axi.bvalid <= 1;
                aw_received <= 0; w_received <= 0;
            end
            if (axi.bvalid && axi.bready) axi.bvalid <= 0;
        end
    end

    always_ff @(posedge axi.ACLK or negedge axi.ARESETn) begin
        if (!axi.ARESETn) begin
            axi.rid <= '0; axi.rvalid <= 0; r_remaining <= '0;
        end else begin
            if (axi.arvalid && axi.arready) begin
                axi.rid <= axi.arid;
                r_remaining <= {1'b0, axi.arlen} + 9'd1;
                axi.rvalid <= 1;
            end else if (axi.rvalid && axi.rready) begin
                r_remaining <= r_remaining - 9'd1;
                if (r_remaining == 9'd1) axi.rvalid <= 0;
            end
        end
    end
endmodule
