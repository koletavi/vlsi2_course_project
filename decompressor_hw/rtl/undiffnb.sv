
//------------------------------------------------------------------------------
// UNDIFFNB - Inverse Delta + Negabinary Decoding (Stage 3 of the decompressor)
//------------------------------------------------------------------------------
// 
// Purpose:
//   Reverses the DIFFNB transform applied by the compressor:
//     1. Invert the cheap negabinary step: delta = (nb ^ NB_MASK) - NB_MASK
//     2. Integrate deltas back into original words via cumulative sum
//        (curr[i] = curr[i-1] + delta[i], with curr[0] = delta[0])
// 
//   This stage is the software-equivalent of the inverse DIFFNB block and
//   matches the algorithm used in decompressor_sw/posit_decompress.py.
// 
// Latency: 1 cycle (combinational logic + output register)
//------------------------------------------------------------------------------
module undiffnb #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64 ) (
    input logic clk,
    input logic nrst,
    input logic [WORD_SIZE-1:0] encoded_packet [PACKET_SIZE-1:0],
    input logic start,
    output logic valid,
    output logic [WORD_SIZE-1:0] decoded_packet [PACKET_SIZE-1:0]
); 

localparam NB_MASK = {WORD_SIZE/2{2'b10}};

logic [WORD_SIZE-1:0] delta [PACKET_SIZE-1:0];
logic [WORD_SIZE-1:0] recovered [PACKET_SIZE-1:0];

// Invert the negabinary transform for every encoded word.
always_comb begin
    for (int i = 0; i < PACKET_SIZE; i++) begin
        delta[i] = (encoded_packet[i] ^ NB_MASK) - NB_MASK;
    end
end 

// FIXME: we can add a pipeline stage here if the critical path is too long,
//        but it will increase the latency by one cycle.

// Integrate deltas to recover the original packet (cumulative sum).
always_comb begin
    logic [WORD_SIZE-1:0] prev;
    prev = delta[0];
    recovered[0] = prev;
    for (int i = 1; i < PACKET_SIZE; i++) begin
        recovered[i] = prev + delta[i];
        prev = recovered[i];
    end
end

// Register the decoded packet. This is the output of Stage 3.
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        decoded_packet <= '{default: '0};
        valid <= 0;
    end else if (start) begin
        for (int i = 0; i < PACKET_SIZE; i++) begin
            decoded_packet[i] <= recovered[i];
        end
        valid <= 1;
    end else begin
        valid <= 0;
    end
end 


endmodule