// ============================================================================
// dma_s7_random_seq.sv - DMA Scenario 7 Constrained-Random Sequence
//
// - 4-byte 정렬, 4KB 범위 및 비중첩 constraint 안에서 정상 transaction 생성.
// - 전송 크기, source/destination 주소 및 backpressure 확률을 constrained-random 조합.
// - Constraint 기반 무작위 정상 전송과 데이터 무결성을 추가 확인.
// ============================================================================

import utility_pkg::*;

class dma_s7_random_seq extends dma_base_seq;
    `uvm_object_utils(dma_s7_random_seq)

    localparam int unsigned RANDOM_TX_COUNT = 5;

    function new(input string name = "dma_s7_random_seq");
        super.new(name);
    endfunction

    // [body] : 정상 constrained-random transaction 반복 생성 및 source memory 초기화
    virtual task body();
        dma_tx t;

        for (int unsigned i = 0; i < RANDOM_TX_COUNT; i++) begin
            t = dma_tx::type_id::create(
                $sformatf("t_s7_id%0d", i + 1)
            );

            start_item(t);

            if (!t.randomize() with {
                size inside {[4:256]};
                size[1:0] == 2'b00;

                src_addr[11:10] dist {
                    2'd0 := 1,
                    [2'd1:2'd2] :/ 2,
                    2'd3 := 1
                };
                dst_addr[11:10] dist {
                    2'd0 := 1,
                    [2'd1:2'd2] :/ 2,
                    2'd3 := 1
                };

                enable == 1'b1;
                start  == 1'b1;
                irq    == 1'b1;

                backpressure_prob inside {[1:99]};
                backpressure_prob dist {
                    [1:30]  :/ 3,
                    [31:70] :/ 3,
                    [71:99] :/ 3
                };
                error_inject == 1'b0;
            }) begin
                `uvm_fatal(
                    "S7_SEQ",
                    $sformatf("Failed to randomize S7 transaction ID %0d", i + 1)
                )
            end

            t.scenario_name = $sformatf(
                "[S7-%0d] Constrained-Random Normal Transfer",
                i + 1
            );

            // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
            preload_src_mem(t.src_addr, t.data_payload);

            finish_item(t);

            `uvm_info(
                "S7_SEQ",
                $sformatf("Generated S7 Transaction: %s", t.convert2string()),
                UVM_HIGH
            )
        end
    endtask
endclass
