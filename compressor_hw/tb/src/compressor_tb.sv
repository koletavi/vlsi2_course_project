// compressor_tb.sv
// Self-checking testbench for compressor.sv

import compressor_ref_pkg::*;

module compressor_tb;

    localparam int WORD_SIZE   = 32;
    localparam int PACKET_SIZE = 64;
    localparam int GROUP_SIZE  = 8;
    localparam int CLK_PERIOD  = 10;
    localparam int VALID_TIMEOUT = 10;

    logic clk;
    logic nrst;
    logic start;
    logic [WORD_SIZE-1:0] data_packet [PACKET_SIZE-1:0];
    logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0];
    logic valid;
    logic [$clog2(PACKET_SIZE+1)-1:0] out_count;
    logic [WORD_SIZE-1:0] key_out;

    int tests_passed;
    int tests_failed;

    compressor #(
        .WORD_SIZE(WORD_SIZE),
        .PACKET_SIZE(PACKET_SIZE),
        .GROUP_SIZE(GROUP_SIZE)
    ) dut (
        .clk(clk),
        .nrst(nrst),
        .start(start),
        .data_packet(data_packet),
        .packed_planes(packed_planes),
        .valid(valid),
        .out_count(out_count),
        .key_out(key_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic reset_dut();
        nrst = 0;
        start = 0;
        for (int i = 0; i < PACKET_SIZE; i++)
            data_packet[i] = '0;
        repeat (2) @(posedge clk);
        nrst = 1;
        @(posedge clk);
    endtask

    task automatic apply_packet(input logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
        for (int i = 0; i < PACKET_SIZE; i++)
            data_packet[i] = packet[i];
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
    endtask

    task automatic dump_hw_result(
        input string test_name,
        input logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]
    );
        int fd;
        int packed_src_idx;
        string path;
        path = {{"../hw_vs_sw/hw/", test_name, ".txt"}};
        fd = $fopen(path, "w");
        if (fd == 0) begin
            $error("[%s] could not open %s for write", test_name, path);
            return;
        end
        $fdisplay(fd, "================================================================================");
        $fdisplay(fd, "COMPRESSION RESULT");
        $fdisplay(fd, "================================================================================");
        $fdisplay(fd, "Source:      HARDWARE (compressor.sv simulation)");
        $fdisplay(fd, "Test:        %s", test_name);
        $fdisplay(fd, "");
        $fdisplay(fd, "CONFIGURATION");
        $fdisplay(fd, "  WORD_SIZE:   %0d", WORD_SIZE);
        $fdisplay(fd, "  PACKET_SIZE: %0d", PACKET_SIZE);
        $fdisplay(fd, "");
        $fdisplay(fd, "--------------------------------------------------------------------------------");
        $fdisplay(fd, "ORIGINAL PACKET (%0d x %0d-bit words)", PACKET_SIZE, WORD_SIZE);
        $fdisplay(fd, "--------------------------------------------------------------------------------");
        for (int i = 0; i < PACKET_SIZE; i++)
            $fdisplay(fd, "  [%2d] 0x%08h  (%0d)", i, packet[i], packet[i]);
        $fdisplay(fd, "");
        $fdisplay(fd, "--------------------------------------------------------------------------------");
        $fdisplay(fd, "COMPRESSED OUTPUT (DIFFNB -> BIT -> RZE)");
        $fdisplay(fd, "--------------------------------------------------------------------------------");
        $fdisplay(fd, "  key_out:    0x%08h", key_out);
        $fdisplay(fd, "  out_count:  %0d", out_count);
        $fdisplay(fd, "");
        if (key_out == '0)
            $fdisplay(fd, "  key_out bit map: (all planes zero)");
        else begin
            $fdisplay(fd, "  key_out bit map (bit i = 1 => original bit-plane i was non-zero):");
            for (int i = 0; i < WORD_SIZE; i++)
                if (key_out[i])
                    $fdisplay(fd, "    plane[%2d] : NON-ZERO", i);
        end
        $fdisplay(fd, "");
        $fdisplay(fd, "  packed_planes (%0d dense entries):", out_count);
        if (out_count == 0)
            $fdisplay(fd, "    (empty)");
        else begin
            packed_src_idx = 0;
            for (int p = 0; p < out_count; p++) begin
                while (packed_src_idx < WORD_SIZE && !key_out[packed_src_idx])
                    packed_src_idx++;
                $fdisplay(fd, "    [%0d] from plane[%2d]", p, packed_src_idx);
                $fdisplay(fd, "         hex: 0x%016h", packed_planes[p]);
                $fdisplay(fd, "         bin: %064b", packed_planes[p]);
                packed_src_idx++;
            end
        end
        $fdisplay(fd, "");
        $fdisplay(fd, "================================================================================");
        $fclose(fd);
        $display("Wrote HW dump: %s", path);
    endtask

    task automatic wait_valid(output logic saw_valid);
        int cycles;
        saw_valid = 0;
        for (cycles = 0; cycles < VALID_TIMEOUT; cycles++) begin
            @(posedge clk);
            if (valid) begin
                saw_valid = 1;
                return;
            end
        end
        $fatal(1, "Timeout waiting for valid (>%0d cycles)", VALID_TIMEOUT);
    endtask

    task automatic check_outputs(
        input string test_name,
        input logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]
    );
        logic [PACKET_SIZE-1:0] exp_planes [WORD_SIZE-1:0];
        logic [WORD_SIZE-1:0] exp_key;
        int exp_count;
        logic saw_valid;
        logic valid_next;

        apply_packet(packet);
        wait_valid(saw_valid);

        if (!saw_valid) begin
            $error("[%s] valid never asserted", test_name);
            tests_failed++;
            return;
        end

        @(posedge clk);
        valid_next = valid;
        if (valid_next)
            $warning("[%s] valid was high for more than one cycle", test_name);

        ref_compress_packet(packet, exp_planes, exp_key, exp_count);

        if (key_out !== exp_key) begin
            $error("[%s] key_out mismatch: got %08h expected %08h",
                   test_name, key_out, exp_key);
            tests_failed++;
            return;
        end

        if (int'(out_count) !== exp_count) begin
            $error("[%s] out_count mismatch: got %0d expected %0d",
                   test_name, out_count, exp_count);
            tests_failed++;
            return;
        end

        for (int i = 0; i < exp_count; i++) begin
            if (packed_planes[i] !== exp_planes[i]) begin
                $error("[%s] packed_planes[%0d] mismatch: got %064b expected %064b",
                       test_name, i, packed_planes[i], exp_planes[i]);
                tests_failed++;
                return;
            end
        end

        for (int i = exp_count; i < WORD_SIZE; i++) begin
            if (packed_planes[i] !== '0) begin
                $error("[%s] packed_planes[%0d] not zeroed: got %064b",
                       test_name, i, packed_planes[i]);
                tests_failed++;
                return;
            end
        end

        $display("PASS: %s (out_count=%0d, key_out=%08h)", test_name, exp_count, exp_key);
        dump_hw_result(test_name, packet);
        tests_passed++;
    endtask

    task automatic fill_all_zeros(output logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
        for (int i = 0; i < PACKET_SIZE; i++)
            packet[i] = '0;
    endtask

    task automatic fill_all_ones(output logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
        for (int i = 0; i < PACKET_SIZE; i++)
            packet[i] = 32'hFFFF_FFFF;
    endtask

    task automatic fill_ramp(output logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
        for (int i = 0; i < PACKET_SIZE; i++)
            packet[i] = (i * 17);
    endtask

    task automatic fill_single_plane(output logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
        for (int i = 0; i < PACKET_SIZE; i++)
            packet[i] = 32'h0000_0020; // only bit-plane 5 is non-zero
    endtask

    task automatic fill_sparse(output logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
        for (int i = 0; i < PACKET_SIZE; i++)
            packet[i] = ((i % 7) == 0) ? 32'hA5_0000 : 32'h0;
    endtask

    task automatic fill_sine_like(output logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
        // First 60 words from compressor_sw/test_input.txt; pad to 64 with zeros.
        logic [WORD_SIZE-1:0] words [PACKET_SIZE-1:0] = '{
            32'h3F80_0000, 32'h3F8C_CC00, 32'h3F99_9800, 32'h3FA6_6400,
            32'h4000_0000, 32'h400C_CC00, 32'h3F80_0000, 32'h3F8C_CC00,
            32'h3F99_9800, 32'h3FA6_6400, 32'h4000_0000, 32'h400C_CC00,
            32'h3F80_0000, 32'h3F8C_CC00, 32'h3F99_9800, 32'h3FA6_6400,
            32'h4000_0000, 32'h400C_CC00, 32'h3F80_0000, 32'h3F8C_CC00,
            32'h3F99_9800, 32'h3FA6_6400, 32'h4000_0000, 32'h400C_CC00,
            32'h3F80_0000, 32'h3F8C_CC00, 32'h3F99_9800, 32'h3FA6_6400,
            32'h4000_0000, 32'h400C_CC00, 32'h3F80_0000, 32'h3F8C_CC00,
            32'h3F99_9800, 32'h3FA6_6400, 32'h4000_0000, 32'h400C_CC00,
            32'h3F80_0000, 32'h3F8C_CC00, 32'h3F99_9800, 32'h3FA6_6400,
            32'h4000_0000, 32'h400C_CC00, 32'h3F80_0000, 32'h3F8C_CC00,
            32'h3F99_9800, 32'h3FA6_6400, 32'h4000_0000, 32'h400C_CC00,
            32'h3F80_0000, 32'h3F8C_CC00, 32'h3F99_9800, 32'h3FA6_6400,
            32'h4000_0000, 32'h400C_CC00, 32'h3F80_0000, 32'h3F8C_CC00,
            32'h3F99_9800, 32'h3FA6_6400, 32'h4000_0000, 32'h400C_CC00,
            32'h0, 32'h0, 32'h0, 32'h0
        };
        for (int i = 0; i < PACKET_SIZE; i++)
            packet[i] = words[i];
    endtask

    task automatic fill_random(output logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
        for (int i = 0; i < PACKET_SIZE; i++)
            packet[i] = $urandom;
    endtask

    initial begin
        logic [WORD_SIZE-1:0] packet_a [PACKET_SIZE-1:0];
        logic [WORD_SIZE-1:0] packet_b [PACKET_SIZE-1:0];

        tests_passed = 0;
        tests_failed = 0;

        $dumpfile("../wave/compressor_tb.vcd");
        $dumpvars(0, compressor_tb);

        reset_dut();

        fill_all_zeros(packet_a);
        check_outputs("all_zeros", packet_a);

        fill_all_ones(packet_a);
        check_outputs("all_ones", packet_a);

        fill_ramp(packet_a);
        check_outputs("ramp", packet_a);

        fill_single_plane(packet_a);
        check_outputs("single_plane", packet_a);

        fill_sparse(packet_a);
        check_outputs("sparse", packet_a);

        fill_sine_like(packet_a);
        check_outputs("sine_like", packet_a);

        fill_random(packet_a);
        check_outputs("random", packet_a);

        fill_ramp(packet_a);
        fill_sparse(packet_b);
        check_outputs("back_to_back_1", packet_a);
        check_outputs("back_to_back_2", packet_b);

        $display("");
        $display("========================================");
        $display("Tests passed: %0d", tests_passed);
        $display("Tests failed: %0d", tests_failed);
        $display("========================================");

        if (tests_failed != 0)
            $fatal(1, "SOME TESTS FAILED");
        else
            $display("ALL TESTS PASSED");

        $finish;
    end

endmodule