
// Delta Negabinary Encoding module - 1 clock cycle
module diffnb #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64 ) (
    input logic clk,
    input logic nrst,
    input logic [WORD_SIZE-1:0] in [PACKET_SIZE-1:0],
    input logic start,
    output logic valid,
    output logic [WORD_SIZE-1:0] out [PACKET_SIZE-1:0]
); 

localparam NB_MASK = {WORD_SIZE/2{2'b10}};

logic [WORD_SIZE-1:0] delta [PACKET_SIZE-1:0];
logic [WORD_SIZE-1:0] nb [PACKET_SIZE-1:0];

// subtract the previous value from the current value to get the difference
always_comb begin
    delta[0] = in[0];
    for (int i = 1; i < PACKET_SIZE; i++) begin
        delta[i] = in[i] - in[i-1];
    end
end 
// FIXME: we can add a pipeline stage here if the critical path is too long, but it will increase the latency by one cycle.

// convert the difference to negabinary representation
always_comb begin
    for (int i = 0; i < PACKET_SIZE; i++) begin
        nb[i] = (delta[i] + NB_MASK) ^ NB_MASK;
    end
end

//output the negabinary representation - pipeline step
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out <= '0;
        valid <= 0;
    end else if (start) begin
        for (int i = 0; i < PACKET_SIZE; i++) begin
            out[i] <= nb[i];
        end
        valid <= 1;
    end else begin
        valid <= 0;
    end
end 


endmodule 