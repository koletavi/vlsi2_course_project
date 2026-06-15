module compressor #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64, parameter GROUP_SIZE = 8 ) (
    input logic clk,
    input logic nrst,
    input logic start,
    input logic [WORD_SIZE-1:0] in [PACKET_SIZE-1:0],
    output logic [WORD_SIZE-1:0] out [PACKET_SIZE-1:0],
    output logic valid,
    output logic [$clog2(PACKET_SIZE+1)-1:0] out_count,
    output logic [WORD_SIZE-1:0] key_out
);

logic[WORD_SIZE-1:0] db_out [PACKET_SIZE-1:0];
logic [PACKET_SIZE-1:0] bit_out [WORD_SIZE-1:0];
logic dn_valid;
logic bit_valid;

// delta negabinary encoding
diffnb #(.WORD_SIZE(WORD_SIZE), .PACKET_SIZE(PACKET_SIZE)) dn_i (
    clk(clk),
    nrst(nrst),
    .in(in),
    .start(start),
    .valid(dn_valid),
    .out(db_out)
);

// bit shuffle/transpose
bit_transpose #(.WORD_SIZE(WORD_SIZE), .PACKET_SIZE(PACKET_SIZE)) bit_i (
    clk(clk),
    nrst(nrst),
    .in(db_out),
    .start(dn_valid),
    .valid(bit_valid),
    .out(bit_out)
);

// repeated zero elimination
rze #(.WORD_SIZE(WORD_SIZE), .PACKET_SIZE(PACKET_SIZE), .GROUP_SIZE(GROUP_SIZE)) rze_i (
    clk(clk),
    nrst(nrst),
    .in(bit_out),
    .start(bit_valid),
    .valid(valid),
    .out(out),
    .out_count(out_count),
    .key_out(key_out)
);

endmodule