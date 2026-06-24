//------------------------------------------------------------------------------
// Pack Group - Dense packing of a small group of planes (helper for RZE)
//------------------------------------------------------------------------------
// 
// Purely combinational helper used inside RZE.
// 
// Given:
//   - a GROUP_SIZE-wide key (bit i set => the corresponding plane is non-zero)
//   - GROUP_SIZE planes (each PACKET_SIZE bits wide)
// 
// It emits:
//   - a densely packed array of the non-zero planes (in the same relative order)
//   - the number of non-zero planes found in this group
// 
// Several of these groups are instantiated in parallel by RZE and then
// concatenated to form the final dense list of surviving bit-planes.
//------------------------------------------------------------------------------
module pack_group #( parameter PACKET_SIZE = 64, parameter GROUP_SIZE = 8 ) (
    input logic [GROUP_SIZE-1:0] key,
    input logic [PACKET_SIZE-1:0] in [GROUP_SIZE-1:0],
    output logic [PACKET_SIZE-1:0] out [GROUP_SIZE-1:0],
    output logic [$clog2(GROUP_SIZE+1)-1:0] count
);

// Walk the group. For every plane whose key bit is set, copy it to the next
// free slot in the output. This produces a dense (zero-free) group.
always_comb begin
    automatic logic [$clog2(GROUP_SIZE+1)-1:0] ptr = 0;
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