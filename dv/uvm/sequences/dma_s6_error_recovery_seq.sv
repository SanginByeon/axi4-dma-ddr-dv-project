// ============================================================================
// dma_s6_error_recovery_seq.sv - DMA Scenario 6 Error Recovery Sequence
//
// - Size error와 BRESP SLVERR 직후 각각 정상 transaction을 연속 실행.
// - S_ERROR에서 S_IDLE을 거쳐 후속 정상 전송으로 복구되는 경로를 확인.
// - 오류 원인별 recovery transaction의 데이터 무결성과 정상 완료를 검증.
// ============================================================================

import utility_pkg::*;

class dma_s6_error_recovery_seq extends dma_base_seq;
    `uvm_object_utils(dma_s6_error_recovery_seq)

    function new(input string name = "dma_s6_error_recovery_seq");
        super.new(name);
    endfunction

    // [body] : 오류 transaction과 후속 정상 transaction의 두 recovery pair 실행
    virtual task body();
        dma_tx t;

        int unsigned test_id[] = '{1, 2, 3, 4};
        int unsigned size_bytes[] = '{3, 16, 64, 16};
        int unsigned error_inject_list[] = '{0, 0, 1, 0};
        bit [31:0] src_addr_list[] = '{
            32'h0000_0100, 32'h0000_0200,
            32'h0000_0300, 32'h0000_0400
        };
        bit [31:0] dst_addr_list[] = '{
            32'h0000_0900, 32'h0000_0A00,
            32'h0000_0B00, 32'h0000_0C00
        };

        foreach (test_id[i]) begin
            int unsigned target_size = size_bytes[i];
            bit target_error_inject = error_inject_list[i];
            bit [31:0] target_src = src_addr_list[i];
            bit [31:0] target_dst = dst_addr_list[i];

            t = dma_tx::type_id::create(
                $sformatf("t_s6_id%0d", test_id[i])
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
                error_inject      == local::target_error_inject;
            }) begin
                `uvm_fatal(
                    "S6_SEQ",
                    $sformatf("Failed to randomize S6 transaction ID %0d", test_id[i])
                )
            end

            case (test_id[i])
                1: t.scenario_name = "[S6-1] Size Error before Recovery";
                2: t.scenario_name = "[S6-2] Normal Transfer after Size Error";
                3: t.scenario_name = "[S6-3] SLVERR before Recovery";
                4: t.scenario_name = "[S6-4] Normal Transfer after SLVERR";
            endcase

            // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
            preload_src_mem(t.src_addr, t.data_payload);

            finish_item(t);

            `uvm_info(
                "S6_SEQ",
                $sformatf("Generated S6 Transaction: %s", t.convert2string()),
                UVM_HIGH
            )
        end
    endtask
endclass
