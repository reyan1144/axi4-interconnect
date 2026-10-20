module axi_arbiter_rr #(
    parameter int NUM_REQUESTERS = 4,
    parameter int INDEX_WIDTH =
        (NUM_REQUESTERS <= 1) ? 1 : $clog2(NUM_REQUESTERS)
) (
    input  logic clk,
    input  logic resetn,

    input  logic [NUM_REQUESTERS-1:0] request,
    input  logic grant_ready,

    output logic [NUM_REQUESTERS-1:0] grant,
    output logic grant_valid,
    output logic [INDEX_WIDTH-1:0] grant_index
);

    logic [INDEX_WIDTH-1:0] priority_pointer;
    logic [INDEX_WIDTH-1:0] locked_index;
    logic locked;

    integer candidate;

    // Select a requester without depending on grant_ready.
    always_comb begin
        grant       = '0;
        grant_valid = 1'b0;
        grant_index = '0;
        candidate   = 0;

        if (resetn) begin
            if (locked) begin
                grant[locked_index] = 1'b1;
                grant_valid         = 1'b1;
                grant_index         = locked_index;
            end else begin
                for (int offset = 0;
                     offset < NUM_REQUESTERS;
                     offset++) begin

                    candidate = int'(priority_pointer) + offset;

                    if (candidate >= NUM_REQUESTERS)
                        candidate = candidate - NUM_REQUESTERS;

                    if (!grant_valid && request[candidate]) begin
                        grant[candidate] = 1'b1;
                        grant_valid      = 1'b1;
                        grant_index      = INDEX_WIDTH'(candidate);
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            priority_pointer <= '0;
            locked_index     <= '0;
            locked           <= 1'b0;
        end else begin
            if (grant_valid && grant_ready) begin
                if (grant_index == NUM_REQUESTERS - 1)
                    priority_pointer <= '0;
                else
                    priority_pointer <= grant_index + 1'b1;

                locked <= 1'b0;
            end else if (grant_valid && !locked) begin
                locked_index <= grant_index;
                locked       <= 1'b1;
            end
        end
    end

endmodule