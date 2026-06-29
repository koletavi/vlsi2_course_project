//------------------------------------------------------------------------------
// BIT - Bit-Plane Transpose (Stage 2 of the decompressor)
//------------------------------------------------------------------------------
// 
// Purpose:
//   Performs a full transpose of the packet: 
//     from  WORD_SIZE bit-planes x  PACKET_SIZE bits
//     to    PACKET_SIZE words  x  WORD_SIZE bits
// 
//   This is the inverse routing of the compressor's bit_transpose stage.
//   Because a matrix transpose is self-inverse, the module structure is
//   identical to the compressor implementation (only signal naming differs
//   to reflect the decompressor data flow).
// 
//   The transpose itself is pure wiring (no logic) and is implemented with a
//   generate loop for clarity.
// 
// Latency: 1 cycle (wires + output register)
//------------------------------------------------------------------------------
module bit_transpose #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64 ) (
    input logic clk,
    input logic nrst,
    input logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0],
    input logic start,
    output logic valid,
    output logic [WORD_SIZE-1:0] encoded_packet [PACKET_SIZE-1:0]
);


    genvar i, j;
    generate
        logic [WORD_SIZE-1:0] tw [PACKET_SIZE-1:0];
        for (i = 0; i < PACKET_SIZE; i++) begin : GEN_ROW
            for (j = 0; j < WORD_SIZE; j++) begin : GEN_COL
                assign tw[i][j] = transposed_planes[j][i];
            end
        end
    endgenerate

// Register the transposed words and the valid flag.
// The transpose array 'tw' is pure combinational wiring.
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        encoded_packet <= '{default: '0};
        valid <= 0;
    end else if (start) begin
        for (int i = 0; i < PACKET_SIZE; i++) begin
            encoded_packet[i] <= tw[i];
        end
        valid <= 1;
    end else begin
        valid <= 0;
    end
end

endmodule