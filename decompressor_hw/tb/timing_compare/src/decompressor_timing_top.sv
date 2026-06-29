// decompressor_timing_top.sv
// Synthesis/implementation top for timing benchmark.
//
// Keeps the 64x32-bit packet array and 32x64-bit plane array inside the fabric
// (not as top-level IO). Only control/status ports are exposed so Vivado can
// place-and-route on Pynq-Z2 without exceeding device pin limits.

module decompressor_timing_top #(
    parameter int WORD_SIZE   = 32,
    parameter int PACKET_SIZE = 64,
    parameter int GROUP_SIZE  = 8
) (
    input  logic clk,
    input  logic nrst,
    input  logic start,
    output logic valid,
    output logic [WORD_SIZE-1:0] key_in,
    output logic [$clog2(PACKET_SIZE+1)-1:0] in_count
);

    logic [WORD_SIZE-1:0] data_packet [PACKET_SIZE-1:0];
    logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0];

    // Hold a representative compressed payload in fabric registers (not top-level IO).
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            for (int i = 0; i < WORD_SIZE; i++)
                packed_planes[i] <= {PACKET_SIZE{1'b1}};
            key_in <= '1;
            in_count <= WORD_SIZE[$clog2(PACKET_SIZE+1)-1:0];
        end
    end

    // Prevent recovered packet from being optimized away during timing closure.
    logic [WORD_SIZE-1:0] data_packet_sink [PACKET_SIZE-1:0];
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            for (int i = 0; i < PACKET_SIZE; i++)
                data_packet_sink[i] <= '0;
        end else begin
            for (int i = 0; i < PACKET_SIZE; i++)
                data_packet_sink[i] <= data_packet[i];
        end
    end

    (* keep_hierarchy = "yes" *)
    decompressor #(
        .WORD_SIZE(WORD_SIZE),
        .PACKET_SIZE(PACKET_SIZE),
        .GROUP_SIZE(GROUP_SIZE)
    ) u_decompressor (
        .clk(clk),
        .nrst(nrst),
        .start(start),
        .packed_planes(packed_planes),
        .in_count(in_count),
        .key_in(key_in),
        .data_packet(data_packet),
        .valid(valid)
    );

endmodule