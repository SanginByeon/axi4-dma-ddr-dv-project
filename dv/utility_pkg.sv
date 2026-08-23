// ============================================================================
// utility_pkg.sv - MMIO Utility Task Package
//
// - MMIO register read/write, DMA 완료 대기 및 status polling task 제공.
// - Baseline testbench 내부 utility task의 별도 package 분리.
// - 기존 task의 동작 및 MMIO 접근 timing 유지.
// - 재사용 안정성 확보를 위한 automatic task 선언.
// ============================================================================

package utility_pkg;

    // 가상 인터페이스 핸들 변수 선언
    virtual mmio_if.tb_mp mif;

    // [MMIO 쓰기] : posedge 정렬 → 한 클록 유지 → ack 대기 → 로그
    task automatic write_dma_reg(input [7:0] addr, input [31:0] data);
        @(posedge mif.clk);
        mif.dma_reg_addr <= addr;  // 주소 제시
        mif.dma_reg_wdata <= data; // 데이터 제시

        mif.dma_reg_write <= 1;  // write 활성
        @(posedge mif.clk);      // 한 클록 유지(슬레이브 래칭 여유)
        mif.dma_reg_write <= 0;  // write 비활성
        wait(mif.dma_reg_ack);   // 설계로부터 완료 응답 대기
        $display("[%6.1f ns] REG[0x%02X] <- 0x%08X", real'($time) / 1000.0, addr, data);
    endtask

    // [MMIO 읽기] : 주소 제시 → 2클록 안정화 → rdata 샘플 → 로그
    task automatic read_dma_reg(input [7:0] addr, output [31:0] data);
        @(posedge mif.clk);
        mif.dma_reg_addr <= addr;  // 주소 제시
        mif.dma_reg_write <= 0;    // read 모드
        @(posedge mif.clk);        // 1클록 여유(파이프라인/복합 경로)
        @(posedge mif.clk);        // 추가 1클록(메타/지연 흡수)
        data = mif.dma_reg_rdata;   // 읽은 데이터 채취
        $display("[%6.1f ns] REG[0x%02X] -> 0x%08X", real'($time) / 1000.0, addr, data);
    endtask

    // [DMA 완료 대기] : 완료/오류/타임아웃 중 첫 사건을 에지 기반으로 포착
    task automatic wait_dma_completion(input int timeout_cycles = 1000);
        $display("[%6.1f ns] Waiting for DMA completion...", real'($time) / 1000.0);
        fork
            begin
                @(posedge mif.dma_done_int);  // 완료 인터럽트 상승엣지
                $display("[%6.1f ns] DMA completion interrupt received!", real'($time) / 1000.0);
            end
            begin
                @(posedge mif.dma_error_int);  // 오류 인터럽트 상승엣지
                $display("[%6.1f ns] DMA error interrupt occurred!", real'($time) / 1000.0);
            end
            begin
                repeat(timeout_cycles) @(posedge mif.clk);  // 타임아웃 카운터
                $display("[%6.1f ns] DMA timeout after %0d cycles", real'($time) / 1000.0, timeout_cycles);
            end
        join_any      // 첫 완료 후 합류

        disable fork;  // 나머지 스레드 종료(리소스 누수 방지)
    endtask

    // [STATUS 폴링] : 인터럽트가 없거나 놓쳤을 때 보조 경로로 완료 확인
    task automatic wait_done_via_status(input int max_tries = 20);
        int i;
        logic [31:0] s;

        for (i = 0; i < max_tries; i++) begin
            read_dma_reg(8'h04, s);  // STATUS(가정 주소 0x04)
            if (s[1]) return;        // done 비트=1이면 즉시 복귀
            @(posedge mif.clk);      // 다음 폴링까지 1클록 대기
        end

        $display("STATUS polling timeout (done=0)");  // 폴링 타임아웃 알림
    endtask

endpackage
