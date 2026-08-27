// ============================================================================
// dma_regression_test.sv - DMA Multi-Seed Backpressure Regression Test
//
// - Simulator run option에서 numeric seed를 읽어 regression sequence에 전달.
// - Seed별 36개 정상 전송을 실행하고 Scoreboard transaction 수를 확인.
// - UVM 오류와 AXI4 W channel assertion violation을 종합하여 결과 판정.
// - Functional coverage와 throughput은 Step 5 regression 판정에서 제외.
// ============================================================================

class dma_regression_test extends uvm_test;
    `uvm_component_utils(dma_regression_test)

    // 한 seed에서 실행하는 backpressure 확률 6종 × 전송 크기 6종
    localparam int EXPECTED_TX_COUNT = 36;

    dma_regression_seq regression_seq;
    dma_env e;
    virtual axi4_if aif;

    int unsigned simulation_seed;

    function new(
        input string name = "dma_regression_test",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // [build_phase] : Seed 확인, Regression Sequence와 UVM Environment 생성
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!$value$plusargs("ntb_random_seed=%d", simulation_seed))
            `uvm_fatal(
                "REGR_TEST",
                "Numeric seed is required: +ntb_random_seed=<seed>"
            )

        regression_seq = dma_regression_seq::type_id::create("regression_seq");
        regression_seq.simulation_seed = simulation_seed;

        // DMA Agent를 stimulus를 생성하는 Active mode로 설정
        uvm_config_db #(uvm_bitstream_t)::set(
            this, "e.a", "is_active", UVM_ACTIVE
        );

        // 현재 seed에서 실행하는 transaction 수를 Scoreboard에 전달
        uvm_config_db #(int)::set(
            this, "e.scb", "expected_count", EXPECTED_TX_COUNT
        );

        e = dma_env::type_id::create("e", this);

        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "aif", aif))
            `uvm_fatal("REGR_TEST", "Unable to access aif from uvm_config_db")
    endfunction

    // [end_of_elaboration_phase] : Regression에 필요한 요약 로그만 출력
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.set_report_verbosity_level_hier(UVM_MEDIUM);
    endfunction

    // [run_phase] : Reset 해제 후 현재 seed의 36개 Regression Transaction 실행
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        wait (aif.aresetn === 1'b1);
        repeat (2) @(posedge aif.aclk);

        `uvm_info(
            "REGR_TEST",
            $sformatf(
                "Starting backpressure regression: seed=%0d, transactions=%0d",
                simulation_seed, EXPECTED_TX_COUNT
            ),
            UVM_LOW
        )

        regression_seq.start(e.a.seqr);

        phase.drop_objection(this);
    endtask

    // [report_phase] : Seed별 checker 결과와 최종 PASS/FAIL 출력
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        generate_axi_checker_report();
        generate_regression_result();
    endfunction

    // [AXI checker report] : Assertion별 violation count 출력
    function void generate_axi_checker_report();
        $display("\n--- AXI4 W Channel Checker Report ---");
        $display(
            " A-01 W payload stable on stall violations: %0d",
            tb.axi_w_checker.vio_w_payload_stable_on_stall
        );
        $display(
            " A-02 WVALID hold violations: %0d",
            tb.axi_w_checker.vio_wvalid_hold
        );
        $display(
            " A-03 WLAST timing violations: %0d",
            tb.axi_w_checker.vio_wlast_timing
        );
        $display(
            " Total AXI W violations: %0d",
            tb.axi_w_checker.vio_total
        );
    endfunction

    // [최종 결과] : Transaction, UVM report 및 AXI checker 결과 종합 판정
    function void generate_regression_result();
        uvm_report_server report_server;
        int actual_error_count;
        int actual_warning_count;
        int actual_fatal_count;
        bit regression_passed;

        report_server = uvm_report_server::get_server();
        actual_error_count = report_server.get_severity_count(UVM_ERROR);
        actual_warning_count = report_server.get_severity_count(UVM_WARNING);
        actual_fatal_count = report_server.get_severity_count(UVM_FATAL);

        regression_passed =
            (actual_error_count == 0) &&
            (actual_warning_count == 0) &&
            (actual_fatal_count == 0) &&
            (e.scb.checked_count == EXPECTED_TX_COUNT) &&
            (tb.axi_w_checker.vio_total == 0);

        $display("\n============================================================");
        $display(" Seed Regression Result");
        $display("============================================================");
        $display(" Simulation seed: %0d", simulation_seed);
        $display(" UVM errors: %0d", actual_error_count);
        $display(" UVM warnings: %0d", actual_warning_count);
        $display(" UVM fatals: %0d", actual_fatal_count);
        $display(
            " Checked transactions: %0d / %0d",
            e.scb.checked_count, EXPECTED_TX_COUNT
        );
        $display(" AXI W violations: %0d", tb.axi_w_checker.vio_total);

        if (regression_passed)
            $display("\n SEED REGRESSION RESULT: PASSED");
        else
            $display("\n SEED REGRESSION RESULT: FAILED");
    endfunction
endclass
