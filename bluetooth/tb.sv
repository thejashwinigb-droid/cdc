module tb_serial_crc24;

    reg         clk;
    reg         rst_n;
    reg         preset_en;
    reg  [23:0] preset_val;
    reg         bit_en;
    reg         din;
    reg         last_bit;
    reg  [23:0] rx_crc_field;
    reg         rx_compare_en;

    wire [23:0] crc_out;
    wire        crc_done;
    wire        crc_match;

    reg  [23:0] expected_crc;
    reg  [79:0] pdu;

    integer i;
    integer errors;
    integer bit_count;

    // DUT
    serial_crc24 dut (
        .clk           (clk),
        .rst_n          (rst_n),
        .preset_en      (preset_en),
        .preset_val     (preset_val),
        .bit_en         (bit_en),
        .din            (din),
        .last_bit       (last_bit),
        .crc_out        (crc_out),
        .crc_done       (crc_done),
        .rx_crc_field   (rx_crc_field),
        .rx_compare_en  (rx_compare_en),
        .crc_match      (crc_match)
    );



 initial begin
    $shm_open("wave.shm");
    $shm_probe("ACTMF");
    end

    // Clock: 10 ns period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Reference model for the documented CRC equations
    function [23:0] ref_crc_step;
        input [23:0] current_crc;
        input        data_bit;

        reg feedback;
        reg [23:0] shifted;

        begin
            feedback = current_crc[23] ^ data_bit;
            shifted  = {current_crc[22:0], 1'b0};

            if (feedback)
                ref_crc_step = shifted ^ 24'h00065B;
            else
                ref_crc_step = shifted;
        end
    endfunction

    // Check CRC output against reference model
    task check_crc;
        begin
            if (crc_out !== expected_crc) begin
                $display(
                    "FAIL: CRC mismatch at time %0t: expected=%h actual=%h",
                    $time, expected_crc, crc_out
                );
                errors = errors + 1;
            end
        end
    endtask

    // Load initial CRC
    task load_crc;
        input [23:0] initial_value;

        begin
            @(negedge clk);
            preset_en  = 1'b1;
            preset_val = initial_value;
            bit_en     = 1'b0;
            last_bit   = 1'b0;

            @(posedge clk);
            #1;
            expected_crc = initial_value;

            check_crc;

            if (crc_done !== 1'b0) begin
                $display("FAIL: crc_done asserted during preset");
                errors = errors + 1;
            end

            @(negedge clk);
            preset_en = 1'b0;
        end
    endtask

    // Send one serial input bit and check the CRC
    task send_bit;
        input data_bit;
        input is_last;

        begin
            @(negedge clk);
            bit_en   = 1'b1;
            din      = data_bit;
            last_bit = is_last;

            @(posedge clk);
            #1;

            expected_crc = ref_crc_step(
                expected_crc, data_bit
            );

            check_crc;

            if (is_last) begin
                if (crc_done !== 1'b1) begin
                    $display("FAIL: crc_done not asserted");
                    errors = errors + 1;
                end
            end
            else begin
                if (crc_done !== 1'b0) begin
                    $display("FAIL: crc_done asserted too early");
                    errors = errors + 1;
                end
            end

            bit_count = bit_count + 1;
        end
    endtask

    // Test sequence
    initial begin
        rst_n         = 1'b0;
        preset_en     = 1'b0;
        preset_val    = 24'h000000;
        bit_en        = 1'b0;
        din           = 1'b0;
        last_bit      = 1'b0;
        rx_crc_field  = 24'h000000;
        rx_compare_en = 1'b0;
        expected_crc  = 24'h000000;
        errors        = 0;
        bit_count     = 0;

        // Example 80-bit PDU test pattern
        pdu = 80'h0111A511A51CDEF0123;

        // -------------------------------
        // TEST 1: Asynchronous reset
        // -------------------------------
        #2;
        if (crc_out !== 24'h000000) begin
            $display("FAIL: reset value incorrect");
            errors = errors + 1;
        end

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // -------------------------------
        // TEST 2: Load advertising CRC init
        // -------------------------------
        load_crc(24'h555555);

        if (crc_out !== 24'h555555) begin
            $display("FAIL: initial CRC is incorrect");
            errors = errors + 1;
        end

        // -------------------------------
        // TEST 3: Process 80 PDU bits
        // LSB of pdu is processed first
        // -------------------------------
        for (i = 0; i < 80; i = i + 1) begin
            if (i == 79)
                send_bit(pdu[i], 1'b1);
            else
                send_bit(pdu[i], 1'b0);
        end

        $display("Processed bits = %0d", bit_count);
        $display("Computed CRC   = 0x%06h", crc_out);

        // -------------------------------
        // TEST 4: CRC hold when bit_en = 0
        // -------------------------------
        @(negedge clk);
        bit_en   = 1'b0;
        last_bit = 1'b0;

        @(posedge clk);
        #1;

        check_crc;

        if (crc_done !== 1'b0) begin
            $display("FAIL: crc_done did not clear");
            errors = errors + 1;
        end

        // -------------------------------
        // TEST 5: RX CRC matching
        // -------------------------------
        rx_crc_field  = expected_crc;
        rx_compare_en = 1'b1;

        #1;
        if (crc_match !== 1'b1) begin
            $display("FAIL: correct RX CRC did not match");
            errors = errors + 1;
        end
        else begin
            $display("PASS: RX CRC match");
        end

        // -------------------------------
        // TEST 6: RX CRC mismatch
        // -------------------------------
        rx_crc_field = expected_crc ^ 24'h000001;

        #1;
        if (crc_match !== 1'b0) begin
            $display("FAIL: incorrect RX CRC matched");
            errors = errors + 1;
        end
        else begin
            $display("PASS: RX CRC mismatch detected");
        end

        // -------------------------------
        // TEST 7: Comparison disabled
        // -------------------------------
        rx_compare_en = 1'b0;

        #1;
        if (crc_match !== 1'b0) begin
            $display("FAIL: comparison enable not respected");
            errors = errors + 1;
        end

        // -------------------------------
        // Final result
        // -------------------------------
        if (errors == 0) begin
            $display("--------------------------------");
            $display("ALL TESTS PASSED");
            $display("--------------------------------");
        end
        else begin
            $display("--------------------------------");
            $display("TESTS FAILED: %0d errors", errors);
            $display("--------------------------------");
        end

        $finish;
    end

endmodule

