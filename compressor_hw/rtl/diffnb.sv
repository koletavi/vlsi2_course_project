
//------------------------------------------------------------------------------
// DIFFNB - Delta + Negabinary Encoding (Stage 1 of the compressor)
//------------------------------------------------------------------------------
// 
// Purpose:
//   Applies a simple first-order predictor (delta = current - previous) followed
//   by a cheap negabinary (base -2) representation. This transform turns small
//   differences (very common in scientific / posit data) into bit patterns that
//   have many leading zeros after the subsequent bit-plane transpose.
// 
//   The first word of the packet is used as-is for the delta (no previous value).
// 
//   This stage is the software-equivalent of the "DIFFNB" block in the LC
//   framework and matches the algorithm used in the SW reference model.
// 
// Latency: 1 cycle (combinational logic + output register)
//------------------------------------------------------------------------------
module diffnb #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64 ) (
    input logic clk,
    input logic nrst,
    input logic [WORD_SIZE-1:0] data_packet [PACKET_SIZE-1:0],
    input logic start,
    output logic valid,
    output logic [WORD_SIZE-1:0] encoded_packet [PACKET_SIZE-1:0]
); 

localparam NB_MASK = {WORD_SIZE/2{2'b10}};

logic [WORD_SIZE-1:0] delta [PACKET_SIZE-1:0];
logic [WORD_SIZE-1:0] nb [PACKET_SIZE-1:0];

// Compute raw delta for every word in the packet.
// For the first word we have no previous value, so delta[0] = data_packet[0].
// All values are treated as unsigned bit patterns; negative deltas appear in 2's-complement form.
always_comb begin
    delta[0] = data_packet[0];
    for (int i = 1; i < PACKET_SIZE; i++) begin
        delta[i] = data_packet[i] - data_packet[i-1];
    end
end 

// FIXME: we can add a pipeline stage here if the critical path is too long,
//        but it will increase the latency by one cycle.

// Apply the negabinary transform to every delta.
// The cheap (delta + NB_MASK) ^ NB_MASK operation produces a representation
// that, after bit-plane transpose, yields many all-zero planes for typical data.
always_comb begin
    for (int i = 0; i < PACKET_SIZE; i++) begin
        nb[i] = (delta[i] + NB_MASK) ^ NB_MASK;
    end
end

// Register the encoded (delta-negabinary) packet. This is the output of Stage 1.
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        encoded_packet <= '0;
        valid <= 0;
    end else if (start) begin
        for (int i = 0; i < PACKET_SIZE; i++) begin
            encoded_packet[i] <= nb[i];
        end
        valid <= 1;
    end else begin
        valid <= 0;
    end
end 


endmodule 