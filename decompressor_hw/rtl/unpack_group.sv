
//------------------------------------------------------------------------------
// Unpack Group - Scatter dense packed planes back into group slots (helper for URZE)
//------------------------------------------------------------------------------
// 
// Purely combinational helper used inside URZE (inverse of pack_group).
// 
// Given:
//   - a GROUP_SIZE-wide key (bit i set => the corresponding plane was non-zero)
//   - GROUP_SIZE densely packed planes (only the non-zero entries, in order)
// 
// It emits:
//   - GROUP_SIZE planes restored to their original bit-position slots
//     (zero planes are inserted where key bits are clear)
// 
// Several of these groups are instantiated in parallel by URZE after the dense
// packed payload is sliced back into per-group chunks.
//------------------------------------------------------------------------------
module unpack_group #( parameter PACKET_SIZE = 64, parameter GROUP_SIZE = 8 ) (
    input logic [GROUP_SIZE-1:0] key,
    input logic [PACKET_SIZE-1:0] in [GROUP_SIZE-1:0],
    output logic [PACKET_SIZE-1:0] out [GROUP_SIZE-1:0]
);

// Walk the group. For every plane whose key bit is set, take the next dense
// entry from 'in' and place it at the original slot. Cleared key bits become zero.
always_comb begin
    automatic logic [$clog2(GROUP_SIZE+1)-1:0] ptr = 0;
    out = '{default: '0};
    for (int i = 0; i < GROUP_SIZE; i++) begin
        if (key[i]) begin
            out[i] = in[ptr];
            ptr++;
        end
    end
end

endmodule