// ============================================================================
// dma_s2_size_error_seq.sv - DMA Scenario 2 Size Error Sequence
//
// - 1·2·3-byte 및 15-byte 전송으로 지원하지 않는 size error 경로를 실행.
// - S_SETUP에서 error_code=0x2와 error interrupt가 발생하는지 확인.
// - 기존 Driver와 Scoreboard의 negative-test 보고 동작은 그대로 유지.
// ============================================================================

import utility_pkg::*;

class dma_s2_size_error_seq extends dma_base_seq;
    `uvm_object_utils(dma_s2_size_error_seq)

    function new(input string name = "dma_s2_size_error_seq");
        super.new(name);
    endfunction

    // [body] : 미지원 전송 크기별 transaction 생성 및 source memory 초기화
    virtual task body();
        dma_tx t;

        int unsigned test_id[] = '{1, 2, 3, 4};
        int unsigned size_bytes[] = '{1, 2, 3, 15};
        bit [31:0] src_addr_list[] = '{
            32'h0000_0080, 32'h0000_0480,
            32'h0000_0C40, 32'h0000_0180
        };
        bit [31:0] dst_addr_list[] = '{
            32'h0000_0380, 32'h0000_0C80,
            32'h0000_0040, 32'h0000_0680
        };

        foreach (test_id[i]) begin
            int unsigned target_size = size_bytes[i];
            bit [31:0] target_src = src_addr_list[i];
            bit [31:0] target_dst = dst_addr_list[i];

            t = dma_tx::type_id::create(
                $sformatf("t_s2_id%0d", test_id[i])
            );

            start_item(t);

            if (!t.randomize() with {
                src_addr == local::target_src;
                dst_addr == local::target_dst;
                size     == local::target_size;

                enable == 1'b1;
                start  == 1'b1;
                irq    == 1'b1;

                backpressure_prob == 0;
                error_inject      == 1'b0;
            }) begin
                `uvm_fatal(
                    "S2_SEQ",
                    $sformatf("Failed to randomize S2 transaction ID %0d", test_id[i])
                )
            end

            t.scenario_name = $sformatf(
                "[S2-%0d] %0dB Size Error",
                test_id[i], target_size
            );

            // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
            preload_src_mem(t.src_addr, t.data_payload);

            finish_item(t);

            `uvm_info(
                "S2_SEQ",
                $sformatf("Generated S2 Transaction: %s", t.convert2string()),
                UVM_HIGH
            )
        end
    endtask
endclass
