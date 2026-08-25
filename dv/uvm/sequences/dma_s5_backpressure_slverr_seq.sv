// ============================================================================
// dma_s5_backpressure_slverr_seq.sv - DMA Scenario 5 Backpressure and SLVERR Sequence
//
// - 1·4·16-beat write burst에 backpressure와 BRESP SLVERR를 함께 적용.
// - Low·medium·high backpressure 조건에서 W 전송과 B 오류 경로를 확인.
// - Error injection과 backpressure 결합 coverage를 목표로 구성.
// ============================================================================

import utility_pkg::*;

class dma_s5_backpressure_slverr_seq extends dma_base_seq;
    `uvm_object_utils(dma_s5_backpressure_slverr_seq)

    function new(input string name = "dma_s5_backpressure_slverr_seq");
        super.new(name);
    endfunction

    // [body] : Burst 길이별 backpressure와 BRESP SLVERR 결합 transaction 생성
    virtual task body();
        dma_tx t;

        int unsigned test_id[] = '{1, 2, 3};
        int unsigned size_bytes[] = '{4, 16, 64};
        int unsigned backpressure_probs[] = '{10, 50, 90};
        bit [31:0] src_addr_list[] = '{
            32'h0000_0300, 32'h0000_0700, 32'h0000_0C00
        };
        bit [31:0] dst_addr_list[] = '{
            32'h0000_0700, 32'h0000_0C00, 32'h0000_0300
        };

        foreach (test_id[i]) begin
            int unsigned target_size = size_bytes[i];
            int unsigned target_prob = backpressure_probs[i];
            bit [31:0] target_src = src_addr_list[i];
            bit [31:0] target_dst = dst_addr_list[i];

            t = dma_tx::type_id::create(
                $sformatf("t_s5_id%0d", test_id[i])
            );

            start_item(t);

            if (!t.randomize() with {
                src_addr == local::target_src;
                dst_addr == local::target_dst;
                size     == local::target_size;

                enable == 1'b1;
                start  == 1'b1;
                irq    == 1'b1;

                backpressure_prob == local::target_prob;
                error_inject      == 1'b1;
            }) begin
                `uvm_fatal(
                    "S5_SEQ",
                    $sformatf("Failed to randomize S5 transaction ID %0d", test_id[i])
                )
            end

            t.scenario_name = $sformatf(
                "[S5-%0d] %0dB Transfer with %0d%% Backpressure and SLVERR",
                test_id[i], target_size, target_prob
            );

            // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
            preload_src_mem(t.src_addr, t.data_payload);

            finish_item(t);

            `uvm_info(
                "S5_SEQ",
                $sformatf("Generated S5 Transaction: %s", t.convert2string()),
                UVM_HIGH
            )
        end
    endtask
endclass
