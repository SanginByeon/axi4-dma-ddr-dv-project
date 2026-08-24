// ============================================================================
// utility_pkg.sv - DMA Verification Utility Package
//
// - MMIO register read/write, DMA 완료 대기 및 status polling task 제공.
// - UVM sequence의 source memory preload와 scoreboard의 backdoor read 지원.
// - 4KB 메모리 범위를 확인하고 backdoor 접근 실패를 UVM fatal로 처리.
// - Step 1 MMIO 접근 timing을 유지하며 진행 로그를 UVM verbosity로 제어.
// - Utility task/function을 automatic으로 선언하여 재진입 가능하게 구성.
// ============================================================================

package utility_pkg;

    `include "uvm_macros.svh"
    import uvm_pkg::*;

    // [Virtual interface] : MMIO utility task에서 사용하는 interface handle
    virtual mmio_if.tb_mp mif;

    // [DDR backdoor] : Memory 경로와 32-bit word 개수
    localparam string DDR_MEM_PATH = "tb.ddr_model.mem";
    localparam int unsigned DDR_WORD_COUNT = 1024;

    // [MMIO 쓰기] : posedge 정렬 → 한 클록 유지 → ack 대기 → 상세 로그
    task automatic write_dma_reg(input [7:0] addr, input [31:0] data);
        @(posedge mif.clk);
        mif.dma_reg_addr  <= addr;  // 주소 제시
        mif.dma_reg_wdata <= data;  // 데이터 제시

        mif.dma_reg_write <= 1'b1;  // write 활성
        @(posedge mif.clk);         // 한 클록 유지(슬레이브 래칭 여유)
        mif.dma_reg_write <= 1'b0;  // write 비활성
        wait (mif.dma_reg_ack);     // 설계로부터 완료 응답 대기
        `uvm_info(
            "MMIO",
            $sformatf("REG[0x%02X] <- 0x%08X", addr, data),
            UVM_HIGH
        )
    endtask

    // [MMIO 읽기] : 주소 제시 → 2클록 안정화 → rdata 샘플 → 상세 로그
    task automatic read_dma_reg(input [7:0] addr, output [31:0] data);
        @(posedge mif.clk);
        mif.dma_reg_addr  <= addr;  // 주소 제시
        mif.dma_reg_write <= 1'b0;  // read 모드
        @(posedge mif.clk);        // 1클록 여유(파이프라인/복합 경로)
        @(posedge mif.clk);        // 추가 1클록(메타/지연 흡수)
        data = mif.dma_reg_rdata;   // 읽은 데이터 채취
        `uvm_info(
            "MMIO",
            $sformatf("REG[0x%02X] -> 0x%08X", addr, data),
            UVM_HIGH
        )
    endtask

    // [DMA 완료 대기] : 완료/오류/타임아웃 중 첫 사건을 에지 기반으로 포착
    task automatic wait_dma_completion(input int timeout_cycles = 1000);
        `uvm_info(
            "DMA_WAIT",
            "Waiting for DMA completion...",
            UVM_MEDIUM
        )
        fork
            begin
                @(posedge mif.dma_done_int);  // 완료 인터럽트 상승엣지
                `uvm_info(
                    "DMA_WAIT",
                    "DMA completion interrupt received!",
                    UVM_MEDIUM
                )
            end
            begin
                @(posedge mif.dma_error_int);  // 오류 인터럽트 상승엣지
                `uvm_info(
                    "DMA_WAIT",
                    "DMA error interrupt occurred!",
                    UVM_MEDIUM
                )
            end
            begin
                repeat (timeout_cycles) @(posedge mif.clk); // 타임아웃 카운터
                `uvm_info(
                    "DMA_WAIT",
                    $sformatf("DMA timeout after %0d cycles", timeout_cycles),
                    UVM_MEDIUM
                )
            end
        join_any      // 첫 완료 후 합류

        disable fork;  // 나머지 스레드 종료(리소스 누수 방지)
    endtask

    // [STATUS 폴링] : 인터럽트가 없거나 놓쳤을 때 보조 경로로 완료 확인
    task automatic wait_done_via_status(input int max_tries = 20);
        int i;
        logic [31:0] s;

        for (i = 0; i < max_tries; i++) begin
            read_dma_reg(8'h04, s);  // STATUS(0x04)
            if (s[1]) return;        // done 비트=1이면 즉시 복귀
            @(posedge mif.clk);      // 다음 폴링까지 1클록 대기
        end

        // Error interrupt 경로에서는 done=0이 정상일 수 있으므로 정보 로그로 처리
        `uvm_info("DMA_WAIT", "STATUS polling timeout (done=0)", UVM_MEDIUM)
    endtask

    // [Source memory preload] : src_addr부터 data_payload를 32-bit word 단위로 주입
    task automatic preload_src_mem(input [31:0] src_addr, input byte data_payload[]);
        for (int i = 0; i < data_payload.size(); i += 4) begin
            bit [31:0] word = 0;
            int unsigned word_idx;  // 메모리 모델의 word index
            string path;

            if (i < data_payload.size())
                word[7:0] = data_payload[i];
            if (i + 1 < data_payload.size())
                word[15:8] = data_payload[i + 1];
            if (i + 2 < data_payload.size())
                word[23:16] = data_payload[i + 2];
            if (i + 3 < data_payload.size())
                word[31:24] = data_payload[i + 3];

            // 바이트 주소를 word index로 변환하고 메모리 범위 확인
            word_idx = (src_addr + i) >> 2;
            if (word_idx >= DDR_WORD_COUNT)
                `uvm_fatal("PRELOAD", $sformatf(
                    "Address out of DDR range: addr=0x%0h, idx=%0d",
                    src_addr + i, word_idx
                ))

            // 메모리 모델의 mem[word_idx]에 데이터 직접 주입
            path = $sformatf("%s[%0d]", DDR_MEM_PATH, word_idx);
            if (!uvm_hdl_deposit(path, word))
                `uvm_fatal("PRELOAD", $sformatf(
                    "uvm_hdl_deposit failed: %s", path
                ))
        end
    endtask

    // [DDR memory read] : 지정 주소의 32-bit word를 backdoor로 읽기
    function automatic void read_ddr_mem(input [31:0] addr, output [31:0] data);
        int unsigned word_idx;
        string path;

        // 바이트 주소를 word index로 변환하고 메모리 범위 확인
        word_idx = addr >> 2;
        if (word_idx >= DDR_WORD_COUNT)
            `uvm_fatal("SCB", $sformatf(
                "Address out of DDR range: addr=0x%0h, idx=%0d",
                addr, word_idx
            ))

        // 메모리 모델의 mem[word_idx]에서 데이터 직접 읽기
        path = $sformatf("%s[%0d]", DDR_MEM_PATH, word_idx);
        if (!uvm_hdl_read(path, data))
            `uvm_fatal("SCB", $sformatf(
                "uvm_hdl_read failed: %s", path
            ))
    endfunction

endpackage
