// decompressor_tb.sv
// Self-checking testbench for decompressor.sv (roundtrip via compressor reference)

import decompressor_ref_pkg::*;

module decompressor_tb;

    localparam int WORD_SIZE   = 32;
    localparam int PACKET_SIZE = 64;
    localparam int GROUP_SIZE  = 8;
    localparam int CLK_PERIOD  = 10;
    localparam int VALID_TIMEOUT = 10;

    logic clk;
    logic nrst;
    logic start;
    logic [WORD_SIZE-1:0] orig_packet [PACKET_SIZE-1:0];
    logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0];
    logic [$clog2(PACKET_SIZE+1)-1:0] in_count;
    logic [WORD_SIZE-1:0] key_in;
    logic [WORD_SIZE-1:0] data_packet [PACKET_SIZE-1:0];
    logic valid;

    int tests_passed;
    int tests_failed;

    decompressor #(
        .WORD_SIZE(WORD_SIZE),
        .PACKET_SIZE(PACKET_SIZE),
        .GROUP_SIZE(GROUP_SIZE)
    ) dut (
        .clk(clk),
        .nrst(nrst),
        .start(start),
        .packed_planes(packed_planes),
        .in_count(in_count),
        .key_in(key_in),
        .data_packet(data_packet),
        .valid(valid)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic reset_dut();
        nrst = 0;
        start = 0;
        in_count = '0;
        key_in = '0;
        for (int i = 0; i < WORD_SIZE; i++)
            packed_planes[i] = '0;
        repeat (2) @(posedge clk);
        nrst = 1;
        @(posedge clk);
    endtask

    task automatic apply_compressed(
        input logic [PACKET_SIZE-1:0] planes [WORD_SIZE-1:0],
        input logic [WORD_SIZE-1:0] key,
        input int count
    );
        for (int i = 0; i < WORD_SIZE; i++)
            packed_planes[i] = planes[i];
        key_in = key;
        in_count = count[$clog2(PACKET_SIZE+1)-1:0];
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
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

    task automatic dump_hw_result(
        input string test_name,
        input logic [WORD_SIZE-1:0] original [PACKET_SIZE-1:0],
        input logic [PACKET_SIZE-1:0] planes [WORD_SIZE-1:0],
        input logic [WORD_SIZE-1:0] key,
        input int count
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
        $fdisplay(fd, "DECOMPRESSION RESULT");
        $fdisplay(fd, "================================================================================");
        $fdisplay(fd, "Source:      HARDWARE (decompressor.sv simulation)");
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
            $fdisplay(fd, "  [%2d] 0x%08h  (%0d)", i, original[i], original[i]);
        $fdisplay(fd, "");
        $fdisplay(fd, "--------------------------------------------------------------------------------");
        $fdisplay(fd, "COMPRESSED INPUT (URZE payload)");
        $fdisplay(fd, "--------------------------------------------------------------------------------");
        $fdisplay(fd, "  key_in:     0x%08h", key);
        $fdisplay(fd, "  in_count:   %0d", count);
        $fdisplay(fd, "");
        if (key == '0)
            $fdisplay(fd, "  key_in bit map: (all planes zero)");
        else begin
            $fdisplay(fd, "  key_in bit map (bit i = 1 => original bit-plane i was non-zero):");
            for (int i = 0; i < WORD_SIZE; i++)
                if (key[i])
                    $fdisplay(fd, "    plane[%2d] : NON-ZERO", i);
        end
        $fdisplay(fd, "");
        $fdisplay(fd, "  packed_planes (%0d dense entries):", count);
        if (count == 0)
            $fdisplay(fd, "    (empty)");
        else begin
            packed_src_idx = 0;
            for (int p = 0; p < count; p++) begin
                while (packed_src_idx < WORD_SIZE && !key[packed_src_idx])
                    packed_src_idx++;
                $fdisplay(fd, "    [%0d] from plane[%2d]", p, packed_src_idx);
                $fdisplay(fd, "         hex: 0x%016h", planes[p]);
                $fdisplay(fd, "         bin: %064b", planes[p]);
                packed_src_idx++;
            end
        end
        $fdisplay(fd, "");
        $fdisplay(fd, "--------------------------------------------------------------------------------");
        $fdisplay(fd, "DECOMPRESSED OUTPUT (URZE -> BIT -> UNDIFFNB)");
        $fdisplay(fd, "--------------------------------------------------------------------------------");
        $fdisplay(fd, "RECOVERED PACKET (%0d x %0d-bit words)", PACKET_SIZE, WORD_SIZE);
        $fdisplay(fd, "--------------------------------------------------------------------------------");
        for (int i = 0; i < PACKET_SIZE; i++)
            $fdisplay(fd, "  [%2d] 0x%08h  (%0d)", i, data_packet[i], data_packet[i]);
        $fdisplay(fd, "");
        $fdisplay(fd, "================================================================================");
        $fclose(fd);
        $display("Wrote HW dump: %s", path);
    endtask

    task automatic check_roundtrip(input string test_name);
        logic [PACKET_SIZE-1:0] cmp_planes [WORD_SIZE-1:0];
        logic [WORD_SIZE-1:0] cmp_key;
        logic [WORD_SIZE-1:0] exp_packet [PACKET_SIZE-1:0];
        int cmp_count;
        logic saw_valid;
        logic valid_next;

        ref_compress_packet(orig_packet, cmp_planes, cmp_key, cmp_count);
        apply_compressed(cmp_planes, cmp_key, cmp_count);
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

        ref_decompress_packet(cmp_planes, cmp_key, exp_packet);

        for (int i = 0; i < PACKET_SIZE; i++) begin
            if (data_packet[i] !== exp_packet[i]) begin
                $error("[%s] data_packet[%0d] mismatch: got %08h expected %08h (orig %08h)",
                       test_name, i, data_packet[i], exp_packet[i], orig_packet[i]);
                tests_failed++;
                return;
            end
        end

        for (int i = 0; i < PACKET_SIZE; i++) begin
            if (data_packet[i] !== orig_packet[i]) begin
                $error("[%s] roundtrip mismatch at word %0d: got %08h expected %08h",
                       test_name, i, data_packet[i], orig_packet[i]);
                tests_failed++;
                return;
            end
        end

        $display("PASS: %s (in_count=%0d, key_in=%08h)", test_name, cmp_count, cmp_key);
        dump_hw_result(test_name, orig_packet, cmp_planes, cmp_key, cmp_count);
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
            packet[i] = 32'h0000_0020;
    endtask

    task automatic fill_sparse(output logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
        for (int i = 0; i < PACKET_SIZE; i++)
            packet[i] = ((i % 7) == 0) ? 32'hA5_0000 : 32'h0;
    endtask

    task automatic fill_sine_like(output logic [WORD_SIZE-1:0] packet [PACKET_SIZE-1:0]);
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

        $dumpfile("../wave/decompressor_tb.vcd");
        $dumpvars(0, decompressor_tb);

        reset_dut();

        fill_all_zeros(packet_a);
        orig_packet = packet_a;
        check_roundtrip("all_zeros");

        fill_all_ones(packet_a);
        orig_packet = packet_a;
        check_roundtrip("all_ones");

        fill_ramp(packet_a);
        orig_packet = packet_a;
        check_roundtrip("ramp");

        fill_single_plane(packet_a);
        orig_packet = packet_a;
        check_roundtrip("single_plane");

        fill_sparse(packet_a);
        orig_packet = packet_a;
        check_roundtrip("sparse");

        fill_sine_like(packet_a);
        orig_packet = packet_a;
        check_roundtrip("sine_like");

        fill_random(packet_a);
        orig_packet = packet_a;
        check_roundtrip("random");

        fill_ramp(packet_a);
        orig_packet = packet_a;
        check_roundtrip("back_to_back_1");
        fill_sparse(packet_b);
        orig_packet = packet_b;
        check_roundtrip("back_to_back_2");

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