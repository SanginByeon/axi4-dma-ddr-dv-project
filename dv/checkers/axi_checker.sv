// ============================================================================
// axi_checker.sv - AXI4 W Channel Protocol Checker
//
// - W channel backpressure 중 WVALID 유지 여부를 SVA로 확인.
// - W channel backpressure 중 WDATA/WSTRB/WLAST 안정성을 SVA로 확인.
// - W channel handshake마다 WLAST와 write burst의 마지막 beat 정렬을 SVA로 확인.
// - Assertion별 violation counter를 제공하여 UVM report phase에서 결과 확인 지원.
// ============================================================================

module axi_checker (
    axi4_if axi,
    input logic [7:0] w_beats_sent
);

    // Assertion별 violation 발생 횟수
    int unsigned vio_total = 0;
    int unsigned vio_w_payload_stable_on_stall = 0;
    int unsigned vio_wvalid_hold = 0;
    int unsigned vio_wlast_timing = 0;

    // [A-01] : Stall이 지속되는 동안 W channel payload 유지
    property p_w_payload_stable_on_stall;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        (axi.wvalid && !axi.wready)
        |=> $stable({axi.wdata, axi.wstrb, axi.wlast});
    endproperty

    // [A-02] : Stall이 지속되는 동안 WVALID 유지
    property p_wvalid_hold;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        (axi.wvalid && !axi.wready)
        |=> axi.wvalid;
    endproperty

    // [A-03] : W handshake마다 WLAST는 AWLEN이 가리키는 마지막 beat에서만 활성화
    property p_wlast_timing;
        @(posedge axi.aclk) disable iff (!axi.aresetn)
        (axi.wvalid && axi.wready)
        |-> (axi.wlast == (w_beats_sent == axi.awlen));
    endproperty

    ap_w_payload_stable_on_stall:
        assert property (p_w_payload_stable_on_stall)
        else begin
            $error("[A-01][AXI_W] Payload changed while stalled");
            vio_total++;
            vio_w_payload_stable_on_stall++;
        end

    ap_wvalid_hold:
        assert property (p_wvalid_hold)
        else begin
            $error("[A-02][AXI_W] WVALID deasserted while stalled");
            vio_total++;
            vio_wvalid_hold++;
        end

    ap_wlast_timing:
        assert property (p_wlast_timing)
        else begin
            $error(
                "[A-03][AXI_W] WLAST timing mismatch: WLAST=%0b, beat=%0d, AWLEN=%0d",
                axi.wlast, w_beats_sent, axi.awlen
            );
            vio_total++;
            vio_wlast_timing++;
        end

endmodule
