//------------------------------------------------------------------------------
// URZE - Unpack Repeated Zero Elimination (Stage 1 of the decompressor)
//------------------------------------------------------------------------------
// 
// Purpose:
//   Inverse of the RZE stage. Given the dense packed_planes payload together
//   with the original key bitmask, scatter each stored plane back to its
//   original bit-position in the transposed plane array.
// 
//   Zero planes (key bit == 0) are re-inserted as all-zero PACKET_SIZE-wide
//   vectors. Non-zero planes are taken sequentially from packed_planes[0 .. in_count-1].
// 
//   Group-wise parallel unpackers (unpack_group) mirror the GROUP_SIZE-wide
//   packers used in the compressor RZE stage.
// 
// Latency: 1 cycle (combinational scatter + output registers)
//------------------------------------------------------------------------------
module urze #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64 , parameter GROUP_SIZE = 8 ) (
    input logic clk,
    input logic nrst,
    input logic start,
    input logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0],
    input logic [$clog2(PACKET_SIZE+1)-1:0] in_count,
    input logic [WORD_SIZE-1:0] key_in,
    output logic valid,
    output logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0]
);

localparam GROUPS = WORD_SIZE / GROUP_SIZE;
localparam GROUP_COUNT_WIDTH = $clog2(GROUP_SIZE+1);
localparam PACKET_PTR_WIDTH = $clog2(PACKET_SIZE+1);

logic [GROUP_COUNT_WIDTH-1:0] group_count [GROUPS-1:0];
logic [PACKET_SIZE-1:0] packed_group [GROUPS-1:0][GROUP_SIZE-1:0];
logic [PACKET_SIZE-1:0] scattered_planes [WORD_SIZE-1:0];

//------------------------------------------------------------------------------
// Derive per-group dense lengths from the key popcount of each GROUP_SIZE slice.
//------------------------------------------------------------------------------
always_comb begin
    for (int g = 0; g < GROUPS; g++) begin
        logic [GROUP_SIZE-1:0] key_slice;
        for (int j = 0; j < GROUP_SIZE; j++)
            key_slice[j] = key_in[g * GROUP_SIZE + j];
        group_count[g] = GROUP_COUNT_WIDTH'($countones(key_slice));
    end
end

//------------------------------------------------------------------------------
// Slice the globally dense packed_planes array back into per-group chunks.
//------------------------------------------------------------------------------
always_comb begin
    logic [PACKET_PTR_WIDTH-1:0] ptr;
    ptr = '0;
    for (int g = 0; g < GROUPS; g++)
        for (int j = 0; j < GROUP_SIZE; j++)
            packed_group[g][j] = '0;
    for (int g = 0; g < GROUPS; g++) begin
        for (int j = 0; j < group_count[g]; j++) begin
            packed_group[g][j] = packed_planes[ptr];
            ptr = ptr + 1;
        end
    end
end

//------------------------------------------------------------------------------
// Scatter each group's dense planes back to their original slots in parallel.
//------------------------------------------------------------------------------
generate
    for (genvar i = 0; i < GROUPS; i++) begin : gen_unpacker
        logic [PACKET_SIZE-1:0] out_slice [GROUP_SIZE-1:0];
        logic [GROUP_SIZE-1:0] key_slice;

        for (genvar j = 0; j < GROUP_SIZE; j++) begin
            assign key_slice[j] = key_in[i * GROUP_SIZE + j];
        end

        unpack_group #(.PACKET_SIZE(PACKET_SIZE), .GROUP_SIZE(GROUP_SIZE)) unpack_i (
            .key(key_slice),
            .in(packed_group[i]),
            .out(out_slice)
        );

        for (genvar j = 0; j < GROUP_SIZE; j++) begin
            assign scattered_planes[i * GROUP_SIZE + j] = out_slice[j];
        end
    end
endgenerate

// FIXME: an extra pipeline stage can be inserted here if the scatter
//        combinational logic ends up on the critical path.

//------------------------------------------------------------------------------
// Final pipeline stage of URZE.
// Register the restored transposed plane array and pulse 'valid' for one cycle.
//------------------------------------------------------------------------------
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        transposed_planes <= '{default: '0};
    end else if (start) begin
        for (int i = 0; i < WORD_SIZE; i++)
            transposed_planes[i] <= scattered_planes[i];
    end
end

always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        valid <= 0;
    end else if (start) begin
        valid <= 1;
    end else begin
        valid <= 0;
    end
end

endmodule