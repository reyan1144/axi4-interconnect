module axi_addr_decoder #(
    parameter int ADDR_WIDTH = 32,
    parameter int NUM_SLAVES = 3,
    parameter int SLAVE_INDEX_WIDTH =
        (NUM_SLAVES <= 1) ? 1 : $clog2(NUM_SLAVES),

    parameter logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]
        SLAVE_BASE_ADDR = '0,

    parameter logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]
        SLAVE_ADDR_SIZE = '0
) (
    input  logic [ADDR_WIDTH-1:0]       address,

    output logic [NUM_SLAVES-1:0]       slave_select,
    output logic [SLAVE_INDEX_WIDTH-1:0] slave_index,
    output logic                         address_valid
);

    logic match_found;

    always_comb begin
        slave_select = '0;
        slave_index  = '0;
        match_found  = 1'b0;

        for (int i = 0; i < NUM_SLAVES; i++) begin
            if (!match_found &&
                address >= SLAVE_BASE_ADDR[i] &&
                address < (SLAVE_BASE_ADDR[i] + SLAVE_ADDR_SIZE[i])) begin

                slave_select[i] = 1'b1;
                slave_index     = SLAVE_INDEX_WIDTH'(i);
                match_found     = 1'b1;
            end
        end

        address_valid = match_found;
    end

endmodule