// ============================================================================
// dma_s3_backpressure_seq.sv - DMA Scenario 3 Backpressure Sequence
//
// - 1·4·16-beat write burst에 10%·50%·90% backpressure를 조합.
// - 실제 W channel stall 중 payload 안정성과 정상 완료를 확인.
// - Error injection 없이 backpressure 내성만 독립적으로 검증.
// ============================================================================

import utility_pkg::*;

class dma_s3_backpressure_seq extends dma_base_seq;
    `uvm_object_utils(dma_s3_backpressure_seq)

    function new(input string name = "dma_s3_backpressure_seq");
        super.new(name);
    endfunction

    // [body] : Burst 길이와 backpressure 확률의 3×3 조합 transaction 생성
    virtual task body();
        dma_tx t;

        int unsigned size_bytes[] = '{4, 16, 64};
        int unsigned backpressure_probs[] = '{10, 50, 90};
        bit [31:0] src_addr_list[] = '{
            32'h0000_0100, 32'h0000_0500, 32'h0000_0C00
        };
        bit [31:0] dst_addr_list[] = '{
            32'h0000_0500, 32'h0000_0C00, 32'h0000_0100
        };

        foreach (backpressure_probs[p]) begin
            foreach (size_bytes[b]) begin
                int unsigned test_id = (p * size_bytes.size()) + b + 1;
                int unsigned target_size = size_bytes[b];
                int unsigned target_prob = backpressure_probs[p];
                bit [31:0] target_src = src_addr_list[b];
                bit [31:0] target_dst = dst_addr_list[b];

                t = dma_tx::type_id::create(
                    $sformatf("t_s3_id%0d", test_id)
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
                    error_inject      == 1'b0;
                }) begin
                    `uvm_fatal(
                        "S3_SEQ",
                        $sformatf("Failed to randomize S3 transaction ID %0d", test_id)
                    )
                end

                t.scenario_name = $sformatf(
                    "[S3-%0d] %0dB Transfer with %0d%% Backpressure",
                    test_id, target_size, target_prob
                );

                // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
                preload_src_mem(t.src_addr, t.data_payload);

                finish_item(t);

                `uvm_info(
                    "S3_SEQ",
                    $sformatf("Generated S3 Transaction: %s", t.convert2string()),
                    UVM_HIGH
                )
            end
        end
    endtask
endclass
