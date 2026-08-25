// ============================================================================
// coverage.sv - DMA Functional Coverage Model
//
// - DMA transaction, FSM 및 AXI4 event coverage를 3개 covergroup으로 분리.
// - Transaction은 완료/오류 interrupt에서 1회, FSM과 AXI event는 clock마다 조건부 sampling.
// - DUT와 testbench의 관측 신호를 직접 사용하여 별도 coverage collector 없이 구성.
// ============================================================================

// [Transaction coverage] : 완료 또는 오류 interrupt마다 transaction 결과를 한 번 sampling
covergroup cg_dma_transaction
    @(posedge tb.mmio.dma_done_int or posedge tb.mmio.dma_error_int);
    option.per_instance = 1;
    option.name = "DMA_Transaction_Coverage";

    // [C-TX-01] : 전송 경계값은 각 값이 독립 bin으로 생성됨
    cp_size_boundary: coverpoint tb.dma_ctrl.size_reg {
        bins boundary[] = {
            1, 2, 3, 4, 12, 15, 16, 60, 64, 68, 80,
            256, 1024, 1028, 2048
        };
    }

    // [C-TX-02] : 4-byte aligned 정상 전송의 크기 분포
    cp_size_range: coverpoint tb.dma_ctrl.size_reg
        iff (
            (tb.dma_ctrl.size_reg >= 4) &&
            (tb.dma_ctrl.size_reg <= 2048) &&
            (tb.dma_ctrl.size_reg[1:0] == 2'b00)
        ) {
        bins size_tiny   = {[4:16]};
        bins size_small  = {[20:256]};
        bins size_medium = {[260:1024]};
        bins size_large  = {[1028:2048]};
    }

    // [C-TX-03] : 전송 크기를 정상, 초기 오류 및 잔여 byte 오류 조건으로 분류
    cp_size_category: coverpoint (
        (tb.dma_ctrl.size_reg < 4) ? 2'd0 :
        ((tb.dma_ctrl.size_reg[1:0] != 2'b00) ? 2'd1 : 2'd2)
    ) {
        bins undersized   = {2'd0};
        bins residual     = {2'd1};
        bins word_aligned = {2'd2};
    }

    // [C-TX-04] : Source 시작 주소가 위치한 4KB memory 영역
    cp_src_region: coverpoint tb.dma_ctrl.src_reg[11:10] {
        bins low  = {2'd0};
        bins mid  = {[2'd1:2'd2]};
        bins high = {2'd3};
    }

    // [C-TX-05] : Destination 시작 주소가 위치한 4KB memory 영역
    cp_dst_region: coverpoint tb.dma_ctrl.dst_reg[11:10] {
        bins low  = {2'd0};
        bins mid  = {[2'd1:2'd2]};
        bins high = {2'd3};
    }

    // [C-TX-06] : DDR memory model에 설정한 W channel backpressure 강도
    cp_backpressure_class: coverpoint tb.ddr_model_ctrl.backpressure_prob {
        bins bp_none   = {0};
        bins bp_low    = {[1:30]};
        bins bp_medium = {[31:70]};
        bins bp_high   = {[71:99]};
        illegal_bins out_of_range = default;
    }

    // [C-TX-07] : BRESP SLVERR 주입 설정
    cp_error_inject: coverpoint tb.ddr_model_ctrl.error_inject {
        bins disabled = {1'b0};
        bins enabled  = {1'b1};
    }

    // [C-TX-08] : DMA가 보고한 실제 종료 오류 코드
    cp_error_code: coverpoint tb.dma_ctrl.stat.error_code {
        bins normal      = {4'h0};
        bins size_error  = {4'h2};
        bins bresp_error = {4'h3};
        illegal_bins unexpected = default;
    }

    // [X-TX-01] : 전송 크기 원인과 실제 error code 연결
    cx_size_result: cross cp_size_category, cp_error_code {
        bins aligned_to_normal =
            binsof(cp_size_category.word_aligned) &&
            binsof(cp_error_code.normal);
        bins undersized_to_size_error =
            binsof(cp_size_category.undersized) &&
            binsof(cp_error_code.size_error);
        bins residual_to_size_error =
            binsof(cp_size_category.residual) &&
            binsof(cp_error_code.size_error);

        ignore_bins other_results =
            (binsof(cp_size_category.word_aligned) &&
             !binsof(cp_error_code.normal)) ||
            (binsof(cp_size_category.undersized) &&
             !binsof(cp_error_code.size_error)) ||
            (binsof(cp_size_category.residual) &&
             !binsof(cp_error_code.size_error));
    }

    // [X-TX-02] : Error injection 설정과 실제 error code 연결
    cx_inject_result: cross cp_error_inject, cp_error_code {
        bins no_inject_normal =
            binsof(cp_error_inject.disabled) &&
            binsof(cp_error_code.normal);
        bins no_inject_size_error =
            binsof(cp_error_inject.disabled) &&
            binsof(cp_error_code.size_error);
        bins inject_to_bresp_error =
            binsof(cp_error_inject.enabled) &&
            binsof(cp_error_code.bresp_error);

        ignore_bins other_results =
            (binsof(cp_error_inject.disabled) &&
             binsof(cp_error_code.bresp_error)) ||
            (binsof(cp_error_inject.enabled) &&
             !binsof(cp_error_code.bresp_error));
    }

    // [X-TX-03] : SLVERR 단독 및 backpressure 결합 조건
    cx_inject_backpressure: cross cp_error_inject, cp_backpressure_class;
endgroup

// [FSM coverage] : DMA state, state transition 및 S_SETUP 분기 sampling
covergroup cg_dma_fsm @(posedge tb.clk);
    option.per_instance = 1;
    option.name = "DMA_FSM_Coverage";

    // [C-FSM-01] : DMA FSM 상태
    cp_state: coverpoint tb.dbg_state iff (tb.resetn) {
        bins idle     = {4'h0};
        bins setup    = {4'h1};
        bins rd_addr  = {4'h2};
        bins rd_data  = {4'h3};
        bins wr_addr  = {4'h4};
        bins wr_data  = {4'h5};
        bins wr_resp  = {4'h6};
        bins next     = {4'h7};
        bins done     = {4'h8};
        bins error    = {4'h9};
        illegal_bins unexpected = default;
    }

    // [C-FSM-02] : 정상, multi-burst, 오류 및 복구 상태 전이
    cp_state_transition: coverpoint tb.dbg_state iff (tb.resetn) {
        bins idle_to_setup   = (4'h0 => 4'h1);
        bins setup_to_rd     = (4'h1 => 4'h2);
        bins rd_addr_to_data = (4'h2 => 4'h3);
        bins rd_to_wr_addr   = (4'h3 => 4'h4);
        bins wr_addr_to_data = (4'h4 => 4'h5);
        bins wr_data_to_resp = (4'h5 => 4'h6);
        bins resp_to_done    = (4'h6 => 4'h8);
        bins done_to_idle    = (4'h8 => 4'h0);
        bins resp_to_next    = (4'h6 => 4'h7);
        bins next_to_setup   = (4'h7 => 4'h1);
        bins setup_to_error  = (4'h1 => 4'h9);
        bins resp_to_error   = (4'h6 => 4'h9);
        bins error_to_idle   = (4'h9 => 4'h0);
        bins error_recovery  = (4'h9 => 4'h0 => 4'h1);
    }

    // [C-FSM-03] : S_SETUP이 실제 burst 길이를 결정하는 cycle만 sampling
    cp_setup_case: coverpoint tb.dma_ctrl.bytes_left
        iff (
            tb.resetn &&
            (tb.dbg_state == 4'h1) &&
            !tb.dma_ctrl.setup_complete
        ) {
        bins invalid_size  = {[1:3]};
        bins one_beat      = {[4:15]};
        bins four_beats    = {[16:63]};
        bins sixteen_beats = {[64:$]};
    }

    // [C-FSM-04] : 64B full burst 이후 잔여 구간에서 선택되는 S_SETUP 분기
    cp_tail_setup_case: coverpoint tb.dma_ctrl.bytes_left
        iff (
            tb.resetn &&
            (tb.dbg_state == 4'h1) &&
            !tb.dma_ctrl.setup_complete &&
            (tb.dma_ctrl.size_reg > 64) &&
            (tb.dma_ctrl.size_reg[1:0] == 2'b00) &&
            (tb.dma_ctrl.bytes_left >= 4) &&
            (tb.dma_ctrl.bytes_left < 64)
        ) {
        bins one_beat_tail   = {[4:15]};
        bins four_beats_tail = {[16:63]};
    }
endgroup

// [AXI event coverage] : AW/W/B channel의 실제 handshake와 stall event sampling
covergroup cg_axi_event @(posedge tb.clk);
    option.per_instance = 1;
    option.name = "AXI_Event_Coverage";

    // [C-AXI-01] : AW handshake에서 실제 burst 길이 sampling
    cp_awlen: coverpoint tb.memory_axi.awlen
        iff (
            tb.resetn &&
            tb.memory_axi.awvalid &&
            tb.memory_axi.awready
        ) {
        bins one_beat      = {8'd0};
        bins four_beats    = {8'd3};
        bins sixteen_beats = {8'd15};
        illegal_bins unexpected = default;
    }

    // [C-AXI-02] : AW handshake 시 해당 write burst에 latch되는 backpressure 설정값
    cp_backpressure_cfg_at_aw: coverpoint tb.ddr_model_ctrl.backpressure_prob
        iff (
            tb.resetn &&
            tb.memory_axi.awvalid &&
            tb.memory_axi.awready
        ) {
        bins bp_none   = {0};
        bins bp_low    = {[1:30]};
        bins bp_medium = {[31:70]};
        bins bp_high   = {[71:99]};
        illegal_bins out_of_range = default;
    }

    // [C-AXI-03] : WVALID cycle의 handshake 성립 또는 stall 여부
    cp_w_event: coverpoint tb.memory_axi.wready
        iff (tb.resetn && tb.memory_axi.wvalid) {
        bins stalled  = {1'b0};
        bins accepted = {1'b1};
    }

    // [C-AXI-04] : 실제 W channel stall이 발생한 burst 길이
    cp_stall_awlen: coverpoint tb.memory_axi.awlen
        iff (
            tb.resetn &&
            tb.memory_axi.wvalid &&
            !tb.memory_axi.wready
        ) {
        bins one_beat      = {8'd0};
        bins four_beats    = {8'd3};
        bins sixteen_beats = {8'd15};
        illegal_bins unexpected = default;
    }

    // [C-AXI-05] : WLAST handshake가 발생한 burst 길이
    cp_wlast_awlen: coverpoint tb.memory_axi.awlen
        iff (
            tb.resetn &&
            tb.memory_axi.wvalid &&
            tb.memory_axi.wready &&
            tb.memory_axi.wlast
        ) {
        bins one_beat      = {8'd0};
        bins four_beats    = {8'd3};
        bins sixteen_beats = {8'd15};
        illegal_bins unexpected = default;
    }

    // [C-AXI-06] : B channel handshake에서 실제 response sampling
    cp_bresp: coverpoint tb.memory_axi.bresp
        iff (
            tb.resetn &&
            tb.memory_axi.bvalid &&
            tb.memory_axi.bready
        ) {
        bins okay   = {2'b00};
        bins slverr = {2'b10};
        ignore_bins unsupported = {2'b01, 2'b11};
    }

    // [C-AXI-07] : B channel handshake에서 error injection 설정 sampling
    cp_error_inject_at_b: coverpoint tb.ddr_model_ctrl.error_inject
        iff (
            tb.resetn &&
            tb.memory_axi.bvalid &&
            tb.memory_axi.bready
        ) {
        bins disabled = {1'b0};
        bins enabled  = {1'b1};
    }

    // [X-AXI-01] : Backpressure 강도와 실제 AWLEN 조합
    cx_backpressure_awlen: cross cp_backpressure_cfg_at_aw, cp_awlen;

    // [X-AXI-02] : Error injection 설정과 실제 BRESP 연결
    cx_bresp_error_inject: cross cp_bresp, cp_error_inject_at_b {
        bins normal_response =
            binsof(cp_bresp.okay) &&
            binsof(cp_error_inject_at_b.disabled);
        bins injected_slverr =
            binsof(cp_bresp.slverr) &&
            binsof(cp_error_inject_at_b.enabled);

        ignore_bins unexpected_pair =
            (binsof(cp_bresp.okay) &&
             binsof(cp_error_inject_at_b.enabled)) ||
            (binsof(cp_bresp.slverr) &&
             binsof(cp_error_inject_at_b.disabled));
    }
endgroup
