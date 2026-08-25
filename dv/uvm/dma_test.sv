// ============================================================================
// dma_test.sv - DMA UVM Test
//
// - Reset 해제 후 기준 전송, backpressure 및 BRESP 오류 주입 scenario를 순차 실행.
// - Agent mode와 예상 transaction 수를 config_db로 환경에 전달.
// - 전체 UVM 계층의 verbosity를 end_of_elaboration phase에서 설정.
// - Functional coverage를 수집하고 report phase에서 coverage와 성능 요약을 출력.
// ============================================================================

class dma_test extends uvm_test;
    `uvm_component_utils(dma_test)

    // 현재 Test에서 실행하여 Scoreboard가 검사해야 하는 전체 transaction 수
    localparam int EXPECTED_TX_COUNT = 4;

    dma_s1_seq s1;
    dma_s2_seq s2;
    dma_s3_1_seq s3_1;
    dma_s3_2_seq s3_2;

    dma_env e;
    virtual axi4_if aif;

    // [커버리지 인스턴스] : 생성 즉시 클록마다 샘플링 시작
    cg_dma_coverage cov_inst = new();

    function new(input string name = "dma_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [build_phase] : Scenario Sequence와 UVM Environment 생성
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        s1 = dma_s1_seq::type_id::create("s1");
        s2 = dma_s2_seq::type_id::create("s2");
        s3_1 = dma_s3_1_seq::type_id::create("s3_1");
        s3_2 = dma_s3_2_seq::type_id::create("s3_2");

        // DMA Agent를 stimulus를 생성하는 Active mode로 설정
        uvm_config_db #(uvm_bitstream_t)::set(
            this, "e.a", "is_active", UVM_ACTIVE
        );

        // 현재 Test에서 실행하는 전체 transaction 수를 Scoreboard에 전달
        uvm_config_db #(int)::set(
            this, "e.scb", "expected_count", EXPECTED_TX_COUNT
        );

        e = dma_env::type_id::create("e", this);

        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "aif", aif))
            `uvm_fatal("TEST", "Unable to access aif from uvm_config_db");
    endfunction

    // [end_of_elaboration_phase] : 전체 UVM 계층의 로그 출력 수준 설정
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.set_report_verbosity_level_hier(UVM_FULL);
    endfunction

    // [run_phase] : Reset 해제 후 기준 전송, backpressure 및 BRESP 오류 주입 Scenario 실행
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        // Reset 해제 후 2클록 동안 안정화한 뒤 시나리오 시작
        wait (aif.aresetn === 1'b1);
        repeat (2) @(posedge aif.aclk);

        s1.start(e.a.seqr);
        s2.start(e.a.seqr);
        s3_1.start(e.a.seqr);
        s3_2.start(e.a.seqr);

        phase.drop_objection(this);
    endtask

    // [report_phase] : 성능 및 functional coverage 결과 출력
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        analyze_performance();
        generate_coverage_report();
    endfunction

    // [성능 분석] : 총 전송량/총 시뮬레이션 시간으로 대략적 Mbps 산출
    function void analyze_performance();
        real total_time_ns, throughput_mbps;
        int total_cycles;

        $display("\n--- Performance Analysis ---");
        total_time_ns = real'($time);             // 현재까지 경과 시간(ns)
        total_cycles = int'(total_time_ns / 10.0); // 100MHz → 10ns/사이클
        throughput_mbps =
            (256.0 + 1024.0 + 16.0 + 64.0) * 8.0 / // 총 비트 수
            total_time_ns * 1000.0;                 // ns→us 보정(대략적)

        $display(" Total execution time: %0.1f ns (%0d cycles)", total_time_ns, total_cycles);
        $display(" Estimated throughput: %0.2f Mbps", throughput_mbps);

        if (throughput_mbps > 100.0)
            $display(" Excellent performance");
        else if (throughput_mbps > 50.0)
            $display(" Good performance");
        else
            $display(" Performance improvement needed");
    endfunction

    // [커버리지 리포트] : 항목별/전체 요약 출력
    function void generate_coverage_report();
        real total_coverage;
        real size_cov, state_cov, align_cov, cross_cov;

        $display("\n--- Coverage Analysis Report ---");
        total_coverage = cov_inst.get_coverage();         // 전체 %
        size_cov = cov_inst.cp_size.get_coverage();       // 크기 분포 %
        state_cov = cov_inst.cp_dma_state.get_coverage(); // 상태 분포 %
        align_cov = (
            cov_inst.cp_src_alignment.get_coverage() +
            cov_inst.cp_dst_alignment.get_coverage()
        ) / 2.0;                                          // 정렬 평균 %
        cross_cov = cov_inst.cx_size_alignment.get_coverage(); // 교차 %

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
    endfunction
endclass
