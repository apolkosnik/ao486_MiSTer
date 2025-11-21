/*
 * Instruction Queue for Superscalar Dispatch
 *
 * This module sits between READ and EXECUTE stages, buffering decoded
 * instructions so the dispatch logic can look ahead and issue multiple
 * instructions in parallel when possible.
 *
 * Queue depth: 4 instructions
 * Issue width: Up to 2 instructions per cycle
 */

`include "defines.v"

module instruction_queue(
    input               clk,
    input               rst_n,

    input               queue_reset,

    // Input from READ stage (only signals that actually exist)
    input               rd_ready,           // Instruction valid from READ stage
    input       [6:0]   rd_cmd,
    input       [3:0]   rd_cmdex,
    input       [10:0]  rd_mutex_next,      // Actual signal name from READ stage
    input       [31:0]  src_wire,           // Source operand from READ stage
    input       [31:0]  dst_wire,           // Destination operand from READ stage
    input               rd_is_8bit,
    input               rd_dst_is_reg,
    input               rd_dst_is_memory,
    input       [5:0]   rd_modregrm,        // [5:3]=reg, [2:0]=rm from decoder[13:8]

    // Outputs for dispatch (head of queue - inst0)
    output              inst0_valid,
    output      [6:0]   inst0_cmd,
    output      [3:0]   inst0_cmdex,
    output      [10:0]  inst0_mutex,
    output      [31:0]  inst0_src,
    output      [31:0]  inst0_dst,
    output              inst0_is_8bit,
    output              inst0_dst_is_reg,
    output              inst0_dst_is_memory,
    output      [5:0]   inst0_modregrm,     // [5:3]=reg, [2:0]=rm

    // Outputs for dispatch (second in queue - inst1)
    output              inst1_valid,
    output      [6:0]   inst1_cmd,
    output      [3:0]   inst1_cmdex,
    output      [10:0]  inst1_mutex,
    output      [31:0]  inst1_src,
    output      [31:0]  inst1_dst,
    output              inst1_is_8bit,
    output              inst1_dst_is_reg,
    output              inst1_dst_is_memory,
    output      [5:0]   inst1_modregrm,     // [5:3]=reg, [2:0]=rm

    // Control signals
    input               dispatch_inst0,     // Dispatch consumed inst0
    input               dispatch_inst1,     // Dispatch consumed inst1

    output              queue_full,
    output              queue_empty,
    output      [2:0]   queue_count
);

//------------------------------------------------------------------------------
// Queue Storage - 4 instruction slots
//------------------------------------------------------------------------------

// Each queue entry stores all instruction properties
reg         valid [0:3];
reg [6:0]   cmd [0:3];
reg [3:0]   cmdex [0:3];
reg [10:0]  mutex [0:3];
reg [31:0]  src [0:3];
reg [31:0]  dst [0:3];
reg         is_8bit [0:3];
reg         dst_is_reg [0:3];
reg         dst_is_memory [0:3];
reg [5:0]   modregrm [0:3];

// Queue pointers
reg [2:0]   head;           // Next instruction to dispatch
reg [2:0]   tail;           // Next free slot
reg [2:0]   count;          // Number of valid instructions

//------------------------------------------------------------------------------
// Queue Status
//------------------------------------------------------------------------------

assign queue_full  = (count == 3'd4);
assign queue_empty = (count == 3'd0);
assign queue_count = count;

//------------------------------------------------------------------------------
// Output Assignments - Head of Queue
//------------------------------------------------------------------------------

assign inst0_valid       = valid[head[1:0]];
assign inst0_cmd         = cmd[head[1:0]];
assign inst0_cmdex       = cmdex[head[1:0]];
assign inst0_mutex       = mutex[head[1:0]];
assign inst0_src         = src[head[1:0]];
assign inst0_dst         = dst[head[1:0]];
assign inst0_is_8bit     = is_8bit[head[1:0]];
assign inst0_dst_is_reg  = dst_is_reg[head[1:0]];
assign inst0_dst_is_memory = dst_is_memory[head[1:0]];
assign inst0_modregrm    = modregrm[head[1:0]];

// Second in queue (head + 1)
wire [1:0] head_plus_1 = head[1:0] + 2'd1;

assign inst1_valid       = (count >= 3'd2) ? valid[head_plus_1] : 1'b0;
assign inst1_cmd         = cmd[head_plus_1];
assign inst1_cmdex       = cmdex[head_plus_1];
assign inst1_mutex       = mutex[head_plus_1];
assign inst1_src         = src[head_plus_1];
assign inst1_dst         = dst[head_plus_1];
assign inst1_is_8bit     = is_8bit[head_plus_1];
assign inst1_dst_is_reg  = dst_is_reg[head_plus_1];
assign inst1_dst_is_memory = dst_is_memory[head_plus_1];
assign inst1_modregrm    = modregrm[head_plus_1];

//------------------------------------------------------------------------------
// Queue Management Logic
//------------------------------------------------------------------------------

wire enqueue = rd_ready && !queue_full;
wire dequeue_count = {1'b0, dispatch_inst0} + {1'b0, dispatch_inst1};

integer i;

always @(posedge clk) begin
    if (rst_n == 1'b0 || queue_reset) begin
        for (i = 0; i < 4; i = i + 1) begin
            valid[i] <= 1'b0;
            cmd[i] <= 7'd0;
            cmdex[i] <= 4'd0;
            mutex[i] <= 11'd0;
            src[i] <= 32'd0;
            dst[i] <= 32'd0;
            is_8bit[i] <= 1'b0;
            dst_is_reg[i] <= 1'b0;
            dst_is_memory[i] <= 1'b0;
            modregrm[i] <= 6'd0;
        end
        head <= 3'd0;
        tail <= 3'd0;
        count <= 3'd0;
    end
    else begin
        // Enqueue from READ stage
        if (enqueue) begin
            valid[tail[1:0]]         <= 1'b1;
            cmd[tail[1:0]]           <= rd_cmd;
            cmdex[tail[1:0]]         <= rd_cmdex;
            mutex[tail[1:0]]         <= rd_mutex_next;
            src[tail[1:0]]           <= src_wire;
            dst[tail[1:0]]           <= dst_wire;
            is_8bit[tail[1:0]]       <= rd_is_8bit;
            dst_is_reg[tail[1:0]]    <= rd_dst_is_reg;
            dst_is_memory[tail[1:0]] <= rd_dst_is_memory;
            modregrm[tail[1:0]]      <= rd_modregrm;
        end

        // Update pointers and count
        if (enqueue && !dequeue_count) begin
            tail <= tail + 3'd1;
            count <= count + 3'd1;
        end
        else if (!enqueue && dequeue_count == 2'd1) begin
            head <= head + 3'd1;
            count <= count - 3'd1;
            valid[head[1:0]] <= 1'b0;
        end
        else if (!enqueue && dequeue_count == 2'd2) begin
            head <= head + 3'd2;
            count <= count - 3'd2;
            valid[head[1:0]] <= 1'b0;
            valid[head_plus_1] <= 1'b0;
        end
        else if (enqueue && dequeue_count == 2'd1) begin
            // Enqueue and dequeue 1 - count stays same
            head <= head + 3'd1;
            tail <= tail + 3'd1;
            valid[head[1:0]] <= 1'b0;
        end
        else if (enqueue && dequeue_count == 2'd2) begin
            // Enqueue 1 and dequeue 2 - count decreases by 1
            head <= head + 3'd2;
            tail <= tail + 3'd1;
            count <= count - 3'd1;
            valid[head[1:0]] <= 1'b0;
            valid[head_plus_1] <= 1'b0;
        end
    end
end

//------------------------------------------------------------------------------

endmodule
