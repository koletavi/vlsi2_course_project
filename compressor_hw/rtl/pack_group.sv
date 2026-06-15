.// Pack Group module - combinational logic
module pack_group #( parameter PACKET_SIZE = 64, parameter GROUP_SIZE = 8 ) (
    input logic [GROUP_SIZE-1:0] key,
    input logic [PACKET_SIZE-1:0] in [GROUP_SIZE-1:0],
    output logic [PACKET_SIZE-1:0] out [GROUP_SIZE-1:0],
    output logic [$clog2(GROUP_SIZE+1)-1:0] count
);

// pack the input data based on the key.
// the key indicates which input data is valid, and the output is packed accordingly.
always_comb begin
    logic [$clog2(GROUP_SIZE+1)-1:0] ptr = 0;
    out = '{default: '0};
    for (int i = 0; i < GROUP_SIZE; i++) begin
        if (key[i]) begin
            out[ptr] = in[i];
            ptr++;
        end
    end
    count = ptr;
end

endmodule