//------------------------------------------------------------------------------
// RZE - Repeated Zero Elimination (Stage 3 of the compressor)
//------------------------------------------------------------------------------
// 
// Purpose:
//   After the bit-plane transpose, each of the WORD_SIZE inputs represents one
//   complete bit-plane across the original PACKET_SIZE words.
// 
//   This stage:
//     1. Identifies which planes are entirely zero (key[i] = |plane[i]).
//     2. Packs only the non-zero planes into a dense array using GROUP_SIZE-wide
//        parallel packers (for hardware efficiency / parallelism).
//     3. Produces a dense list of the surviving planes together with the original
//        key (so a decompressor can scatter them back) and a count.
// 
//   The output "packed_planes" contains the kept planes in the low out_count
//   entries; higher entries are zeroed for cleanliness.
// 
//   This is the only stage that actually reduces the data volume.
// 
// Latency: 1 cycle (combinational packing + output registers)
//------------------------------------------------------------------------------
module rze #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64 , parameter GROUP_SIZE = 8 ) (
    input logic clk,
    input logic nrst,
    input logic start,
    input logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0],
    output logic valid,
    output logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0],
    output logic [$clog2(PACKET_SIZE+1)-1:0] out_count,
    output logic [WORD_SIZE-1:0] key_out
);



localparam GROUPS = WORD_SIZE / GROUP_SIZE;
localparam PACKET_PTR_WIDTH = $clog2(PACKET_SIZE+1);

logic [WORD_SIZE-1:0] key;

//------------------------------------------------------------------------------
// Build a one-hot-style key: key[i] == 1 means the i-th bit-plane is non-zero.
// This key is later used by the decompressor to know where to place each
// packed plane back into the original bit-position ordering.
// 
// The logic is purely combinational and is not on the critical path, so we
// keep it outside the clocked stage (saves one cycle of latency).
//------------------------------------------------------------------------------
always_comb begin
        key = '0;
        for (int i = 0; i < WORD_SIZE; i++) begin
            key[i] = |transposed_planes[i];
        end
end


logic [PACKET_SIZE-1:0] packed_group [GROUPS-1:0][GROUP_SIZE-1:0];
logic [$clog2(GROUP_SIZE+1)-1:0] group_count [GROUPS-1:0];
logic [PACKET_SIZE-1:0] dense_data [WORD_SIZE-1:0];

//------------------------------------------------------------------------------
// Pack the non-zero planes in parallel using GROUP_SIZE-wide packers.
// Each pack_group takes a slice of  GROUP_SIZE  planes + the corresponding
// bits from the key and emits a densely packed group plus a count.
//------------------------------------------------------------------------------
generate
    for (genvar i = 0; i < GROUPS; i++) begin : gen_packer
        logic [PACKET_SIZE-1:0] in_slice [GROUP_SIZE-1:0];
        logic [GROUP_SIZE-1:0] key_slice;

        // Slice the plane array and the key for this group of GROUP_SIZE planes.
        for (genvar j = 0; j < GROUP_SIZE; j++) begin
            assign in_slice[j] = transposed_planes[i*GROUP_SIZE + j];
            assign key_slice[j] = key[i*GROUP_SIZE + j];
        end

        pack_group #(.PACKET_SIZE(PACKET_SIZE), .GROUP_SIZE(GROUP_SIZE)) pack_i (
            .key(key_slice),
            .in(in_slice),
            .out(packed_group[i]),
            .count(group_count[i])
        );

    end
endgenerate

// FIXME: an extra pipeline stage can be inserted here if the packing
//        combinational logic ends up on the critical path.

//------------------------------------------------------------------------------
// Assemble the independently packed groups into one dense array (dense_data).
// The result is a contiguous list of all surviving planes; higher indices
// remain zero because we initialized the array to zero.
//------------------------------------------------------------------------------
always_comb begin 
    logic [PACKET_PTR_WIDTH-1:0] ptr;
    ptr= '0;
    dense_data = '{default: '0};
    for (int i = 0; i < GROUPS; i++) begin
        for (int j = 0; j < GROUP_SIZE; j++) begin
            if (j < group_count[i]) begin
                dense_data[ptr] = packed_group[i][j];
                ptr = ptr + 1;
            end
        end
    end
end


//------------------------------------------------------------------------------
// Final (only) pipeline stage of RZE.
// We register the three outputs that a downstream block (or decompressor) needs:
//   packed_planes - the actual compressed payload (dense non-zero planes)
//   key_out       - tells the receiver which bit positions the planes belong to
//   out_count     - tells the receiver how many planes are valid
//
// 'valid' is a one-cycle pulse that indicates the outputs are stable.
//------------------------------------------------------------------------------
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        packed_planes <= '{default: '0};
    end else if (start) begin
        packed_planes <= dense_data;
    end
end

always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        key_out <= '0;
    end else if (start) begin
        key_out <= key;
    end
end

always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out_count <= '0;
    end else if (start) begin
        out_count <= ptr;
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