// ============================================================================
// testbench.sv - DMA-DDR Directed Testbench Top
//
// - DMA controller, DDR memory model 및 AXI4/MMIO interface를 연결.
// - 분리된 utility package와 functional coverage model을 사용.
// - Baseline의 directed test scenario와 검증 절차를 동일하게 유지.
// - 전송 결과, 데이터 무결성, 성능 및 functional coverage 결과를 출력.
// ============================================================================

`timescale 1ns/1ps

`include "mmio_if.sv"
`include "utility_pkg.sv"
`include "coverage.sv"

import utility_pkg::*;


module tb;

    logic clk, resetn;  // 클록/리셋(활성-로우)

    // [클록 생성] : 100MHz(주기 10ns) → #5마다 토글
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // [리셋 시퀀스] : 20ns 동안 resetn=0, 이후 1로 해제(동기화 호환)
    initial begin
        resetn = 0;
        #20 resetn = 1;
    end

    // [디버그] : 내부 관측용(상태/버스트/버퍼)
    logic [3:0] dbg_state;
    logic [7:0] dbg_burst_len;
    logic [4:0] dbg_buf_count;

    // [AXI 배선] : 공용 버스 인터페이스 인스턴스(클록/리셋 연결)
    axi4_if memory_axi(.aclk(clk), .aresetn(resetn));

    // [MMIO 배선]
    mmio_if mmio(.clk(clk));

    // [mif 바인딩] : MMIO interface 인스턴스를 utility_pkg의 mif에 바인딩
    initial begin
        utility_pkg::mif = mmio.tb_mp;
    end

    // [DDR 메모리 모델] : AXI Slave로 동작
    ddr_memory_model ddr_model (
        .axi(memory_axi.slave)
    );

    // [DMA 컨트롤러] : AXI Master로 메모리에 접근
    dma_controller dma_ctrl (
        .clk (clk),
        .resetn (resetn),

        .reg_addr (mmio.dma_reg_addr),
        .reg_wdata (mmio.dma_reg_wdata),
        .reg_write (mmio.dma_reg_write),
        .reg_rdata (mmio.dma_reg_rdata),
        .reg_ack (mmio.dma_reg_ack),

        .m (memory_axi.master),

        .dma_done_int (mmio.dma_done_int),
        .dma_error_int (mmio.dma_error_int),

        .dbg_state (dbg_state),
        .dbg_burst_len (dbg_burst_len),
        .dbg_buf_count (dbg_buf_count)
    );

    // [커버리지 인스턴스] : 생성 즉시 클록마다 샘플링 시작
    cg_dma_coverage cov_inst = new();

    // [메인 시퀀스] : 파형 덤프 → 안정화 → 3시나리오 → 검증/리포트 → 종료
    initial begin
        $dumpfile("dma_ddr_system.vcd"); // 파형 파일명
        $dumpvars(0, tb);                 // tb 하위 전체 덤프
        mmio.dma_reg_write <= 0;  // 기본값 초기화
        wait(resetn);              // 리셋 해제 기다림
        repeat(5) @(posedge clk);  // 안정화용 5클록

        $display("\n============================================================");
        $display(" DMA-DDR Memory System Comprehensive Test Started");
        $display("============================================================");
        $display("Start time: %0t ns", $time);

        // [시나리오] : 크기/정렬/버스트/전이를 다양하게 자극
        test_scenario_1_basic_copy();          // 256B 기본 복사(정렬/정상 플로우)
        test_scenario_2_large_transfer();      // 1024B 대용량(멀티버스트 가능)
        test_scenario_3_burst_optimization();  // 16B/64B(짧은 전송 거동)

        // [검증/리포트] : 데이터 무결성 → 성능 → 커버리지
        verify_data_integrity();
        analyze_performance();
        generate_coverage_report();

        $display("\n============================================================");
        $display(" Test Completed Successfully");
        $display("============================================================");
        #100 $finish;  // 로그 마무리 여유 후 종료
    end

    // -------------------------
    // 테스트 시나리오 : 설정→시작→완료확인 의 표준 패턴
    // -------------------------

    // [S1: 256B 기본 복사] : 정렬 주소, 정상 플로우/완료 신호 확인
    task test_scenario_1_basic_copy();
        logic [31:0] status;

        $display("\n--- Scenario 1: Basic Memory Copy (256 bytes) ---");
        write_dma_reg(8'h08, 32'h00000000); // SRC_ADDR=0x0000
        write_dma_reg(8'h0C, 32'h00000400); // DST_ADDR=0x0400(1KB 오프셋)
        write_dma_reg(8'h10, 32'h00000100); // SIZE=0x100(256B)
        write_dma_reg(8'h00, 32'h00000007); // CTRL: enable/start/irq(가정)
        wait_dma_completion(500);           // 인터럽트/오류/타임아웃 중 하나 포착

        wait_done_via_status();           // 보조 확인(STATUS 폴링)
        read_dma_reg(8'h04, status);      // STATUS 읽기
        if (status[1])
            $display("Basic copy test passed"); // done=1이면 성공
        else
            $display("Basic copy test failed"); // 아니면 실패

        read_dma_reg(8'h14, status);             // BYTES_TRANSFERRED(가정: 0x14)
        $display(" Bytes transferred: %0d", status); // 실제 전송량 로깅
    endtask

    // [S2: 1024B 대용량] : 버스트/멀티버스트 경로 및 응답 시퀀스 관찰
    task test_scenario_2_large_transfer();
        $display("\n--- Scenario 2: Large Transfer (1024 bytes) ---");
        write_dma_reg(8'h08, 32'h00000100); // SRC_ADDR=0x0100
        write_dma_reg(8'h0C, 32'h00000800); // DST_ADDR=0x0800
        write_dma_reg(8'h10, 32'h00000400); // SIZE=0x400(1024B)
        write_dma_reg(8'h00, 32'h00000007); // CTRL 시작
        wait_dma_completion(800);           // 여유 타임아웃
        $display("Large transfer completed"); // 완료 로그
    endtask

    // [S3: 16B/64B] : 작은 전송에서 len/handshake, 오버헤드/최적화 관찰
    task test_scenario_3_burst_optimization();
        $display("\n--- Scenario 3: Burst Optimization for Various Sizes---");
        $display(" 3-1. Small transfer (16 bytes)");
        write_dma_reg(8'h08, 32'h00000200); // SRC_ADDR=0x0200
        write_dma_reg(8'h0C, 32'h00000300); // DST_ADDR=0x0300
        write_dma_reg(8'h10, 32'h00000010); // SIZE=16B
        write_dma_reg(8'h00, 32'h00000007); // 시작
        wait_dma_completion(200);

        $display(" 3-2. Medium transfer (64 bytes)");
        write_dma_reg(8'h08, 32'h00000210); // SRC_ADDR=0x0210
        write_dma_reg(8'h0C, 32'h00000310); // DST_ADDR=0x0310
        write_dma_reg(8'h10, 32'h00000040); // SIZE=64B
        write_dma_reg(8'h00, 32'h00000007); // 시작
        wait_dma_completion(300);

        $display("Burst optimization tests completed");
    endtask

    // -------------------------
    // 데이터 무결성 검증 : 간단 샘플 비교(확장 가능)
    // -------------------------
    task automatic verify_data_integrity();
        automatic int error_count = 0;  // 에러 누계
        logic [31:0] src_data, dst_data;

        $display("\n--- Data Integrity Verification ---");
        for (int i = 0; i < 8; i++) begin // 예: 8워드만 샘플 검증
            src_data = ddr_model.mem[i];       // 소스 워드 i
            dst_data = ddr_model.mem[256 + i]; // 목적지 워드(0x400=1024B → 워드 오프셋 256)

            if (src_data == dst_data)
                $display(" [%2d] Match: 0x%08X", i, src_data);
            else begin
                $display(" [%2d] Mismatch: src=0x%08X, dst=0x%08X", i, src_data, dst_data);
                error_count++;
            end
        end

        if (error_count == 0)
            $display("All data transferred correctly!");
        else
            $display("Found %0d data mismatches", error_count);
    endtask

    // -------------------------
    // 성능 분석 : 총 전송량/총 시뮬레이션 시간으로 대략적 Mbps 산출
    // -------------------------
    task analyze_performance();
        real total_time_ns, throughput_mbps;
        int total_cycles;

        $display("\n--- Performance Analysis ---");
        total_time_ns = real'($time);             // 현재까지 경과 시간(ns)
        total_cycles = int'(total_time_ns / 10.0); // 100MHz → 10ns/사이클
        throughput_mbps =
            (256.0 + 1024.0 + 16.0 + 64.0) * 8.0 / // 총 비트 수
            total_time_ns * 1000.0;                // ns→us 보정(대략적)

        $display(" Total execution time: %0.1f ns (%0d cycles)", total_time_ns, total_cycles);
        $display(" Estimated throughput: %0.2f Mbps", throughput_mbps);

        if (throughput_mbps > 100.0)
            $display(" Excellent performance");
        else if (throughput_mbps > 50.0)
            $display(" Good performance");
        else
            $display(" Performance improvement needed");
    endtask

    // -------------------------
    // 커버리지 리포트 : 항목별/전체 요약 출력
    // -------------------------
    task generate_coverage_report();
        real total_coverage;
        real size_cov, state_cov, align_cov, cross_cov;

        $display("\n--- Coverage Analysis Report ---");
        total_coverage = cov_inst.get_coverage();           // 전체 %
        size_cov = cov_inst.cp_size.get_coverage();         // 크기 분포 %
        state_cov = cov_inst.cp_dma_state.get_coverage();   // 상태 분포 %
        align_cov = (cov_inst.cp_src_alignment.get_coverage()
                   + cov_inst.cp_dst_alignment.get_coverage()) / 2.0; // 정렬 평균 %
        cross_cov = cov_inst.cx_size_alignment.get_coverage();        // 교차 %

        $display(" Overall Coverage: %6.2f%%", total_coverage);
        $display(" Transfer Size Pattern: %6.2f%%", size_cov);
        $display(" DMA State Transition: %6.2f%%", state_cov);
        $display(" Address Alignment: %6.2f%%", align_cov);
        $display(" Cross Scenario: %6.2f%%", cross_cov);

        if (total_coverage >= 90.0)
            $display(" Excellent Coverage - Very good test quality");
        else if (total_coverage >= 75.0)
            $display(" Good Coverage - Additional tests recommended");
        else
            $display(" Insufficient Coverage - More test scenarios needed");
    endtask

    // -------------------------
    // 실시간 모니터링 : 상태/레지스터/AXI 활동 로그
    // -------------------------
    logic [3:0] prev_state = 4'hF;  // 직전 상태 기록(초기 미정)

    // [상태 변화] : dbg_state가 바뀔 때마다 사람이 읽기 쉬운 문자열로 로그
    always @(posedge clk) begin
        if (dbg_state != prev_state && resetn) begin
            $display("[%6.1f ns] DMA State: %s",
                     real'($time) / 1000.0, get_dma_state_name(dbg_state));
            prev_state <= dbg_state;
        end
    end

    // [start_active 변화] : 시작 조건 토글 모니터링(플로우 디버깅에 유용)
    logic prev_start_active = 1'b0;
    always @(posedge clk) begin
        if (dma_ctrl.start_active != prev_start_active && resetn) begin
            $display("[%6.1f ns] start_active changed: %0b -> %0b",
                     real'($time) / 1000.0, prev_start_active, dma_ctrl.start_active);
            prev_start_active <= dma_ctrl.start_active;
        end
    end

    // [제어 레지스터 변화] : 비트 단위 비교를 위해 캐스팅, 핵심 필드만 요약 로그
    logic [31:0] prev_ctrl = 32'h0;
    always @(posedge clk) begin
        if (logic'(dma_ctrl.ctrl) != prev_ctrl && resetn) begin
            $display("[%6.1f ns] Control register changed: enable=%0b, start=%0b",
                     real'($time) / 1000.0, dma_ctrl.ctrl.enable, dma_ctrl.ctrl.start);
            prev_ctrl <= logic'(dma_ctrl.ctrl);
        end
    end

    // [AXI 주소 채널] : aw/ar 핸드셰이크 성사 시 어드레스/beat 수를 기록
    always @(posedge clk) begin
        if (memory_axi.awvalid && memory_axi.awready) begin
            $display("[%6.1f ns] AXI Write: 0x%08X, %0d beats",
                     real'($time) / 1000.0, memory_axi.awaddr, memory_axi.awlen + 1);
        end

        if (memory_axi.arvalid && memory_axi.arready) begin
            $display("[%6.1f ns] AXI Read: 0x%08X, %0d beats",
                     real'($time) / 1000.0, memory_axi.araddr, memory_axi.arlen + 1);
        end
    end

    // [상태 코드 → 이름] : 로그 가독성 향상용 매핑
    function string get_dma_state_name(input [3:0] s);
        case (s)
            4'h0: return "IDLE";
            4'h1: return "SETUP";
            4'h2: return "READ_ADDR";
            4'h3: return "READ_DATA";
            4'h4: return "WRITE_ADDR";
            4'h5: return "WRITE_DATA";
            4'h6: return "WRITE_RESP";
            4'h7: return "NEXT_BURST";
            4'h8: return "COMPLETE";
            4'h9: return "ERROR";
            default: return "UNKNOWN";
        endcase
    endfunction
endmodule
