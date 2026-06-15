//------------------------------------------------------------------------------
// BIT - Bit-Plane Transpose (Stage 2 of the compressor)
//------------------------------------------------------------------------------
// 
// Purpose:
//   Performs a full transpose of the packet: 
//     from  PACKET_SIZE words  x  WORD_SIZE bits
//     to    WORD_SIZE bit-planes x  PACKET_SIZE bits
// 
//   After this stage each "word" in the data path represents one bit position
//   across the entire original packet. This view makes it possible for the
//   following RZE stage to identify and discard entire all-zero bit-planes,
//   which is the main source of compression for correlated data (e.g. posit
//   arrays after the DIFFNB predictor).
// 
//   The transpose itself is pure wiring (no logic) and is implemented with a
//   generate loop for clarity.
// 
// Latency: 1 cycle (wires + output register)
//------------------------------------------------------------------------------
module bit_transpose #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64 ) (
    input logic clk,
    input logic nrst,
    input logic [WORD_SIZE-1:0] encoded_packet [PACKET_SIZE-1:0],
    input logic start,
    output logic valid,
    output logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0]
);


    genvar i, j;
    generate
        logic [PACKET_SIZE-1:0] tw [WORD_SIZE-1:0];
        for (i = 0; i < WORD_SIZE; i++) begin : GEN_ROW
            for (j = 0; j < PACKET_SIZE; j++) begin : GEN_COL
                assign tw[i][j] = encoded_packet[j][i];
            end
        end
    endgenerate

// Register the transposed bit-planes and the valid flag.
// The transpose array 'tw' is pure combinational wiring.
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        transposed_planes <= '{default: '0};
        valid <= 0;
    end else if (start) begin
        for (int i = 0; i < WORD_SIZE; i++) begin
            transposed_planes[i] <= tw[i];
        end
        valid <= 1;
    end else begin
        valid <= 0;
    end
end

endmodule