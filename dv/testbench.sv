// ============================================================================
// testbench.sv - DMA-DDR UVM Testbench Top
//
// - DMA controller, DDR memory model 및 AXI4/MMIO/DDR model interface를 연결.
// - UVM 환경에 virtual interface를 전달하고 dma_test를 실행.
// - 정상 경계값, 오류, backpressure 및 constrained-random 시나리오를 실행.
// - Transaction 기반 scoreboard로 전체 전송 영역의 데이터 무결성을 검증.
// - AXI4 W 채널의 backpressure 신호 유지와 WLAST timing을 assertion으로 검증.
// - Transaction/FSM/AXI event functional coverage 및 성능 결과를 UVM report phase에서 출력.
// - DMA 상태와 AXI 활동을 verbosity 기반 UVM 로그로 제공.
// ============================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "mmio_if.sv"
`include "utility_pkg.sv"
import utility_pkg::*;

`include "coverage.sv"
`include "axi_checker.sv"

`include "dma_tx.sv"
`include "dma_base_seq.sv"
`include "dma_s1_boundary_seq.sv"
`include "dma_s2_size_error_seq.sv"
`include "dma_s3_backpressure_seq.sv"
`include "dma_s4_slverr_seq.sv"
`include "dma_s5_backpressure_slverr_seq.sv"
`include "dma_s6_error_recovery_seq.sv"
`include "dma_s7_random_seq.sv"
`include "dma_driver.sv"
`include "dma_monitor.sv"
`include "dma_scoreboard.sv"
`include "dma_agent.sv"
`include "dma_env.sv"
`include "dma_test.sv"

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

    // [DDR memory model 제어] : UVM 환경에서 backpressure와 BRESP 오류 설정 전달
    ddr_model_if ddr_model_ctrl(.aclk(clk), .aresetn(resetn));

    // [DDR 메모리 모델] : AXI Slave로 동작
    ddr_memory_model ddr_model (
        .axi     (memory_axi.slave),
        .ddr_cfg (ddr_model_ctrl)
    );

    // [DMA 컨트롤러] : AXI Master로 메모리에 접근
    dma_controller #(
        .DEBUG_LOG_ENABLE (1'b0)
    ) dma_ctrl (
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

    // [AXI4 W checker] : Backpressure 중 신호 유지와 마지막 beat의 WLAST timing 확인
    axi_checker axi_w_checker (
        .axi          (memory_axi),
        .w_beats_sent (dma_ctrl.w_beats_sent)
    );

    // [UVM 시작] : 실제 interface를 virtual interface로 전달한 뒤 test 실행
    initial begin
        uvm_config_db #(virtual mmio_if.tb_mp)::set(
            null, "*", "mif", mmio.tb_mp
        );
        uvm_config_db #(virtual axi4_if)::set(
            null, "*", "aif", memory_axi
        );
        uvm_config_db #(virtual ddr_model_if)::set(
            null, "*", "dif", ddr_model_ctrl
        );

        run_test("dma_test");
    end

    // [시뮬레이션 관측] : 파형 덤프와 시작 정보 출력
    initial begin
        $dumpfile("dma_ddr_system.vcd"); // 파형 파일명
        $dumpvars(0, tb);                 // tb 하위 전체 덤프
        wait(resetn);                     // 리셋 해제 기다림
        repeat(5) @(posedge clk);         // 안정화용 5클록

        `uvm_info(
            "TB",
            "\n============================================================\n DMA-DDR UVM Verification Started\n============================================================",
            UVM_LOW
        )
    end

    // [실시간 모니터링] : 상태/레지스터/AXI 활동 로그
    logic [3:0] prev_state = 4'hF;  // 직전 상태 기록(초기 미정)

    // [상태 변화] : dbg_state가 바뀔 때마다 사람이 읽기 쉬운 문자열로 로그
    always @(posedge clk) begin
        if (dbg_state != prev_state && resetn) begin
            `uvm_info(
                "TB",
                $sformatf("DMA State: %s", get_dma_state_name(dbg_state)),
                UVM_HIGH
            )
            prev_state <= dbg_state;
        end
    end

    // [start_active 변화] : 시작 조건 토글 모니터링(플로우 디버깅에 유용)
    logic prev_start_active = 1'b0;
    always @(posedge clk) begin
        if (dma_ctrl.start_active != prev_start_active && resetn) begin
            `uvm_info(
                "TB",
                $sformatf(
                    "start_active changed: %0b -> %0b",
                    prev_start_active, dma_ctrl.start_active
                ),
                UVM_HIGH
            )
            prev_start_active <= dma_ctrl.start_active;
        end
    end

    // [제어 레지스터 변화] : 비트 단위 비교 후 핵심 필드만 요약하여 출력
    logic [31:0] prev_ctrl = 32'h0;
    always @(posedge clk) begin
        if (logic'(dma_ctrl.ctrl) != prev_ctrl && resetn) begin
            `uvm_info(
                "TB",
                $sformatf(
                    "Control register changed: enable=%0b, start=%0b",
                    dma_ctrl.ctrl.enable, dma_ctrl.ctrl.start
                ),
                UVM_HIGH
            )
            prev_ctrl <= logic'(dma_ctrl.ctrl);
        end
    end

    // [AXI 주소 채널] : aw/ar 핸드셰이크 성사 시 어드레스/beat 수를 기록
    always @(posedge clk) begin
        if (memory_axi.awvalid && memory_axi.awready) begin
            `uvm_info(
                "TB",
                $sformatf(
                    "AXI Write: 0x%08X, %0d beats",
                    memory_axi.awaddr, memory_axi.awlen + 1
                ),
                UVM_HIGH
            )
        end

        if (memory_axi.arvalid && memory_axi.arready) begin
            `uvm_info(
                "TB",
                $sformatf(
                    "AXI Read: 0x%08X, %0d beats",
                    memory_axi.araddr, memory_axi.arlen + 1
                ),
                UVM_HIGH
            )
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
