// compressor.sv
// Top-level module for a 3-stage hardware compressor optimized for posit-encoded data.
// 
// Target configuration (configurable via parameters):
//   - WORD_SIZE   = 32 bits per word
//   - PACKET_SIZE = 64 words per packet
// 
// Pipeline (one clock cycle per stage):
//   1. DIFFNB       - Delta + Negabinary encoding (first-order predictor + cheap negabinary transform)
//   2. BIT          - Bit-plane transpose (reorganizes data so that RZE can drop entire zero planes)
//   3. RZE          - Repeated Zero Elimination (drop all-zero bit-planes, pack survivors densely)
// 
// Outputs after a packet is processed:
//   - packed_planes : Densely packed non-zero bit-planes (each plane is PACKET_SIZE bits wide)
//   - key_out       : Bitmask (WORD_SIZE bits) indicating which original bit positions had non-zero planes
//   - out_count     : Number of valid planes present in packed_planes[0 .. out_count-1]
// 
// Interface behavior:
//   - Assert 'start' with a full packet on data_packet[]
//   - 'valid' pulses for one cycle when packed_planes, key_out, and out_count are ready
// 
// Notes:
//   - The design currently assumes complete packets of PACKET_SIZE words.
//   - All stages are intentionally kept to one cycle each for simplicity.

// FIXME: additional pipeline stages can be added between the modules if the critical path
//        is too long (each added stage increases latency by one cycle).
// FIXME: add support for partial packets (requires extra logic to handle variable packet length).
module compressor #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64, parameter GROUP_SIZE = 8 ) (
    input logic clk,
    input logic nrst,
    input logic start,
    input logic [WORD_SIZE-1:0] data_packet [PACKET_SIZE-1:0],
    output logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0],
    output logic valid,
    output logic [$clog2(PACKET_SIZE+1)-1:0] out_count,
    output logic [WORD_SIZE-1:0] key_out
);

logic[WORD_SIZE-1:0] encoded_packet [PACKET_SIZE-1:0];
logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0];
logic dn_valid;
logic bit_valid;

// delta negabinary encoding
diffnb #(.WORD_SIZE(WORD_SIZE), .PACKET_SIZE(PACKET_SIZE)) dn_i (
    .clk(clk),
    .nrst(nrst),
    .data_packet(data_packet),
    .start(start),
    .valid(dn_valid),
    .encoded_packet(encoded_packet)
);

// bit shuffle/transpose
bit_transpose #(.WORD_SIZE(WORD_SIZE), .PACKET_SIZE(PACKET_SIZE)) bit_i (
    .clk(clk),
    .nrst(nrst),
    .encoded_packet(encoded_packet),
    .start(dn_valid),
    .valid(bit_valid),
    .transposed_planes(transposed_planes)
);

// repeated zero elimination
rze #(.WORD_SIZE(WORD_SIZE), .PACKET_SIZE(PACKET_SIZE), .GROUP_SIZE(GROUP_SIZE)) rze_i (
    .clk(clk),
    .nrst(nrst),
    .transposed_planes(transposed_planes),
    .start(bit_valid),
    .valid(valid),
    .packed_planes(packed_planes),
    .out_count(out_count),
    .key_out(key_out)
);

endmodule