// Channel stability/known-value checks, not a full AXI transaction scoreboard.
module axi_burst_protocol_checker (
    axi_if    axi,
    output int error_count     // number of assertion failures (optional)
);

    initial error_count = 0;

    // VALID and payload must remain stable while stalled

    a_aw_stable: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.awvalid && !axi.awready
        |=> axi.awvalid &&
            $stable({axi.awid, axi.awaddr, axi.awlen,
                     axi.awsize, axi.awburst})
    ) else begin error_count++; $error("AXI: AW changed while stalled"); end

    a_w_stable: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.wvalid && !axi.wready
        |=> axi.wvalid &&
            $stable({axi.wdata, axi.wstrb, axi.wlast})
    ) else begin error_count++; $error("AXI: W changed while stalled"); end

    a_b_stable: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.bvalid && !axi.bready
        |=> axi.bvalid &&
            $stable({axi.bid, axi.bresp})
    ) else begin error_count++; $error("AXI: B changed while stalled"); end

    a_ar_stable: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.arvalid && !axi.arready
        |=> axi.arvalid &&
            $stable({axi.arid, axi.araddr, axi.arlen,
                     axi.arsize, axi.arburst})
    ) else begin error_count++; $error("AXI: AR changed while stalled"); end

    a_r_stable: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.rvalid && !axi.rready
        |=> axi.rvalid &&
            $stable({axi.rid, axi.rdata, axi.rresp, axi.rlast})
    ) else begin error_count++; $error("AXI: R changed while stalled"); end

    // Handshake signals must not contain X or Z

    a_handshake_known: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        !$isunknown({
            axi.awvalid, axi.awready,
            axi.wvalid,  axi.wready,
            axi.bvalid,  axi.bready,
            axi.arvalid, axi.arready,
            axi.rvalid,  axi.rready
        })
    ) else begin error_count++; $error("AXI: handshake signal contains X or Z"); end

    // A valid payload must not contain X or Z

    a_aw_known: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.awvalid |->
        !$isunknown({axi.awid, axi.awaddr, axi.awlen,
                     axi.awsize, axi.awburst})
    ) else begin error_count++; $error("AXI: AW payload contains X or Z"); end

    a_w_known: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.wvalid |->
        !$isunknown({axi.wdata, axi.wstrb, axi.wlast})
    ) else begin error_count++; $error("AXI: W payload contains X or Z"); end

    a_b_known: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.bvalid |->
        !$isunknown({axi.bid, axi.bresp})
    ) else begin error_count++; $error("AXI: B payload contains X or Z"); end

    a_ar_known: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.arvalid |->
        !$isunknown({axi.arid, axi.araddr, axi.arlen,
                     axi.arsize, axi.arburst})
    ) else begin error_count++; $error("AXI: AR payload contains X or Z"); end

    a_r_known: assert property (
        @(posedge axi.ACLK) disable iff (!axi.ARESETn)
        axi.rvalid |->
        !$isunknown({axi.rid, axi.rdata, axi.rresp, axi.rlast})
    ) else begin error_count++; $error("AXI: R payload contains X or Z"); end

endmodule
