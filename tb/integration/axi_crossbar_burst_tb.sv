`timescale 1ns/1ps
// Test-only traffic agent. Two instances share the crossbar.
module axi_day26_agent #(parameter int MASTER = 0, parameter int NUM_RANDOM = 300) (
    input logic clk, resetn, prep_done,
    output logic prepared = 0, done = 0,
    output int error_total,
    axi_if bus
);
    // TB drives the master side through plain signals
    logic        awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    logic [3:0]  awid = 0, arid = 0;
    logic [31:0] awaddr = 0, araddr = 0, wdata = 0;
    logic [7:0]  awlen = 0, arlen = 0;
    logic [2:0]  awsize = 0, arsize = 0;
    logic [1:0]  awburst = 0, arburst = 0;
    logic [3:0]  wstrb = 0;
    logic        wlast = 0;

    assign bus.awvalid = awvalid; assign bus.awid = awid; assign bus.awaddr = awaddr;
    assign bus.awlen = awlen; assign bus.awsize = awsize; assign bus.awburst = awburst;
    assign bus.wvalid = wvalid; assign bus.wdata = wdata; assign bus.wstrb = wstrb; assign bus.wlast = wlast;
    assign bus.bready = bready;
    assign bus.arvalid = arvalid; assign bus.arid = arid; assign bus.araddr = araddr;
    assign bus.arlen = arlen; assign bus.arsize = arsize; assign bus.arburst = arburst;
    assign bus.rready = rready;

    logic [7:0] ref_mem [8192];   // reference memory, bytes

    int errors = 0, wr_bursts = 0, rd_bursts = 0, wr_beats = 0, rd_beats = 0, slverr_seen = 0;

    task automatic check(bit cond, string msg);
        if (!cond) begin
            errors++;
            if (errors <= 10) $display("ERROR t=%0t: %s", $time, msg);
        end
    endtask

    // Beat address as defined by the AXI spec
    function automatic logic [31:0] ref_addr(logic [31:0] start, int n, int l, int s, logic [1:0] b);
        longint nb = 1 << s, total = nb * (l + 1);
        longint aligned = (start / nb) * nb, wb = (start / total) * total, a;
        if (b == 2'b00 || n == 0) return start;
        a = aligned + n * nb;
        if (b == 2'b10 && a >= wb + total) a = a - total;
        return 32'(a);
    endfunction

    // Independent reference for boundary and address-map errors
    function automatic bit ref_bad(logic [31:0] start, int l, int s, logic [1:0] b);
        longint nb = 1 << s;
        return (start >= 32'h2000) ||
               ((b == 2'b01) && ((start >> 12) != (((start / nb) * nb + l * nb) >> 12)));
    endfunction

    function automatic logic [31:0] ref_word(logic [31:0] a);
        int w = (a >> 2) % 2048;
        return {ref_mem[w*4+3], ref_mem[w*4+2], ref_mem[w*4+1], ref_mem[w*4]};
    endfunction

    bit awaiting_wlast = 0;
    always @(posedge clk) if (resetn && awaiting_wlast && bus.bvalid)
        check(0, "BVALID asserted before final W beat completed");

    // VALID and payload must hold while the TB stalls B or R.
    // Sampled 2 ns after the falling edge: the TB only drives on falling
    // edges and the DUT only changes on rising edges, so values are settled.
    logic        b_stalled = 0, r_stalled = 0;
    logic [5:0]  b_hold;
    logic [38:0] r_hold;
    always @(negedge clk) begin
        #2;
        if (resetn) begin
            if (b_stalled) check(bus.bvalid && {bus.bid, bus.bresp} == b_hold, "B changed while stalled");
            if (r_stalled) check(bus.rvalid && {bus.rid, bus.rdata, bus.rresp, bus.rlast} == r_hold,
                                 "R changed while stalled");
            b_stalled = bus.bvalid && !bus.bready;
            r_stalled = bus.rvalid && !bus.rready;
            b_hold    = {bus.bid, bus.bresp};
            r_hold    = {bus.rid, bus.rdata, bus.rresp, bus.rlast};
        end
    end

    // All TB driving happens on falling edges. A handshake is seen 1 ns
    // later (VALID and READY both high), and it completes on the next
    // rising edge.
    // wlast_beat: beat that carries WLAST (normally l; other values test bad WLAST)
    task automatic write_burst(logic [3:0] id, logic [31:0] a, int l, int s, logic [1:0] b,
                               int wlast_beat = -1);
        bit bad = ref_bad(a, l, s, b);
        bit wlast_ok;
        int nbeats;
        if (wlast_beat < 0) wlast_beat = l;
        nbeats   = wlast_beat + 1;
        wlast_ok = (wlast_beat == l);

        awaiting_wlast = 1;
        @(negedge clk);
        // AW and W start together, so W is offered before AW is accepted
        fork
            begin
                repeat ($urandom_range(0, 2)) @(negedge clk);
                awvalid = 1; awid = id; awaddr = a; awlen = 8'(l); awsize = 3'(s); awburst = b;
                #1;
                while (!bus.awready) begin @(negedge clk); #1; end
                @(negedge clk);
                awvalid = 0;
            end
            begin
                for (int n = 0; n < nbeats; n++) begin
                    logic [31:0] d = $urandom();
                    logic [3:0]  st;
                    logic [31:0] ba = ref_addr(a, n, l, s, b);
                    st = '0;
                    for (int j=0; j<4; j++)
                        if (j >= int'(ba % 4) && j <= int'(((ba / (1 << s)) * (1 << s)) % 4 + (1 << s) - 1))
                            st[j] = 1'($urandom_range(0,1));
                    while ($urandom_range(0, 3) == 0) @(negedge clk);
                    wvalid = 1; wdata = d; wstrb = st; wlast = (n == wlast_beat);
                    #1;
                    while (!bus.wready) begin @(negedge clk); #1; end
                    @(negedge clk);
                    wvalid = 0; wlast = 0;
                    // Memory is written only by beats of a good burst before any WLAST error
                    if (!bad && n < l && n < wlast_beat || !bad && n == l && wlast_ok)
                        for (int i = 0; i < 4; i++)
                            if (st[i]) ref_mem[((ba >> 2) % 2048) * 4 + i] = d[i*8 +: 8];
                    if (n == nbeats-1) awaiting_wlast = 0;
                    wr_beats++;
                end
            end
        join

        // B: random back-pressure
        while ($urandom_range(0, 2) == 0) @(negedge clk);
        bready = 1;
        #1;
        while (!bus.bvalid) begin @(negedge clk); #1; end
        check(bus.bid == id, $sformatf("BID %0d expected %0d", bus.bid, id));
        check(bus.bresp == ((bad || !wlast_ok) ? 2'b11 : 2'b00),
              $sformatf("BRESP %0d for write a=%h len=%0d size=%0d burst=%0d wlast_beat=%0d",
                        bus.bresp, a, l, s, b, wlast_beat));
        if (bus.bresp == 2'b11) slverr_seen++;
        @(negedge clk);
        bready = 0;
        wr_bursts++;
    endtask

    task automatic read_burst(logic [3:0] id, logic [31:0] a, int l, int s, logic [1:0] b);
        bit bad = ref_bad(a, l, s, b);
        @(negedge clk);
        repeat ($urandom_range(0, 2)) @(negedge clk);
        arvalid = 1; arid = id; araddr = a; arlen = 8'(l); arsize = 3'(s); arburst = b;
        #1;
        while (!bus.arready) begin @(negedge clk); #1; end
        @(negedge clk);
        arvalid = 0;

        for (int n = 0; n <= l; n++) begin
            logic [31:0] ba = ref_addr(a, n, l, s, b);
            while ($urandom_range(0, 3) == 0) @(negedge clk);
            rready = 1;
            #1;
            while (!bus.rvalid) begin @(negedge clk); #1; end
            check(bus.rid == id && bus.rlast == (n == l),
                  $sformatf("read a=%h beat %0d/%0d: rid=%0d rlast=%0b", a, n, l, bus.rid, bus.rlast));
            if (bad)
                check(bus.rresp == 2'b11, $sformatf("read a=%h: expected DECERR", a));
            else
                check(bus.rresp == 2'b00 && bus.rdata == ref_word(ba),
                      $sformatf("read a=%h len=%0d size=%0d burst=%0d beat %0d (addr %h): rdata=%h exp=%h",
                                a, l, s, b, n, ba, bus.rdata, ref_word(ba)));
            @(negedge clk);
            rready = 0;
            rd_beats++;
        end
        if (bad) slverr_seen++;
        // No extra beat after RLAST
        #1;
        check(!bus.rvalid, "RVALID after RLAST");
        rd_bursts++;
    endtask

    assign error_total = errors;
    // Separated channel tasks make it possible to queue AW/AR ahead of data.
    task automatic send_aw(int id, logic [31:0] a, int l);
        @(negedge clk);
        awvalid=1; awid=4'(id); awaddr=a; awlen=8'(l); awsize=2; awburst=1;
        #1; while (!bus.awready) begin @(negedge clk); #1; end
        @(negedge clk); awvalid=0;
    endtask
    task automatic send_w(logic [31:0] a, int l);
        for (int n=0;n<=l;n++) begin
            @(negedge clk); wvalid=1; wdata=32'hCAFE0000+n; wstrb=15; wlast=(n==l);
            #1; while (!bus.wready) begin @(negedge clk); #1; end
            @(negedge clk); wvalid=0; wlast=0;
            for (int j=0;j<4;j++) ref_mem[int'(a)+n*4+j] = 8'((32'hCAFE0000+n) >> (j*8));
        end
    endtask
    task automatic get_b(int id);
        @(negedge clk); bready=1;
        #1; while (!bus.bvalid) begin @(negedge clk); #1; end
        check(bus.bid==4'(id) && bus.bresp==0, "pipelined B ID/response mismatch");
        @(negedge clk); bready=0;
    endtask
    task automatic send_ar(int id, logic [31:0] a, int l);
        @(negedge clk); arvalid=1; arid=4'(id); araddr=a; arlen=8'(l); arsize=2; arburst=1;
        #1; while (!bus.arready) begin @(negedge clk); #1; end
        @(negedge clk); arvalid=0;
    endtask
    task automatic get_r_known(int id, logic [31:0] a, int l);
        for(int n=0;n<=l;n++) begin
            @(negedge clk); rready=1; #1;
            while(!bus.rvalid) begin @(negedge clk); #1; end
            check(bus.rid==4'(id) && bus.rresp==0 && bus.rdata==ref_word(a+32'(n*4)) && bus.rlast==(n==l),
                  "same-ID read ordering/data mismatch");
            @(negedge clk); rready=0;
        end
    endtask
    // Receive two queued reads in either cross-slave completion order.
    task automatic get_two_reads;
        int beats[2];
        int k;
        beats[0]=0; beats[1]=0;
        repeat (8) begin
            repeat ($urandom_range(1,3)) @(negedge clk);
            rready=1; #1;
            while (!bus.rvalid) begin @(negedge clk); #1; end
            k = (bus.rid == 4'd2) ? 0 : 1;
            check(bus.rid==2 || bus.rid==3, "queued RID unknown");
            check(bus.rresp==0 && bus.rdata==ref_word((k==0 ? 32'h400 : 32'h1400)+beats[k]*4),
                  "queued R data mismatch");
            check(bus.rlast == (beats[k]==3), "queued RLAST mismatch");
            beats[k]++;
            @(negedge clk); rready=0;
        end
        check(beats[0]==4 && beats[1]==4, "queued read beat totals mismatch");
    endtask

    initial begin
        for (int i=0;i<8192;i++) ref_mem[i]=0;
        wait(resetn); @(negedge clk);
        if (MASTER==0) begin
            // Near-boundary legal cases, including unaligned first beats.
            write_burst(1,32'hFF8,1,2,1); read_burst(1,32'hFF8,1,2,1);
            write_burst(1,32'hFFF,0,2,1); read_burst(1,32'hFFC,0,2,1);
            write_burst(1,32'hFFD,0,1,1); read_burst(1,32'hFFC,0,2,1);
            // Crossings must DECERR before either real slave sees an address.
            write_burst(4,32'hFF8,2,2,1); read_burst(4,32'hFF8,2,2,1);
            write_burst(5,32'hFFF,1,0,1); read_burst(5,32'hFFF,1,0,1);
            write_burst(6,32'hFFC,255,2,1); read_burst(6,32'hFFC,255,2,1);
            write_burst(7,32'h1FFC,1,2,1); read_burst(7,32'h1FFC,1,2,1);
            // Unmapped multi-beat bursts use the same error sink.
            write_burst(8,32'h8000,7,2,1); read_burst(8,32'h8000,7,2,1);
            // Rejected writes must not corrupt either side of the boundary.
            read_burst(0,32'hFF0,3,2,1); read_burst(0,32'h1000,7,2,1);
            read_burst(0,32'h1FF0,3,2,1);
            // FIXED and WRAP near the page edge are not INCR crossings.
            write_burst(1,32'hFFC,15,2,0); read_burst(1,32'hFFC,15,2,0);
            write_burst(1,32'hFFC,15,2,2); read_burst(1,32'hFC0,15,2,1);
            // 256-beat legal transfer exercises 8-bit LEN + 1 widening.
            write_burst(1,32'h400,255,2,1); read_burst(1,32'h400,255,2,1);
            // Two accepted AWs before any W or B; W follows AW order.
            send_aw(2,32'h400,3); send_aw(3,32'h1400,3);
            send_w(32'h400,3); send_w(32'h1400,3);
            // Arbitration starts with port 0 in this idle/drained case.
            // Receive independently of order instead of assuming a winner.
            begin
                bit seen2,seen3;
                seen2=0; seen3=0;
                repeat(2) begin
                    @(negedge clk); bready=1; #1;
                    while(!bus.bvalid) begin @(negedge clk); #1; end
                    check(bus.bresp==0,"queued B response mismatch");
                    if(bus.bid==2) begin check(!seen2,"duplicate BID2"); seen2=1; end
                    else if(bus.bid==3) begin check(!seen3,"duplicate BID3"); seen3=1; end
                    else check(0,"unknown queued BID");
                    @(negedge clk); bready=0;
                end
                check(seen2 && seen3,"missing queued B");
            end
            send_ar(2,32'h400,3); send_ar(3,32'h1400,3); get_two_reads();
            // Same-ID transfers to a different port must wait for retirement.
            send_aw(9,32'h500,3);
            fork
                begin send_aw(9,32'h1500,3); end
                begin
                    send_w(32'h500,3);
                    repeat(5) @(negedge clk);
                    #1; check(awvalid && !bus.awready,"same-ID AW switched slave before B");
                    get_b(9);
                end
            join
            send_w(32'h1500,3); get_b(9);
            send_ar(9,32'h500,3);
            fork
                begin send_ar(9,32'h1500,3); end
                begin
                    repeat(5) @(negedge clk);
                    #1; check(arvalid && !bus.arready,"same-ID AR switched slave before RLAST");
                    get_r_known(9,32'h500,3);
                end
            join
            get_r_known(9,32'h1500,3);
            prepared=1;
        end else wait(prep_done);
        @(negedge clk);
        // Masters contend for both slaves, but use separate memory locations.
        repeat(NUM_RANDOM) begin
            logic [31:0] a;
            int l,s,b;
            b=$urandom_range(0,2); s=$urandom_range(0,2);
            l=(b==2) ? ((2 << $urandom_range(0,3))-1) : $urandom_range(0,15);
            a=32'($urandom_range(0,1)*4096 + 256 + MASTER*2048 + $urandom_range(0,63)*4);
            if(b!=2) a=a+32'($urandom_range(0,(1<<s)-1));
            write_burst(4'($urandom()),a,l,s,2'(b));
            read_burst(4'($urandom()),a,l,s,2'(b));
        end
        repeat(5) @(negedge clk);
        $display("master=%0d writes=%0d Wbeats=%0d reads=%0d Rbeats=%0d DECERRs=%0d errors=%0d",
            MASTER,wr_bursts,wr_beats,rd_bursts,rd_beats,slverr_seen,errors);
        done=1;
    end
endmodule

module axi_crossbar_burst_tb;
    logic clk=0, resetn=0, test_done=0;
    initial while(!test_done) #5 clk=~clk;
    axi_if #(.ID_WIDTH(4)) up[2](.ACLK(clk),.ARESETn(resetn));
    axi_if #(.ID_WIDTH(5)) down[2](.ACLK(clk),.ARESETn(resetn));
    logic [1:0] prepared,done;
    int errors[2],up_checks[2],down_checks[2];
    int wr_inflight[2], rd_inflight[2], max_wr[2], max_rd[2];
    axi_crossbar_top #(.NUM_MASTERS(2),.NUM_SLAVES(2),.MAX_OUTSTANDING(4),
        .SLAVE_BASE_ADDR({32'h1000,32'h0}),
        .SLAVE_ADDR_SIZE({32'h1000,32'h1000})) dut(.s_axi(up),.m_axi(down));
    for(genvar g=0;g<2;g++) begin: gen
        axi_day26_agent #(.MASTER(g)) agent(.clk(clk),.resetn(resetn),.prep_done(prepared[0]),
            .prepared(prepared[g]),.done(done[g]),.error_total(errors[g]),.bus(up[g]));
        axi_slave_burst #(.ID_WIDTH(5),.MEM_DEPTH(1024)) mem(.axi(down[g]));
        axi_burst_protocol_checker uc(.axi(up[g]),.error_count(up_checks[g]));
        axi_burst_protocol_checker dc(.axi(down[g]),.error_count(down_checks[g]));
        // Independent formula: last beat address must remain on the first page.
        function automatic bit crossing(logic [31:0] a, int l,int s,int b);
            longint last_address;
            last_address=(64'(a)/(64'd1<<s))*(64'd1<<s)+64'(l)*(64'd1<<s);
            return b==1 && (64'(a)>>12)!=(last_address>>12);
        endfunction
        always @(posedge clk) begin
            if(resetn) begin
                if(down[g].awvalid)
                    if(crossing(down[g].awaddr,int'(down[g].awlen),int'(down[g].awsize),int'(down[g].awburst)))
                        $fatal(1,"crossing AW reached real slave %0d",g);
                if(down[g].arvalid)
                    if(crossing(down[g].araddr,int'(down[g].arlen),int'(down[g].arsize),int'(down[g].arburst)))
                        $fatal(1,"crossing AR reached real slave %0d",g);
                wr_inflight[g] = wr_inflight[g] + int'(up[g].awvalid && up[g].awready) - int'(up[g].bvalid && up[g].bready);
                rd_inflight[g] = rd_inflight[g] + int'(up[g].arvalid && up[g].arready) - int'(up[g].rvalid && up[g].rready && up[g].rlast);
                if(wr_inflight[g]>max_wr[g]) max_wr[g]=wr_inflight[g];
                if(rd_inflight[g]>max_rd[g]) max_rd[g]=rd_inflight[g];
                if(wr_inflight[g]>4 || rd_inflight[g]>4 || wr_inflight[g]<0 || rd_inflight[g]<0)
                    $fatal(1,"outstanding count out of range");
            end else begin
                wr_inflight[g]=0;rd_inflight[g]=0;max_wr[g]=0;max_rd[g]=0;
            end
        end
    end
    initial begin
        repeat(4) @(negedge clk); resetn=1;
        wait(&done); repeat(4) @(negedge clk);
        for(int g=0;g<2;g++) begin
            if(errors[g] || up_checks[g] || down_checks[g] || wr_inflight[g] || rd_inflight[g])
                $fatal(1,"DAY 26 CROSSBAR FAILED");
        end
        if(max_wr[0]<2 || max_rd[0]<2) $fatal(1,"multiple outstanding not exercised");
        $display("master0 peak outstanding: writes=%0d reads=%0d",max_wr[0],max_rd[0]);
        $display("DAY 26 CROSSBAR PASSED");
        test_done=1; $finish;
    end
    initial begin
        #20_000_000; $fatal(1,"DAY 26 CROSSBAR FAILED: timeout");
    end
endmodule
