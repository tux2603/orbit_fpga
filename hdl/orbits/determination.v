// An AXI-Lite peripheral for the ZYNQ processor for performing orbital determinations

module determination_interface #(
        // Parameters for the AXI-Lite interface
        parameter C_S_AXI_DATA_WIDTH = 32,
        parameter C_S_AXI_ADDR_WIDTH = 7
    ) (
        // AXI4-Lite Slave Interface
        input wire s_axi_aclk,
        input wire s_axi_aresetn,
        input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
        input wire [2:0] s_axi_awprot,
        input wire s_axi_awvalid,
        output reg s_axi_awready = 1'b1,
        input wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
        input wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
        input wire s_axi_wvalid,
        output reg s_axi_wready = 1'b1,
        output reg [1:0] s_axi_bresp = 2'b00,
        output reg s_axi_bvalid = 1'b0,
        input wire s_axi_bready,
        input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
        input wire [2:0] s_axi_arprot,
        input wire s_axi_arvalid,
        output reg s_axi_arready = 1'b1,
        output reg [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
        output wire [1:0] s_axi_rresp,
        output reg s_axi_rvalid = 1'b0,
        input wire s_axi_rready

        // TODO: do we want an interrupt that triggers when a determination is complete?

        // TODO: add a (stream based?) interface going to the scheduler
    );

/* 
    Registers:
        0x00(rw) - control register
            bit 0: start determination
            bit 8: determination done
            bit 9: error flag
            TODO: do we want to add a bit to indicate that the determination is in progress?
        0x04(rw) - reserved
        0x08(rw) - reserved
        0x0C(rw) - reserved
        0x10(rw) - r0.x (start position x)
            bit 0-31: r0.x (32-bit float)
        0x14(rw) - r0.y (start position y)
            bit 0-31: r0.y (32-bit float)
        0x18(rw) - r0.z (start position z)
            bit 0-31: r0.z (32-bit float)
        0x1C(rw) - start time
            bit 0-31: start time (32-bit int, seconds since epoch)
        0x20(rw) - r1.x (end position x)
            bit 0-31: r1.x (32-bit float)
        0x24(rw) - r1.y (end position y)
            bit 0-31: r1.y (32-bit float)
        0x28(rw) - r1.z (end position z)
            bit 0-31: r1.z (32-bit float)
        0x2C(rw) - end time
            bit 0-31: end time (32-bit int, seconds since epoch)
        0x30(rw) - gravitational parameter (μ)
            bit 0-31: μ (32-bit float)
        0x34(rw) - reserved
        0x38(rw) - reserved
        0x3C(rw) - reserved
        0x40(ro) - semi-major axis (a)
            bit 0-31: a (32-bit float)
        0x44(ro) - eccentricity (e)
            bit 0-31: e (32-bit float)
        0x48(ro) - inclination (i)
            bit 0-31: i (32-bit float)
        0x4C(ro) - longitude of ascending node (Ω)
            bit 0-31: Ω (32-bit float)
        0x50(ro) - argument of periapsis (ω)
            bit 0-31: ω (32-bit float)
        0x54(ro) - true anomaly at epoch (ν)
            bit 0-31: ν (32-bit float)
        0x58(ro) - reserved
        0x5C(ro) - reserved
        0x60(ro) - reserved
        0x64(ro) - reserved
        0x68(ro) - reserved
        0x6C(ro) - reserved
        0x70(ro) - reserved
        0x74(ro) - reserved
        0x78(ro) - reserved
        0x7C(ro) - reserved
    */

    // ##### Constants and parameters for the AXI-Lite interface #####

    localparam NUM_REGS = (2**C_S_AXI_ADDR_WIDTH) / (C_S_AXI_DATA_WIDTH/8); // Number of registers in the AXI-Lite interface
    localparam ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1; // Address LSB for the AXI-Lite interface. Only works for 32-bit and 64-bit data widths
    localparam MEM_ADDR_BITS = C_S_AXI_ADDR_WIDTH - ADDR_LSB; // Number of address bits used to actually address the registers
    localparam READ_ONLY_START_ADDR = 'h40; // Address of the first read-only register


    // ##### Internal AXI status signals #####

    reg axi_awaddr_latched = 1'b0;
    reg axi_wdata_latched = 1'b0;

    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr_reg = 'b0;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_wdata_reg = 'b0;
    reg [C_S_AXI_DATA_WIDTH/8-1 : 0] axi_wstrb_reg = 'b0;


    // ##### Register file and initialization #####

    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_reg_file [0:NUM_REGS-1];

    initial begin : AXI_REG_FILE_INIT
        integer i;
        for (i = 0; i < NUM_REGS; i = i + 1) begin
            axi_reg_file[i] = 'b0;
        end
    end


    // ##### AXI-Lite Write Logic #####
    // TODO: do we want some sort of logic to lock out the write interface while a determination is in progress?
    // TODO: add more rigorous handling of the start, done, and error bits in the control register. For example, when the determination request is accepted by the scheduler,
    // TODO:  the start bit should be cleared, and when the determination is complete, the done bit should be set. The error bit should be set if the determination fails for any reason.

    always @(posedge s_axi_aclk) begin : AXI_WRITE_FSM
        integer i, reg_addr, byte_index;

        // Reset logic
        if (!s_axi_aresetn) begin
            for (i = 0; i < NUM_REGS; i = i + 1) begin
                axi_reg_file[i] <= 'b0;
            end

            axi_awaddr_latched <= 1'b0;
            axi_wdata_latched <= 1'b0;
            axi_awaddr_reg <= 'b0;
            axi_wdata_reg <= 'b0;
            axi_wstrb_reg <= 'b0;

            // Default to being ready to accept writes
            s_axi_awready <= 1'b1;
            s_axi_wready <= 1'b1;
            s_axi_bvalid <= 1'b0;
        end

        // Update logic. Note that only addresses 0x00-0x3C are writeable, so discard any attempts to write to addresses 0x40-0x7C
        else begin
            // update the data array and mark the data as latched
            if (s_axi_awvalid && s_axi_awready) begin
                axi_awaddr_latched = 1'b1;
                axi_awaddr_reg = s_axi_awaddr;

                s_axi_awready <= 1'b0; // Deassert ready until the write is complete
            end

            // update the address array and mark the address as latched
            if (s_axi_wvalid && s_axi_wready) begin
                axi_wdata_latched = 1'b1;
                axi_wdata_reg = s_axi_wdata;
                axi_wstrb_reg = s_axi_wstrb;

                s_axi_wready <= 1'b0; // Deassert ready until the write is complete
            end

            // If both the address and data have been latched, perform the write
            if (axi_awaddr_latched && axi_wdata_latched) begin
                // First, check that the address is valid
                if (axi_awaddr_reg < READ_ONLY_START_ADDR) begin
                    // Figure out the register index that we are writing to
                    reg_addr = axi_awaddr_reg[ADDR_LSB +: MEM_ADDR_BITS];

                    // Perform the write operation, taking into account the write strobes
                    for (byte_index = 0; byte_index < C_S_AXI_DATA_WIDTH/8; byte_index = byte_index + 1) begin
                        if (axi_wstrb_reg[byte_index]) begin
                            axi_reg_file[reg_addr][byte_index*8 +: 8] <= axi_wdata_reg[byte_index*8 +: 8];
                        end
                    end

                    // Special behavior for the control register: if the start bit is set, clear the done and error bits
                    if (reg_addr == 0) begin
                        if (axi_wdata_reg[0] && axi_wstrb_reg[0]) begin
                            axi_reg_file[0][8] <= 1'b0; // Clear the done bit
                            axi_reg_file[0][9] <= 1'b0; // Clear the error bit
                        end
                    end

                    // Special behavior for the control register: if a '1' is written to the done or error bits, clear them
                    if (reg_addr == 0) begin
                        if (axi_wdata_reg[8] && axi_wstrb_reg[1]) begin
                            axi_reg_file[0][8] <= 1'b0; // Clear the done bit
                        end
                        if (axi_wdata_reg[9] && axi_wstrb_reg[1]) begin
                            axi_reg_file[0][9] <= 1'b0; // Clear the error bit
                        end
                    end

                    s_axi_bresp <= 2'b00; // OKAY response
                end

                // Address is invalid, so return a SLVERR response
                else begin
                    s_axi_bresp <= 2'b10; // SLVERR
                end

                // Handle the rest of the write cleanup and response logic
                axi_awaddr_latched <= 1'b0;
                axi_wdata_latched <= 1'b0;
                s_axi_bvalid <= 1'b1; // Assert the write response valid signal
            end

            // Clear the write response when the master acknowledges it and mark that we are ready to accept new writes
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0; 
                s_axi_awready <= 1'b1;
                s_axi_wready <= 1'b1;
            end
        end
    end


    // ##### AXI-Lite Read logic #####

    always @(posedge s_axi_aclk) begin : AXI_READ_FSM
        integer reg_addr;

        // Reset logic
        if (!s_axi_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 'b0;

            s_axi_arready <= 1'b1; // Default to being ready to accept reads
            s_axi_rvalid <= 1'b0;
        end

        // Update logic
        else begin
            // If the master is requesting a read, latch the address and prepare the data to be sent back
            if (s_axi_arvalid && s_axi_arready) begin
                reg_addr = s_axi_araddr[ADDR_LSB +: MEM_ADDR_BITS];
                s_axi_rdata <= axi_reg_file[reg_addr];

                s_axi_arready <= 1'b0; // Deassert ready until the read is complete
                s_axi_rvalid <= 1'b1; // Assert that the read data is valid
            end

            // Clear the read response when the master acknowledges it and mark that we are ready to accept new reads
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
                s_axi_arready <= 1'b1;
            end
        end
    end

    // The read response is always OKAY, since we don't have any error conditions for reads
    assign s_axi_rresp = 2'b00; // OKAY response

    // TODO: add a (stream based?) interface going to the scheduler
endmodule


