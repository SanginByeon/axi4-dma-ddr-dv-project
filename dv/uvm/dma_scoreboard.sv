// ============================================================================
// dma_scoreboard.sv - DMA UVM Scoreboard
//
// - Monitor가 전달한 DMA transaction의 source와 destination memory를
//   backdoor로 읽어 전체 전송 구간의 데이터 무결성을 32-bit word 단위로 판정.
// - Unknown data와 누락·중복 transaction을 검출하여 검증 신뢰성을 확보.
// ============================================================================

class dma_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(dma_scoreboard)

    uvm_analysis_imp #(dma_tx, dma_scoreboard) recv;

    // Monitor로부터 수신하여 데이터 무결성 검사를 수행한 transaction 수
    int checked_count;

    // Test에서 생성할 것으로 설정한 예상 transaction 수
    int expected_count;

    function new(input string name = "dma_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [build_phase] : Analysis implementation과 transaction count 설정
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        recv = new("recv", this);
        checked_count = 0;

        // Test에서 전달한 예상 transaction 수를 가져와 누락·중복 검사에 사용
        if (!uvm_config_db #(int)::get(this, "", "expected_count", expected_count))
            `uvm_fatal("SCB", "Unable to get expected_count from uvm_config_db")
    endfunction

    // [write] : Monitor가 전달한 transaction을 수신하여 데이터 무결성 검사 수행
    virtual function void write(input dma_tx t);
        checked_count++;

        `uvm_info(
            "SCB",
            $sformatf(
                "Rcvd transaction #%0d from dma_monitor: %s",
                checked_count, t.convert2string()
            ),
            UVM_HIGH
        )

        check_dma_transfer(t);
    endfunction

    // [check_dma_transfer] : 전송 구간의 source와 destination data를 word 단위로 비교
    virtual function void check_dma_transfer(dma_tx t);
        int mismatch_count = 0;
        int unknown_count = 0;
        logic [31:0] src_data, dst_data;

        // Monitor가 수집한 주소와 크기를 기반으로 source/destination data 읽기
        for (int i = 0; i < t.size; i += 4) begin
            read_ddr_mem(t.src_addr + i, src_data);
            read_ddr_mem(t.dst_addr + i, dst_data);

            // X/Z가 포함된 데이터는 서로 같더라도 검증 실패로 처리
            if ($isunknown(src_data) || $isunknown(dst_data)) begin
                `uvm_error(
                    "SCB",
                    $sformatf(
                        "[%0d] Unknown data detected: src=0x%h, dst=0x%h",
                        i, src_data, dst_data
                    )
                )
                unknown_count++;
            end else if (src_data == dst_data)
                `uvm_info(
                    "SCB",
                    $sformatf("[%0d] Match src=0x%h, dst=0x%h", i, src_data, dst_data),
                    UVM_FULL
                )
            else begin
                `uvm_error(
                    "SCB",
                    $sformatf("[%0d] Mismatch src=0x%h, dst=0x%h", i, src_data, dst_data)
                )
                mismatch_count++;
            end
        end

        if ((mismatch_count == 0) && (unknown_count == 0))
            `uvm_info("SCB", "Data Transfer Verification PASSED", UVM_MEDIUM)
        else
            `uvm_error(
                "SCB",
                $sformatf(
                    "Data Transfer Verification FAILED: mismatches=%0d, unknowns=%0d",
                    mismatch_count, unknown_count
                )
            )
    endfunction

    // [check_phase] : 예상 transaction의 누락·중복 여부 확인
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        if (checked_count != expected_count)
            `uvm_error(
                "SCB",
                $sformatf(
                    "Transaction count mismatch: expected=%0d, checked=%0d",
                    expected_count, checked_count
                )
            )
        else
            `uvm_info(
                "SCB",
                $sformatf("All expected transactions checked: %0d", checked_count),
                UVM_LOW
            )
    endfunction
endclass
