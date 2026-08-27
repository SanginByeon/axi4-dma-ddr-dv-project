// ============================================================================
// dma_regression_seq.sv - DMA Multi-Seed Backpressure Regression Sequence
//
// - 하나의 seed에서 6개 전송 크기와 6개 backpressure 확률을 조합.
// - 정상 DMA 전송 36건을 생성하여 random stall timing에 대한 안정성을 반복 확인.
// - 각 transaction 전에 source memory를 검증용 data pattern으로 초기화.
// - BRESP error injection은 Step 4에서 검증을 완료했으므로 적용하지 않음.
// ============================================================================

import utility_pkg::*;

class dma_regression_seq extends dma_base_seq;
    `uvm_object_utils(dma_regression_seq)

    // Test에서 전달받아 scenario 이름에 기록할 simulator seed
    int unsigned simulation_seed;

    function new(input string name = "dma_regression_seq");
        super.new(name);
    endfunction

    // [body] : Backpressure 확률 6종과 전송 크기 6종의 6×6 matrix 생성
    virtual task body();
        dma_tx t;

        int unsigned size_bytes[] = '{4, 16, 64, 80, 512, 1028};
        int unsigned backpressure_probs[] = '{0, 10, 30, 50, 70, 90};

        foreach (backpressure_probs[p]) begin
            foreach (size_bytes[s]) begin
                int unsigned test_id = (p * size_bytes.size()) + s + 1;
                int unsigned target_size = size_bytes[s];
                int unsigned target_prob = backpressure_probs[p];

                t = dma_tx::type_id::create(
                    $sformatf("t_regr_id%0d", test_id)
                );

                start_item(t);

                if (!t.randomize() with {
                    src_addr == 32'h0000_0000;
                    dst_addr == 32'h0000_0800;
                    size     == local::target_size;

                    enable == 1'b1;
                    start  == 1'b1;
                    irq    == 1'b1;

                    backpressure_prob == local::target_prob;
                    error_inject      == 1'b0;
                }) begin
                    `uvm_fatal(
                        "REGR_SEQ",
                        $sformatf(
                            "Failed to randomize regression transaction ID %0d",
                            test_id
                        )
                    )
                end

                t.scenario_name = $sformatf(
                    "[REGR-SEED%0d-P%0d-S%0d] Backpressure Regression",
                    simulation_seed, target_prob, target_size
                );

                // 각 transaction 실행 전에 source memory를 data pattern으로 초기화
                preload_src_mem(t.src_addr, t.data_payload);

                finish_item(t);

                `uvm_info(
                    "REGR_SEQ",
                    $sformatf("Generated Regression Transaction: %s", t.convert2string()),
                    UVM_HIGH
                )
            end
        end
    endtask
endclass
