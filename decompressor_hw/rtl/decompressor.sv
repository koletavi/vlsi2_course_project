// decompressor.sv
// Top-level module for a 3-stage hardware decompressor optimized for posit-encoded data.
// 
// Target configuration (configurable via parameters):
//   - WORD_SIZE   = 32 bits per word
//   - PACKET_SIZE = 64 words per packet
// 
// Pipeline (one clock cycle per stage):
//   1. URZE        - Unpack Repeated Zero Elimination (scatter dense planes using key)
//   2. BIT         - Bit-plane transpose (self-inverse of the compressor BIT stage)
//   3. UNDIFFNB    - Inverse delta + negabinary decoding (cumulative sum predictor)
// 
// Inputs (produced by compressor.sv):
//   - packed_planes : Densely packed non-zero bit-planes (each plane is PACKET_SIZE bits wide)
//   - key_in        : Bitmask (WORD_SIZE bits) indicating which original bit positions had non-zero planes
//   - in_count      : Number of valid planes present in packed_planes[0 .. in_count-1]
// 
// Outputs after a packet is processed:
//   - data_packet[] : Recovered original PACKET_SIZE x WORD_SIZE-bit words
// 
// Interface behavior:
//   - Assert 'start' with compressed payload on packed_planes[], key_in, and in_count
//   - 'valid' pulses for one cycle when data_packet[] is ready
// 
// Notes:
//   - The design currently assumes complete packets of PACKET_SIZE words.
//   - All stages are intentionally kept to one cycle each for simplicity.

// FIXME: additional pipeline stages can be added between the modules if the critical path
//        is too long (each added stage increases latency by one cycle).
// FIXME: add support for partial packets (requires extra logic to handle variable packet length).
module decompressor #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64, parameter GROUP_SIZE = 8 ) (
    input logic clk,
    input logic nrst,
    input logic start,
    input logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0],
    input logic [$clog2(PACKET_SIZE+1)-1:0] in_count,
    input logic [WORD_SIZE-1:0] key_in,
    output logic [WORD_SIZE-1:0] data_packet [PACKET_SIZE-1:0],
    output logic valid
);

logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0];
logic [WORD_SIZE-1:0] encoded_packet [PACKET_SIZE-1:0];
logic urze_valid;
logic bit_valid;

// unpack repeated zero elimination
urze #(.WORD_SIZE(WORD_SIZE), .PACKET_SIZE(PACKET_SIZE), .GROUP_SIZE(GROUP_SIZE)) urze_i (
    .clk(clk),
    .nrst(nrst),
    .packed_planes(packed_planes),
    .in_count(in_count),
    .key_in(key_in),
    .start(start),
    .valid(urze_valid),
    .transposed_planes(transposed_planes)
);

// bit shuffle/transpose (self-inverse)
bit_transpose #(.WORD_SIZE(WORD_SIZE), .PACKET_SIZE(PACKET_SIZE)) bit_i (
    .clk(clk),
    .nrst(nrst),
    .transposed_planes(transposed_planes),
    .start(urze_valid),
    .valid(bit_valid),
    .encoded_packet(encoded_packet)
);

// inverse delta negabinary decoding
undiffnb #(.WORD_SIZE(WORD_SIZE), .PACKET_SIZE(PACKET_SIZE)) undn_i (
    .clk(clk),
    .nrst(nrst),
    .encoded_packet(encoded_packet),
    .start(bit_valid),
    .valid(valid),
    .decoded_packet(data_packet)
);

endmodule